import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/coach.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/coaches/coach_detail_screen.dart';
import 'package:playsphere/features/coaches/coach_profile_edit_screen.dart';

/// The coach directory.
///
/// This is the one listing in the product where somebody reads a page and
/// then hands over a child, so what the tests protect is not the layout. It
/// is the three ways a self-declared directory can mislead: implying a claim
/// has been checked when it has not, letting a minor publish an invitation
/// carrying their phone number, and printing "₹0" for a coach who simply did
/// not publish a rate.
void main() {
  CoachProfile coach({
    String uid = 'uid_coach',
    String name = 'Ramesh Babu',
    List<String> sports = const ['cricket'],
    int ratePaise = 0,
    bool verified = false,
    bool accepting = true,
    bool active = true,
  }) =>
      CoachProfile(
        uid: uid,
        displayName: name,
        sportIds: sports,
        headline: 'Ex-Ranji seamer, twelve years with junior sides',
        city: 'Warangal',
        district: 'Hanamkonda',
        yearsExperience: 12,
        certifications: const ['NIS Patiala'],
        ageGroups: const ['U12', 'U16'],
        sessionRatePaise: ratePaise,
        acceptingStudents: accepting,
        isActive: active,
        isVerified: verified,
      );

  group('what the listing says', () {
    test('an unpublished rate reads as on request, never as free', () {
      // "₹0/session" is a promise of free coaching that nobody made, and a
      // great many coaches settle a monthly fee in conversation.
      expect(coach().rateLabel, 'Rate on request');
      expect(coach(ratePaise: 50000).rateLabel, contains('500'));
    });

    test('an empty sport list is not a claim to coach everything', () {
      // The opposite of `Ground.servesSport`, deliberately: a bare maidan
      // really does host anything, but a person who has listed no sport has
      // made no claim and must not surface under every one.
      expect(coach(sports: const []).coaches('cricket'), isFalse);
      expect(coach(sports: const ['cricket']).coaches('cricket'), isTrue);
      expect(coach(sports: const ['cricket']).coaches('kabaddi'), isFalse);
    });
  });

  group('search tokens', () {
    test('cover the words somebody would actually type', () {
      final tokens = coach().searchTokens.toSet();
      for (final word in ['ramesh', 'babu', 'warangal', 'cricket', 'nis',
        'patiala', 'hanamkonda']) {
        expect(tokens, contains(word), reason: '"$word" should find this coach');
      }
    });

    test('split a compound sport id into its words', () {
      // Nobody types an underscore. `table_tennis` has to be findable by
      // either half — the same rule `Ground.tokenize` follows.
      final tokens =
          coach(sports: const ['table_tennis']).searchTokens.toSet();
      expect(tokens, containsAll(['table', 'tennis']));
      expect(tokens, isNot(contains('table_tennis')));
    });

    test('drop single characters', () {
      // A one-letter token matches nearly every document, which would make
      // the array-contains anchor as wide as a full scan.
      expect(CoachProfile.tokenize(['a bc']), ['bc']);
    });
  });

  group('what the client may not write', () {
    test('a new listing cannot arrive verified', () {
      // The badge decides whether a parent trusts the page. Mirrored in
      // `firestore.rules`, which is the copy that actually enforces it —
      // this proves the client does not even try.
      final payload = coach(verified: true).toCreate();
      expect(payload['isVerified'], false);
    });

    test('an edit does not carry the verified flag at all', () {
      expect(coach(verified: true).toUpdate().containsKey('isVerified'), isFalse);
      expect(coach().toUpdate().containsKey('createdAt'), isFalse);
    });

    test('search tokens are derived on every write, never entered', () {
      // A listing edited to add a sport has to become findable by it in the
      // same save.
      final updated = coach().copyWith(sportIds: ['kabaddi']).toUpdate();
      expect(updated['searchTokens'], contains('kabaddi'));
      expect(updated['searchTokens'], isNot(contains('cricket')));
    });
  });

  // -------------------------------------------------------------------------
  // The screens
  // -------------------------------------------------------------------------

  AppUser user({required DateTime dob}) => AppUser(
        uid: 'uid_me',
        displayName: 'Ravi Kumar',
        email: 'ravi@example.com',
        dateOfBirth: dob,
        gender: Gender.male,
        profileComplete: true,
      );

  Widget harness(Widget screen, {AppUser? me, CoachProfile? listing}) {
    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(me?.uid),
        currentUserProvider.overrideWith((ref) => Stream.value(me)),
        myCoachProfileProvider.overrideWith((ref) => Stream.value(listing)),
        coachProvider.overrideWith((ref, uid) => Stream.value(listing)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/x',
          routes: [GoRoute(path: '/x', builder: (_, __) => screen)],
        ),
      ),
    );
  }

  testWidgets('a minor is told why, not shown a form that will fail',
      (tester) async {
    // The real gate is `subjectIsAdult` in firestore.rules. This one exists
    // so a sixteen-year-old reads a sentence rather than filling in ten
    // fields and watching the save fail with a permission error.
    await tester.pumpWidget(harness(
      const CoachProfileEditScreen(),
      me: user(dob: DateTime.now().subtract(const Duration(days: 365 * 16))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Not yet'), findsOneWidget);
    expect(find.text('List me as a coach'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('an adult gets the form', (tester) async {
    await tester.pumpWidget(harness(
      const CoachProfileEditScreen(),
      me: user(dob: DateTime(1990, 3, 2)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Not yet'), findsNothing);
    expect(find.text('List me as a coach'), findsOneWidget);
  });

  testWidgets('an unverified page says nothing here has been checked',
      (tester) async {
    await tester.pumpWidget(harness(
      const CoachDetailScreen(uid: 'uid_coach'),
      me: user(dob: DateTime(1990, 3, 2)),
      listing: coach(),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('has not been checked by PlaySphere'),
      findsOneWidget,
    );
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('a verified page still refuses to call itself a recommendation',
      (tester) async {
    // Verification means an identity and a credential were looked at. It is
    // not a background check, and a page that let a parent read it as one
    // would be the most dangerous screen in the product.
    await tester.pumpWidget(harness(
      const CoachDetailScreen(uid: 'uid_coach'),
      me: user(dob: DateTime(1990, 3, 2)),
      listing: coach(verified: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('not a background check'), findsOneWidget);
    expect(find.textContaining('not a recommendation'), findsOneWidget);
  });

  testWidgets('a delisted profile says so rather than reading as live',
      (tester) async {
    // Still reachable by anybody holding the link.
    await tester.pumpWidget(harness(
      const CoachDetailScreen(uid: 'uid_coach'),
      me: user(dob: DateTime(1990, 3, 2)),
      listing: coach(active: false),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('does not appear in searches'),
      findsOneWidget,
    );
  });
}
