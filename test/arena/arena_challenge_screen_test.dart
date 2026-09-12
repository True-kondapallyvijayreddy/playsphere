import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/arena/arena_challenge_screen.dart';

/// Who a member can actually reach.
///
/// The requirement is "anyone in any club I belong to", which sounds like it
/// needs no test until you notice the two ways it silently fails: a person in
/// two of your clubs appearing twice, and a per-club cap hiding everybody past
/// the thirtieth name in a school of two hundred.
void main() {
  const me = 'uid_me';
  const school = 'org_school';
  const academy = 'org_academy';

  Membership member(String orgId, String uid, String name) => Membership(
        uid: uid,
        orgId: orgId,
        role: MembershipRole.member,
        status: MembershipStatus.active,
        displayName: name,
      );

  Organization org(String id, String name) => Organization(
        id: id,
        name: name,
        orgType: OrgType.school,
        visibility: OrgVisibility.public,
        ownerUid: 'uid_owner',
        inviteCode: 'CODE$id',
      );

  Future<void> pump(
    WidgetTester tester, {
    required Map<String, List<Membership>> clubs,
    Map<String, String> clubNames = const {},
  }) async {
    final router = GoRouter(
      initialLocation: '/arena/new/chess',
      routes: [
        GoRoute(
          path: '/arena/new/:gameId',
          builder: (_, state) => ArenaChallengeScreen(
            gameId: state.pathParameters['gameId'] ?? '',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          myMembershipsProvider.overrideWith(
            (ref) => Stream.value([
              for (final orgId in clubs.keys)
                member(orgId, me, 'Me'),
            ]),
          ),
          for (final entry in clubs.entries)
            orgMembersProvider(entry.key)
                .overrideWith((ref) => Stream.value(entry.value)),
          for (final entry in clubNames.entries)
            organizationProvider(entry.key).overrideWith(
              (ref) => Stream.value(org(entry.key, entry.value)),
            ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists members from every club the person belongs to',
      (tester) async {
    await pump(
      tester,
      clubs: {
        school: [member(school, 'uid_a', 'Anita')],
        academy: [member(academy, 'uid_b', 'Bhaskar')],
      },
      clubNames: {school: 'Nizampet High School', academy: 'Kompally Academy'},
    );

    expect(find.text('Anita'), findsOneWidget);
    expect(find.text('Bhaskar'), findsOneWidget);
    // At least once, not exactly once: the club chip in the app bar names the
    // club in use as well, which is the chrome doing its job.
    expect(find.text('Nizampet High School'), findsAtLeastNWidgets(1));
    expect(find.text('Kompally Academy'), findsAtLeastNWidgets(1));
  });

  testWidgets('someone in two of your clubs is listed once, with both clubs',
      (tester) async {
    await pump(
      tester,
      clubs: {
        school: [member(school, 'uid_a', 'Anita')],
        academy: [member(academy, 'uid_a', 'Anita')],
      },
      clubNames: {school: 'Nizampet High School', academy: 'Kompally Academy'},
    );

    expect(find.text('Anita'), findsOneWidget);
    expect(
      find.text('Nizampet High School · Kompally Academy'),
      findsOneWidget,
    );
  });

  testWidgets('a big club is not truncated', (tester) async {
    // The old per-club list stopped at thirty, which quietly broke the
    // promise on any club bigger than that — which is most schools.
    await pump(
      tester,
      clubs: {
        school: [
          for (var i = 0; i < 60; i++)
            member(school, 'uid_$i', 'Player ${i.toString().padLeft(2, '0')}'),
        ],
      },
      clubNames: {school: 'Nizampet High School'},
    );

    expect(find.textContaining('60 people across your clubs'), findsOneWidget);

    // The last name by sort order really is reachable by scrolling.
    await tester.scrollUntilVisible(
      find.text('Player 59'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Player 59'), findsOneWidget);
  });

  testWidgets('search spans every club at once', (tester) async {
    await pump(
      tester,
      clubs: {
        school: [member(school, 'uid_a', 'Anita')],
        academy: [member(academy, 'uid_b', 'Bhaskar')],
      },
      clubNames: {school: 'Nizampet High School', academy: 'Kompally Academy'},
    );

    await tester.enterText(find.byType(TextField).first, 'bhas');
    await tester.pumpAndSettle();

    expect(find.text('Bhaskar'), findsOneWidget);
    expect(find.text('Anita'), findsNothing);
  });

  testWidgets('you can search by club name too', (tester) async {
    await pump(
      tester,
      clubs: {
        school: [member(school, 'uid_a', 'Anita')],
        academy: [member(academy, 'uid_b', 'Bhaskar')],
      },
      clubNames: {school: 'Nizampet High School', academy: 'Kompally Academy'},
    );

    await tester.enterText(find.byType(TextField).first, 'Kompally');
    await tester.pumpAndSettle();

    expect(find.text('Bhaskar'), findsOneWidget);
    expect(find.text('Anita'), findsNothing);
  });

  testWidgets('you are never in your own opponent list', (tester) async {
    await pump(
      tester,
      clubs: {
        school: [
          member(school, me, 'Me'),
          member(school, 'uid_a', 'Anita'),
        ],
      },
      clubNames: {school: 'Nizampet High School'},
    );

    expect(find.text('Anita'), findsOneWidget);
    expect(find.text('Me'), findsNothing);
  });

  testWidgets('a member with no club is pointed at the player code',
      (tester) async {
    await pump(tester, clubs: const {});

    expect(
      find.textContaining('not in a club yet'),
      findsOneWidget,
    );
    expect(find.text('PSOS-XXXXX'), findsOneWidget);
  });

  testWidgets('pending members are not listed', (tester) async {
    // Somebody who has asked to join but not been approved is not yet a
    // member of the club, and challenging them would leak the club roster.
    await pump(
      tester,
      clubs: {
        school: [
          member(school, 'uid_a', 'Anita'),
          const Membership(
            uid: 'uid_p',
            orgId: school,
            role: MembershipRole.member,
            status: MembershipStatus.pending,
            displayName: 'Pending Person',
          ),
        ],
      },
      clubNames: {school: 'Nizampet High School'},
    );

    expect(find.text('Anita'), findsOneWidget);
    expect(find.text('Pending Person'), findsNothing);
  });
}
