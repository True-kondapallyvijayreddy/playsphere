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
import 'package:playsphere/features/orgs/org_home_screen.dart';

/// Renders the organization home screen the way a freshly-created club sees
/// it — no competitions, no fixtures, no pending members.
///
/// This is the screen a founder lands on immediately after creating a club,
/// and it is the first screen in the app to use [AppScaffold], so it is the
/// first to build a NavigationRail. Nothing else covered it: the Dart suite
/// was pure domain logic and the rules suite only exercises Firestore.
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

  Widget harness({
    required List<Competition> competitions,
    required Size surface,
  }) {
    final router = GoRouter(
      initialLocation: '/org/$orgId',
      routes: [
        GoRoute(
          path: '/org/:orgId',
          builder: (_, state) =>
              OrgHomeScreen(orgId: state.pathParameters['orgId']!),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('uid_owner'),
        organizationProvider.overrideWith((ref, id) => Stream.value(organization)),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        ),
        competitionsProvider.overrideWith((ref, id) => Stream.value(competitions)),
        liveFixturesProvider.overrideWith((ref, id) => Stream.value(<Fixture>[])),
        pendingMembersProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Size size, List<Competition> comps) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(competitions: comps, surface: size));
    await tester.pumpAndSettle();
  }

  group('OrgHomeScreen renders without throwing', () {
    testWidgets('on a wide window — the NavigationRail layout', (tester) async {
      // 1400x900 is a laptop browser, which is what a founder actually uses
      // and the layout branch that had never been exercised.
      await pumpAt(tester, const Size(1400, 900), const []);

      expect(tester.takeException(), isNull);
      expect(find.text('No events yet'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('on a medium window — the collapsed rail', (tester) async {
      await pumpAt(tester, const Size(800, 900), const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('on a phone window — the bottom navigation layout', (tester) async {
      await pumpAt(tester, const Size(420, 900), const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('with competitions present', (tester) async {
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
      );
      await pumpAt(tester, const Size(1400, 900), [comp]);

      expect(tester.takeException(), isNull);
      expect(find.text('Inter-house Badminton'), findsOneWidget);
    });
  });
}
