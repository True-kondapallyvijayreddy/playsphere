import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/geo.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/models/player_listing.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/career_repository.dart';
import 'package:playsphere/data/discovery_repository.dart';
import 'package:playsphere/features/discover/discover_screen.dart';
import 'package:playsphere/features/discover/player_listing_edit_screen.dart';

/// The discovery screen, rendered.
///
/// It is the first screen in the app to put a `TabBarView` inside
/// `AppScaffold`'s body — which is itself an `Expanded` inside a `Column` —
/// and an unbounded constraint reaching a `TabBarView` is a blank page rather
/// than an error anybody would notice in review. So this pins the layout as
/// much as the behaviour.
///
/// The filtering itself is covered by `discovery_test.dart` against the pure
/// functions, and the read grants by `test/security/discovery.test.mjs`.
class _FakeDiscovery extends DiscoveryRepository {
  const _FakeDiscovery({
    this.clubs = const [],
    this.listings = const [],
    this.mine,
  });

  final List<Organization> clubs;
  final List<PlayerListing> listings;
  final PlayerListing? mine;

  @override
  Stream<List<Organization>> watchPublicClubs({int limit = 300}) =>
      Stream.value(clubs);

  @override
  Future<List<PlayerListing>> fetchPlayers(DiscoveryQuery query) async =>
      listings;

  @override
  Stream<PlayerListing?> watchMyListing(String uid) => Stream.value(mine);
}

void main() {
  final me = AppUser(
    uid: 'uid_me',
    displayName: 'Asha',
    email: 'asha@example.com',
    dateOfBirth: DateTime(1995, 4, 11),
    gender: Gender.female,
    geo: const GeoLocation(state: 'Telangana', district: 'Warangal'),
  );

  final child = AppUser(
    uid: 'uid_child',
    displayName: 'Ravi',
    email: 'ravi@example.com',
    dateOfBirth: DateTime(2014, 1, 1),
    gender: Gender.male,
  );

  Organization club(String id, String name, {String? district}) => Organization(
        id: id,
        name: name,
        orgType: OrgType.cityClub,
        visibility: OrgVisibility.public,
        ownerUid: 'uid_owner',
        inviteCode: 'ABC234',
        geo: GeoLocation(district: district),
        memberCount: 12,
      );

  PlayerListing person(String uid, String name) => PlayerListing(
        uid: uid,
        displayName: name,
        sportIds: const ['cricket'],
        intents: const [PlayerIntent.club],
        geo: const GeoLocation(state: 'Telangana', district: 'Warangal'),
        matchesPlayed: 8,
      );

  Widget harness({
    required Widget screen,
    _FakeDiscovery repository = const _FakeDiscovery(),
    bool premium = false,
    AppUser? account,
  }) {
    final router = GoRouter(
      initialLocation: '/here',
      routes: [
        GoRoute(path: '/here', builder: (_, __) => screen),
        for (final path in [
          '/org/:orgId',
          '/player/:uid',
          '/me/listing',
          '/premium',
          '/orgs/new',
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
        authUidProvider.overrideWithValue('uid_me'),
        currentUserProvider.overrideWith((ref) => Stream.value(me)),
        authUserProvider.overrideWith((ref) => Stream.value(account ?? me)),
        myMembershipsProvider.overrideWith((ref) => Stream.value(const [])),
        isPremiumProvider.overrideWithValue(premium),
        discoveryRepositoryProvider.overrideWithValue(repository),
        careerProvider.overrideWith(
          (ref, uid) => Stream.value(const <CareerLine>[]),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pump(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  group('finding a club', () {
    testWidgets('lists public clubs without throwing', (tester) async {
      await pump(
        tester,
        harness(
          screen: const DiscoverScreen(),
          repository: _FakeDiscovery(
            clubs: [club('a', 'Kazipet Cricket Club', district: 'Warangal')],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Kazipet Cricket Club'), findsOneWidget);
    });

    testWidgets('seeds the place box from the searcher\'s own district',
        (tester) async {
      // Somebody who has already said where they play should not have to type
      // it again to find anything.
      await pump(
        tester,
        harness(
          screen: const DiscoverScreen(),
          repository: _FakeDiscovery(
            clubs: [
              club('a', 'Kazipet Cricket Club', district: 'Warangal'),
              club('b', 'Hyderabad Academy', district: 'Hyderabad'),
            ],
          ),
        ),
      );

      expect(find.text('Kazipet Cricket Club'), findsOneWidget);
      expect(find.text('Hyderabad Academy'), findsNothing);
    });

    testWidgets('offers starting one when the search finds nothing',
        (tester) async {
      // The honest answer for the first person in a district: there is
      // nothing here yet, so here is the other thing you can do.
      await pump(
        tester,
        harness(screen: const DiscoverScreen()),
      );

      expect(find.text('No clubs match that'), findsOneWidget);
      await tester.tap(find.text('Start a club instead'));
      await tester.pumpAndSettle();
      expect(find.text('AT /orgs/new'), findsOneWidget);
    });
  });

  group('finding people', () {
    Future<void> openPeople(WidgetTester tester) async {
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
    }

    testWidgets('renders directory cards without throwing', (tester) async {
      await pump(
        tester,
        harness(
          screen: const DiscoverScreen(),
          repository: _FakeDiscovery(listings: [person('uid_other', 'Bhavya')]),
        ),
      );
      await openPeople(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Bhavya'), findsOneWidget);
    });

    testWidgets('a free member is offered Premium, not the profile',
        (tester) async {
      await pump(
        tester,
        harness(
          screen: const DiscoverScreen(),
          repository: _FakeDiscovery(listings: [person('uid_other', 'Bhavya')]),
        ),
      );
      await openPeople(tester);
      await tester.tap(find.text('Bhavya'));
      await tester.pumpAndSettle();

      expect(find.text('AT /player/uid_other'), findsNothing);
      expect(find.text('See Premium'), findsOneWidget);
      // And it closes without argument.
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Bhavya'), findsOneWidget);
    });

    testWidgets('a Premium member opens it', (tester) async {
      await pump(
        tester,
        harness(
          screen: const DiscoverScreen(),
          repository: _FakeDiscovery(listings: [person('uid_other', 'Bhavya')]),
          premium: true,
        ),
      );
      await openPeople(tester);
      await tester.tap(find.text('Bhavya'));
      await tester.pumpAndSettle();

      expect(find.text('AT /player/uid_other'), findsOneWidget);
    });

    testWidgets('your own card is never behind the gate', (tester) async {
      await pump(
        tester,
        harness(
          screen: const DiscoverScreen(),
          repository: _FakeDiscovery(listings: [person('uid_me', 'Asha')]),
        ),
      );
      await openPeople(tester);
      await tester.tap(find.text('Asha (you)'));
      await tester.pumpAndSettle();

      expect(find.text('AT /player/uid_me'), findsOneWidget);
    });

    testWidgets('always offers the way into the directory', (tester) async {
      // Being findable is the other half of finding, and it sits above the
      // results rather than in a menu.
      await pump(tester, harness(screen: const DiscoverScreen()));
      await openPeople(tester);

      expect(find.text('Let people find you'), findsOneWidget);
      await tester.tap(find.text('Let people find you'));
      await tester.pumpAndSettle();
      expect(find.text('AT /me/listing'), findsOneWidget);
    });
  });

  group('listing yourself', () {
    testWidgets('an adult gets the form', (tester) async {
      await pump(
        tester,
        harness(screen: const PlayerListingEditScreen()),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('List me'), findsOneWidget);
    });

    testWidgets('a minor is told why, not shown a form that will fail',
        (tester) async {
      // The rules refuse the write. Showing the form anyway would spend
      // somebody's time and end in a permission error they cannot act on.
      await pump(
        tester,
        harness(
          screen: const PlayerListingEditScreen(),
          account: child,
        ),
      );

      expect(find.text('The directory is for adults'), findsOneWidget);
      expect(find.text('List me'), findsNothing);
    });

    testWidgets('an existing listing offers a way back off', (tester) async {
      await pump(
        tester,
        harness(
          screen: const PlayerListingEditScreen(),
          repository: _FakeDiscovery(mine: person('uid_me', 'Asha')),
        ),
      );

      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Take me off the directory'), findsOneWidget);
    });
  });
}
