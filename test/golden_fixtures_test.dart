import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/kabaddi_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/volleyball_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// The six golden fixtures CLAUDE.md §12.5 names by hand.
///
/// A golden fixture is an event log replayed against a **hand-written expected
/// result**. That distinction is the whole point: the engine tests elsewhere
/// in this suite check `replay(script) == play(script)`, which runs the same
/// reducer twice and would pass even if every rule were wrong. Nothing here
/// compares the code to itself — every expectation below was worked out from
/// the laws of the sport and written down before the assertion.
///
/// The six cases are the ones the spec singles out because they are where
/// real scoring engines break:
///
///   1. cricket — a wide, a no-ball and a run-out in one over
///   2. badminton — 29-29 going to 30 on the cap
///   3. table tennis — deuce at 10-10 running out to 13-11
///   4. volleyball — the change of ends in the deciding set
///   5. kabaddi — a super tackle and an all-out
///   6. tennis — the tiebreak serve order
void main() {
  // ==========================================================================
  group('GOLDEN 1 — cricket: wide, no-ball and run-out in one over', () {
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

    /// The log. Deliberately written out as data, so the fixture reads as a
    /// scorecard rather than as code.
    final log = <ScoreAction>[
      const ScoreAction(
        type: 'open',
        payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
      ),
      // 1. A legal ball, four runs.
      const ScoreAction(type: 'runs', payload: {'runs': 4}),
      // 2. A wide. Not a legal ball; nothing run off it, so the strike does
      //    not rotate and A1 keeps the bowling.
      const ScoreAction(type: 'wide', payload: {'runs': 0}),
      // 3. A no-ball hit for six. Not a legal ball; grants a free hit.
      const ScoreAction(type: 'no_ball', payload: {'runs': 6}),
      // 4. The free hit — only a run-out is possible. Two runs taken, the
      //    non-striker is run out going back for the second.
      const ScoreAction(
        type: 'wicket',
        payload: {
          'type': 'run_out',
          'playerId': 'A2',
          'fielder': 'B5',
          'assist': 'B7',
          'runs': 2,
        },
      ),
      const ScoreAction(type: 'new_batter', payload: {'playerId': 'A3'}),
      // 5. Two byes. A legal ball; charged to neither batter nor bowler.
      const ScoreAction(type: 'bye', payload: {'runs': 2}),
      // 6. A single.
      const ScoreAction(type: 'runs', payload: {'runs': 1}),
    ];

    late Map<String, dynamic> state;
    setUp(() => state = cricket.replay(log, ctx));

    test('the team total is 17', () {
      // 4 (off bat) + 1 (wide penalty) + 7 (no-ball: 1 + 6)
      // + 2 (run-out delivery) + 2 (byes) + 1 (single) = 17.
      final inn = (state['innings'] as List).first as Map;
      expect(inn['runs'], 17);
    });

    test('only four deliveries were legal', () {
      // The wide and the no-ball are re-bowled. The four, the run-out ball,
      // the byes and the single are the legal ones.
      final inn = (state['innings'] as List).first as Map;
      expect(inn['legalBalls'], 4);
    });

    test('extras are 4: one wide plus its run, one no-ball, two byes', () {
      final inn = (state['innings'] as List).first as Map;
      final extras = inn['extras'] as Map;
      expect(extras['wide'], 1, reason: 'the penalty; nothing was run');
      expect(extras['noBall'], 1, reason: 'the penalty only — 6 went to the bat');
      expect(extras['bye'], 2);
      expect(extras['legBye'], 0);
      expect(inn['extras'], isA<Map>());
    });

    test("the striker's figures exclude wides, byes and the extras", () {
      final a1 = PlayerTally.of(state, 'A1');
      // 4 off the bat, 6 off the no-ball, 2 on the run-out ball, 1 single.
      expect(a1['runsScored'], 13);
      // The four, the no-ball (faced), the run-out ball, the byes, the
      // single. NOT the wide.
      expect(a1['ballsFaced'], 5);
      expect(a1['fours'], 1);
      expect(a1['sixes'], 1);
      expect(a1['dismissed'], null, reason: 'the non-striker went, not A1');
    });

    test('the non-striker is the one recorded out', () {
      expect(PlayerTally.of(state, 'A2')['dismissed'], 1);
      final inn = (state['innings'] as List).first as Map;
      final fow = (inn['fow'] as List).single as Map;
      expect(fow['playerId'], 'A2');
      expect(fow['runs'], 14, reason: 'the score when the wicket fell');
    });

    test('the bowler is charged for the wide and no-ball but not the byes', () {
      final b1 = PlayerTally.of(state, 'B1');
      // 4 + 1 (wide) + 7 (no-ball) + 2 (run-out ball) + 1 = 15. NOT the byes.
      expect(b1['runsConceded'], 15);
      expect(b1['ballsBowled'], 4);
      expect(b1['wickets'], null, reason: 'a run-out is not the bowler\'s');
    });

    test('the fielders get the run-out and the assist', () {
      expect(PlayerTally.of(state, 'B5')['runOuts'], 1);
      expect(PlayerTally.of(state, 'B7')['runOutAssists'], 1);
    });

    test('the free hit was consumed by the run-out delivery', () {
      expect(state['freeHit'], isFalse);
    });

    test('the rendered scorecard agrees with the innings', () {
      final card = cricket.card(state, ctx, inningsIndex: 0);
      expect(card, isNotNull);
      expect(card!.runs, 17);
      expect(card.wickets, 1);
      expect(card.legalBalls, 4);
      // Four legal balls reads as "0.4" on a scorecard, but decimalises to
      // 4/6 = 0.667 for any rate calculation — never 0.4.
      expect(card.oversText, '0.4');
      expect(card.legalBalls / card.ballsPerOver, closeTo(4 / 6, 0.0001));
      expect(card.extrasTotal, 4, reason: '1 wide + 1 no-ball + 2 bye');
    });
  });

  // ==========================================================================
  group('GOLDEN 2 — badminton: 29-29 to 30 on the hard cap', () {
    const badminton = BadmintonPlugin();
    final ctx = ScoringContext(
      entrantAName: 'Sindhu',
      entrantBName: 'Marin',
      config: RulePresets.resolve(sportId: 'badminton').toMap(),
    );

    ScoreAction rally(Side s) => ScoreAction(type: 'rally', side: s);

    test('20-20 does not end the game, and 21-20 does not either', () {
      final toTwenty = <ScoreAction>[
        for (var i = 0; i < 20; i++) ...[rally(Side.a), rally(Side.b)],
      ];
      var state = badminton.replay(toTwenty, ctx);
      expect(state['currentA'], 20);
      expect(state['currentB'], 20);
      expect(state['gamesA'], 0);

      state = badminton.replay([...toTwenty, rally(Side.a)], ctx);
      expect(state['gamesA'], 0, reason: '21-20 is only one clear');
    });

    test('29-29 then one point takes the game 30-29', () {
      final log = <ScoreAction>[
        for (var i = 0; i < 29; i++) ...[rally(Side.a), rally(Side.b)],
        rally(Side.a),
      ];
      final state = badminton.replay(log, ctx);

      expect(state['gamesA'], 1);
      expect(state['gamesB'], 0);
      // The cap is the ONLY reason this game ended — the margin is one.
      expect(
        (state['completedGames'] as List).single,
        {'a': 30, 'b': 29},
      );
      expect(state['currentA'], 0, reason: 'a new game has started');
    });

    test('the winner of the game serves first in the next one', () {
      final log = <ScoreAction>[
        for (var i = 0; i < 29; i++) ...[rally(Side.a), rally(Side.b)],
        rally(Side.a),
      ];
      final state = badminton.replay(log, ctx);
      expect(state['server'], 'a');
    });
  });

  // ==========================================================================
  group('GOLDEN 3 — table tennis: deuce at 10-10 out to 13-11', () {
    const tt = TableTennisPlugin();
    final ctx = ScoringContext(
      entrantAName: 'Sharath',
      entrantBName: 'Sathiyan',
      config: RulePresets.resolve(sportId: 'table_tennis').toMap(),
    );

    ScoreAction point(Side s) => ScoreAction(type: 'point', side: s);

    test('11-10 does not take the game — the margin is one', () {
      final log = <ScoreAction>[
        for (var i = 0; i < 10; i++) ...[point(Side.a), point(Side.b)],
        point(Side.a),
      ];
      final state = tt.replay(log, ctx);
      expect(state['currentA'], 11);
      expect(state['currentB'], 10);
      expect(state['gamesA'], 0, reason: 'a game needs two clear');
    });

    test('the game runs out to 13-11', () {
      // 10-10, then A, B, A, A — reaching 13-11 with two clear.
      final log = <ScoreAction>[
        for (var i = 0; i < 10; i++) ...[point(Side.a), point(Side.b)],
        point(Side.a), // 11-10
        point(Side.b), // 11-11
        point(Side.a), // 12-11
        point(Side.a), // 13-11 — game
      ];
      final state = tt.replay(log, ctx);

      expect(state['gamesA'], 1);
      expect((state['completedGames'] as List).single, {'a': 13, 'b': 11});
    });

    test('service alternates every point once deuce is reached', () {
      // Before deuce, service changes every two points.
      var state = tt.replay([point(Side.a)], ctx);
      final afterOne = tt.serverFor(state, ctx);
      state = tt.replay([point(Side.a), point(Side.b)], ctx);
      expect(
        tt.serverFor(state, ctx),
        isNot(afterOne),
        reason: 'service passes after the second point',
      );

      // At 10-10 it changes every single point.
      final toDeuce = <ScoreAction>[
        for (var i = 0; i < 10; i++) ...[point(Side.a), point(Side.b)],
      ];
      final atDeuce = tt.replay(toDeuce, ctx);
      final serverAtDeuce = tt.serverFor(atDeuce, ctx);
      final afterNext = tt.replay([...toDeuce, point(Side.a)], ctx);
      expect(
        tt.serverFor(afterNext, ctx),
        isNot(serverAtDeuce),
        reason: 'one serve each at deuce',
      );
    });
  });

  // ==========================================================================
  group('GOLDEN 4 — volleyball: the deciding-set change of ends', () {
    const volleyball = VolleyballPlugin();
    final ctx = ScoringContext(
      entrantAName: 'Hyderabad',
      entrantBName: 'Warangal',
      config: RulePresets.resolve(sportId: 'volleyball').toMap(),
    );

    // `how: opponent_error` is the one way a point belongs to nobody, which
    // is what lets a fixture drive a scoreline without inventing a squad.
    ScoreAction point(Side s) => ScoreAction(
          type: 'point',
          side: s,
          payload: const {'how': 'opponent_error'},
        );

    /// Wins [n] sets for a side by running them out 25-0.
    List<ScoreAction> winSets(Side side, int n) => [
          for (var s = 0; s < n; s++)
            for (var i = 0; i < 25; i++) point(side),
        ];

    test('the deciding set is to 15, not 25', () {
      final log = [...winSets(Side.a, 2), ...winSets(Side.b, 2)];
      final state = volleyball.replay(log, ctx);
      expect(state['setsA'], 2);
      expect(state['setsB'], 2);
      expect(volleyball.isDecidingSet(state, ctx), isTrue);
      expect(volleyball.targetForCurrentSet(state, ctx), 15);
    });

    test('ends change when a side reaches 8 in the deciding set', () {
      final base = [...winSets(Side.a, 2), ...winSets(Side.b, 2)];

      // At 7 the switch has not come up yet.
      var state = volleyball.replay(
        [...base, for (var i = 0; i < 7; i++) point(Side.a)],
        ctx,
      );
      expect(volleyball.shouldSwitchEnds(state, ctx), isFalse);

      // At 8 it does.
      state = volleyball.replay(
        [...base, for (var i = 0; i < 8; i++) point(Side.a)],
        ctx,
      );
      expect(volleyball.shouldSwitchEnds(state, ctx), isTrue);
      expect(state['currentA'], 8);

      // The pad offers the control precisely then.
      final groups = volleyball.controls(state, ctx);
      expect(
        groups.any((g) => g.controls.any((c) => c.action == 'switch_ends')),
        isTrue,
      );
    });

    test('recording the change clears the prompt', () {
      final log = [
        ...winSets(Side.a, 2),
        ...winSets(Side.b, 2),
        for (var i = 0; i < 8; i++) point(Side.a),
        const ScoreAction(type: 'switch_ends'),
      ];
      final state = volleyball.replay(log, ctx);
      expect(state['endsSwapped'], isTrue);
      expect(volleyball.shouldSwitchEnds(state, ctx), isFalse);
    });

    test('ends do not change mid-set in an ordinary set', () {
      final state = volleyball.replay(
        [for (var i = 0; i < 12; i++) point(Side.a)],
        ctx,
      );
      expect(volleyball.isDecidingSet(state, ctx), isFalse);
      expect(volleyball.shouldSwitchEnds(state, ctx), isFalse);

      final rejected = volleyball.apply(
        state,
        const ScoreAction(type: 'switch_ends'),
        ctx,
      );
      expect(rejected.isAccepted, isFalse);
    });

    test('a deciding set has no cap: 16-14 wins, 15-14 does not', () {
      final base = [...winSets(Side.a, 2), ...winSets(Side.b, 2)];
      final to14 = [
        ...base,
        for (var i = 0; i < 14; i++) ...[point(Side.a), point(Side.b)],
      ];
      var state = volleyball.replay([...to14, point(Side.a)], ctx);
      expect(state['setsA'], 2, reason: '15-14 is only one clear');

      state = volleyball.replay([...to14, point(Side.a), point(Side.a)], ctx);
      expect(state['setsA'], 3);
      expect(state['complete'], isTrue);
    });
  });

  // ==========================================================================
  group('GOLDEN 5 — kabaddi: super tackle and all-out', () {
    const kabaddi = KabaddiPlugin();
    final ctx = ScoringContext(
      entrantAName: 'Telugu Titans',
      entrantBName: 'Bengal Warriors',
      config: RulePresets.resolve(sportId: 'kabaddi').toMap(),
      lineupA: [
        for (var n = 1; n <= 7; n++) MatchPlayer(id: 'a$n', name: 'A$n'),
      ],
      lineupB: [
        for (var n = 1; n <= 7; n++) MatchPlayer(id: 'b$n', name: 'B$n'),
      ],
    );

    ScoreAction raid(Side side, String raider, int touched) => ScoreAction(
          type: 'raid',
          side: side,
          payload: {'playerId': raider, 'touched': touched},
        );

    test('a tackle with a full defence is worth one, not two', () {
      final state = kabaddi.replay([
        const ScoreAction(
          type: 'tackle',
          side: Side.b,
          payload: {'defenderIds': ['b1', 'b2']},
        ),
      ], ctx);
      expect(state['b'], 1, reason: 'seven defenders on the mat — ordinary');
    });

    test('a super tackle with three or fewer defenders is worth two', () {
      // Reduce B to three by touching four of them in one raid.
      final log = <ScoreAction>[
        raid(Side.a, 'a1', 4), // B down to 3, A scores 4
        const ScoreAction(
          type: 'tackle',
          side: Side.b,
          payload: {'defenderIds': ['b1', 'b2']},
        ),
      ];
      final state = kabaddi.replay(log, ctx);

      expect(state['a'], 4);
      expect(state['b'], 2, reason: 'a depleted defence stopping a raid');
      // The two points are shared between the two tacklers.
      expect(PlayerTally.of(state, 'b1')['superTackles'], 0.5);
      expect(PlayerTally.of(state, 'b2')['tacklePoints'], 1.0);
    });

    test('emptying the mat is an all-out worth two and revives the side', () {
      // Touch all seven of B across two raids.
      final log = <ScoreAction>[
        raid(Side.a, 'a1', 4), // B: 7 -> 3
        raid(Side.a, 'a2', 3), // B: 3 -> 0, all out
      ];
      final state = kabaddi.replay(log, ctx);

      // 4 + 3 raid points, plus 2 for the all-out.
      expect(state['a'], 9);
      expect(state['allOutsA'], 1);
      // Both sides return to full strength.
      expect(state['onCourtA'], 7);
      expect(state['onCourtB'], 7);
    });

    test('a super-10 is recognised at ten raid points', () {
      final log = <ScoreAction>[
        raid(Side.a, 'a1', 4),
        raid(Side.a, 'a1', 3),
        raid(Side.a, 'a1', 3),
      ];
      final state = kabaddi.replay(log, ctx);
      expect(PlayerTally.of(state, 'a1')['raidPoints'], 10);

      final column =
          KabaddiPlugin.columns.firstWhere((c) => c.key == 'super10');
      expect(column.valueFrom(PlayerTally.of(state, 'a1')), 1);
    });

    test('two empty raids make the next one do-or-die', () {
      final log = <ScoreAction>[
        raid(Side.a, 'a1', 0),
        raid(Side.a, 'a2', 0),
      ];
      final state = kabaddi.replay(log, ctx);
      expect(kabaddi.isDoOrDie(state, Side.a, ctx), isTrue);
      expect(kabaddi.isDoOrDie(state, Side.b, ctx), isFalse);
    });
  });

  // ==========================================================================
  group('GOLDEN 6 — tennis: the tiebreak serve order', () {
    const tennis = TennisPlugin();
    final ctx = ScoringContext(
      entrantAName: 'Bopanna',
      entrantBName: 'Nagal',
      config: RulePresets.resolve(sportId: 'tennis').toMap(),
    );

    ScoreAction point(Side s) => ScoreAction(type: 'point', side: s);

    /// Wins one game for [side] from love.
    List<ScoreAction> game(Side side) => [for (var i = 0; i < 4; i++) point(side)];

    /// Six games each, taking the set to a tiebreak.
    List<ScoreAction> toSixAll() => [
          for (var i = 0; i < 6; i++) ...[...game(Side.a), ...game(Side.b)],
        ];

    test('six games all starts a tiebreak', () {
      final state = tennis.replay(toSixAll(), ctx);
      expect(state['gamesA'], 6);
      expect(state['gamesB'], 6);
      expect(state['inTiebreak'], isTrue);
    });

    test('serve order is one point, then two at a time', () {
      final base = toSixAll();
      var state = tennis.replay(base, ctx);
      final opener = tennis.serverFor(state);

      // Point 1 was served by the opener. After it, service passes.
      state = tennis.replay([...base, point(Side.a)], ctx);
      final second = tennis.serverFor(state);
      expect(second, isNot(opener), reason: 'one point, then change');

      // Points 2 and 3 belong to the same server.
      state = tennis.replay([...base, point(Side.a), point(Side.a)], ctx);
      expect(tennis.serverFor(state), second, reason: 'two in a row');

      // Point 4 goes back to the opener.
      state = tennis.replay(
        [...base, point(Side.a), point(Side.a), point(Side.a)],
        ctx,
      );
      expect(tennis.serverFor(state), opener, reason: 'and back again');

      // And two more for them.
      state = tennis.replay(
        [...base, ...List.generate(4, (_) => point(Side.a))],
        ctx,
      );
      expect(tennis.serverFor(state), opener);
    });

    test('a tiebreak is won 7-5, but not 7-6', () {
      final base = toSixAll();

      // 6-5 up, one more point takes it 7-5.
      final to6_5 = [
        ...base,
        for (var i = 0; i < 5; i++) ...[point(Side.a), point(Side.b)],
        point(Side.a),
      ];
      var state = tennis.replay(to6_5, ctx);
      expect(state['setsA'], 0, reason: '6-5 is not enough');

      state = tennis.replay([...to6_5, point(Side.a)], ctx);
      expect(state['setsA'], 1, reason: '7-5 takes the set');
    });

    test('a tiebreak at 6-6 must be won by two', () {
      final base = toSixAll();
      final to6All = [
        ...base,
        for (var i = 0; i < 6; i++) ...[point(Side.a), point(Side.b)],
      ];

      var state = tennis.replay([...to6All, point(Side.a)], ctx);
      expect(state['setsA'], 0, reason: '7-6 is only one clear');

      state = tennis.replay([...to6All, point(Side.a), point(Side.a)], ctx);
      expect(state['setsA'], 1, reason: '8-6 takes it');
    });
  });
}
