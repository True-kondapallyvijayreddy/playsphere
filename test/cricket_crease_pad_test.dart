import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/features/scoring/widgets/crease_pad.dart';

/// The cricket pad: the crease it states, and the keypad it draws.
///
/// Two things are pinned here, and they are the two the old stacked pad got
/// wrong rather than merely drew plainly.
///
///  * **Who is on strike.** It rotates on an odd run and again at the end of
///    every over, without anybody pressing anything to rotate it. The pad has
///    to follow, because a scorer who loses it puts runs on the wrong batter
///    and no later care can separate two players' figures again.
///  * **The extras drawer.** Sixteen graded extras exist and all sixteen have
///    to be reachable, but the plain wide is the overwhelming majority of
///    every innings ever scored. It is one tap; the rest are behind a `+`.
void main() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  final ctx = ScoringContext(
    entrantAName: 'Warangal',
    entrantBName: 'Nizamabad',
    config: const {
      'oversPerInnings': 2,
      'ballsPerOver': 6,
      'playersPerTeam': 11,
      'battingFirst': 'a',
    },
    lineupA: squad('A'),
    lineupB: squad('B'),
  );

  Map<String, dynamic> play(
    Map<String, dynamic> state,
    List<ScoreAction> actions,
  ) {
    var s = state;
    for (final a in actions) {
      final r = cricket.apply(s, a, ctx);
      expect(r.isAccepted, isTrue,
          reason: 'rejected "${a.type}": ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  ScoreAction runs(int n) => ScoreAction(type: 'runs', payload: {'runs': n});

  Map<String, dynamic> started() => play(cricket.initialState(ctx), const [
        ScoreAction(
          type: 'open',
          payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
        ),
      ]);

  CreaseBoard board(Map<String, dynamic> state) {
    final b = cricket.creaseBoard(state, ctx);
    expect(b, isNotNull, reason: 'cricket must describe its own pad');
    return b!;
  }

  group('the board states the crease', () {
    test('the openers start with A1 on strike', () {
      final b = board(started());
      expect(b.batters.map((x) => x.name), ['A Player 1', 'A Player 2']);
      expect(b.batters.first.onStrike, isTrue);
      expect(b.batters.last.onStrike, isFalse);
      expect(b.bowler?.name, 'B Player 1');
    });

    test('an odd run moves the asterisk to the other end', () {
      final b = board(play(started(), [runs(1)]));
      expect(b.batters.first.name, 'A Player 2');
      expect(b.batters.first.onStrike, isTrue);
      // And the single is on the batter who actually hit it, not on whoever
      // happens to be on strike after it.
      final struck = b.batters.firstWhere((x) => x.name == 'A Player 1');
      expect(struck.runs, 1);
      expect(struck.balls, 1);
    });

    test('an even run leaves the striker where they were', () {
      final b = board(play(started(), [runs(2)]));
      expect(b.batters.first.name, 'A Player 1');
      expect(b.batters.first.onStrike, isTrue);
    });

    test('strike rotates again at the end of the over', () {
      // Six twos: the striker keeps strike all over, then swaps at the end.
      final b = board(play(started(), [for (var i = 0; i < 6; i++) runs(2)]));
      expect(b.batters.first.name, 'A Player 2');
      expect(b.batters.first.onStrike, isTrue);
      // Nobody has been named for the next over yet, and the pad says so
      // rather than drawing an empty row.
      expect(b.bowler, isNull);
      expect(b.notes, contains('NEW BOWLER'));
    });

    test('a strike rate is undefined off no balls, not zero', () {
      expect(board(started()).batters.first.strikeRate, '—');
      expect(board(play(started(), [runs(4)])).batters.first.strikeRate,
          '400.0');
    });

    test('the figures are the sport\'s own notation', () {
      final b = board(play(started(), [runs(1), runs(1), runs(4)]));
      expect(b.score, '6-0');
      // Three balls of a six-ball over, never 0.5.
      expect(b.overs, '0.3');
      expect(b.oversOf, '2');
      expect(b.bowler?.overs, '0.3');
      // Six runs off half an over is twelve an over.
      expect(b.bowler?.economy, '12.0');
    });
  });

  group('the board carries the last balls', () {
    test('a dot is a dot, a boundary is coloured as one', () {
      final b = board(play(started(), [runs(0), runs(4), runs(6)]));
      expect(b.timeline.map((c) => c.label), ['•', '4', '6']);
      expect(
        b.timeline.map((c) => c.kind),
        [BallKind.dot, BallKind.boundary, BallKind.maximum],
      );
    });

    test('extras name themselves and their value', () {
      final b = board(play(started(), [
        const ScoreAction(type: 'wide'),
        const ScoreAction(type: 'wide', payload: {'runs': 3}),
        const ScoreAction(type: 'no_ball', payload: {'runs': 4}),
        const ScoreAction(type: 'bye', payload: {'runs': 2}),
        const ScoreAction(type: 'leg_bye', payload: {'runs': 1}),
      ]));
      expect(
        b.timeline.map((c) => c.label),
        ['Wd', 'Wd+3', 'Nb+4', '2B', '1Lb'],
      );
      expect(b.timeline.every((c) => c.kind == BallKind.extra), isTrue);
    });

    test('a wicket prints as a wicket whatever else the ball was', () {
      final b = board(play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'run_out', 'delivery': 'no_ball', 'playerId': 'A1'},
        ),
      ]));
      expect(b.timeline.single.label, 'W');
      expect(b.timeline.single.kind, BallKind.wicket);
    });

    test('the ball that closes an over is marked', () {
      final b = board(play(started(), [for (var i = 0; i < 6; i++) runs(2)]));
      expect(b.timeline.length, 6);
      expect(b.timeline.last.endsOver, isTrue);
      expect(b.timeline.take(5).every((c) => c.endsOver), isFalse);
    });

    test('a wide does not close an over, because it is not a delivery', () {
      final b = board(play(started(), [
        for (var i = 0; i < 5; i++) runs(2),
        const ScoreAction(type: 'wide'),
      ]));
      expect(b.timeline.last.endsOver, isFalse);
    });
  });

  group('the extras keypad', () {
    /// Cricket's own controls, so the test cannot pass against a keypad that
    /// happens to have the right words on it.
    List<ScoreControlGroup> groupsFor(Map<String, dynamic> state) =>
        cricket.controls(state, ctx);

    /// The pad is taller than the 800x600 test viewport, so a tile has to be
    /// scrolled to before it can be pressed — the same thing a scorer's thumb
    /// does, and nothing the pad is doing wrong.
    Future<void> tapTile(WidgetTester tester, String label) async {
      final tile = find.text(label);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    Widget harness(Map<String, dynamic> state, {List<ScoreControl>? tapped}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CreasePad(
              board: board(state),
              groups: groupsFor(state),
              enabled: true,
              canUndo: true,
              onUndo: () {},
              onControl: (c) => tapped?.add(c),
            ),
          ),
        ),
      );
    }

    testWidgets('the common extras are one tap and the graded ones are behind',
        (tester) async {
      final tapped = <ScoreControl>[];
      await tester.pumpWidget(harness(started(), tapped: tapped));
      await tester.pumpAndSettle();

      for (final label in ['WD', 'WD+', 'NB', 'NB+', 'BYE', 'BYE+', 'LB']) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }
      // Wd+3 is reachable, but not by occupying the pad.
      expect(find.text('Wd+3'), findsNothing);

      await tapTile(tester, 'WD');
      expect(tapped.single.action, 'wide');
      expect(tapped.single.payload['runs'], isNull);
    });

    testWidgets('the + tile opens the full ladder and applies the choice',
        (tester) async {
      final tapped = <ScoreControl>[];
      await tester.pumpWidget(harness(started(), tapped: tapped));
      await tester.pumpAndSettle();

      await tapTile(tester, 'WD+');
      for (final label in ['Wd+1', 'Wd+2', 'Wd+3', 'Wd+4']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Wd+3'));
      await tester.pumpAndSettle();
      expect(tapped.single.action, 'wide');
      expect(tapped.single.payload['runs'], 3);
    });

    testWidgets('the striker is marked with the asterisk a scorecard uses',
        (tester) async {
      await tester.pumpWidget(harness(play(started(), [runs(1)])));
      await tester.pumpAndSettle();

      expect(find.text('A Player 2 *'), findsOneWidget);
      expect(find.text('A Player 1'), findsOneWidget);
    });

    testWidgets('it fits a phone mid-innings, with the chase on', (tester) async {
      // The width this is actually used at. A pad that overflows is not a
      // cosmetic problem: Flutter clips the overflowing content, so the tile
      // that falls off the edge is a delivery the scorer cannot enter.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Second innings, chasing, so the header carries its heaviest load:
      // team, innings, score, three stats, the target line and the notes.
      final chase = play(started(), [
        for (var i = 0; i < 6; i++) runs(2),
        const ScoreAction(type: 'new_bowler', payload: {'playerId': 'B2'}),
        for (var i = 0; i < 6; i++) runs(1),
        const ScoreAction(
          type: 'open',
          payload: {'striker': 'B1', 'nonStriker': 'B2', 'bowler': 'A1'},
        ),
        const ScoreAction(type: 'no_ball', payload: {'runs': 4}),
        runs(6),
      ]);

      final b = board(chase);
      expect(b.chaseNeed, isNotNull, reason: 'the second innings is a chase');

      await tester.pumpWidget(harness(chase));
      await tester.pumpAndSettle();

      // `pumpAndSettle` does not fail on an overflow; the error is reported
      // and swallowed, so it has to be asked for by name.
      expect(tester.takeException(), isNull);
    });
  });
}
