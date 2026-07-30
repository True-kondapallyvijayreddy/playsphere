import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Cricket's contribution to the shared player tally, and the dismissal cases
/// that a total-only engine gets wrong.
///
/// The tally matters because it is the only thing the career aggregator and
/// the rating service read. Before it existed, every cricket match in the
/// product contributed nothing at all to a player's lifelong record — which
/// is the record the whole product is built to keep.
void main() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  ScoringContext ctxWith([Map<String, dynamic> overrides = const {}]) =>
      ScoringContext(
        entrantAName: 'Warangal',
        entrantBName: 'Nizamabad',
        config: RulePresets.resolve(
          sportId: 'cricket',
          overrides: {
            'oversPerInnings': 5,
            'playersPerTeam': 11,
            'battingFirst': 'a',
            ...overrides,
          },
        ).toMap(),
        lineupA: squad('A'),
        lineupB: squad('B'),
      );

  final ctx = ctxWith();

  Map<String, dynamic> play(
    Map<String, dynamic> state,
    List<ScoreAction> actions, {
    ScoringContext? context,
  }) {
    var s = state;
    for (final a in actions) {
      final r = cricket.apply(s, a, context ?? ctx);
      expect(r.isAccepted, isTrue,
          reason: 'rejected "${a.type}": ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  ScoreAction open() => const ScoreAction(
        type: 'open',
        payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
      );

  ScoreAction runs(int n) => ScoreAction(type: 'runs', payload: {'runs': n});

  Map<String, num> tally(Map<String, dynamic> s, String id) =>
      PlayerTally.of(s, id);

  Map<String, dynamic> started([ScoringContext? c]) =>
      play(cricket.initialState(c ?? ctx), [open()], context: c);

  // ==========================================================================
  group('the shared tally mirrors the scorecard', () {
    test('batting figures reach the tally, split by who was on strike', () {
      final s = play(started(), [runs(4), runs(1), runs(6), runs(0)]);

      // A1 faced the 4 and the single; the single put A2 on strike, so the
      // six and the dot are A2's.
      final a1 = tally(s, 'A1');
      expect(a1['runsScored'], 5);
      expect(a1['ballsFaced'], 2);
      expect(a1['fours'], 1);
      expect(a1['sixes'], null);

      final a2 = tally(s, 'A2');
      expect(a2['runsScored'], 6);
      expect(a2['ballsFaced'], 2);
      expect(a2['sixes'], 1);
    });

    test('bowling figures reach the tally', () {
      final s = play(started(), [
        runs(4),
        runs(0),
        runs(0),
        runs(2),
        runs(0),
        runs(0),
      ]);
      final b1 = tally(s, 'B1');
      expect(b1['ballsBowled'], 6);
      expect(b1['runsConceded'], 6);
      expect(b1['wickets'], null);
    });

    test('a maiden over reaches the tally', () {
      final s = play(started(), [
        runs(0), runs(0), runs(0), runs(0), runs(0), runs(0),
      ]);
      expect(tally(s, 'B1')['maidens'], 1);
      expect(tally(s, 'B1')['runsConceded'], null);
    });

    test('byes reach neither the batter nor the bowler', () {
      final s = play(started(), [
        const ScoreAction(type: 'bye', payload: {'runs': 4}),
      ]);
      final a1 = tally(s, 'A1');
      expect(a1['runsScored'], null, reason: 'byes are not the batter\'s runs');
      expect(a1['ballsFaced'], 1, reason: 'but the ball was faced');
      expect(tally(s, 'B1')['runsConceded'], null,
          reason: 'and the bowler is not charged');
      expect(tally(s, 'B1')['ballsBowled'], 1);
    });

    test('wides charge the bowler but cost the batter no ball faced', () {
      final s = play(started(), [
        const ScoreAction(type: 'wide', payload: {'runs': 0}),
      ]);
      expect(tally(s, 'A1')['ballsFaced'], null);
      expect(tally(s, 'B1')['runsConceded'], 1);
      expect(tally(s, 'B1')['ballsBowled'], null,
          reason: 'a wide is not a legal delivery');
    });

    test('the tally is rebuilt from the innings, never double-counted', () {
      // Scoring the same runs across many balls must not compound: the mirror
      // recomputes rather than incrementing.
      final s = play(started(), [runs(2), runs(2), runs(2)]);
      expect(tally(s, 'A1')['runsScored'], 6);
      expect(tally(s, 'A1')['ballsFaced'], 3);
    });
  });

  // ==========================================================================
  group('dismissals', () {
    test('a run-out is not credited to the bowler, but is to the fielder', () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {
            'type': 'run_out',
            'fielder': 'B5',
            'assist': 'B7',
          },
        ),
      ]);
      expect(tally(s, 'B1')['wickets'], null, reason: 'not the bowler\'s');
      expect(tally(s, 'B5')['runOuts'], 1);
      expect(tally(s, 'B7')['runOutAssists'], 1);
    });

    test('a catch is credited to the fielder and the wicket to the bowler', () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'caught', 'fielder': 'B4'},
        ),
      ]);
      expect(tally(s, 'B1')['wickets'], 1);
      expect(tally(s, 'B4')['catches'], 1);
    });

    test('a stumping is credited to the keeper, not as a catch', () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'stumped', 'keeper': 'B2'},
        ),
      ]);
      expect(tally(s, 'B2')['stumpings'], 1);
      expect(tally(s, 'B2')['catches'], null);
      expect(tally(s, 'B1')['wickets'], 1);
    });

    test('the dismissed batter is counted, and only once', () {
      final s = play(started(), [
        const ScoreAction(type: 'wicket', payload: {'type': 'bowled'}),
      ]);
      expect(tally(s, 'A1')['dismissed'], 1);
      expect(tally(s, 'A2')['dismissed'], null);
    });
  });

  // ==========================================================================
  group('a non-striker run-out debits the right batter', () {
    test('the non-striker goes, and the striker keeps their place', () {
      var s = started();
      // A1 faces two balls and is on strike.
      s = play(s, [runs(2), runs(2)]);
      expect(tally(s, 'A1')['ballsFaced'], 2);

      // A2, backing up, is run out at the bowler's end.
      s = play(s, [
        const ScoreAction(
          type: 'wicket',
          payload: {
            'type': 'run_out',
            'playerId': 'A2',
            'fielder': 'B3',
          },
        ),
      ]);

      // A2 is the one dismissed. This is the figure a naive engine corrupts:
      // it marks the striker out and ends their innings on the spot.
      expect(tally(s, 'A2')['dismissed'], 1);
      expect(tally(s, 'A1')['dismissed'], null,
          reason: 'the striker was not out');

      // The delivery was legal and the striker did face it, so their ball
      // count moves on — but their runs and their wicket do not.
      expect(tally(s, 'A1')['ballsFaced'], 3);
      expect(tally(s, 'A1')['runsScored'], 4);

      // The vacant end is the non-striker's.
      final inn = (s['innings'] as List).first as Map;
      expect(inn['striker'], 'A1');
      expect(inn['nonStriker'], isNull);
    });

    test('fall of wicket names the batter who actually went', () {
      var s = started();
      s = play(s, [
        runs(1), // A2 now on strike
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'run_out', 'playerId': 'A1', 'fielder': 'B3'},
        ),
      ]);
      final inn = (s['innings'] as List).first as Map;
      final fow = (inn['fow'] as List).first as Map;
      expect(fow['playerId'], 'A1');
    });

    test('a batter not at the crease cannot be dismissed', () {
      final r = cricket.apply(
        started(),
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'run_out', 'playerId': 'A9'},
        ),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });
  });

  // ==========================================================================
  group('a wicket can fall off an illegal delivery', () {
    test('a stumping off a wide keeps the wide and does not consume a ball',
        () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {
            'type': 'stumped',
            'keeper': 'B2',
            'delivery': 'wide',
          },
        ),
      ]);

      final inn = (s['innings'] as List).first as Map;
      expect(inn['runs'], 1, reason: 'the wide penalty still stands');
      expect((inn['extras'] as Map)['wide'], 1);
      expect(inn['legalBalls'], 0, reason: 'a wide is not a legal delivery');
      expect(inn['wickets'], 1);
      expect(tally(s, 'B2')['stumpings'], 1);
    });

    test('a run-out off a no-ball keeps the penalty and the free hit', () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {
            'type': 'run_out',
            'playerId': 'A2',
            'fielder': 'B3',
            'delivery': 'no_ball',
          },
        ),
      ]);

      final inn = (s['innings'] as List).first as Map;
      expect(inn['runs'], 1, reason: 'the no-ball penalty still stands');
      expect(inn['legalBalls'], 0);
      expect(s['freeHit'], isTrue, reason: 'a no-ball still grants a free hit');
      expect(tally(s, 'B1')['wickets'], null, reason: 'run-out, not the bowler');
    });

    test('an ordinary wicket still consumes a legal delivery', () {
      final s = play(started(), [
        const ScoreAction(type: 'wicket', payload: {'type': 'bowled'}),
      ]);
      final inn = (s['innings'] as List).first as Map;
      expect(inn['legalBalls'], 1);
    });
  });

  // ==========================================================================
  group('rule config drives the numbers, not constants', () {
    test('the tennis-ball preset charges two for a wide and grants no free hit',
        () {
      final tennisBall = ctxWith(
        RulePresets.resolve(presetId: 'cricket_tennis_ball').toMap()
          ..['battingFirst'] = 'a',
      );
      final s = play(
        started(tennisBall),
        [const ScoreAction(type: 'wide', payload: {'runs': 0})],
        context: tennisBall,
      );
      final inn = (s['innings'] as List).first as Map;
      expect(inn['runs'], 2, reason: 'a wide costs two under these rules');

      final afterNoBall = play(
        s,
        [const ScoreAction(type: 'no_ball', payload: {'runs': 0})],
        context: tennisBall,
      );
      expect(afterNoBall['freeHit'], isFalse,
          reason: 'this preset disables the free hit');
    });

    test('a free hit is granted when the preset enables it', () {
      final s = play(started(), [
        const ScoreAction(type: 'no_ball', payload: {'runs': 0}),
      ]);
      expect(s['freeHit'], isTrue);
    });
  });

  // ==========================================================================
  group('replay', () {
    test('replaying the log reproduces the tally exactly', () {
      final script = [
        open(),
        runs(4),
        const ScoreAction(type: 'wide', payload: {'runs': 1}),
        runs(1),
        const ScoreAction(type: 'no_ball', payload: {'runs': 6}),
        const ScoreAction(type: 'bye', payload: {'runs': 2}),
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'caught', 'fielder': 'B4'},
        ),
        const ScoreAction(type: 'new_batter', payload: {'playerId': 'A3'}),
        runs(2),
      ];

      final direct = play(cricket.initialState(ctx), script);
      final replayed = cricket.replay(script, ctx);
      expect(replayed, direct);
      // And the tally survives the round trip rather than coming back empty.
      expect(PlayerTally.of(replayed, 'A1')['runsScored'], isNotNull);
      expect(PlayerTally.of(replayed, 'B4')['catches'], 1);
    });
  });
}
