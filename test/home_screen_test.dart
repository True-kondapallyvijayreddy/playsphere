import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/challenge.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/scoring_request.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/career_repository.dart';
import 'package:playsphere/features/home/home_screen.dart';
import 'package:playsphere/shared/live_dot.dart';
import 'package:playsphere/shared/module_drawer.dart';
import 'package:playsphere/shared/playsphere_logo.dart';

/// Covers the screen every signed-in member now lands on.
///
/// It is the first screen that reads across CLUBS rather than inside one, so
/// the thing worth pinning down is that a person in two clubs sees both, and
/// that a person in none is told what to do about it rather than shown an
/// empty page.
void main() {
  const orgA = 'org_school';
  const orgB = 'org_academy';

  const school = Organization(
    id: orgA,
    name: 'Nizampet High School',
    orgType: OrgType.school,
    visibility: OrgVisibility.public,
    ownerUid: 'uid_me',
    inviteCode: 'ABC234',
    memberCount: 42,
  );

  const academy = Organization(
    id: orgB,
    name: 'Kompally Sports Academy',
    orgType: OrgType.academy,
    visibility: OrgVisibility.unlisted,
    ownerUid: 'uid_other',
    inviteCode: 'XYZ789',
    memberCount: 18,
  );

  final me = AppUser(
    uid: 'uid_me',
    displayName: 'Ravi Kumar',
    email: 'ravi@example.com',
    dateOfBirth: DateTime(2004, 5, 20),
    gender: Gender.male,
    profileComplete: true,
  );

  Membership membership(String orgId, MembershipRole role) => Membership(
        uid: 'uid_me',
        orgId: orgId,
        role: role,
        status: MembershipStatus.active,
        displayName: 'Ravi Kumar',
        joinedAt: DateTime(2025, 1, 1),
      );

  const liveMatch = Fixture(
    id: 'fx1',
    orgId: orgA,
    compId: 'comp1',
    entrantAId: 'a',
    entrantBId: 'b',
    entrantAName: 'Blue House',
    entrantBName: 'Red House',
    status: FixtureStatus.live,
    roundLabel: 'Semi-final',
  );

  ScoringRequest scoringRequest(String orgId) => ScoringRequest(
        uid: 'uid_umpire',
        orgId: orgId,
        compId: 'comp1',
        fixtureId: 'fx1',
        displayName: 'Lakshmi N',
        matchLabel: 'Blue House v Red House',
        status: ScoringRequestStatus.pending,
        note: 'I am the umpire today',
      );

  Widget harness({
    required List<Membership> memberships,
    List<Fixture> live = const [],
    List<Competition> competitions = const [],
    List<ScoringRequest> scoringRequests = const [],
  }) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        // Destinations the dashboard links to. Each renders its own path so a
        // test can assert WHERE a tap landed, not merely that it did not
        // crash.
        for (final path in [
          '/orgs',
          '/orgs/join',
          '/orgs/new',
          '/me',
          '/org/:orgId',
          '/org/:orgId/live',
        ])
          GoRoute(
            path: path,
            builder: (_, state) => Scaffold(
              body: Center(child: Text('AT ${state.uri.path}')),
            ),
          ),
      ],
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('uid_me'),
        currentUserProvider.overrideWith((ref) => Stream.value(me)),
        myMembershipsProvider.overrideWith((ref) => Stream.value(memberships)),
        organizationProvider.overrideWith(
          (ref, id) => Stream.value(id == orgA ? school : academy),
        ),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(
            id == orgA ? MembershipRole.member : MembershipRole.eventManager,
          ),
        ),
        competitionsProvider.overrideWith((ref, id) => Stream.value(competitions)),
        liveFixturesProvider.overrideWith(
          (ref, id) => Stream.value(id == orgA ? live : const []),
        ),
        pendingMembersProvider.overrideWith((ref, id) => Stream.value(const [])),
        incomingChallengesProvider.overrideWith(
          (ref, id) => const AsyncValue<List<Challenge>>.data([]),
        ),
        myScoringAssignmentsProvider.overrideWith(
          (ref) => Stream.value(const <Fixture>[]),
        ),
        careerProvider.overrideWith(
          (ref, uid) => Stream.value(const <CareerLine>[]),
        ),
        playerMemoriesProvider.overrideWith((ref, uid) => Stream.value(const [])),
        pendingScoringRequestsProvider.overrideWith(
          (ref, id) => Stream.value(scoringRequests),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Advances past any entry animation without requiring the tree to go
  /// still.
  ///
  /// `pumpAndSettle` cannot be used on this screen: a live match shows a
  /// [LiveDot], which pulses for as long as the match is live and so never
  /// settles by design. One long pump reaches the end state of the finite
  /// animations — the drawer slide, ink, route transitions — which is all
  /// these tests are waiting for.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Tall enough for the whole module menu to be laid out at once.
  ///
  /// The menu is a `ListView`, so its off-screen entries have no elements and
  /// no finder can see them. Without the room, "is this module offered?" and
  /// "is it merely below the fold?" are the same result — which is how the
  /// menu tests came to be passing against the dashboard's Explore grid
  /// instead of against the menu.
  const drawerView = Size(420, 1600);

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await settle(tester);
  }

  /// Scoped deliberately: the dashboard behind the open drawer carries tiles
  /// with several of the same labels, so an unscoped `find.text` proves
  /// nothing about the menu.
  Finder inDrawer(String label) => find.descendant(
        of: find.byType(ModuleDrawer),
        matching: find.text(label),
      );

  Future<void> pump(
    WidgetTester tester,
    Widget widget, {
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await settle(tester);
  }

  testWidgets('greets the member and lists every club they belong to',
      (tester) async {
    await pump(
      tester,
      harness(
        memberships: [
          membership(orgA, MembershipRole.member),
          membership(orgB, MembershipRole.eventManager),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ravi'), findsWidgets);
    expect(find.text('Nizampet High School'), findsOneWidget);
    expect(find.text('Kompally Sports Academy'), findsOneWidget);

    // The brand and the account button are the two fixed points of the shell.
    // The wordmark is a two-span rich text so "Play" and "Sphere" can be
    // coloured differently; `find.text` reads through to the plain text, so
    // it matches the one in the app bar.
    expect(find.byType(PlaySphereLogo), findsOneWidget);
    expect(find.text('PlaySphere'), findsOneWidget);
    expect(find.byTooltip('You and your clubs'), findsOneWidget);
  });

  testWidgets('surfaces a live match from any of the clubs', (tester) async {
    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        live: const [liveMatch],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Blue House'), findsOneWidget);
    expect(find.text('Red House'), findsOneWidget);
    expect(find.text('1 LIVE'), findsOneWidget);
    expect(find.textContaining('being played right now'), findsWidgets);
    expect(find.byType(LiveDot), findsWidgets);
  });

  testWidgets('tells a member with no club what to do about it',
      (tester) async {
    await pump(tester, harness(memberships: const []));

    expect(tester.takeException(), isNull);
    expect(find.text('You are not in a club yet'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    // Scoped to the card: "Create a club" is also a standing quick-action
    // chip, so an unscoped finder matches twice and says nothing about
    // whether the card that explains the situation is on screen.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('You are not in a club yet'),
          matching: find.byType(Card),
        ),
        matching: find.text('Create a club'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the three-lines menu carries the modules that are not on the bar',
      (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgB, MembershipRole.eventManager)]),
      size: drawerView,
    );

    await openMenu(tester);

    expect(inDrawer('Rules library'), findsOneWidget);
    expect(inDrawer('Looking for'), findsOneWidget);
    expect(inDrawer('Umpire & scorer registry'), findsOneWidget);
    // An event manager holds viewAnalytics, so it is offered.
    expect(inDrawer('Analytics'), findsOneWidget);
    expect(find.text('Kompally Sports Academy'), findsWidgets);
  });

  testWidgets('a member without analytics rights is not offered analytics',
      (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
      size: drawerView,
    );

    await openMenu(tester);

    expect(inDrawer('Analytics'), findsNothing);
    // The dashboard's own Explore grid must not leak it either — that grid
    // carries a tile of the same name behind the open drawer, which is what
    // made the scoped finder above necessary in the first place.
    expect(find.text('Analytics'), findsNothing);
    expect(inDrawer('Rules library'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The counters and the Explore tiles: small, and each one a door.
  // -------------------------------------------------------------------------

  /// The card a given label sits in — how these tests measure a tile without
  /// reaching for a private widget type.
  Finder cardAround(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(Card),
      );

  testWidgets('the counters open the page each one is counting',
      (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    await tester.tap(find.text('Clubs'));
    await settle(tester);
    expect(find.text('AT /orgs'), findsOneWidget);
  });

  testWidgets('a counter with a club behind it opens that club',
      (tester) async {
    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        live: const [liveMatch],
      ),
    );

    await tester.tap(find.text('Live now').first);
    await settle(tester);
    expect(find.text('AT /org/$orgA/live'), findsOneWidget);
  });

  testWidgets('the career counters open the career profile', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    await tester.tap(find.text('Matches'));
    await settle(tester);
    expect(find.text('AT /me'), findsOneWidget);
  });

  testWidgets('a counter with no club behind it goes nowhere', (tester) async {
    await pump(tester, harness(memberships: const []));

    // "Events" is club-scoped, and this person has no club for it to point
    // at. It still shows its zero; it just must not navigate into a route
    // built from a club id that does not exist.
    await tester.tap(find.text('Events'));
    await settle(tester);

    expect(find.textContaining('AT '), findsNothing);
    expect(find.text('Events'), findsOneWidget);
  });

  testWidgets('the dashboard tiles stay compact on a phone', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    // Guards the regression this replaced: AdaptiveGrid sized tiles by
    // width:height ratio, so dropping to one column on a phone made each
    // Explore tile 162px tall and the counters ran to three rows. Heights
    // here are the fixed extents, not ratios, so they hold at every width.
    expect(tester.getSize(cardAround('Clubs')).height, lessThanOrEqualTo(84));
    expect(
      tester.getSize(cardAround('Rules library')).height,
      lessThanOrEqualTo(70),
    );
  });

  testWidgets('an Explore tile opens its page', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    await tester.scrollUntilVisible(
      find.text('Career profile'),
      200,
      // Named explicitly: the counters and the Explore grid are themselves
      // scrollables, so an unqualified search finds several.
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible stops as soon as any part of the tile is in the
    // viewport, which can leave its centre — where tap aims — off-screen.
    await tester.ensureVisible(find.text('Career profile'));
    await settle(tester);

    await tester.tap(find.text('Career profile'));
    await settle(tester);

    expect(find.text('AT /me'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Somebody asking to score, and the admin answering without leaving home.
  // -------------------------------------------------------------------------

  testWidgets('shows an admin who is waiting to score, and what they said',
      (tester) async {
    await pump(
      tester,
      harness(
        // orgB is the event-manager membership, so this person can grant it.
        memberships: [membership(orgB, MembershipRole.eventManager)],
        scoringRequests: [scoringRequest(orgB)],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Waiting on you'), findsOneWidget);
    expect(find.text('Lakshmi N wants to score'), findsOneWidget);
    expect(find.text('Blue House v Red House'), findsWidgets);
    expect(find.textContaining('I am the umpire today'), findsOneWidget);
    expect(find.text('Let them score'), findsOneWidget);
  });

  testWidgets('does not put a request in front of someone who cannot grant it',
      (tester) async {
    // orgA is a plain membership. Showing an approval prompt to a member who
    // would only get a permission error is worse than showing nothing.
    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        scoringRequests: [scoringRequest(orgA)],
      ),
    );

    expect(find.text('Lakshmi N wants to score'), findsNothing);
    expect(find.text('Waiting on you'), findsNothing);
  });

  testWidgets('renders on a laptop window with the rail', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
      size: const Size(1400, 950),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Nizampet High School'), findsWidgets);
  });
}
