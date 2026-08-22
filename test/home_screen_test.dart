import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/errors/app_exception.dart';
import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/challenge.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/scoring_request.dart';
import 'package:playsphere/core/notifications/notification_model.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/career_repository.dart';
import 'package:playsphere/features/home/home_screen.dart';
import 'package:playsphere/features/notifications/notifications_screen.dart';
import 'package:playsphere/shared/account_button.dart';
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
    /// Clubs whose live-fixtures read is refused, to exercise Bug #4.
    Set<String> liveReadFailsFor = const {},
  }) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        // The real screen, not a stub: what used to sit in the middle of the
        // dashboard now lives here, and these tests still have to prove it
        // reaches the person it is waiting on.
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        // Destinations the dashboard links to. Each renders its own path so a
        // test can assert WHERE a tap landed, not merely that it did not
        // crash.
        for (final path in [
          '/orgs',
          '/orgs/join',
          '/orgs/new',
          '/me',
          // Matches and Sports are separate destinations. They both used to
          // resolve to '/me', which is exactly what these routes now prove
          // they no longer do (Bug #2).
          '/me/matches',
          '/me/sports',
          '/org/:orgId',
          '/org/:orgId/live',
          '/live',
          '/events/mine',
          // The dashboard's own doors: the sport directory behind "Explore
          // sport", the RSVP page the RSVP counter opens, and the career
          // profile the Explore list links to.
          '/sports',
          '/rsvp',
          '/player/:uid',
          '/scout/search',
          '/grounds',
          '/events',
          '/sponsor',
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
          (ref, id) => liveReadFailsFor.contains(id)
              ? Stream<List<Fixture>>.error(
                  const PermissionDeniedException(),
                  StackTrace.empty,
                )
              : Stream.value(id == orgA ? live : const []),
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
        // The durable activity feed behind the bell and the Notifications
        // screen — see NotificationRepository. Left un-mocked this reaches
        // real Firestore, which is not initialised under `flutter test`.
        myNotificationFeedProvider.overrideWith(
          (ref) => Stream.value(const <AppNotification>[]),
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
  const drawerView = Size(420, 2200);

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

  /// Scrolls the drawer until [label] is built.
  ///
  /// The drawer is a `ListView`, so it only builds what is on screen — an
  /// entry below the fold genuinely does not exist in the tree yet. As modules
  /// are added the list outgrows a phone viewport, which is what the scrolling
  /// is for rather than a sign anything overflowed.
  Future<void> scrollToInDrawer(WidgetTester tester, String label) async {
    await tester.dragUntilVisible(
      inDrawer(label),
      find
          .descendant(
            of: find.byType(ModuleDrawer),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -120),
    );
    await settle(tester);
  }

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

  testWidgets(
      'shows the date and the claim, and carries counts rather than lists',
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
    // Deliberately no "Good morning/evening, Ravi" salutation — it used to
    // be the single largest thing on the dashboard for a fact the member
    // already knows.
    expect(find.textContaining('Ravi'), findsNothing);
    expect(find.textContaining('Good '), findsNothing);
    expect(find.text('ALL SPORTS. ONE OS.'), findsOneWidget);

    // The dashboard holds COUNTS, not lists. Two clubs produce a "2" on the
    // Clubs tile and no club cards at all — the list belongs on /orgs, where
    // it has room to be complete. This is the whole shape of the screen and
    // the reason it fits above the fold.
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Nizampet High School'), findsNothing);
    expect(find.text('Kompally Sports Academy'), findsNothing);

    // The brand and the account button are the two fixed points of the shell.
    // The wordmark is a two-span rich text so "Play" and "Sphere" can be
    // coloured differently; `find.text` reads through to the plain text, so
    // it matches the one in the app bar.
    expect(find.byType(PlaySphereLogo), findsOneWidget);
    expect(find.text('PlaySphere'), findsOneWidget);
    expect(find.byTooltip('You and your clubs'), findsOneWidget);
  });

  testWidgets('counts a live match rather than drawing its scorecard',
      (tester) async {
    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        live: const [liveMatch],
      ),
    );

    expect(tester.takeException(), isNull);
    // The scorecard itself lives on /live. What belongs here is the fact
    // that there IS one, which is a number and a dot.
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('in progress'), findsOneWidget);
    expect(find.byType(LiveDot), findsWidgets);
    expect(find.text('Blue House'), findsNothing);
  });

  testWidgets('a member with no club still gets a usable dashboard',
      (tester) async {
    await pump(tester, harness(memberships: const []));

    expect(tester.takeException(), isNull);
    // The "You are not in a club yet" card is gone with the rest of the
    // lists. What replaces it is not an explanation but a way in: the two
    // primary actions are on screen whether or not this person has a club,
    // and Explore is the one that works without one.
    expect(find.text('Explore sport'), findsOneWidget);
    expect(find.text('Play sport'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
  });

  testWidgets('the three-lines menu carries the modules that are not on the bar',
      (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgB, MembershipRole.eventManager)]),
      size: drawerView,
    );

    await openMenu(tester);

    expect(inDrawer('Looking for'), findsOneWidget);
    expect(inDrawer('Coaches'), findsOneWidget);
    expect(inDrawer('Umpire & scorer registry'), findsOneWidget);
    expect(inDrawer('Rules library'), findsOneWidget);
    // An event manager holds viewAnalytics, so it is offered — below the fold
    // now that the drawer carries rankings, tournaments and venues too.
    await scrollToInDrawer(tester, 'Analytics');
    expect(inDrawer('Analytics'), findsOneWidget);
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

  /// The tappable tile a given label sits in — how these tests measure and
  /// tap a tile without reaching for a private widget type.
  ///
  /// Every counter and every Explore row is an `InkWell`, so this is the same
  /// helper for both. It was a `Card` ancestor scoped to an `AdaptiveGrid`
  /// when the dashboard was a grid of cards; neither is on the screen any
  /// more, which is why every test using it had gone stale.
  Finder tileAround(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .first;

  /// The counter tile with this label.
  ///
  /// A bare `find.text` is enough now: the dashboard holds counts rather than
  /// lists, so no heading duplicates a counter's label. The scoped version
  /// existed because "Live now" was both a counter and the heading over a
  /// live ticker that no longer exists.
  Finder statTile(String label) => find.text(label);

  /// Taps a counter, scrolling it into view first.
  Future<void> tapStatTile(WidgetTester tester, String label) async {
    final tile = statTile(label);
    await tester.ensureVisible(tile);
    // settle(), not pumpAndSettle(): the live dot pulses for as long as a
    // match is live, so there is no frame at which the tree goes quiet.
    await settle(tester);
    await tester.tap(tile);
  }

  testWidgets('the counters open the page each one is counting',
      (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    await tapStatTile(tester, 'Clubs');
    await settle(tester);
    expect(find.text('AT /orgs'), findsOneWidget);
  });

  // The "Live now" counter is a sum across every club, not one club's own —
  // so unlike a per-club tile it opens the cross-club Live Now hub rather
  // than any single organization's live page.
  testWidgets('the Live now counter opens the cross-club live hub',
      (tester) async {
    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        live: const [liveMatch],
      ),
    );

    await tapStatTile(tester, 'Live');
    await settle(tester);
    expect(find.text('AT /live'), findsOneWidget);
  });

  // A member with a lot going on at once must not have live scorecards push
  // clubs, events and the rest of the dashboard off several screens' worth
  // of scrolling. The preview stops at three; everything past that is one
  // tap away on the cross-club hub rather than simply missing.
  // A member with a lot going on at once must not have live scorecards push
  // the rest of the dashboard off several screens' worth of scrolling. The
  // dashboard holds the COUNT; the matches themselves are one tap away on the
  // cross-club hub. This used to be a three-card preview with a "More" link,
  // which is the shape that made the screen two and a half screenfuls long.
  testWidgets('five live matches are a count, not five cards', (tester) async {
    final live = [
      for (var i = 0; i < 5; i++)
        Fixture(
          id: 'fx$i',
          orgId: orgA,
          compId: 'comp1',
          entrantAId: 'a$i',
          entrantBId: 'b$i',
          entrantAName: 'Team A$i',
          entrantBName: 'Team B$i',
          status: FixtureStatus.live,
        ),
    ];

    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        live: live,
      ),
    );
    await settle(tester);

    // Not one entrant name anywhere. The scorecards live on /live.
    for (var i = 0; i < 5; i++) {
      expect(find.text('Team A$i'), findsNothing);
    }
    // Scoped to the tile. The bottom bar's "Live now" item carries the same
    // number as its own badge, which is correct and not what this is about.
    expect(
      find.descendant(of: tileAround('Live'), matching: find.text('5')),
      findsOneWidget,
    );
    expect(find.text('in progress'), findsOneWidget);
    // No "More" link under a preview list, because there is no preview list.
    // Scoped to the dashboard itself: the bottom bar has a "More" tab, which
    // is the module menu and not what this is guarding.
    expect(
      find.descendant(
        of: find.byType(ListView).first,
        matching: find.textContaining('More'),
      ),
      findsNothing,
    );
  });

  testWidgets('counts only the events that are open for entry', (tester) async {
    Competition comp(String id, CompetitionStatus status) => Competition(
          id: id,
          orgId: orgA,
          name: 'Event $id',
          sportId: 'badminton',
          sportName: 'Badminton',
          archetype: CompetitionArchetype.versus,
          entrantType: EntrantType.individual,
          format: CompetitionFormat.roundRobin,
          status: status,
          category: const CompetitionCategory(label: 'Open'),
          scoringPluginKey: 'set_based',
        );

    final competitions = [
      for (var i = 0; i < 6; i++)
        comp('open$i', CompetitionStatus.registrationOpen),
      comp('running', CompetitionStatus.inProgress),
      comp('later', CompetitionStatus.scheduled),
    ];

    await pump(
      tester,
      harness(
        memberships: [membership(orgA, MembershipRole.member)],
        competitions: competitions,
      ),
    );
    await settle(tester);

    // No event names at all — the list belongs on /events/mine. What is here
    // is the six that are open, and not the running or scheduled ones.
    expect(find.textContaining('Event open'), findsNothing);
    expect(find.text('Event running'), findsNothing);
    expect(find.text('Event later'), findsNothing);
    expect(find.text('6'), findsOneWidget);

    await tapStatTile(tester, 'Events');
    await settle(tester);
    expect(find.text('AT /events/mine'), findsOneWidget);
  });

  // Bug #2. These two tiles carry different labels and different numbers, and
  // both used to push '/me' — so tapping either landed on the career profile
  // and neither showed the thing it had just counted. The point of the pair
  // of tests is that they now land in DIFFERENT places.
  testWidgets('the Matches counter opens the matches list', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    await tapStatTile(tester, 'Matches');
    await settle(tester);

    expect(find.text('AT /me/matches'), findsOneWidget);
    expect(find.text('AT /me'), findsNothing);
  });

  testWidgets('the Sports counter opens the sports list', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    // The label is singular at a count of one, which is what this fixture
    // has — the tile helper matches on whatever is rendered.
    await tapStatTile(tester, 'Sports');
    await settle(tester);

    expect(find.text('AT /me/sports'), findsOneWidget);
    expect(find.text('AT /me/matches'), findsNothing);
  });

  testWidgets('a counter with no club behind it goes nowhere', (tester) async {
    await pump(tester, harness(memberships: const []));

    // "Events" is club-scoped, and this person has no club for it to point
    // at. It still shows its zero; it just must not navigate into a route
    // built from a club id that does not exist.
    await tapStatTile(tester, 'Events');
    await settle(tester);

    // `'AT /'` and not `'AT '`: the hero renders the date in caps, so on any
    // Saturday "SAT 22 AUG" matched the looser probe and this test failed
    // once a week for reasons that had nothing to do with routing.
    expect(find.textContaining('AT /'), findsNothing);
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
    expect(tester.getSize(tileAround('Clubs')).height, lessThanOrEqualTo(96));

    // Three across on a phone, so six counters are two rows rather than six.
    // Measured off the tile rather than asserted as a column count, because
    // the width is what a wrapped fourth tile would give away.
    final grid = tester.getSize(
      find.ancestor(of: find.text('Clubs'), matching: find.byType(Wrap)).first,
    );
    expect(
      tester.getSize(tileAround('Clubs')).width,
      lessThan(grid.width / 2),
    );

    // An Explore row is a ListTile, not a 162px card.
    expect(
      tester.getSize(tileAround('Career profile')).height,
      lessThanOrEqualTo(80),
    );
  });

  testWidgets('the Rules library is in the menu, not on the dashboard',
      (tester) async {
    // Bug #7: reference material somebody opens once a season was taking a
    // tile in the most valuable space in the app, duplicating a module-menu
    // entry that was already there.
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
      size: drawerView,
    );

    expect(find.text('Rules library'), findsNothing);

    await openMenu(tester);
    expect(inDrawer('Rules library'), findsOneWidget);
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
  // Somebody asking to score, and the admin answering from the bell.
  //
  // These obligations used to sit in the middle of the dashboard. They now
  // live behind the notification bell, so what these tests pin down is that
  // moving them did not lose them: the dashboard stays clear, the bell says
  // how many are waiting, and the request is still answerable in one tap.
  // -------------------------------------------------------------------------

  Future<void> openBell(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.notifications_outlined).first);
    await settle(tester);
  }

  testWidgets('the dashboard itself no longer carries pending actions',
      (tester) async {
    await pump(
      tester,
      harness(
        memberships: [membership(orgB, MembershipRole.eventManager)],
        scoringRequests: [scoringRequest(orgB)],
      ),
    );

    // Neither the old wording nor the new one belongs on the dashboard —
    // pending actions live behind the bell (Bug #5).
    expect(find.text('Waiting on you'), findsNothing);
    expect(find.text('Needs your action'), findsNothing);
    expect(find.text('Lakshmi N wants to score'), findsNothing);
  });

  testWidgets('the bell sits beside the profile photo', (tester) async {
    // Bug #5 asked for the bell "beside profile Photo on top right". Pinned
    // by horizontal position rather than by reading the widget list, because
    // it is the on-screen adjacency that was asked for.
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
    );

    final bell = tester.getCenter(
      find.byIcon(Icons.notifications_outlined).first,
    );
    final account = tester.getCenter(find.byType(AccountButton).first);

    // Same row, bell immediately to the left of the photo.
    expect(bell.dy, closeTo(account.dy, 4));
    expect(bell.dx, lessThan(account.dx));
    expect(account.dx - bell.dx, lessThan(80));
  });

  testWidgets('the bell counts what is waiting and opens it', (tester) async {
    await pump(
      tester,
      harness(
        // orgB is the event-manager membership, so this person can grant it.
        memberships: [membership(orgB, MembershipRole.eventManager)],
        scoringRequests: [scoringRequest(orgB)],
      ),
    );

    // The badge is the whole reason taking this off the home screen is safe.
    expect(find.widgetWithText(Badge, '1'), findsOneWidget);

    await openBell(tester);

    expect(tester.takeException(), isNull);
    // Reworded: "Waiting on you" named a state without saying what to do
    // about it, which is what users found confusing.
    expect(find.text('Needs your action'), findsOneWidget);
    expect(find.text('Waiting on you'), findsNothing);
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

    // Not merely absent from the dashboard — absent from the bell too, which
    // must not count an obligation this person has no way to discharge.
    expect(find.byType(Badge), findsNothing);

    await openBell(tester);

    expect(find.text('Lakshmi N wants to score'), findsNothing);
    // Combined empty state now that the screen also carries a club-activity
    // feed (empty here, via the override above): "Nothing here yet" covers
    // both, rather than the action-items-only wording that applied before
    // there was a second thing on this screen to be empty.
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  // Bug #4. A person in two clubs used to lose EVERY live match because one
  // club's collection-group read was refused — the screen showed "Could not
  // load live matches" and nothing else.
  group('a club whose live matches cannot be read', () {
    testWidgets('does not take the other clubs down with it', (tester) async {
      await pump(
        tester,
        harness(
          memberships: [
            membership(orgA, MembershipRole.member),
            membership(orgB, MembershipRole.eventManager),
          ],
          live: [liveMatch],
          liveReadFailsFor: {orgB},
        ),
      );

      // The match at the club that DID load is still counted. The dashboard
      // holds counts rather than cards now, so what proves the other club
      // survived is the number — one live match, not a dash.
      expect(
        find.descendant(of: tileAround('Live'), matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.text('Could not load live matches'), findsNothing);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('is reported rather than silently dropped', (tester) async {
      await pump(
        tester,
        harness(
          memberships: [
            membership(orgA, MembershipRole.member),
            membership(orgB, MembershipRole.eventManager),
          ],
          live: [liveMatch],
          liveReadFailsFor: {orgB},
        ),
      );

      // Showing the matches that loaded is only half of it. Quietly dropping
      // a club would tell a player nothing is on at the ground they are
      // standing in, which is the failure the strict combiner existed to
      // prevent — so the notice has to be there too.
      //
      // The notice used to be a full-width banner under a list of live
      // cards. Both are gone, so it is now the tile's own detail line —
      // same promise, one line instead of a section.
      expect(find.text('1 club unavailable'), findsOneWidget);
    });

    testWidgets('every club failing still reports an error', (tester) async {
      await pump(
        tester,
        harness(
          memberships: [membership(orgA, MembershipRole.member)],
          liveReadFailsFor: {orgA},
        ),
      );

      // Nothing loaded at all, so a zero would be a lie — the tile draws an
      // em dash and says why. See `HomeCount.unknown`.
      expect(
        find.descendant(of: tileAround('Live'), matching: find.text('—')),
        findsOneWidget,
      );
      expect(find.text('could not load'), findsOneWidget);
      expect(
        find.descendant(of: tileAround('Live'), matching: find.text('0')),
        findsNothing,
      );
    });
  });

  testWidgets('renders on a laptop window with the rail', (tester) async {
    await pump(
      tester,
      harness(memberships: [membership(orgA, MembershipRole.member)]),
      size: const Size(1400, 950),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
    // The club is a count here, not a name — the dashboard reads the same at
    // 1400pt as on a phone, which is the point of the rail test. The club's
    // name belongs to `/orgs`, one tap away through this tile.
    expect(find.text('Clubs'), findsOneWidget);
    expect(
      find.descendant(of: tileAround('Clubs'), matching: find.text('1')),
      findsOneWidget,
    );
  });
}
