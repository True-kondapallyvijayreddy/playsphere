import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/challenge.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/tournament_invite.dart';
import 'package:playsphere/core/notifications/notification_model.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/home/home_providers.dart';

/// One club at a time.
///
/// Written against "if I choose a club on top, we need to see everything about
/// that club only — we cannot mix the club and info". Somebody who owns two
/// clubs selects one; nothing about the other may reach a list.
void main() {
  const a = 'org_a';
  const b = 'org_b';
  const host = 'org_host';

  Membership owner(String orgId) => Membership(
        uid: 'uid_me',
        orgId: orgId,
        role: MembershipRole.owner,
        status: MembershipStatus.active,
        displayName: 'Me',
      );

  TournamentInvite inviteTo(String orgId) => TournamentInvite(
        id: '${host}_t1_$orgId',
        tournamentId: 't1',
        tournamentName: 'Summer Games',
        fromOrgId: host,
        fromOrgName: 'Host',
        toOrgId: orgId,
        toOrgName: orgId,
        status: 'pending',
      );

  Challenge challengeTo(String orgId) => Challenge(
        id: 'ch_$orgId',
        fromOrgId: host,
        toOrgId: orgId,
        fromOrgName: 'Host',
        toOrgName: orgId,
        sportId: 'cricket',
        status: 'pending',
      );

  AppNotification note(String id, Map<String, String> params) =>
      AppNotification(
        id: id,
        type: NotificationType.tournamentInvite,
        title: id,
        body: '',
        createdAt: DateTime(2026, 9, 13),
        deepLink: params.isEmpty ? null : DeepLink('/x', params: params),
      );

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('uid_me'),
        myMembershipsProvider
            .overrideWith((ref) => Stream.value([owner(a), owner(b)])),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        ),
        incomingTournamentInvitesProvider
            .overrideWith((ref, id) => Stream.value([inviteTo(id)])),
        liveIncomingTournamentInvitesProvider
            .overrideWith((ref, id) => Stream.value([inviteTo(id)])),
        incomingChallengesProvider
            .overrideWith((ref, id) => AsyncValue.data([challengeTo(id)])),
        pendingMembersProvider.overrideWith(
          (ref, id) => Stream.value([
            Membership(
              uid: 'applicant_$id',
              orgId: id,
              role: MembershipRole.member,
              status: MembershipStatus.pending,
              displayName: 'Applicant',
            ),
          ]),
        ),
        myNotificationFeedProvider.overrideWith(
          (ref) => Stream.value([
            note('about_a', {'orgId': a}),
            note('about_b', {'orgId': b}),
            note('invite_for_b', {'clubId': b}),
            note('personal', const {}),
            note('some_other_club', {'orgId': host}),
          ]),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Lets every stream above deliver its first value.
  Future<void> settle(ProviderContainer c) async {
    // Keep the scoped providers alive while the streams arrive.
    final subs = [
      c.listen(myTournamentInvitesProvider, (_, __) {}),
      c.listen(myIncomingChallengesProvider, (_, __) {}),
      c.listen(myPendingApprovalsProvider, (_, __) {}),
      c.listen(myScopedNotificationFeedProvider, (_, __) {}),
      c.listen(invitedSeasonContextProvider((hostOrgId: host, tournamentId: 't1')),
          (_, __) {}),
    ];
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });
  }

  test('only the selected club is in scope', () async {
    final c = container();
    await settle(c);

    c.read(currentClubIdProvider.notifier).switchTo(b);
    await settle(c);
    expect(c.read(scopedOrgIdsProvider), [b]);

    c.read(currentClubIdProvider.notifier).switchTo(a);
    await settle(c);
    expect(c.read(scopedOrgIdsProvider), [a]);
  });

  test('invitations, challenges and join requests never mix clubs', () async {
    final c = container();
    await settle(c);
    c.read(currentClubIdProvider.notifier).switchTo(a);
    await settle(c);

    expect(
      c.read(myTournamentInvitesProvider).value!.map((i) => i.toOrgId),
      [a],
    );
    expect(
      c.read(myIncomingChallengesProvider).value!.map((x) => x.toOrgId),
      [a],
    );
    expect(
      c.read(myPendingApprovalsProvider).value!.map((m) => m.orgId),
      [a],
    );

    c.read(currentClubIdProvider.notifier).switchTo(b);
    await settle(c);
    expect(
      c.read(myTournamentInvitesProvider).value!.map((i) => i.toOrgId),
      [b],
    );
    expect(
      c.read(myIncomingChallengesProvider).value!.map((x) => x.toOrgId),
      [b],
    );
  });

  test('another season page names the SELECTED club as the invited one',
      () async {
    final c = container();
    await settle(c);
    c.read(currentClubIdProvider.notifier).switchTo(b);
    await settle(c);

    final ctx = c.read(
      invitedSeasonContextProvider((hostOrgId: host, tournamentId: 't1')),
    );
    expect(ctx?.orgId, b);
  });

  test('notifications about my other club are held back', () async {
    final c = container();
    await settle(c);
    c.read(currentClubIdProvider.notifier).switchTo(a);
    await settle(c);

    expect(
      c.read(myScopedNotificationFeedProvider).value!.map((n) => n.id),
      ['about_a', 'personal', 'some_other_club'],
    );
  });

  test('a start button never falls back to another club', () async {
    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('uid_me'),
        myMembershipsProvider.overrideWith(
          (ref) => Stream.value([
            Membership(
              uid: 'uid_me',
              orgId: a,
              role: MembershipRole.member,
              status: MembershipStatus.active,
              displayName: 'Me',
            ),
            owner(b),
          ]),
        ),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(
      actingOrgIdProvider(Capability.manageCompetitions),
      (_, __) {},
    );
    addTearDown(sub.close);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    c.read(currentClubIdProvider.notifier).switchTo(a);
    // A plain member of the selected club: no New event, and certainly not
    // New event for club B.
    expect(c.read(actingOrgIdProvider(Capability.manageCompetitions)), isNull);
  });
}
