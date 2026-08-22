import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/features/scoring/widgets/duel_pad.dart';

/// The two-sided pad, and the boards the racket sports hand it.
///
/// The pad is deliberately dumb: it draws a [DuelBoard] and triggers the
/// controls the plugin declared. That split is what these tests pin — the
/// board has to be right per sport, and the pad has to take its tap action
/// from the control list rather than from anything it decides itself, or a
/// finished match would still accept points.
void main() {
  const ctx = ScoringContext(
    entrantAName: 'Anand',
    entrantBName: 'Bhavani',
    lineupA: [MatchPlayer(id: 'p1', name: 'Anand')],
    lineupB: [MatchPlayer(id: 'p2', name: 'Bhavani')],
    config: {'pointsPerSet': 21, 'setsToWin': 2, 'hardCap': 30},
  );

  Map<String, dynamic> rally(
    ScoringPlugin plugin,
    Map<String, dynamic> state,
    Side side,
    int times, {
    String type = 'rally',
  }) {
    var s = state;
    for (var i = 0; i < times; i++) {
      s = plugin.apply(s, ScoreAction(type: type, side: side), ctx).state;
    }
    return s;
  }

  group('badminton board', () {
    const plugin = BadmintonPlugin();

    test('the serving side is marked, and only one of them', () {
      final board = plugin.duelBoard(plugin.initialState(ctx), ctx)!;
      expect(board.a.serving ^ board.b.serving, isTrue);
    });

    test('names the server and the court they serve from', () {
      final board = plugin.duelBoard(plugin.initialState(ctx), ctx)!;
      final serving = board.a.serving ? board.a : board.b;
      // Right court at 0-0: the service court is derived from the score, and
      // a scorer checking "should he be standing there" is the whole reason
      // it is on the panel.
      expect(serving.serverName, contains('right court'));
    });

    test('calls game point, and match point when the game would end it', () {
      var state = plugin.initialState(ctx);
      state = rally(plugin, state, Side.a, 20);
      expect(plugin.duelBoard(state, ctx)!.a.tag, 'Game point');

      // One game up, and 20-0 in the second: the next rally takes the match.
      state = rally(plugin, state, Side.a, 1);
      state = rally(plugin, state, Side.a, 20);
      expect(plugin.duelBoard(state, ctx)!.a.tag, 'Match point');
    });

    test('no game point at deuce, where nobody is one rally from the game',
        () {
      var state = plugin.initialState(ctx);
      state = rally(plugin, state, Side.a, 20);
      state = rally(plugin, state, Side.b, 20);
      final board = plugin.duelBoard(state, ctx)!;
      expect(board.a.tag, isNull);
      expect(board.b.tag, isNull);
    });

    test('a finished match shows games won, not the last rally\'s zeros', () {
      var state = plugin.initialState(ctx);
      state = rally(plugin, state, Side.a, 21);
      state = rally(plugin, state, Side.a, 21);
      expect(state['complete'], isTrue);

      final board = plugin.duelBoard(state, ctx)!;
      // The point counters were zeroed when the second game closed. A board
      // built from them would read "0" against the match winner.
      expect(board.a.score, '2');
      expect(board.b.score, '0');
      expect(board.a.tag, 'Won');
      expect(board.a.serving, isFalse);
      expect(board.b.serving, isFalse);
    });

    test('the strip carries every game, with the one in play marked', () {
      var state = plugin.initialState(ctx);
      state = rally(plugin, state, Side.a, 21);
      state = rally(plugin, state, Side.b, 5);
      final periods = plugin.duelBoard(state, ctx)!.periods;
      expect(periods.length, 2);
      expect(periods.first.a, 21);
      expect(periods.first.current, isFalse);
      expect(periods.last.b, 5);
      expect(periods.last.current, isTrue);
    });
  });

  group('tennis board', () {
    const plugin = TennisPlugin();

    test('the big number is the game score, not a raw point count', () {
      var state = plugin.initialState(ctx);
      state = rally(plugin, state, Side.a, 2, type: 'point');
      // Two points is thirty, and a pad that showed "2" would be showing a
      // number that appears on no tennis scoreboard anywhere.
      expect(plugin.duelBoard(state, ctx)!.a.score, '30');
    });

    test('a break point is flagged against the receiver, not the server', () {
      var state = plugin.initialState(ctx);
      final server = Side.fromWire(state['server'] as String);
      state = rally(plugin, state, server.opposite, 3, type: 'point');
      final board = plugin.duelBoard(state, ctx)!;
      expect(board[server.opposite].tag, 'Break point');
      expect(board[server].tag, isNull);
    });
  });

  group('table tennis board', () {
    const plugin = TableTennisPlugin();

    test('serve alternates every two points', () {
      var state = plugin.initialState(ctx);
      final first = plugin.duelBoard(state, ctx)!.a.serving;
      state = rally(plugin, state, Side.a, 2, type: 'point');
      expect(plugin.duelBoard(state, ctx)!.a.serving, !first);
    });
  });

  group('the pad itself', () {
    const board = DuelBoard(
      a: DuelSide(name: 'Anand', score: '20', sub: 'Games 1', pips: 20),
      b: DuelSide(
        name: 'Bhavani',
        score: '18',
        sub: 'Games 0',
        serving: true,
        pips: 18,
      ),
      periods: [DuelPeriod(label: 'G2', a: 20, b: 18, current: true)],
      status: 'Game 2 · to 21',
      pipTarget: 21,
      pointsNote: '21 points per game · best of 3',
      endsNote: 'Anand left · Bhavani right',
    );

    const groups = [
      ScoreControlGroup(title: 'Rally won by', controls: [
        ScoreControl(
          action: 'rally',
          label: 'Anand',
          side: Side.a,
          style: ControlStyle.primary,
        ),
        ScoreControl(
          action: 'rally',
          label: 'Bhavani',
          side: Side.b,
          style: ControlStyle.primary,
        ),
      ]),
      ScoreControlGroup(title: 'Corrections', controls: [
        ScoreControl(
          action: 'correct',
          label: '−1 Anand',
          side: Side.a,
          style: ControlStyle.subtle,
        ),
        ScoreControl(
          action: 'correct',
          label: '−1 Bhavani',
          side: Side.b,
          style: ControlStyle.subtle,
        ),
      ]),
      // Styled `danger` and owned by a side, which is how the pad finds a
      // retirement without knowing the word — see `DuelPad._dangerFor`.
      ScoreControlGroup(title: 'Retire', controls: [
        ScoreControl(
          action: 'retire',
          label: 'Anand retires',
          side: Side.a,
          style: ControlStyle.danger,
        ),
        ScoreControl(
          action: 'retire',
          label: 'Bhavani retires',
          side: Side.b,
          style: ControlStyle.danger,
        ),
      ]),
      // Belongs to neither side, so it stays in the tray.
      ScoreControlGroup(title: 'Match', controls: [
        ScoreControl(
          action: 'interval',
          label: 'Interval taken',
          style: ControlStyle.secondary,
        ),
      ]),
    ];

    Widget harness(
      List<ScoreControlGroup> g,
      void Function(ScoreControl) onControl, {
      bool enabled = true,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: DuelPad(
              board: board,
              groups: g,
              enabled: enabled,
              canUndo: true,
              onUndo: () {},
              onControl: onControl,
            ),
          ),
        );

    testWidgets('tapping a half scores for that side', (tester) async {
      final fired = <ScoreControl>[];
      await tester.pumpWidget(harness(groups, fired.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();

      expect(fired.single.side, Side.a);
      expect(fired.single.action, 'rally');
    });

    testWidgets('a long press on a half takes the point back', (tester) async {
      final fired = <ScoreControl>[];
      await tester.pumpWidget(harness(groups, fired.add));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('20'));
      await tester.pumpAndSettle();

      expect(fired.single.action, 'correct');
      expect(fired.single.side, Side.a);
    });

    testWidgets('each side owns its point, correction and retirement',
        (tester) async {
      await tester.pumpWidget(harness(groups, (_) {}));
      await tester.pumpAndSettle();

      // The card already says whose it is, in its name bar. Nothing that
      // belongs to one side is repeated as a tray chip below: that would give
      // the same action two homes and make the tray look like where scoring
      // happens.
      expect(find.text('ANAND'), findsOneWidget);
      expect(find.text('−1 Anand'), findsNothing);

      // One +1 and one undo per card, and a retire on each — the three
      // labelled actions that live on a side.
      expect(find.text('+1'), findsNWidgets(2));
      expect(find.byIcon(Icons.undo_rounded), findsNWidgets(2));
      expect(find.text('RETIRE'), findsNWidgets(2));

      // What belongs to neither side is what the tray is for, and it is still
      // there: moving the side-owned controls onto the cards must not have
      // taken the rest of the sport's actions with them.
      expect(find.text('Interval taken'), findsOneWidget);
    });

    testWidgets('ticks a box per point won, and outlines the rest',
        (tester) async {
      await tester.pumpWidget(harness(groups, (_) {}));
      await tester.pumpAndSettle();

      // A tick per point won, and an outlined box for every point still to
      // play: 20 + 18 ticks against a target of 21 a side. The empty boxes
      // are half the point of the grid, so they are counted too.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(20 + 18));

      // The format and the ends line are both on screen, which is what the
      // header and the strip under the cards exist to say.
      expect(find.text('21 points per game · best of 3'), findsOneWidget);
      expect(find.text('Anand left · Bhavani right'), findsOneWidget);
      expect(find.text('Game 2 · to 21'), findsOneWidget);
    });

    testWidgets('no controls means nothing is tappable — the live view',
        (tester) async {
      final fired = <ScoreControl>[];
      await tester.pumpWidget(harness(const [], fired.add, enabled: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('20'));
      await tester.longPress(find.text('18'));
      await tester.pumpAndSettle();

      expect(fired, isEmpty);
    });
  });
}
