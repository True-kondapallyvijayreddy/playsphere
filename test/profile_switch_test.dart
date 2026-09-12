import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playsphere/core/l10n/locale_controller.dart';
import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/family/profile_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Switching into a child's profile.
///
/// The behaviour these pin down is the one thing the feature is: the app does
/// not "act on behalf of" a child in a few participation screens, it BECOMES
/// that child everywhere. So the tests are about one provider —
/// [currentUidProvider] — because it is the single point every screen reads,
/// and about the handful of things that must deliberately NOT follow it.
void main() {
  const guardianUid = 'uid_guardian';
  const childUid = 'uid_child';
  const otherChildUid = 'uid_child_two';

  AppUser person(
    String uid, {
    String? custodianUid,
    DateTime? claimedAt,
    String name = 'Player',
  }) =>
      AppUser(
        uid: uid,
        displayName: name,
        email: custodianUid == null ? 'a@example.com' : '',
        dateOfBirth: DateTime(2015, 5, 1),
        gender: Gender.male,
        profileComplete: true,
        custodianUid: custodianUid,
        claimedAt: claimedAt,
      );

  /// A container with a signed-in guardian and whichever children are given.
  ///
  /// [authUidProvider] is overridden rather than the auth stream because the
  /// split between "the account" and "the profile in use" is exactly what is
  /// under test, and overriding the account is how a test says which is which.
  Future<ProviderContainer> household({
    List<AppUser> children = const [],
    SharedPreferences? prefs,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authUidProvider.overrideWithValue(guardianUid),
        authUserProvider.overrideWith(
          (ref) => Stream.value(person(guardianUid, name: 'Guardian')),
        ),
        myManagedChildrenProvider.overrideWith((ref) => Stream.value(children)),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    // Let the overridden streams deliver before anything reads them.
    container.listen(myManagedChildrenProvider, (_, __) {});
    await container.read(myManagedChildrenProvider.future);
    return container;
  }

  group('who the app is', () {
    test('is the account until a profile is chosen', () async {
      final container = await household();
      expect(container.read(currentUidProvider), guardianUid);
      expect(container.read(isActingAsChildProvider), isFalse);
    });

    test('becomes the child the moment one is switched into', () async {
      final container = await household(
        children: [person(childUid, custodianUid: guardianUid)],
      );
      container.read(actingProfileUidProvider.notifier).switchTo(childUid);

      expect(container.read(currentUidProvider), childUid);
      expect(container.read(isActingAsChildProvider), isTrue);
    });

    test('switching back to the account clears it', () async {
      final container = await household(
        children: [person(childUid, custodianUid: guardianUid)],
      );
      final notifier = container.read(actingProfileUidProvider.notifier);
      notifier.switchTo(childUid);
      notifier.switchTo(null);

      expect(container.read(currentUidProvider), guardianUid);
      expect(container.read(isActingAsChildProvider), isFalse);
    });

    test('switching to the account\'s own uid is not "acting as"', () async {
      // The switcher offers the account holder's own face beside the
      // children's, and tapping it must be a return rather than a profile
      // called by the same name as the account.
      final container = await household(
        children: [person(childUid, custodianUid: guardianUid)],
      );
      container.read(actingProfileUidProvider.notifier).switchTo(guardianUid);

      expect(container.read(actingProfileUidProvider), isNull);
      expect(container.read(isActingAsChildProvider), isFalse);
    });
  });

  group('what must not follow the switch', () {
    test('the list of children stays the account\'s', () async {
      // Scoping this to the profile in use would empty it the moment it was
      // used, stranding the guardian inside a child's profile with no way
      // back — the switcher is built from this list.
      final container = await household(
        children: [person(childUid, custodianUid: guardianUid)],
      );
      container.read(actingProfileUidProvider.notifier).switchTo(childUid);

      expect(
        container.read(myManagedChildrenProvider).valueOrNull?.single.uid,
        childUid,
      );
    });
  });

  group('which profiles can be switched into', () {
    test('only children who have not claimed their own account', () async {
      final container = await household(children: [
        person(childUid, custodianUid: guardianUid, name: 'Unclaimed'),
        person(
          otherChildUid,
          custodianUid: guardianUid,
          claimedAt: DateTime(2026, 1, 1),
          name: 'Claimed',
        ),
      ]);

      expect(
        container.read(switchableProfilesProvider).map((c) => c.uid),
        [childUid],
      );
    });

    test('a child who claims mid-session is dropped, not left selected',
        () async {
      // Custody ends server-side at the same instant. Left selected, every
      // screen would be a permission error rather than an empty state.
      final children = [person(childUid, custodianUid: guardianUid)];
      final container = await household(children: children);
      container.read(actingProfileUidProvider.notifier).switchTo(childUid);

      final claimed = ProviderContainer(
        overrides: [
          authUidProvider.overrideWithValue(guardianUid),
          myManagedChildrenProvider.overrideWith(
            (ref) => Stream.value([
              person(
                childUid,
                custodianUid: guardianUid,
                claimedAt: DateTime(2026, 1, 1),
              ),
            ]),
          ),
        ],
      );
      addTearDown(claimed.dispose);
      claimed.read(actingProfileUidProvider.notifier).switchTo(childUid);
      claimed.listen(actingProfileGuardProvider, (_, __) {});
      await claimed.read(myManagedChildrenProvider.future);
      claimed.read(actingProfileGuardProvider);
      await Future<void>.delayed(Duration.zero);

      expect(claimed.read(actingProfileUidProvider), isNull);
      expect(claimed.read(currentUidProvider), guardianUid);
    });
  });

  group('the choice survives the app closing', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a switch is written to storage and read back', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = await household(
        children: [person(childUid, custodianUid: guardianUid)],
        prefs: prefs,
      );
      first.read(actingProfileUidProvider.notifier).switchTo(childUid);

      // A second container is a second launch: nothing carries over but the
      // stored preference.
      final relaunched = await household(
        children: [person(childUid, custodianUid: guardianUid)],
        prefs: prefs,
      );
      expect(relaunched.read(currentUidProvider), childUid);
    });

    test('the choice is per account, so another sign-in starts fresh',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final mine = await household(
        children: [person(childUid, custodianUid: guardianUid)],
        prefs: prefs,
      );
      mine.read(actingProfileUidProvider.notifier).switchTo(childUid);

      final somebodyElse = ProviderContainer(
        overrides: [
          authUidProvider.overrideWithValue('uid_someone_else'),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(somebodyElse.dispose);

      expect(somebodyElse.read(actingProfileUidProvider), isNull);
      expect(somebodyElse.read(currentUidProvider), 'uid_someone_else');
    });
  });

  group('the switcher itself', () {
    testWidgets('shows one face per profile and switches on a tap',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authUidProvider.overrideWithValue(guardianUid),
          authUserProvider.overrideWith(
            (ref) => Stream.value(person(guardianUid, name: 'Lakshmi')),
          ),
          myManagedChildrenProvider.overrideWith(
            (ref) => Stream.value([
              person(childUid, custodianUid: guardianUid, name: 'Arjun'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, __) => const Scaffold(
                    body: SingleChildScrollView(child: ProfileSwitcherStrip()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lakshmi'), findsOneWidget);
      expect(find.text('Arjun'), findsOneWidget);
      expect(find.text('Add child'), findsOneWidget);

      await tester.tap(find.text('Arjun'));
      await tester.pumpAndSettle();

      expect(container.read(currentUidProvider), childUid);
    });

    testWidgets('renders nothing for an account with no children',
        (tester) async {
      // A switcher with one face on it is furniture.
      final container = ProviderContainer(
        overrides: [
          authUidProvider.overrideWithValue(guardianUid),
          authUserProvider.overrideWith(
            (ref) => Stream.value(person(guardianUid, name: 'Lakshmi')),
          ),
          myManagedChildrenProvider.overrideWith(
            (ref) => Stream.value(const <AppUser>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ProfileSwitcherStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Who is playing?'), findsNothing);
    });
  });
}
