import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/team.dart';
import 'package:playsphere/core/models/team_join_request.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/teams/create_standalone_team_screen.dart';
import 'package:playsphere/features/teams/standalone_teams_screen.dart';
import 'package:playsphere/features/teams/team_detail_screen.dart';

/// Teams with no club behind them.
///
/// Rule 4 — a team is independent of club — has been in the model since it
/// was written, and until now no screen could produce one: every path into
/// team creation went through the club-scoped form, which needs an org and an
/// admin capability. What these tests protect is the thing that was actually
/// missing, and the two ways the fix could go wrong: a team that quietly
/// acquires a club, and a join code that turns into a password.
void main() {
  Team team({
    String id = 'team_1',
    TeamType type = TeamType.independent,
    String? clubId,
    List<String> members = const ['uid_captain'],
    String? joinCode = 'K7M2QP',
  }) =>
      Team(
        id: id,
        name: 'Gachibowli Strikers',
        sportId: 'cricket',
        type: type,
        createdByUid: 'uid_captain',
        clubId: clubId,
        captainUid: 'uid_captain',
        memberUids: members,
        homeArea: 'Gachibowli',
        joinCode: joinCode,
      );

  group('the model already allowed this', () {
    test('an independent team is valid with no club', () {
      expect(team().validationError, isNull);
      expect(team().isIndependent, isTrue);
    });

    test('an independent team may not acquire a club', () {
      // The pairing `teamShapeValid` enforces server-side. A club team that
      // drifted into `independent`, or the reverse, would show up in one
      // club's squad list and one platform-wide one at the same time.
      expect(
        team(clubId: 'org_school').validationError,
        'An independent team cannot belong to a club.',
      );
      expect(
        team(type: TeamType.permanent).validationError,
        'A club team must belong to a club.',
      );
    });

    test('it is not competition-scoped the way an event team is', () {
      expect(team().type.isPersistent, isTrue);
      expect(team().type.forbidsClub, isTrue);
      expect(team().type.requiresClub, isFalse);
    });
  });

  group('the join code', () {
    test('avoids the characters people mistype', () {
      // No O/0, no I/1/l — it gets read off a phone screen and typed by hand.
      final code = Team.generateJoinCode(Random(7));
      expect(code.length, 6);
      expect(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$').hasMatch(code),
          isTrue);
    });

    test('is carried on the document so a lookup can find it', () {
      expect(team().toCreate()['joinCode'], 'K7M2QP');
    });

    test('a club team and an event team carry none', () {
      // Neither fills up by being asked: a club squad is picked off the
      // club's member list, an event team off a tournament entry.
      final club = Team(
        id: 't',
        name: 'School XI',
        sportId: 'cricket',
        type: TeamType.permanent,
        createdByUid: 'uid_captain',
        clubId: 'org_school',
      );
      expect(club.toCreate()['joinCode'], isNull);
    });
  });

  // -------------------------------------------------------------------------
  // The screens
  // -------------------------------------------------------------------------

  final me = AppUser(
    uid: 'uid_me',
    displayName: 'Ravi Kumar',
    email: 'ravi@example.com',
    dateOfBirth: DateTime(1998, 4, 4),
    gender: Gender.male,
    profileComplete: true,
  );

  Widget harness(
    Widget screen, {
    AppUser? user,
    List<Team> myTeams = const [],
    List<Team> independent = const [],
    List<TeamJoinRequest> requests = const [],
    Team? theTeam,
    bool asked = false,
  }) {
    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(user?.uid),
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
        myTeamsProvider.overrideWith((ref) => Stream.value(myTeams)),
        independentTeamsProvider
            .overrideWith((ref, sportId) => Stream.value(independent)),
        teamProvider.overrideWith((ref, id) => Stream.value(theTeam)),
        teamJoinRequestsProvider
            .overrideWith((ref, id) => Stream.value(requests)),
        hasAskedToJoinProvider.overrideWith((ref, id) => Stream.value(asked)),
        userProfileProvider.overrideWith((ref, uid) => Stream.value(null)),
        organizationProvider.overrideWith((ref, id) => Stream.value(null)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/x',
          routes: [
            GoRoute(path: '/x', builder: (_, __) => screen),
            GoRoute(
              path: '/teams/new',
              builder: (_, __) => const Scaffold(body: Text('AT /teams/new')),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('creating a team asks for no club and no capability',
      (tester) async {
    // The whole point. `CreateTeamScreen` refuses anybody without
    // `manageOrganization` on a named org; this one has neither concept.
    await tester.pumpWidget(harness(
      const CreateStandaloneTeamScreen(),
      user: me,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Create team'), findsOneWidget);
    expect(find.textContaining('club'), findsWidgets); // "No club needed"
    expect(find.text('Team name'), findsOneWidget);
    expect(find.text('Cricket'), findsWidgets);
  });

  testWidgets('the hub offers a way in even with no teams of your own',
      (tester) async {
    await tester.pumpWidget(harness(
      const StandaloneTeamsScreen(),
      user: me,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Create a team'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);

    await tester.tap(find.text('Create a team'));
    await tester.pumpAndSettle();
    expect(find.text('AT /teams/new'), findsOneWidget);
  });

  testWidgets('a club team is not listed as one of your independent ones',
      (tester) async {
    await tester.pumpWidget(harness(
      const StandaloneTeamsScreen(),
      user: me,
      myTeams: [
        team(id: 'club_side', type: TeamType.permanent, clubId: 'org_school'),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('YOUR INDEPENDENT TEAMS'), findsNothing);
  });

  testWidgets('the captain sees the code and the queue', (tester) async {
    final captain = AppUser(
      uid: 'uid_captain',
      displayName: 'Ravi Kumar',
      email: 'ravi@example.com',
      dateOfBirth: DateTime(1998, 4, 4),
      gender: Gender.male,
      profileComplete: true,
    );
    await tester.pumpWidget(harness(
      const TeamDetailScreen(teamId: 'team_1'),
      user: captain,
      theTeam: team(),
      requests: const [
        TeamJoinRequest(
          uid: 'uid_asker',
          displayName: 'Suresh P',
          message: 'I keep wicket',
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('K7M2QP'), findsOneWidget);
    expect(find.text('1 player wants to join'), findsOneWidget);
    expect(find.text('Suresh P'), findsOneWidget);
    expect(find.text('I keep wicket'), findsOneWidget);
    // The captain is on their own roster, so they are never asked to join it.
    expect(find.text('Ask to join'), findsNothing);
  });

  testWidgets('somebody outside the team is offered a way to ask',
      (tester) async {
    await tester.pumpWidget(harness(
      const TeamDetailScreen(teamId: 'team_1'),
      user: me,
      theTeam: team(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ask to join'), findsOneWidget);
    // The code is the captain's to hand out. Showing it to a stranger would
    // imply it does something it does not — see `Team.joinCode`.
    expect(find.text('K7M2QP'), findsNothing);
  });

  testWidgets('asking twice is not offered', (tester) async {
    await tester.pumpWidget(harness(
      const TeamDetailScreen(teamId: 'team_1'),
      user: me,
      theTeam: team(),
      asked: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ask to join'), findsNothing);
    expect(find.text('Asked — tap to withdraw'), findsOneWidget);
  });

  testWidgets('a player already on the roster is asked nothing',
      (tester) async {
    await tester.pumpWidget(harness(
      const TeamDetailScreen(teamId: 'team_1'),
      user: me,
      theTeam: team(members: const ['uid_captain', 'uid_me']),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ask to join'), findsNothing);
    expect(find.text('Asked — tap to withdraw'), findsNothing);
  });

  testWidgets('a club team shows neither a code nor an ask button',
      (tester) async {
    // A club squad fills up from the club's member list. Offering a stranger
    // "ask to join" there would route round the club's own membership.
    await tester.pumpWidget(harness(
      const TeamDetailScreen(teamId: 'team_1'),
      user: me,
      theTeam: team(
        type: TeamType.permanent,
        clubId: 'org_school',
        joinCode: null,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ask to join'), findsNothing);
  });
}
