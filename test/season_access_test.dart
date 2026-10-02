import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_official.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/models/tournament_invite.dart';
import 'package:playsphere/core/models/tournament_official.dart';
import 'package:playsphere/core/models/venue.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/domain/tournament/season_access.dart';
import 'package:playsphere/features/tournaments/officials_screen.dart';
import 'package:playsphere/features/tournaments/tournament_detail_screen.dart';

/// What each role gets on a season page — and, as importantly, does not.
///
/// Written against "any member in the club can add umpires, grounds and edit
/// everything on the season board". The capability is resolved through the
/// real path — a membership row → its rank → [SeasonAccess] — not by
/// overriding a capability set, so a rank that quietly gains a power fails
/// here.
void main() {
  const orgId = 'org_host';
  const tid = 'season_1';

  group('SeasonAccess.resolve', () {
    test('ranks that run competitions organize', () {
      for (final role in [
        MembershipRole.owner,
        MembershipRole.admin,
        MembershipRole.eventManager,
      ]) {
        expect(
          SeasonAccess.resolve(
            capabilities: PermissionMatrix.capabilitiesOf(role),
            uid: 'u',
            roster: const [],
          ).role,
          SeasonRole.organizer,
          reason: role.label,
        );
      }
    });

    test('a scorer rank or a place on the panel officiates', () {
      expect(
        SeasonAccess.resolve(
          capabilities:
              PermissionMatrix.capabilitiesOf(MembershipRole.judgeScorer),
          uid: 'u',
          roster: const [],
        ).role,
        SeasonRole.official,
      );
      expect(
        SeasonAccess.resolve(
          capabilities: PermissionMatrix.capabilitiesOf(MembershipRole.member),
          uid: 'ump',
          roster: const [TournamentOfficial(uid: 'ump', name: 'Ump')],
        ).role,
        SeasonRole.official,
      );
    });

    test('a member, or nobody signed in, spectates', () {
      expect(
        SeasonAccess.resolve(
          capabilities: PermissionMatrix.capabilitiesOf(MembershipRole.member),
          uid: 'u',
          roster: const [],
        ).canManage,
        isFalse,
      );
      expect(
        SeasonAccess.resolve(capabilities: const {}, uid: null, roster: const [])
            .role,
        SeasonRole.spectator,
      );
    });
  });

  // ---------------------------------------------------------------------
  // The page itself, rendered as each role.
  // ---------------------------------------------------------------------

  const tournament = Tournament(
    id: tid,
    orgId: orgId,
    name: 'Summer Games 2026',
    status: TournamentStatus.inProgress,
  );

  const cricket = Competition(
    id: 'cri',
    orgId: orgId,
    tournamentId: tid,
    name: 'Cricket Cup',
    sportId: 'cricket',
    sportName: 'Cricket',
    archetype: CompetitionArchetype.versus,
    entrantType: EntrantType.team,
    format: CompetitionFormat.groupThenKnockout,
    status: CompetitionStatus.inProgress,
    category: CompetitionCategory(label: 'Open'),
    scoringPluginKey: 'goal_based',
  );

  Fixture match(
    String id, {
    required String a,
    required String b,
    String? winner,
    bool draft = false,
    List<MatchOfficial> officials = const [],
    DateTime? at,
  }) =>
      Fixture(
        id: id,
        orgId: orgId,
        compId: 'cri',
        tournamentId: tid,
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: winner == null ? FixtureStatus.scheduled : FixtureStatus.completed,
        winnerEntrantId: winner,
        bracket: Bracket.group,
        groupId: 'A',
        isDraft: draft,
        officials: officials,
        scheduledAt: at,
        summary: winner == null ? '' : '120-98',
      );

  final fixtures = [
    match('m1', a: 'Lions', b: 'Tigers', winner: 'Lions'),
    match(
      'm2',
      a: 'Lions',
      b: 'Eagles',
      at: DateTime.now().add(const Duration(days: 1)),
      officials: const [MatchOfficial(uid: 'uid_ump', name: 'Umpire Ravi')],
    ),
    match('m3', a: 'Placeholder One', b: 'Placeholder Two', draft: true),
    // A match still to play with nobody to umpire it — the one thing on this
    // season that genuinely needs the organizer's attention, and what
    // `_NeedsAttention` is for.
    //
    // It used to be the draft timetable that put the card on the desk, but a
    // season with `status: inProgress` and no per-sport stamps now reads as
    // published season-wide (see `Tournament.publishedSeasonWide` — nothing
    // writes that status any more, so it means an old, already-published
    // document). This harness therefore had nothing needing attention at all,
    // and the desk was right to show no card.
    match(
      'm4',
      a: 'Tigers',
      b: 'Eagles',
      at: DateTime.now().add(const Duration(days: 2)),
    ),
  ];

  const badminton = Competition(
    id: 'bad',
    orgId: orgId,
    tournamentId: tid,
    name: 'Badminton Open',
    sportId: 'badminton',
    sportName: 'Badminton',
    archetype: CompetitionArchetype.versus,
    entrantType: EntrantType.individual,
    format: CompetitionFormat.knockout,
    status: CompetitionStatus.inProgress,
    category: CompetitionCategory(label: 'Open'),
    scoringPluginKey: 'badminton',
  );

  Widget harness({
    required String uid,
    required MembershipRole? role,
    List<TournamentOfficial> roster = const [],
    List<Competition> events = const [cricket],
    String location = '/org/$orgId/tournaments/$tid',
  }) {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/org/:orgId/tournaments/:tournamentId',
          builder: (_, s) => const TournamentDetailScreen(
            orgId: orgId,
            tournamentId: tid,
          ),
          routes: [
            GoRoute(
              path: 'officials',
              builder: (_, s) =>
                  const OfficialsScreen(orgId: orgId, tournamentId: tid),
            ),
            GoRoute(
              path: 'desk',
              builder: (_, s) =>
                  const SeasonDeskScreen(orgId: orgId, tournamentId: tid),
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        myMembershipsProvider.overrideWith(
          (ref) => Stream.value([
            if (role != null)
              Membership(
                uid: uid,
                orgId: orgId,
                role: role,
                status: MembershipStatus.active,
                displayName: 'Me',
              ),
          ]),
        ),
        orgMembersProvider.overrideWith(
          (ref, id) => Stream.value(const <Membership>[]),
        ),
        organizationProvider.overrideWith(
          (ref, id) => Stream.value(const Organization(
            id: orgId,
            name: 'Host Club',
            orgType: OrgType.school,
            visibility: OrgVisibility.public,
            ownerUid: 'uid_owner',
            inviteCode: 'ABC234',
          )),
        ),
        venuesProvider.overrideWith((ref, id) => Stream.value(const <Venue>[])),
        tournamentProvider.overrideWith((ref, key) => Stream.value(tournament)),
        tournamentEventsProvider
            .overrideWith((ref, key) => Stream.value(events)),
        tournamentFixturesProvider
            .overrideWith((ref, key) => Stream.value(fixtures)),
        tournamentOfficialsProvider
            .overrideWith((ref, key) => Stream.value(roster)),
        tournamentInvitesProvider.overrideWith(
          (ref, key) => Stream.value(const <TournamentInvite>[]),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpPage(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  /// Every organizer-only thing on the season page.
  void expectNoOrganizerControls() {
    expect(find.byTooltip('More actions'), findsNothing,
        reason: 'the edit / venues / invite menu');
    expect(find.text('Add a sport or event'), findsNothing);
    expect(find.text('Umpire panel'), findsNothing);
    expect(find.text('Venue planner'), findsNothing);
    expect(find.text('NEEDS YOUR ATTENTION'), findsNothing);
    expect(find.text('Assign'), findsNothing);
    expect(find.text('Change'), findsNothing);
    expect(find.byTooltip('Edit event details'), findsNothing);
    expect(find.textContaining('Draw & schedule'), findsNothing);
    expect(find.textContaining('schedule published'), findsNothing);
    expect(find.textContaining('Publish '), findsNothing);
    expect(find.text('Organizers'), findsNothing);
  }

  testWidgets('a plain member gets the plain page', (tester) async {
    await pumpPage(tester, harness(uid: 'uid_member', role: MembershipRole.member));

    expectNoOrganizerControls();
    // …no staffing…
    expect(find.text('Umpires'), findsNothing);
    expect(find.textContaining('Your matches to umpire'), findsNothing);
    // …no organizer's draft placeholders…
    expect(find.textContaining('Placeholder'), findsNothing);
    // …and everything a spectator came for.
    expect(find.text('Summer Games 2026'), findsOneWidget);
    expect(find.text('Season at a glance'), findsOneWidget);
    expect(find.text('Timetable'), findsOneWidget);
    expect(find.text('LEADERBOARD'), findsOneWidget);
    expect(find.text('Cricket Cup · Group A'), findsOneWidget);
    expect(find.text('Lions'), findsWidgets);
  });

  testWidgets('somebody from outside the club gets the same plain page',
      (tester) async {
    await pumpPage(tester, harness(uid: 'uid_visitor', role: null));
    expectNoOrganizerControls();
    expect(find.text('LEADERBOARD'), findsOneWidget);
  });

  testWidgets('an umpire on the panel sees their matches, and no controls',
      (tester) async {
    await pumpPage(
      tester,
      harness(
        uid: 'uid_ump',
        role: MembershipRole.member,
        roster: const [TournamentOfficial(uid: 'uid_ump', name: 'Umpire Ravi')],
      ),
    );

    expectNoOrganizerControls();
    expect(find.text('Your matches to umpire (1)'), findsOneWidget);
    expect(find.text('UMPIRES'), findsOneWidget);
    expect(find.textContaining('Placeholder'), findsNothing);
  });

  testWidgets('the owner sees the plain page with one door to the desk',
      (tester) async {
    await pumpPage(tester, harness(uid: 'uid_owner', role: MembershipRole.owner));

    // The season page is stats and leaderboards for the owner too (user,
    // 2026-09-13) — the work lives on the desk.
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.text('Organizer desk'), findsOneWidget);
    expect(find.text('NEEDS YOUR ATTENTION'), findsNothing);
    expect(find.text('Add a sport or event'), findsNothing);
    expect(find.text('Venue planner'), findsNothing);
    expect(find.text('Assign'), findsNothing);
    expect(find.text('LEADERBOARD'), findsOneWidget);
  });

  testWidgets('the owner gets the organizer desk', (tester) async {
    await pumpPage(
      tester,
      harness(
        uid: 'uid_owner',
        role: MembershipRole.owner,
        location: '/org/$orgId/tournaments/$tid/desk',
      ),
    );

    expect(find.text('Add a sport or event'), findsOneWidget);
    expect(find.text('Umpire panel'), findsWidgets);
    expect(find.text('Venue planner'), findsOneWidget);
    expect(find.text('Invite clubs'), findsOneWidget);
    expect(find.text('NEEDS YOUR ATTENTION'), findsOneWidget);
    expect(find.text('Assign'), findsOneWidget);
  });

  testWidgets('a member cannot open the desk', (tester) async {
    await pumpPage(
      tester,
      harness(
        uid: 'uid_member',
        role: MembershipRole.member,
        location: '/org/$orgId/tournaments/$tid/desk',
      ),
    );
    expect(find.text('For the season organizers'), findsOneWidget);
    expect(find.text('NEEDS YOUR ATTENTION'), findsNothing);
  });

  testWidgets('several sports get a drop-down that opens one at a time',
      (tester) async {
    await pumpPage(
      tester,
      harness(
        uid: 'uid_member',
        role: MembershipRole.member,
        events: const [cricket, badminton],
      ),
    );

    final picker = find.byKey(const ValueKey('season-sport-picker'));
    expect(picker, findsOneWidget);
    // "All sports": every sport listed as a folded header.
    expect(find.text('Cricket'), findsWidgets);
    expect(find.text('Badminton'), findsWidgets);
    expect(find.text('LEADERBOARD'), findsNothing);

    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cricket').last);
    await tester.pumpAndSettle();

    // Only cricket, and open.
    expect(find.text('LEADERBOARD'), findsOneWidget);
    expect(find.text('Cricket Cup · Group A'), findsOneWidget);
    expect(find.text('Badminton Open'), findsNothing);
  });

  testWidgets('the umpire panel screen turns a member away', (tester) async {
    await pumpPage(
      tester,
      harness(
        uid: 'uid_member',
        role: MembershipRole.member,
        location: '/org/$orgId/tournaments/$tid/officials',
      ),
    );

    expect(find.text('For the season organizers'), findsOneWidget);
    expect(find.byTooltip('Add an official'), findsNothing);
    expect(find.text('Assign officials across the bracket'), findsNothing);
  });
}
