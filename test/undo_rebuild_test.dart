import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// UNDO, and the rebuild it depends on — CLAUDE.md §12.1.
///
/// The rule is that the event log is never mutated: a mistake is withdrawn by
/// appending a reversal, and the projection is recomputed from the events that
/// survive. These tests pin that the log keeps growing, that the withdrawn
/// event stops counting, and that a rebuild from scratch equals the state you
/// would have had if the mistake had never been made.
void main() {
  // A tiny log helper: sequence numbers are assigned in order, as the real
  // service does.
  List<LoggedAction> logOf(List<ScoreAction> actions) => [
        for (var i = 0; i < actions.length; i++)
          LoggedAction(seq: i + 1, action: actions[i]),
      ];

  ScoreAction undo(int seq) => ScoreAction(
        type: ScoringPlugin.undoActionType,
        payload: {'reversesSeq': seq},
      );

  // ==========================================================================
  group('badminton', () {
    const badminton = BadmintonPlugin();
    final ctx = ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      config: RulePresets.resolve(sportId: 'badminton').toMap(),
    );

    ScoreAction rally(Side side) => ScoreAction(type: 'rally', side: side);

    test('a withdrawn rally stops counting', () {
      final withMistake = badminton.rebuild(
        logOf([rally(Side.a), rally(Side.a), rally(Side.b)]),
        ctx,
      );
      expect(withMistake['currentA'], 2);
      expect(withMistake['currentB'], 1);

      // Seq 3 was a misread — the rally actually went to A.
      final corrected = badminton.rebuild(
        logOf([rally(Side.a), rally(Side.a), rally(Side.b), undo(3)]),
        ctx,
      );
      expect(corrected['currentA'], 2);
      expect(corrected['currentB'], 0);
    });

    test('a correction equals the state where the mistake never happened', () {
      final corrected = badminton.rebuild(
        logOf([rally(Side.a), rally(Side.b), rally(Side.a), undo(2)]),
        ctx,
      );
      final never = badminton.rebuild(
        logOf([rally(Side.a), rally(Side.a)]),
        ctx,
      );
      // Identical in every respect, including whose serve it is — which is
      // the part a naive "just decrement the score" undo gets wrong.
      expect(corrected['currentA'], never['currentA']);
      expect(corrected['currentB'], never['currentB']);
      expect(corrected['server'], never['server']);
    });

    test('an event in the middle of the log can be withdrawn', () {
      final corrected = badminton.rebuild(
        logOf([
          rally(Side.a),
          rally(Side.b), // the mistake
          rally(Side.a),
          rally(Side.a),
          undo(2),
        ]),
        ctx,
      );
      expect(corrected['currentA'], 3);
      expect(corrected['currentB'], 0);
    });

    test('an undo can itself be undone', () {
      final log = logOf([
        rally(Side.a),
        rally(Side.b),
        undo(2), // withdraw B's point
        undo(3), // ...no, that was wrong: put it back
      ]);
      final s = badminton.rebuild(log, ctx);
      expect(s['currentA'], 1);
      expect(s['currentB'], 1, reason: 'the withdrawal was itself withdrawn');
    });

    test('the undo event is never applied as a scoring action', () {
      // An engine that tried to `apply` an undo would reject it as unknown
      // and the rebuild would be wrong. Prove it is filtered out instead.
      final s = badminton.rebuild(logOf([rally(Side.a), undo(1)]), ctx);
      expect(s['currentA'], 0);
      expect(s['currentB'], 0);
    });

    test('an undo naming no event is ignored rather than crashing', () {
      final s = badminton.rebuild(
        [
          const LoggedAction(seq: 1, action: ScoreAction(type: 'rally', side: Side.a)),
          const LoggedAction(
            seq: 2,
            action: ScoreAction(type: ScoringPlugin.undoActionType),
          ),
        ],
        ctx,
      );
      expect(s['currentA'], 1);
    });

    test('out-of-order log entries are sorted before replay', () {
      final shuffled = [
        LoggedAction(seq: 3, action: rally(Side.b)),
        LoggedAction(seq: 1, action: rally(Side.a)),
        LoggedAction(seq: 2, action: rally(Side.a)),
      ];
      final s = badminton.rebuild(shuffled, ctx);
      expect(s['currentA'], 2);
      expect(s['currentB'], 1);
    });

    test('withdrawing a game-winning point reopens the game', () {
      final script = <ScoreAction>[
        for (var i = 0; i < 21; i++) rally(Side.a),
      ];
      final won = badminton.rebuild(logOf(script), ctx);
      expect(won['gamesA'], 1);

      final withdrawn = badminton.rebuild(
        logOf([...script, undo(21)]),
        ctx,
      );
      expect(withdrawn['gamesA'], 0, reason: 'the game is live again');
      expect(withdrawn['currentA'], 20);
    });
  });

  // ==========================================================================
  group('cricket', () {
    const cricket = CricketPlugin();

    List<MatchPlayer> squad(String p) => [
          for (var n = 1; n <= 11; n++)
            MatchPlayer(id: '$p$n', name: '$p Player $n'),
        ];

    final ctx = ScoringContext(
      entrantAName: 'Warangal',
      entrantBName: 'Nizamabad',
      config: RulePresets.resolve(
        sportId: 'cricket',
        overrides: {'oversPerInnings': 5, 'battingFirst': 'a'},
      ).toMap(),
      lineupA: squad('A'),
      lineupB: squad('B'),
    );

    const open = ScoreAction(
      type: 'open',
      payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
    );

    ScoreAction runs(int n) => ScoreAction(type: 'runs', payload: {'runs': n});

    test('a ball entered as 6 instead of 4 can be corrected', () {
      // The scorer taps 6, realises it was a 4.
      final wrong = cricket.rebuild(logOf([open, runs(2), runs(6)]), ctx);
      expect((wrong['innings'] as List).first['runs'], 8);

      final corrected = cricket.rebuild(
        logOf([open, runs(2), runs(6), undo(3), runs(4)]),
        ctx,
      );
      final inn = (corrected['innings'] as List).first as Map;
      expect(inn['runs'], 6);
      expect(inn['legalBalls'], 2, reason: 'still two legal deliveries');

      // And the batter's own figures are right, not just the team total.
      final a1 = PlayerTally.of(corrected, 'A1');
      expect(a1['runsScored'], 6);
      expect(a1['ballsFaced'], 2);
      expect(a1['sixes'], null, reason: 'the six never happened');
      expect(a1['fours'], 1);
    });

    test('a wrongly recorded wicket can be withdrawn', () {
      final withWicket = cricket.rebuild(
        logOf([
          open,
          runs(4),
          const ScoreAction(
            type: 'wicket',
            payload: {'type': 'caught', 'fielder': 'B4'},
          ),
        ]),
        ctx,
      );
      expect((withWicket['innings'] as List).first['wickets'], 1);
      expect(PlayerTally.of(withWicket, 'B4')['catches'], 1);

      final corrected = cricket.rebuild(
        logOf([
          open,
          runs(4),
          const ScoreAction(
            type: 'wicket',
            payload: {'type': 'caught', 'fielder': 'B4'},
          ),
          undo(3),
        ]),
        ctx,
      );
      final inn = (corrected['innings'] as List).first as Map;
      expect(inn['wickets'], 0);
      expect(inn['striker'], 'A1', reason: 'the batter is back at the crease');
      expect(PlayerTally.of(corrected, 'B4')['catches'], null,
          reason: 'the fielder loses the catch too');
    });

    test('the fall-of-wicket list loses the withdrawn entry', () {
      final corrected = cricket.rebuild(
        logOf([
          open,
          const ScoreAction(type: 'wicket', payload: {'type': 'bowled'}),
          undo(2),
        ]),
        ctx,
      );
      final inn = (corrected['innings'] as List).first as Map;
      expect(inn['fow'], isEmpty);
    });
  });

  // ==========================================================================
  group('rebuild is a pure function of the surviving log', () {
    const badminton = BadmintonPlugin();
    final ctx = ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      config: RulePresets.resolve(sportId: 'badminton').toMap(),
    );

    ScoreAction rally(Side side) => ScoreAction(type: 'rally', side: side);

    test('rebuilding twice gives the same answer', () {
      final log = logOf([
        rally(Side.a),
        rally(Side.b),
        rally(Side.a),
        undo(2),
        rally(Side.b),
      ]);
      expect(badminton.rebuild(log, ctx), badminton.rebuild(log, ctx));
    });

    test('a log with no corrections matches plain replay', () {
      final actions = [rally(Side.a), rally(Side.b), rally(Side.a)];
      expect(
        badminton.rebuild(logOf(actions), ctx),
        badminton.replay(actions, ctx),
      );
    });

    test('an empty log rebuilds to the opening state', () {
      expect(badminton.rebuild(const [], ctx), badminton.initialState(ctx));
    });
  });
}
