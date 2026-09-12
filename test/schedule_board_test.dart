import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/schedule/schedule_view_model.dart';
import 'package:playsphere/features/competitions/widgets/schedule_board.dart';

Fixture fixture({
  required String id,
  required String a,
  required String b,
  String? groupId = 'A',
  int round = 1,
  int index = 0,
  DateTime? at,
  FixtureStatus status = FixtureStatus.scheduled,
  String summary = '',
  String? court,
}) =>
    Fixture(
      id: id,
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: a,
      entrantBId: b,
      entrantAName: a,
      entrantBName: b,
      groupId: groupId,
      round: round,
      matchIndex: index,
      scheduledAt: at,
      status: status,
      summary: summary,
      courtId: court,
    );

Entrant entrant(String id, {String? clubId, String? teamId, String? uid,
    List<String> members = const []}) =>
    Entrant(
      id: id,
      displayName: id,
      entrantType: uid != null ? EntrantType.individual : EntrantType.team,
      uid: uid,
      clubId: clubId,
      teamId: teamId,
      memberUids: members,
    );

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  group('MyEntrants', () {
    test('claims an entrant by account, squad, team or club', () {
      final mine = MyEntrants.resolve(
        entrants: [
          entrant('solo', uid: 'me'),
          entrant('squad', members: ['someone', 'me']),
          entrant('myTeam', teamId: 't1'),
          entrant('myClub', clubId: 'org_mine'),
          entrant('theirs', clubId: 'org_theirs', members: ['other']),
        ],
        uid: 'me',
        myOrgIds: {'org_mine'},
        myTeamIds: {'t1'},
      );
      expect(mine, {'solo', 'squad', 'myTeam', 'myClub'});
    });

    test('claims nothing for a signed-out spectator', () {
      expect(
        MyEntrants.resolve(entrants: [entrant('a', clubId: 'org1')]),
        isEmpty,
      );
    });
  });

  group('ScheduleFormat', () {
    test('an unscheduled match reads TBC, never 00:00', () {
      expect(ScheduleFormat.when(fixture(id: 'f', a: 'A', b: 'B')), 'TBC');
      // The epoch is what an older draft bracket wrote instead of null, and
      // it rendered as a confident midnight kick-off.
      expect(
        ScheduleFormat.when(
          fixture(id: 'f', a: 'A', b: 'B', at: DateTime(1970)),
        ),
        'TBC',
      );
    });

    test('unscheduled matches sort last, not first', () {
      final placed = fixture(
        id: 'placed',
        a: 'A',
        b: 'B',
        at: DateTime(2026, 10, 12, 9),
      );
      final floating = fixture(id: 'floating', a: 'C', b: 'D');
      final list = [floating, placed]..sort(ScheduleFormat.byTime);
      expect(list.first.id, 'placed');
    });

    test('sections a groups-and-knockout draw with knockout last', () {
      final sections = ScheduleFormat.toSections([
        fixture(id: 'ko', a: 'W1', b: 'W2', groupId: null, round: 4),
        fixture(id: 'b1', a: 'C', b: 'D', groupId: 'B'),
        fixture(id: 'a1', a: 'A', b: 'B', groupId: 'A'),
      ]);
      expect(
        sections.map((s) => s.title),
        ['Group A', 'Group B', 'Knockout'],
      );
    });

    test('marks a row as ours when either side is ours', () {
      final sections = ScheduleFormat.toSections(
        [
          fixture(id: 'f1', a: 'e_mine', b: 'e_other'),
          fixture(id: 'f2', a: 'e_other', b: 'e_third', index: 1),
        ],
        mineEntrantIds: {'e_mine'},
      );
      expect(sections.single.rows.map((r) => r.mine), [true, false]);
    });
  });

  group('ScheduleBoard', () {
    final bigDraw = [
      for (var i = 0; i < 40; i++)
        fixture(
          id: 'f$i',
          a: 'Team ${String.fromCharCode(65 + i % 8)}',
          b: 'Team ${String.fromCharCode(73 + i % 8)}',
          groupId: String.fromCharCode(65 + i % 4),
          round: i ~/ 8 + 1,
          index: i,
        ),
    ];

    testWidgets('a large draw opens with its groups collapsed', (t) async {
      await pump(t, ScheduleBoard(fixtures: bigDraw));

      // Section headers are there; the matches under them are not.
      expect(find.text('Group A'), findsOneWidget);
      expect(find.text('Group D'), findsOneWidget);
      expect(find.byType(MatchRow), findsNothing);

      await t.tap(find.text('Group A'));
      await t.pump();
      expect(find.byType(MatchRow), findsWidgets);
    });

    testWidgets('a small draw opens showing its matches', (t) async {
      await pump(t, ScheduleBoard(fixtures: bigDraw.take(8).toList()));
      expect(find.byType(MatchRow), findsWidgets);
    });

    testWidgets('the group holding our matches opens even in a large draw',
        (t) async {
      await pump(
        t,
        ScheduleBoard(
          fixtures: bigDraw,
          mineEntrantIds: const {'Team A'},
        ),
      );
      // Group A contains "Team A"; the other three do not open.
      expect(find.byType(MatchRow), findsWidgets);
      expect(find.textContaining('ours'), findsWidgets);
    });

    testWidgets('"Ours" filters the board down to our own matches', (t) async {
      await pump(
        t,
        ScheduleBoard(
          fixtures: bigDraw,
          mineEntrantIds: const {'Team A'},
        ),
      );

      await t.tap(find.textContaining('Ours ('));
      await t.pump();

      final rows = t.widgetList<MatchRow>(find.byType(MatchRow));
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.mine), isTrue);
    });

    testWidgets('offers a download beside the heading', (t) async {
      await pump(t, ScheduleBoard(fixtures: bigDraw));
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('offers no download when there is nothing to print',
        (t) async {
      await pump(t, const ScheduleBoard(fixtures: []));
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('the "Ours" chip is hidden when nothing is ours', (t) async {
      await pump(t, ScheduleBoard(fixtures: bigDraw));
      expect(find.textContaining('Ours ('), findsNothing);
    });

    testWidgets('pins the next of our matches above the groups', (t) async {
      await pump(
        t,
        ScheduleBoard(
          fixtures: [
            fixture(
              id: 'later',
              a: 'Ours',
              b: 'Them',
              at: DateTime(2026, 10, 12, 15),
            ),
            fixture(
              id: 'sooner',
              a: 'Ours',
              b: 'Others',
              index: 1,
              at: DateTime(2026, 10, 12, 9),
            ),
          ],
          mineEntrantIds: const {'Ours'},
        ),
      );

      expect(find.text('Your next match'), findsOneWidget);
      expect(find.textContaining('Ours  v  Others'), findsWidgets);
    });

    testWidgets('organizer actions collapse into one overflow menu',
        (t) async {
      await pump(
        t,
        ScheduleBoard(
          fixtures: [fixture(id: 'f1', a: 'A', b: 'B')],
          actionsBuilder: (_) => [
            ScheduleAction(
              icon: Icons.edit_calendar_outlined,
              label: 'Move this match',
              onSelected: () {},
            ),
            ScheduleAction(
              icon: Icons.play_circle_outline,
              label: 'Start this match early',
              onSelected: () {},
            ),
          ],
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      expect(find.text('Move this match'), findsOneWidget);
      expect(find.text('Start this match early'), findsOneWidget);
    });
  });
}
