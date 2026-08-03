import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/football_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/features/scoring/widgets/box_score_table.dart';

/// The scorecard widgets, driven by real engine output rather than by
/// hand-written fixtures.
///
/// Twelve engines computed a [BoxScore] and cricket built a full
/// [InningsCard], and nothing in `lib/features` or `lib/shared` mentioned any
/// of those types — spectators and scorers only ever saw a headline string.
/// These tests pin the whole path: play events through the engine, hand the
/// resulting fixture to the widget, and assert the numbers reach the screen.
void main() {
  List<MatchPlayer> squad(String prefix, int n) => [
        for (var i = 1; i <= n; i++)
          MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
      ];

  Fixture fixtureWith({
    required String pluginKey,
    required Map<String, dynamic> scoreState,
    required Map<String, dynamic> config,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
  }) =>
      Fixture(
        id: 'fx1',
        orgId: 'org1',
        compId: 'comp1',
        entrantAId: 'ea',
        entrantBId: 'eb',
        entrantAName: 'Warangal FC',
        entrantBName: 'Nizamabad FC',
        status: FixtureStatus.live,
        scoringPluginKey: pluginKey,
        scoringConfig: config,
        scoreState: scoreState,
        lineupA: lineupA,
        lineupB: lineupB,
      );

  Future<void> pump(WidgetTester tester, Fixture fixture) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchScorecard(fixture: fixture),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('generic box score', () {
    const football = FootballPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Warangal FC',
      entrantBName: 'Nizamabad FC',
      config: const {'periods': 2, 'allowDraw': true},
      lineupA: squad('A', 11),
      lineupB: squad('B', 11),
    );

    Map<String, dynamic> playedState() {
      var s = football.initialState(ctx);
      for (final a in const [
        ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'assistId': 'A10'},
        ),
        ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9'},
        ),
      ]) {
        final r = football.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: r.rejection);
        s = r.state;
      }
      return s;
    }

    testWidgets('renders the scorer\'s line with the engine\'s own numbers',
        (tester) async {
      await pump(
        tester,
        fixtureWith(
          pluginKey: FootballPlugin.pluginKey,
          scoreState: playedState(),
          config: const {'periods': 2, 'allowDraw': true},
          lineupA: squad('A', 11),
          lineupB: squad('B', 11),
        ),
      );

      expect(find.text('Scorecard'), findsOneWidget);
      expect(find.text('Warangal FC'), findsWidgets);
      // The two-goal scorer and the assister are both on the sheet.
      expect(find.text('A Player 9'), findsOneWidget);
      expect(find.text('A Player 10'), findsOneWidget);
      // Column headings come from the plugin, not from this widget.
      expect(find.text('G'), findsWidgets);
      expect(find.text('A'), findsWidgets);
    });

    testWidgets('lists named players who never appeared as did-not-play',
        (tester) async {
      await pump(
        tester,
        fixtureWith(
          pluginKey: FootballPlugin.pluginKey,
          scoreState: playedState(),
          config: const {'periods': 2, 'allowDraw': true},
          lineupA: squad('A', 11),
          lineupB: squad('B', 11),
        ),
      );

      // A row of zeroes reads as "contributed nothing"; the sheet has to say
      // the difference.
      expect(
        find.textContaining('Did not play:'),
        findsWidgets,
      );
    });

    testWidgets('renders nothing at all before anyone has done anything',
        (tester) async {
      await pump(
        tester,
        fixtureWith(
          pluginKey: FootballPlugin.pluginKey,
          scoreState: football.initialState(ctx),
          config: const {'periods': 2, 'allowDraw': true},
          lineupA: squad('A', 11),
          lineupB: squad('B', 11),
        ),
      );

      // An empty "Scorecard" heading over an empty card reads as a fault.
      expect(find.text('Scorecard'), findsNothing);
    });
  });

  group('cricket innings card', () {
    const cricket = CricketPlugin();
    const config = {'oversPerInnings': 2, 'ballsPerOver': 6, 'playersPerSide': 3};

    final ctx = ScoringContext(
      entrantAName: 'Warangal FC',
      entrantBName: 'Nizamabad FC',
      config: config,
      lineupA: squad('A', 3),
      lineupB: squad('B', 3),
    );

    Map<String, dynamic> playedState() {
      var s = cricket.initialState(ctx);
      final actions = <ScoreAction>[
        const ScoreAction(
          type: 'open',
          payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
        ),
        const ScoreAction(type: 'runs', payload: {'runs': 4}),
        const ScoreAction(type: 'runs', payload: {'runs': 6}),
        const ScoreAction(type: 'runs', payload: {'runs': 1}),
        const ScoreAction(type: 'wide', payload: {'runs': 0}),
      ];
      for (final a in actions) {
        final r = cricket.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    testWidgets('shows the batting card, extras and the bowling figures',
        (tester) async {
      final state = playedState();
      final card = cricket.card(state, ctx);
      expect(card, isNotNull, reason: 'the engine must produce an innings');

      await pump(
        tester,
        fixtureWith(
          pluginKey: CricketPlugin.pluginKey,
          scoreState: state,
          config: config,
          lineupA: squad('A', 3),
          lineupB: squad('B', 3),
        ),
      );

      expect(find.text('Scorecard'), findsOneWidget);
      // The headline the engine computed, rendered verbatim — the widget does
      // not recompute a score.
      expect(find.text(card!.headline), findsOneWidget);
      // Batting and bowling sections, both keyed off the domain model.
      expect(find.text('Bowling'), findsOneWidget);
      expect(find.text('Batter'), findsOneWidget);
      expect(find.text('Bowler'), findsOneWidget);
      // The opener faced the whole over; the non-striker is on the card too.
      expect(find.textContaining('A Player 1'), findsWidgets);
      // One wide, so extras must be visible rather than folded into the total.
      expect(find.textContaining('Extras 1'), findsOneWidget);
      // The bowler who bowled is listed by name.
      expect(find.text('B Player 1'), findsOneWidget);
    });
  });
}
