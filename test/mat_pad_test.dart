import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/kabaddi_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/features/scoring/widgets/mat_pad.dart';

/// The mat pad, and the board kabaddi hands it.
///
/// Same split as the duel pad: the pad is dumb and draws a [MatBoard], the
/// plugin decides what is on it. These pin the two halves of that — the board
/// has to describe the mat truthfully, and the pad has to take every action
/// from the control list rather than from anything it decides for itself.
void main() {
  const kabaddi = KabaddiPlugin();

  final ctx = ScoringContext(
    entrantAName: 'India A',
    entrantBName: 'India B',
    config: RulePresets.resolve(sportId: 'kabaddi').toMap(),
    lineupA: [
      for (var n = 1; n <= 7; n++)
        MatchPlayer(id: 'A$n', name: 'A Player $n', jerseyNumber: '$n'),
    ],
    lineupB: [
      for (var n = 1; n <= 7; n++)
        MatchPlayer(id: 'B$n', name: 'B Player $n', jerseyNumber: '$n'),
    ],
  );

  Map<String, dynamic> apply(
    Map<String, dynamic> s,
    String type, {
    Side side = Side.neutral,
    Map<String, dynamic> payload = const {},
  }) {
    final r = kabaddi.apply(s, ScoreAction(type: type, side: side, payload: payload), ctx);
    expect(r.isAccepted, isTrue, reason: r.rejection);
    return r.state;
  }

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> state, {
    void Function(ScoreControl)? onControl,
    Size size = const Size(1200, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MatPad(
            board: kabaddi.matBoard(state, ctx)!,
            groups: kabaddi.controls(state, ctx),
            onControl: onControl ?? (_) {},
            onUndo: () {},
            canUndo: true,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  group('the board', () {
    test('kabaddi asks for the mat pad and returns one', () {
      expect(kabaddi.padLayout, PadLayout.mat);
      expect(kabaddi.matBoard(kabaddi.initialState(ctx), ctx), isNotNull);
    });

    test('the strength is exact even when no names are known', () {
      final blind = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: ctx.config,
      );
      final s = kabaddi.apply(
        kabaddi.initialState(blind),
        const ScoreAction(type: 'raid', side: Side.a, payload: {'touched': 2}),
        blind,
      ).state;

      final board = kabaddi.matBoard(s, blind)!;
      expect(board.b.strength, 5);
      expect(board.b.fullStrength, 7);
      // No line-up was entered, so there are no names to draw — and the pad
      // must say five rather than invent five players.
      expect(board.b.active, isEmpty);
    });

    test('players out are listed in the order they come back', () {
      final s = apply(
        kabaddi.initialState(ctx),
        'raid',
        side: Side.b,
        payload: {'touched': 2, 'defenderIds': ['A3', 'A5']},
      );

      final board = kabaddi.matBoard(s, ctx)!;
      expect(board.a.out.map((p) => p.id), ['A3', 'A5']);
      expect(board.a.active.map((p) => p.id), isNot(contains('A3')));
      expect(board.a.strength, 5);
    });

    test('do-or-die is on the board, not left for the scorer to track', () {
      var s = kabaddi.initialState(ctx);
      expect(kabaddi.matBoard(s, ctx)!.a.alert, isNull);

      s = apply(s, 'raid', side: Side.a, payload: const {'touched': 0});
      s = apply(s, 'raid', side: Side.a, payload: const {'touched': 0});

      expect(kabaddi.matBoard(s, ctx)!.a.alert, 'DO OR DIE');
    });

    test('the turn names the defenders on the mat, which decides the points',
        () {
      final s = apply(
        kabaddi.initialState(ctx),
        'raid',
        side: Side.b,
        payload: const {'touched': 3},
      );

      final turn = kabaddi.matBoard(s, ctx)!.turn!;
      expect(turn.side, Side.a);
      expect(turn.counterValue, 7);
      expect(turn.counterLabel, 'DEFENDERS ON MAT');
    });

    test('the scorecard row sums to the score in its own last column', () {
      var s = apply(kabaddi.initialState(ctx), 'raid',
          side: Side.a, payload: const {'touched': 1, 'bonus': true});
      s = apply(s, 'technical', side: Side.a);
      s = apply(s, 'tackle', side: Side.b);

      final board = kabaddi.matBoard(s, ctx)!;
      expect(board.scorecardColumns.last, 'Total');
      for (final row in board.scorecard) {
        final parts = row.values.sublist(0, row.values.length - 1);
        expect(parts.fold<int>(0, (x, y) => x + y), row.values.last);
      }
    });
  });

  group('the pad', () {
    testWidgets('draws both scores, the rosters and the scorecard',
        (tester) async {
      await pump(tester, kabaddi.initialState(ctx));

      // Twice each: once on the scoreboard, once as the roster heading.
      expect(find.text('INDIA A — RAIDING'), findsOneWidget);
      expect(find.text('INDIA A'), findsOneWidget);
      expect(find.text('INDIA B'), findsNWidgets(2));
      expect(find.text('A Player 1'), findsWidgets);
      expect(find.text('Raid history'.toUpperCase()), findsOneWidget);
      expect(find.text('Scorecard'.toUpperCase()), findsOneWidget);
    });

    testWidgets('a scoring tile fires the control the plugin declared',
        (tester) async {
      ScoreControl? fired;
      await pump(
        tester,
        kabaddi.initialState(ctx),
        onControl: (c) => fired = c,
      );

      await tester.tap(find.text('Touch 1'));
      await tester.pump();

      expect(fired, isNotNull);
      expect(fired!.action, 'raid');
      expect(fired!.payload['touched'], 1);
      // Nothing to ask before it applies — which is the whole design.
      expect(fired!.needsInput, isFalse);
    });

    testWidgets('a finished match offers no way to score', (tester) async {
      final s = apply(kabaddi.initialState(ctx), 'finish');
      await pump(tester, s);

      expect(find.text('Touch 1'), findsNothing);
      expect(find.text('Reopen to correct'), findsOneWidget);
    });

    testWidgets('the pending queue is drawn once, with its question',
        (tester) async {
      final s = apply(kabaddi.initialState(ctx), 'raid',
          side: Side.a, payload: const {'touched': 2});

      await pump(tester, s);

      expect(find.text('Pending details'.toUpperCase()), findsOneWidget);
      expect(find.textContaining('Raid #1'), findsOneWidget);
      // Two touches by an unnamed raider leaves two questions open: who
      // raided, and which two defenders it put out.
      expect(find.text('Raider? · Players out?'), findsOneWidget);
      // The plugin also offers these as ordinary controls so a stacked pad
      // can clear them. This pad draws them properly, and must not draw them
      // a second time as an anonymous tile.
      expect(find.text('Details pending'.toUpperCase()), findsNothing);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('completing a detail asks who, and carries the parked id',
        (tester) async {
      final s = apply(kabaddi.initialState(ctx), 'raid',
          side: Side.a, payload: const {'touched': 2});

      ScoreControl? fired;
      await pump(tester, s, onControl: (c) => fired = c);
      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(fired!.action, 'attribute');
      expect(fired!.payload['id'], 'p1');
      expect(
        fired!.prompts.map((p) => p.key),
        ['playerId', 'defenderIds'],
      );
    });

    testWidgets('fits a phone without overflowing', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      var s = apply(kabaddi.initialState(ctx), 'raid',
          side: Side.a, payload: const {'touched': 2});
      s = apply(s, 'tackle', side: Side.b);

      await pump(tester, s, size: const Size(390, 2600));

      expect(errors, isEmpty, reason: errors.map((e) => e.summary).join('\n'));
    });
  });
}
