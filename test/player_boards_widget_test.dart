import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/tournament/player_boards.dart';
import 'package:playsphere/features/tournaments/widgets/leaderboard_cards.dart';

/// The tournament's player charts, on screen.
///
/// [PlayerBoards] has been computed and correct since §17 shipped and nothing
/// ever rendered it — the provider had no reader, so every tournament's
/// batting and bowling charts were simply absent. These tests pin the path
/// from fixtures to pixels, so the card cannot quietly stop being wired again.
void main() {
  Fixture match({
    required String id,
    required Map<String, Map<String, num>> tallies,
  }) {
    var state = <String, dynamic>{};
    for (final entry in tallies.entries) {
      state = PlayerTally.addAll(state, entry.key, entry.value);
    }
    return Fixture(
      id: id,
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'a',
      entrantBId: 'b',
      entrantAName: 'Warriors',
      entrantBName: 'Titans',
      status: FixtureStatus.completed,
      winnerEntrantId: 'a',
      lineupA: [
        for (final playerId in tallies.keys)
          MatchPlayer(
            id: playerId,
            name: playerId[0].toUpperCase() + playerId.substring(1),
            uid: playerId == 'visitor' ? null : playerId,
          ),
      ],
      scoreState: state,
    );
  }

  Future<void> pump(WidgetTester tester, PlayerBoards? boards) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PlayerBoardsCard(boards: boards)),
          ),
        ),
      );

  testWidgets('draws a chart per counter, leading with the deepest', (t) async {
    await pump(
      t,
      PlayerBoards.from([
        match(id: 'f1', tallies: {
          'rahul': {'runs': 74, 'wickets': 1},
          'karthik': {'runs': 42},
          'vikram': {'runs': 31},
        }),
      ]),
    );

    expect(find.text('Player charts'), findsOneWidget);
    // Counter keys reach the screen as people read them, not as camelCase.
    expect(find.widgetWithText(ChoiceChip, 'Runs'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Wickets'), findsOneWidget);
    // Runs describes this sport better — three players have a figure — so it
    // is the tab offered first, and its rows are what is showing.
    expect(find.text('Rahul'), findsOneWidget);
    expect(find.text('74'), findsOneWidget);
  });

  testWidgets('switching the chart switches the rows', (t) async {
    await pump(
      t,
      PlayerBoards.from([
        match(id: 'f1', tallies: {
          'rahul': {'runs': 74},
          'karthik': {'runs': 42},
          'suresh': {'wickets': 5},
        }),
      ]),
    );

    expect(find.text('Suresh'), findsNothing);
    await t.tap(find.widgetWithText(ChoiceChip, 'Wickets'));
    await t.pumpAndSettle();
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    // The runs board's leader is no longer on screen.
    expect(find.text('Rahul'), findsNothing);
  });

  testWidgets('an individual draw charts without any line-up', (t) async {
    // The shape the whole participants fix exists for: nobody is named in a
    // line-up, so before `scoredPlayers` this card drew nothing at all for a
    // singles bracket played to a final.
    var state = PlayerTally.addAll({}, 'uid_alice', const {'aces': 12});
    state = PlayerTally.addAll(state, 'uid_bhavya', const {'aces': 5});

    await pump(
      t,
      PlayerBoards.from([
        Fixture(
          id: 'f1',
          orgId: 'org1',
          compId: 'comp1',
          entrantAId: 'uid_alice',
          entrantBId: 'uid_bhavya',
          entrantAName: 'Alice',
          entrantBName: 'Bhavya',
          entrantAUid: 'uid_alice',
          entrantBUid: 'uid_bhavya',
          status: FixtureStatus.completed,
          winnerEntrantId: 'uid_alice',
          scoreState: state,
        ),
      ]),
    );

    expect(find.widgetWithText(ChoiceChip, 'Aces'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a guest is ranked and marked as one', (t) async {
    await pump(
      t,
      PlayerBoards.from([
        match(id: 'f1', tallies: {
          'visitor': {'runs': 88},
          'rahul': {'runs': 12},
        }),
      ]),
    );

    expect(find.text('Visitor'), findsOneWidget);
    // Said out loud rather than left looking like a profile that will not open.
    expect(find.text('guest'), findsOneWidget);
  });

  testWidgets('nothing recorded draws nothing at all', (t) async {
    // Normal for a chess draw, and for a tournament on its first morning. An
    // empty card explaining itself would be noise on both.
    await pump(t, PlayerBoards.from(const []));
    expect(find.text('Player charts'), findsNothing);

    await pump(t, null);
    expect(find.text('Player charts'), findsNothing);
  });

  testWidgets('a multi-sport season splits its charts by sport', (t) async {
    // Mockup 12: a season leaderboard is per sport. One merged set leaves a
    // hockey parent scrolling past six cricket charts to reach theirs.
    Fixture inSport(String id, String sportId, Map<String, num> tally) {
      return Fixture(
        id: id,
        orgId: 'org1',
        compId: 'comp_$sportId',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'A',
        entrantBName: 'B',
        status: FixtureStatus.completed,
        winnerEntrantId: 'a',
        sportId: sportId,
        lineupA: [MatchPlayer(id: 'p_$sportId', name: sportId, uid: 'p_$sportId')],
        scoreState: PlayerTally.addAll({}, 'p_$sportId', tally),
      );
    }

    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerBoardsCard(
              bySport: PlayerBoards.bySport([
                inSport('f1', 'cricket', const {'runs': 74}),
                inSport('f2', 'football', const {'goals': 3}),
              ]),
            ),
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ChoiceChip, 'Cricket'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Football'), findsOneWidget);
    // Cricket leads, so its counter is what is offered and its row is showing.
    expect(find.widgetWithText(ChoiceChip, 'Runs'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Goals'), findsNothing);

    await t.tap(find.widgetWithText(ChoiceChip, 'Football'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Goals'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Runs'), findsNothing);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a single-sport tournament grows no sport row', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerBoardsCard(
              bySport: PlayerBoards.bySport([
                match(id: 'f1', tallies: {
                  'rahul': {'runs': 74},
                }),
              ]),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Player charts'), findsOneWidget);
    // One option is not a choice, so no control offers it.
    expect(find.widgetWithText(ChoiceChip, 'Cricket'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Runs'), findsOneWidget);
  });
}
