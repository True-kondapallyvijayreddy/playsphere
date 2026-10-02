import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/models/tournament_invite.dart';
import 'package:playsphere/core/models/tournament_official.dart';
import 'package:playsphere/core/models/venue.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/discovery_repository.dart';
import 'package:playsphere/features/invitations/invite_clubs_screen.dart';
import 'package:playsphere/features/invitations/season_register_screen.dart';
import 'package:playsphere/features/home/open_registrations.dart';
import 'package:playsphere/features/invitations/widgets/invitation_card.dart';
import 'package:playsphere/features/sports/sport_hub_providers.dart';
import 'package:playsphere/features/tournaments/tournament_detail_screen.dart';

/// The invitations space: a host writes to clubs it finds by name, area and
/// sport; an invited club reads a letter with a Register button; the button
/// lands on a page of what can be entered.
void main() {
  const host = 'org_host';
  const tid = 'season_1';

  Organization club(
    String id,
    String name, {
    String? district,
    String? city,
    OrgVisibility visibility = OrgVisibility.public,
  }) =>
      Organization(
        id: id,
        name: name,
        orgType: OrgType.cityClub,
        visibility: visibility,
        ownerUid: 'uid_$id',
        inviteCode: 'ABC234',
        district: district,
        city: city,
      );

  final hostClub = club(host, 'XYZ Sports Club', district: 'Rangareddy');
  final directory = [
    hostClub,
    club('org_a', 'Adibatla Strikers', district: 'Rangareddy'),
    club('org_b', 'Ibrahimpatnam XI', district: 'Rangareddy'),
    club('org_c', 'Warangal Warriors', district: 'Warangal'),
  ];

  final season = Tournament(
    id: tid,
    orgId: host,
    name: 'Summer Games 2026',
    status: TournamentStatus.entriesOpen,
    startDate: DateTime(2026, 8, 12),
    endDate: DateTime(2026, 8, 24),
  );

  Competition event(
    String id,
    String sportId,
    String sportName, {
    CompetitionStatus status = CompetitionStatus.registrationOpen,
    EntrantType entrantType = EntrantType.team,
  }) =>
      Competition(
        id: id,
        orgId: host,
        tournamentId: tid,
        name: 'Summer Games 2026 — $sportName',
        sportId: sportId,
        sportName: sportName,
        archetype: CompetitionArchetype.versus,
        entrantType: entrantType,
        format: CompetitionFormat.knockout,
        status: status,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        venue: 'Adibatla, Hyderabad',
      );

  final events = [
    event('cri', 'cricket', 'Cricket'),
    event(
      'tt',
      'table_tennis',
      'Table Tennis',
      status: CompetitionStatus.draft,
      entrantType: EntrantType.individual,
    ),
  ];

  List<Override> common({
    required String uid,
    required List<Membership> memberships,
    Tournament? tournament,
    List<TournamentInvite> sent = const [],
    List<TournamentInvite> received = const [],
    Set<String> entered = const {},
  }) =>
      [
        currentUidProvider.overrideWithValue(uid),
        // What this profile already holds a live entry in, as `orgId/compId`.
        // The season page reads it to decide between a Register button and
        // "Already registered" — see `SeasonEntryStatus`.
        profileEntryRefsProvider.overrideWithValue(entered),
        myMembershipsProvider.overrideWith((ref) => Stream.value(memberships)),
        orgMembersProvider
            .overrideWith((ref, id) => Stream.value(const <Membership>[])),
        organizationProvider.overrideWith(
          (ref, id) => Stream.value(
            directory.firstWhere((o) => o.id == id, orElse: () => hostClub),
          ),
        ),
        venuesProvider.overrideWith((ref, id) => Stream.value(const <Venue>[])),
        tournamentProvider
            .overrideWith((ref, key) => Stream.value(tournament ?? season)),
        tournamentEventsProvider
            .overrideWith((ref, key) => Stream.value(events)),
        tournamentFixturesProvider
            .overrideWith((ref, key) => Stream.value(const <Fixture>[])),
        tournamentOfficialsProvider.overrideWith(
          (ref, key) => Stream.value(const <TournamentOfficial>[]),
        ),
        tournamentInvitesProvider.overrideWith((ref, key) => Stream.value(sent)),
        liveIncomingTournamentInvitesProvider
            .overrideWith((ref, id) => Stream.value(received)),
        incomingTournamentInvitesProvider.overrideWith(
          (ref, id) => Stream.value([
            for (final i in received)
              if (i.isPending) i,
          ]),
        ),
        discoveryRepositoryProvider.overrideWithValue(_Directory(directory)),
        sportEventsProvider.overrideWith(
          (ref, sportId) => AsyncValue.data([
            for (final e in events)
              if (e.sportId == sportId) e,
          ]),
        ),
      ];

  Membership member(String uid, String orgId, MembershipRole role) =>
      Membership(
        uid: uid,
        orgId: orgId,
        role: role,
        status: MembershipStatus.active,
        displayName: 'Me',
      );

  Future<void> pump(
    WidgetTester tester, {
    required List<Override> overrides,
    required String location,
    Object? extra,
  }) async {
    tester.view.physicalSize = const Size(700, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      initialExtra: extra,
      routes: [
        GoRoute(
          path: '/org/:orgId/tournaments/:tournamentId',
          builder: (_, s) =>
              const TournamentDetailScreen(orgId: host, tournamentId: tid),
          routes: [
            GoRoute(
              path: 'desk',
              builder: (_, s) =>
                  const SeasonDeskScreen(orgId: host, tournamentId: tid),
            ),
            GoRoute(
              path: 'invite',
              builder: (_, s) =>
                  const InviteClubsScreen(orgId: host, tournamentId: tid),
            ),
            GoRoute(
              path: 'register',
              builder: (_, s) =>
                  const SeasonRegisterScreen(orgId: host, tournamentId: tid),
            ),
          ],
        ),
        GoRoute(
          path: '/card',
          builder: (_, s) => Scaffold(
            body: ListView(
              children: [
                for (final i in s.extra as List<TournamentInvite>)
                  InvitationCard(invite: i),
              ],
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('inviting clubs', () {
    final owner = [member('uid_owner', host, MembershipRole.owner)];

    testWidgets('writes the letter from the season\'s own facts',
        (tester) async {
      await pump(
        tester,
        overrides: common(uid: 'uid_owner', memberships: owner),
        location: '/org/$host/tournaments/$tid/invite',
      );

      final letter = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .firstWhere((t) => t.startsWith('Dear sports enthusiasts'));
      expect(letter, contains('We from XYZ Sports Club are conducting'));
      expect(letter, contains('Summer Games 2026 — a season for Cricket and '
          'Table Tennis — from 12 Aug to 24 Aug 2026 at Adibatla, Hyderabad.'));
      expect(find.text('Share on WhatsApp & more'), findsOneWidget);
    });

    testWidgets('finds clubs by area, never lists the host, selects them all',
        (tester) async {
      await pump(
        tester,
        overrides: common(uid: 'uid_owner', memberships: owner),
        location: '/org/$host/tournaments/$tid/invite',
      );

      expect(
        find.widgetWithText(CheckboxListTile, 'XYZ Sports Club'),
        findsNothing,
        reason: 'a club cannot invite itself',
      );
      expect(find.text('3 clubs found'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Area — district, city, mandal or village'),
        'Warangal',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 club found'), findsOneWidget);
      expect(find.text('Warangal Warriors'), findsOneWidget);
      expect(find.text('Adibatla Strikers'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Area — district, city, mandal or village'),
        'Rangareddy',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all 2'));
      await tester.pumpAndSettle();
      expect(find.text('Send to 2 clubs'), findsOneWidget);
    });

    testWidgets('clubs already invited are shown with their answer',
        (tester) async {
      final invite = TournamentInvite(
        id: '${host}_${tid}_org_a',
        tournamentId: tid,
        tournamentName: season.name,
        fromOrgId: host,
        fromOrgName: hostClub.name,
        toOrgId: 'org_a',
        toOrgName: 'Adibatla Strikers',
        status: 'accepted',
      );
      await pump(
        tester,
        overrides:
            common(uid: 'uid_owner', memberships: owner, sent: [invite]),
        location: '/org/$host/tournaments/$tid/invite',
      );
      expect(find.text('2 clubs found'), findsOneWidget);
      expect(find.textContaining('1 coming'), findsOneWidget);
    });

    testWidgets('a plain member cannot open the composer', (tester) async {
      await pump(
        tester,
        overrides: common(
          uid: 'uid_m',
          memberships: [member('uid_m', host, MembershipRole.member)],
        ),
        location: '/org/$host/tournaments/$tid/invite',
      );
      expect(find.text('For the season organizers'), findsOneWidget);
      expect(find.text('Send invitations'), findsNothing);
    });
  });

  group('an invited club', () {
    final invite = TournamentInvite(
      id: '${host}_${tid}_org_a',
      tournamentId: tid,
      tournamentName: season.name,
      fromOrgId: host,
      fromOrgName: hostClub.name,
      toOrgId: 'org_a',
      toOrgName: 'Adibatla Strikers',
      status: 'pending',
      sportNames: const ['Cricket', 'Table Tennis'],
      place: 'Adibatla, Hyderabad',
      startDate: season.startDate,
      endDate: season.endDate,
    );

    testWidgets('reads a letter its organizers can accept and register from',
        (tester) async {
      await pump(
        tester,
        overrides: common(
          uid: 'uid_a',
          memberships: [member('uid_a', 'org_a', MembershipRole.owner)],
          received: [invite],
        ),
        location: '/card',
        extra: [invite],
      );

      // An invitation sent before letters existed still reads as one.
      expect(find.textContaining('Dear sports enthusiasts'), findsOneWidget);
      expect(find.textContaining('Cricket and Table Tennis'), findsWidgets);
      expect(find.text('Accept & register'), findsOneWidget);
      expect(find.text('Not this time'), findsOneWidget);
    });

    testWidgets('a plain member of the invited club is sent to the page, '
        'not offered the answer', (tester) async {
      await pump(
        tester,
        overrides: common(
          uid: 'uid_p',
          memberships: [member('uid_p', 'org_a', MembershipRole.member)],
          received: [invite],
        ),
        location: '/card',
        extra: [invite],
      );

      expect(find.text('Open registration'), findsOneWidget);
      expect(find.text('Not this time'), findsNothing);
    });

    testWidgets('the registration page lists what is open and what is not',
        (tester) async {
      await pump(
        tester,
        overrides: common(
          uid: 'uid_a',
          memberships: [member('uid_a', 'org_a', MembershipRole.owner)],
          received: [invite],
        ),
        location: '/org/$host/tournaments/$tid/register',
      );

      expect(find.text('1 event taking entries'), findsOneWidget);
      expect(find.text('Enter a team'), findsOneWidget);
      expect(find.text('Opens soon'), findsOneWidget);
      // Unanswered, so the organizer is asked to accept first.
      expect(find.text('Accept invitation'), findsOneWidget);
    });
  });

  group('a tournament is a one-sport season', () {
    testWidgets('its page calls it a tournament and offers Register',
        (tester) async {
      const tournament = Tournament(
        id: tid,
        orgId: host,
        name: 'Open Badminton Championship',
        kind: SeasonKind.tournament,
        status: TournamentStatus.entriesOpen,
      );
      await pump(
        tester,
        overrides: common(
          uid: 'uid_visitor',
          memberships: const [],
          tournament: tournament,
        ),
        location: '/org/$host/tournaments/$tid',
      );
      expect(find.text('TOURNAMENT'), findsOneWidget);
      expect(find.text('Register for this tournament'), findsOneWidget);
    });

    // The bug, stated as a test: "even after registration is done and
    // confirmed by the host club, it still shows the Registration option".
    testWidgets('once entered, it says so instead of offering Register',
        (tester) async {
      const tournament = Tournament(
        id: tid,
        orgId: host,
        name: 'Open Badminton Championship',
        kind: SeasonKind.tournament,
        status: TournamentStatus.entriesOpen,
      );
      await pump(
        tester,
        overrides: common(
          uid: 'uid_visitor',
          memberships: const [],
          tournament: tournament,
          // The only draw taking entries in this fixture is `cri`; `tt` is a
          // draft. So an entry in `cri` leaves nothing open to enter.
          entered: {'$host/cri'},
        ),
        location: '/org/$host/tournaments/$tid',
      );
      expect(find.text('Already registered'), findsOneWidget);
      expect(find.text('Register for this tournament'), findsNothing);
    });

    // Half in. The button has to stay — there is still a draw to enter — but
    // it must stop pretending nothing has happened yet.
    testWidgets('with one draw entered and another open, it counts both',
        (tester) async {
      await pump(
        tester,
        overrides: common(
          uid: 'uid_visitor',
          memberships: const [],
          entered: {'$host/cri'},
          tournament: const Tournament(
            id: tid,
            orgId: host,
            name: 'Summer Season',
            status: TournamentStatus.entriesOpen,
          ),
        ),
        location: '/org/$host/tournaments/$tid',
      );
      expect(find.text('Already registered'), findsOneWidget);
    });

    testWidgets('its organizers get Invite clubs on the desk',
        (tester) async {
      await pump(
        tester,
        overrides: common(
          uid: 'uid_owner',
          memberships: [member('uid_owner', host, MembershipRole.owner)],
        ),
        location: '/org/$host/tournaments/$tid/desk',
      );
      expect(find.text('Invite clubs'), findsOneWidget);
      expect(find.text('Register for this season'), findsNothing);
    });
  });
}

class _Directory extends DiscoveryRepository {
  const _Directory(this.clubs);

  final List<Organization> clubs;

  @override
  Stream<List<Organization>> watchPublicClubs({
    int limit = DiscoveryRepository.maxClubsScanned,
  }) =>
      Stream.value(clubs);
}
