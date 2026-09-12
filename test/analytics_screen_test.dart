import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/analytics/analytics_screen.dart';

/// The analytics screen, on the screen size it is actually read on.
///
/// Two things this pins. The first is that every number leads somewhere: the
/// screen used to be six inert tiles and five bar charts, so an organizer who
/// spotted a wrong number had to go and find the list it came from by hand.
/// The second is that the tiles fit — they now carry a hint line under the
/// label, and a KPI grid sized by width:height ratio rather than by height is
/// exactly how a tile that looks right four-up on a laptop overflows two-up on
/// a phone.
void main() {
  const orgId = 'org_test';

  const organization = Organization(
    id: orgId,
    name: 'Test Sports Club',
    orgType: OrgType.school,
    visibility: OrgVisibility.public,
    ownerUid: 'uid_owner',
    inviteCode: 'ABC234',
  );

  const comp = Competition(
    id: 'c1',
    orgId: orgId,
    name: 'Inter-house Badminton',
    sportId: 'badminton',
    sportName: 'Badminton',
    archetype: CompetitionArchetype.versus,
    entrantType: EntrantType.individual,
    format: CompetitionFormat.roundRobin,
    status: CompetitionStatus.registrationOpen,
    category: CompetitionCategory(label: 'Open'),
    scoringPluginKey: 'set_based',
    entrantCount: 24,
    fixtureCount: 12,
  );

  final members = [
    for (var i = 1; i <= 6; i++)
      Membership(
        uid: 'm$i',
        orgId: orgId,
        displayName: 'Member $i',
        role: MembershipRole.member,
        status: MembershipStatus.active,
        joinedAt: DateTime.now().subtract(Duration(days: i * 3)),
      ),
    const Membership(
      uid: 'p1',
      orgId: orgId,
      displayName: 'Hopeful',
      role: MembershipRole.member,
      status: MembershipStatus.pending,
    ),
  ];

  String? pushedTo;

  Widget harness({required List<Membership> roster}) {
    final router = GoRouter(
      initialLocation: '/org/$orgId/analytics',
      routes: [
        GoRoute(
          path: '/org/:orgId/analytics',
          builder: (_, state) =>
              AnalyticsScreen(orgId: state.pathParameters['orgId']!),
        ),
        // Every destination the screen can send somebody to, collapsed into
        // one recording page — the assertion is that the tap LANDS, not what
        // the destination renders.
        GoRoute(
          path: '/org/:orgId/members',
          builder: (_, state) {
            pushedTo = state.uri.path;
            return const Scaffold(body: Text('roster'));
          },
        ),
        GoRoute(
          path: '/org/:orgId/live',
          builder: (_, state) {
            pushedTo = state.uri.path;
            return const Scaffold(body: Text('live'));
          },
        ),
        GoRoute(
          path: '/org/:orgId/stats/:sportId',
          builder: (_, state) {
            pushedTo = state.uri.path;
            return const Scaffold(body: Text('sport record'));
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('uid_owner'),
        organizationProvider
            .overrideWith((ref, id) => Stream.value(organization)),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        ),
        competitionsProvider.overrideWith((ref, id) => Stream.value([comp])),
        liveFixturesProvider.overrideWith((ref, id) => Stream.value(<Fixture>[])),
        orgMembersProvider.overrideWith((ref, id) => Stream.value(roster)),
        pendingMembersProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    List<Membership>? roster,
  }) async {
    pushedTo = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(roster: roster ?? members));
    await tester.pumpAndSettle();
  }

  group('AnalyticsScreen lays out without overflowing', () {
    testWidgets('on a phone', (tester) async {
      // 390x844 is an iPhone, which is what a village club secretary reads
      // this on. A KPI tile that overflows here shows a yellow-and-black
      // stripe over the number.
      await pumpAt(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
      expect(find.text('Active members'), findsOneWidget);
    });

    testWidgets('on a laptop', (tester) async {
      await pumpAt(tester, const Size(1400, 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with an empty club', (tester) async {
      // No members, no entries: every breakdown falls to its empty line and
      // the pending banner must not appear at all.
      await pumpAt(tester, const Size(390, 844), roster: const []);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('waiting to join'), findsNothing);
    });
  });

  group('every number opens the list it was counted from', () {
    testWidgets('the members tile opens the roster', (tester) async {
      await pumpAt(tester, const Size(1400, 900));

      await tester.tap(find.text('Active members'));
      await tester.pumpAndSettle();

      expect(pushedTo, '/org/$orgId/members');
    });

    testWidgets('the live tile opens live matches', (tester) async {
      await pumpAt(tester, const Size(1400, 900));

      await tester.tap(find.text('Live right now'));
      await tester.pumpAndSettle();

      expect(pushedTo, '/org/$orgId/live');
    });

    testWidgets('a sport bar opens that sport\'s record', (tester) async {
      await pumpAt(tester, const Size(1400, 900));

      // The bar is labelled with the catalogue's icon and name, so match on
      // the name rather than on the whole string.
      await tester.tap(find.textContaining('Badminton').last);
      await tester.pumpAndSettle();

      expect(pushedTo, '/org/$orgId/stats/badminton');
    });
  });

  group('a pending join request is not just another tile', () {
    testWidgets('it is promoted to a banner of its own', (tester) async {
      await pumpAt(tester, const Size(1400, 900));

      expect(find.textContaining('waiting to join'), findsWidgets);

      await tester.tap(find.textContaining('1 person is waiting to join'));
      await tester.pumpAndSettle();
      expect(pushedTo, '/org/$orgId/members');
    });
  });
}
