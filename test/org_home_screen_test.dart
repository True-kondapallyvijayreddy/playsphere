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
import 'package:playsphere/features/orgs/widgets/club_sections_grid.dart';

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
    MembershipRole role = MembershipRole.owner,
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
          (ref, id) => PermissionMatrix.capabilitiesOf(role),
        ),
        competitionsProvider.overrideWith((ref, id) => Stream.value(competitions)),
        liveFixturesProvider.overrideWith((ref, id) => Stream.value(<Fixture>[])),
        pendingMembersProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    List<Competition> comps, {
    MembershipRole role = MembershipRole.owner,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(competitions: comps, surface: size, role: role),
    );
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

  // -------------------------------------------------------------------------
  // The club's own index.
  //
  // These screens used to be reachable from two places, neither of them this
  // one: four of them from the bottom bar, and the rest from a drawer hanging
  // off every route in the app. The drawer was the defect — it was a GLOBAL
  // menu holding CLUB-scoped links, pointed at whichever club the person had
  // joined most recently, so opening club B and tapping Gallery showed club
  // A's photographs. The drawer is gone and its club half is here, where
  // `orgId` is the club on screen and cannot be anything else.
  // -------------------------------------------------------------------------

  group('the club carries its own sections', () {
    /// Tall enough for the whole page to lay out: the grid is inside a
    /// `ListView`, so a tile below the fold has no element and no finder can
    /// see it.
    const tall = Size(420, 2400);

    Finder inGrid(String label) => find.descendant(
          of: find.byType(ClubSectionsGrid),
          matching: find.text(label),
        );

    testWidgets('every section of this club, on this club', (tester) async {
      await pumpAt(tester, tall, const []);

      for (final label in [
        'Tournaments',
        'Members',
        'Gallery',
        'Rankings',
        'Venues',
        'Files',
        'Store',
      ]) {
        expect(inGrid(label), findsOneWidget, reason: '$label lost its door');
      }
    });

    testWidgets('and does not repeat what the bar already carries',
        (tester) async {
      // The two the bottom bar holds for the whole time you are inside a
      // club. Drawing them again eighty pixels below the bar is exactly the
      // clutter this change exists to remove.
      await pumpAt(tester, tall, const []);

      expect(inGrid('Live now'), findsNothing);
      expect(inGrid('Challenges'), findsNothing);
      // Still on the bar, though — removed from the grid, not from the app.
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Challenges'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('nor what the buttons and the app bar already carry',
        (tester) async {
      await pumpAt(tester, tall, const []);

      // The extended FAB, the gear in the app bar.
      expect(inGrid('New event'), findsNothing);
      expect(inGrid('Club settings'), findsNothing);
      expect(find.text('New event'), findsOneWidget);
    });

    testWidgets('analytics is hidden from a member who cannot see it',
        (tester) async {
      await pumpAt(tester, tall, const [], role: MembershipRole.member);

      expect(inGrid('Analytics'), findsNothing);
      expect(find.text('Analytics'), findsNothing);
      // The rest of the grid is untouched.
      expect(inGrid('Gallery'), findsOneWidget);
    });

    testWidgets('an owner does see analytics', (tester) async {
      await pumpAt(tester, tall, const []);
      expect(inGrid('Analytics'), findsOneWidget);
    });

    testWidgets('and survives a club whose document will not load',
        (tester) async {
      // The grid sits outside `_ClubHeader`, which draws nothing without a
      // loaded Organization. Since the app-wide drawer was removed these are
      // the only doors to this club's gallery, files and venues, so a slow or
      // unreadable club document must not take them with it.
      tester.view.physicalSize = tall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('uid_owner'),
            // Never emits: the club document has not arrived.
            organizationProvider.overrideWith(
              (ref, id) => const Stream<Organization?>.empty(),
            ),
            myCapabilitiesProvider.overrideWith(
              (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
            ),
            competitionsProvider.overrideWith(
              (ref, id) => Stream.value(const <Competition>[]),
            ),
            liveFixturesProvider.overrideWith(
              (ref, id) => Stream.value(<Fixture>[]),
            ),
            pendingMembersProvider.overrideWith(
              (ref, id) => Stream.value(const []),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/org/$orgId',
              routes: [
                GoRoute(
                  path: '/org/:orgId',
                  builder: (_, state) =>
                      OrgHomeScreen(orgId: state.pathParameters['orgId']!),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Sports Club'), findsNothing);
      expect(inGrid('Gallery'), findsOneWidget);
      expect(inGrid('Files'), findsOneWidget);
    });
  });
}
