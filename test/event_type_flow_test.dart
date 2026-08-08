import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/domain/event_type.dart';
import 'package:playsphere/features/competitions/choose_event_type_screen.dart';

/// Feature #8 — event creation must ask the event TYPE first, and change
/// what it asks for based on the answer.
///
/// "New event" used to open straight onto the single-sport competition form.
/// That form assumes a field assembled by registration, which is wrong for
/// three of the four things clubs actually create: a season spans several
/// sports with an entry list each, a single match has both sides named on the
/// spot, and a challenge is addressed to another club and has no entries at
/// all until they accept.
void main() {
  const orgId = 'org_school';

  const school = Organization(
    id: orgId,
    name: 'Nizampet High School',
    orgType: OrgType.school,
    visibility: OrgVisibility.public,
    ownerUid: 'uid_me',
    inviteCode: 'ABC234',
    memberCount: 42,
  );

  final me = AppUser(
    uid: 'uid_me',
    displayName: 'Ravi Kumar',
    email: 'ravi@example.com',
    dateOfBirth: DateTime(1994, 5, 20),
    gender: Gender.male,
    profileComplete: true,
  );

  Widget harness() {
    final router = GoRouter(
      initialLocation: '/org/$orgId/new-event',
      routes: [
        GoRoute(
          path: '/org/:orgId/new-event',
          builder: (_, state) =>
              ChooseEventTypeScreen(orgId: state.pathParameters['orgId']!),
        ),
        // Each destination renders its own path, so a test asserts WHERE the
        // choice landed rather than merely that something happened.
        for (final path in [
          '/org/:orgId/new-event/tournament',
          '/org/:orgId/new-event/season',
          '/org/:orgId/quick-match',
          '/org/:orgId/challenges',
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
        organizationProvider.overrideWith((ref, id) => Stream.value(school)),
        myMembershipsProvider.overrideWith((ref) => Stream.value(const [])),
        myCapabilitiesProvider.overrideWith(
          (ref, id) => PermissionMatrix.capabilitiesOf(MembershipRole.owner),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('the type is asked first', () {
    testWidgets('all four types are offered with an explanation each',
        (tester) async {
      await pump(tester);

      for (final type in EventType.values) {
        expect(
          find.text(type.label),
          findsOneWidget,
          reason: '${type.label} must be offered',
        );
        expect(find.text(type.tagline), findsOneWidget);
      }
    });

    testWidgets('nothing is created until a type is chosen', (tester) async {
      await pump(tester);

      // The chooser is a decision screen, not a form. There is no Create
      // button on it to press by accident.
      expect(find.text('Create'), findsNothing);
      expect(find.textContaining('AT '), findsNothing);
    });
  });

  group('each type opens its own flow', () {
    testWidgets('Season opens the multi-sport form', (tester) async {
      await pump(tester);
      await choose(tester, 'Season');

      expect(find.text('AT /org/$orgId/new-event/season'), findsOneWidget);
    });

    testWidgets('Tournament opens the single-sport form', (tester) async {
      await pump(tester);
      await choose(tester, 'Tournament');

      expect(find.text('AT /org/$orgId/new-event/tournament'), findsOneWidget);
    });

    testWidgets('Single match goes to the quick-match screen', (tester) async {
      await pump(tester);
      await choose(tester, 'Single match');

      // Not the event form: that would write a competition with no fixture,
      // which shows in the club list and can never be played.
      expect(find.text('AT /org/$orgId/quick-match'), findsOneWidget);
    });

    testWidgets('Challenge goes to the challenges screen', (tester) async {
      await pump(tester);
      await choose(tester, 'Challenge another club');

      expect(find.text('AT /org/$orgId/challenges'), findsOneWidget);
    });

    testWidgets('the four types land in four different places',
        (tester) async {
      // The whole point of Feature #8. Pinned as one assertion because the
      // failure being guarded against is two of them collapsing onto the
      // same destination, which is how this started.
      final destinations = <String>{};
      for (final label in [
        'Season',
        'Tournament',
        'Single match',
        'Challenge another club',
      ]) {
        await pump(tester);
        await choose(tester, label);
        final text = tester
            .widgetList<Text>(find.textContaining('AT '))
            .first
            .data!;
        destinations.add(text);
      }

      expect(destinations, hasLength(4));
    });
  });

  group('what each type means', () {
    test('only seasons and tournaments gather a field by registration', () {
      expect(EventType.season.takesRegistrations, isTrue);
      expect(EventType.tournament.takesRegistrations, isTrue);
      // Both sides are known by the time anything is written, so capacity,
      // waitlist and participation model are questions with no answer.
      expect(EventType.singleMatch.takesRegistrations, isFalse);
      expect(EventType.challenge.takesRegistrations, isFalse);
    });

    test('only a season spans several sports', () {
      expect(EventType.season.isMultiSport, isTrue);
      for (final other in [
        EventType.tournament,
        EventType.singleMatch,
        EventType.challenge,
      ]) {
        expect(other.isMultiSport, isFalse);
      }
    });

    test('wire values are stable', () {
      // Persisted on documents, so renaming one silently re-types events.
      expect(EventType.season.wire, 'season');
      expect(EventType.tournament.wire, 'tournament');
      expect(EventType.singleMatch.wire, 'single_match');
      expect(EventType.challenge.wire, 'challenge');
      expect(EventType.fromWire('season'), EventType.season);
      expect(EventType.fromWire('nonsense'), EventType.tournament);
    });
  });
}
