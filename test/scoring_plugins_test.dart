import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/goal_based_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/set_based_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/simple_points_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// Applies a script of actions and returns the final state, failing loudly on
/// any rejection that the test did not expect.
Map<String, dynamic> run(
  ScoringPlugin plugin,
  ScoringContext ctx,
  List<ScoreAction> actions, {
  Map<String, dynamic>? from,
}) {
  var state = from ?? plugin.initialState(ctx);
  for (final a in actions) {
    final result = plugin.apply(state, a, ctx);
    expect(
      result.isAccepted,
      isTrue,
      reason: 'Action "${a.type}" was rejected: ${result.rejection}',
    );
    state = result.state;
  }
  return state;
}

ScoreAction point(Side side) => ScoreAction(type: 'point', side: side);

void main() {
  const ctx = ScoringContext(entrantAName: 'A', entrantBName: 'B');

  group('SimplePointsPlugin', () {
    const plugin = SimplePointsPlugin();

    test('counts points for each side', () {
      final state = run(plugin, ctx, [
        point(Side.a),
        point(Side.a),
        point(Side.b),
      ]);
      expect(state['a'], 2);
      expect(state['b'], 1);
    });

    test('a correction cannot drive a score below zero', () {
      final result = plugin.apply(
        plugin.initialState(ctx),
        const ScoreAction(type: 'correct', side: Side.a),
        ctx,
      );
      expect(result.isAccepted, isFalse);
      expect(result.rejection, contains('zero'));
    });

    test('reaching the target ends the match', () {
      const target = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {'target': 3, 'winBy': 1},
      );
      final state = run(plugin, target, [
        point(Side.a),
        point(Side.a),
        point(Side.a),
      ]);
      expect(state['complete'], isTrue);
      expect(state['winner'], 'a');
    });

    test('a finished match rejects further scoring', () {
      const target = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {'target': 1, 'winBy': 1},
      );
      final done = run(plugin, target, [point(Side.a)]);
      final result = plugin.apply(done, point(Side.b), target);
      expect(result.isAccepted, isFalse);
    });
  });

  group('SetBasedPlugin — badminton rules', () {
    const plugin = SetBasedPlugin();
    const badminton = ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      config: {
        'pointsPerSet': 21,
        'setsToWin': 2,
        'winBy': 2,
        'hardCap': 30,
      },
    );

    test('a game is not won at 21 when the lead is only one', () {
      // 20-20, then A scores: 21-20 is NOT a game.
      final state = run(plugin, badminton, [
        for (var i = 0; i < 20; i++) point(Side.a),
        for (var i = 0; i < 20; i++) point(Side.b),
        point(Side.a),
      ]);
      expect(state['setsA'], 0, reason: '21-20 must not close the game');
      expect(state['currentA'], 21);
      expect(state['currentB'], 20);
    });

    test('a two point lead closes the game', () {
      final state = run(plugin, badminton, [
        for (var i = 0; i < 20; i++) point(Side.a),
        for (var i = 0; i < 20; i++) point(Side.b),
        point(Side.a),
        point(Side.a),
      ]);
      expect(state['setsA'], 1);
      expect(state['currentA'], 0, reason: 'a new game starts at zero');
    });

    test('the hard cap at 30 ends a game even with a one point lead', () {
      // Drive to 29-29, then a single point must take it.
      final state = run(plugin, badminton, [
        for (var i = 0; i < 29; i++) ...[point(Side.a), point(Side.b)],
        point(Side.a),
      ]);
      expect(state['setsA'], 1, reason: '30-29 wins under the cap');
    });

    test('two games wins the match', () {
      var state = plugin.initialState(badminton);
      for (var game = 0; game < 2; game++) {
        state = run(
          plugin,
          badminton,
          [for (var i = 0; i < 21; i++) point(Side.a)],
          from: state,
        );
      }
      expect(state['complete'], isTrue);
      expect(state['winner'], 'a');
      expect(plugin.outcome(state, badminton).winnerSide, Side.a);
    });
  });

  group('SetBasedPlugin — volleyball deciding set', () {
    const plugin = SetBasedPlugin();
    const volleyball = ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      config: {
        'pointsPerSet': 25,
        'decidingSetPoints': 15,
        'setsToWin': 3,
        'winBy': 2,
      },
    );

    test('the fifth set is played to 15, not 25', () {
      var state = plugin.initialState(volleyball);
      // A takes two sets, B takes two sets -> 2-2, deciding set next.
      for (var i = 0; i < 2; i++) {
        state = run(plugin, volleyball,
            [for (var j = 0; j < 25; j++) point(Side.a)], from: state);
      }
      for (var i = 0; i < 2; i++) {
        state = run(plugin, volleyball,
            [for (var j = 0; j < 25; j++) point(Side.b)], from: state);
      }
      expect(state['setsA'], 2);
      expect(state['setsB'], 2);

      // 15 points now takes the match.
      state = run(plugin, volleyball,
          [for (var j = 0; j < 15; j++) point(Side.a)], from: state);
      expect(state['complete'], isTrue);
      expect(state['winner'], 'a');
    });
  });

  group('GoalBasedPlugin', () {
    const plugin = GoalBasedPlugin();

    test('basketball scores 1, 2 and 3 pointers', () {
      const basketball = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {'scoreValues': [1, 2, 3], 'periods': 4, 'allowDraw': false},
      );
      final state = run(plugin, basketball, [
        const ScoreAction(type: 'score', side: Side.a, payload: {'value': 3}),
        const ScoreAction(type: 'score', side: Side.a, payload: {'value': 2}),
        const ScoreAction(type: 'score', side: Side.b, payload: {'value': 1}),
      ]);
      expect(state['a'], 5);
      expect(state['b'], 1);
    });

    test('a level score cannot be finished when draws are disallowed', () {
      const noDraws = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {'allowDraw': false},
      );
      final result =
          plugin.apply(plugin.initialState(noDraws), const ScoreAction(type: 'finish'), noDraws);
      expect(result.isAccepted, isFalse);
      expect(result.rejection, contains('level'));
    });

    test('periods cannot exceed the configured count', () {
      const football = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {'periods': 2},
      );
      final afterFirst = run(
        plugin,
        football,
        [const ScoreAction(type: 'next_period')],
      );
      final result = plugin.apply(
        afterFirst,
        const ScoreAction(type: 'next_period'),
        football,
      );
      expect(result.isAccepted, isFalse);
    });
  });

  group('CricketPlugin', () {
    const plugin = CricketPlugin();
    const t20 = ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      config: {
        'oversPerInnings': 2,
        'ballsPerOver': 6,
        'playersPerTeam': 11,
      },
    );

    Map<String, dynamic> innings(Map<String, dynamic> state, [int index = 0]) =>
        (state['innings'] as List)[index] as Map<String, dynamic>;

    test('a wide adds a run but does NOT consume a delivery', () {
      final state = run(plugin, t20, [
        const ScoreAction(type: 'wide'),
      ]);
      final i = innings(state);
      expect(i['runs'], 1);
      expect(i['legalBalls'], 0, reason: 'a wide is not a legal delivery');
      expect((i['extras'] as Map)['wide'], 1);
    });

    test('a no-ball adds a run, does not consume a ball, and sets a free hit',
        () {
      final state = run(plugin, t20, [
        const ScoreAction(type: 'no_ball'),
      ]);
      expect(innings(state)['runs'], 1);
      expect(innings(state)['legalBalls'], 0);
      expect(state['freeHit'], isTrue);
    });

    test('on a free hit only a run out is allowed', () {
      final afterNoBall =
          run(plugin, t20, [const ScoreAction(type: 'no_ball')]);

      final bowled = plugin.apply(
        afterNoBall,
        const ScoreAction(type: 'wicket'),
        t20,
      );
      expect(bowled.isAccepted, isFalse);
      expect(bowled.rejection, contains('Free hit'));

      final runOut = plugin.apply(
        afterNoBall,
        const ScoreAction(type: 'wicket', payload: {'runOut': true}),
        t20,
      );
      expect(runOut.isAccepted, isTrue);
    });

    test('byes are extras but DO consume a delivery', () {
      final state = run(plugin, t20, [
        const ScoreAction(type: 'bye', payload: {'runs': 2}),
      ]);
      final i = innings(state);
      expect(i['runs'], 2);
      expect(i['legalBalls'], 1);
      expect((i['extras'] as Map)['bye'], 2);
    });

    test('the innings closes after the configured number of overs', () {
      // 2 overs = 12 legal deliveries.
      final state = run(plugin, t20, [
        for (var i = 0; i < 12; i++)
          const ScoreAction(type: 'runs', payload: {'runs': 1}),
      ]);
      expect(innings(state)['closed'], isTrue);
      expect(state['inningsIndex'], 1, reason: 'the chase should have started');
      expect(state['target'], 13, reason: '12 runs scored, target is 13');
    });

    test('a chase ends the moment the target is passed', () {
      var state = run(plugin, t20, [
        for (var i = 0; i < 6; i++)
          const ScoreAction(type: 'runs', payload: {'runs': 1}),
        const ScoreAction(type: 'end_innings'),
      ]);
      expect(state['target'], 7);

      // Chasing side reaches 7 on the third ball — the match must end there.
      state = run(plugin, t20, [
        const ScoreAction(type: 'runs', payload: {'runs': 3}),
        const ScoreAction(type: 'runs', payload: {'runs': 3}),
        const ScoreAction(type: 'runs', payload: {'runs': 1}),
      ], from: state);

      expect(state['complete'], isTrue);
      expect(state['winner'], 'b');
    });

    test('levelling the target is a tie, not a win', () {
      var state = run(plugin, t20, [
        for (var i = 0; i < 6; i++)
          const ScoreAction(type: 'runs', payload: {'runs': 1}),
        const ScoreAction(type: 'end_innings'),
      ]);
      // Target is 7; the chase makes exactly 6 then runs out of overs.
      state = run(plugin, t20, [
        for (var i = 0; i < 6; i++)
          const ScoreAction(type: 'runs', payload: {'runs': 1}),
        const ScoreAction(type: 'end_innings'),
      ], from: state);

      expect(state['complete'], isTrue);
      expect(state['tie'], isTrue);
      expect(state['winner'], isNull);
    });

    test('overs read correctly with wides interleaved', () {
      final state = run(plugin, t20, [
        const ScoreAction(type: 'runs', payload: {'runs': 1}),
        const ScoreAction(type: 'wide'),
        const ScoreAction(type: 'runs', payload: {'runs': 1}),
        const ScoreAction(type: 'wide'),
        const ScoreAction(type: 'runs', payload: {'runs': 1}),
      ]);
      final line = plugin.statusLine(state, t20)!;
      expect(line, startsWith('0.3'),
          reason: 'three legal balls despite two wides');
    });
  });

  group('replay reproduces state exactly', () {
    test('a scripted badminton game replays to the same score', () {
      const plugin = SetBasedPlugin();
      const badminton = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {'pointsPerSet': 21, 'setsToWin': 2, 'winBy': 2, 'hardCap': 30},
      );

      final actions = <ScoreAction>[
        for (var i = 0; i < 15; i++) point(Side.a),
        for (var i = 0; i < 9; i++) point(Side.b),
        for (var i = 0; i < 6; i++) point(Side.a),
      ];

      final live = run(plugin, badminton, actions);
      final replayed = plugin.replay(actions, badminton);

      expect(replayed['setsA'], live['setsA']);
      expect(replayed['currentA'], live['currentA']);
      expect(replayed['currentB'], live['currentB']);
    });
  });

  group('ScoringRegistry', () {
    test('every catalogued sport resolves to a real plugin', () {
      for (final sport in SportCatalog.all) {
        final plugin = ScoringRegistry.forSport(sport.id);
        expect(plugin.key, sport.pluginKey,
            reason: '${sport.name} must resolve to its declared plugin');
      }
    });

    test('an unknown plugin key falls back rather than throwing', () {
      // Guarantees a competition created by a newer build still opens in an
      // older one instead of showing a permanently broken match screen.
      final plugin = ScoringRegistry.resolve('a_sport_from_the_future');
      expect(plugin.key, SimplePointsPlugin.pluginKey);
    });

    test('every sport can produce controls from its initial state', () {
      for (final sport in SportCatalog.all) {
        final plugin = ScoringRegistry.forSport(sport.id);
        final ctx = ScoringContext(
          entrantAName: 'A',
          entrantBName: 'B',
          config: sport.config,
        );
        final controls = plugin.controls(plugin.initialState(ctx), ctx);
        expect(controls, isNotEmpty,
            reason: '${sport.name} must offer at least one scoring control');
      }
    });
  });
}
