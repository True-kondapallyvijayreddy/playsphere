import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// `maxOversPerBowler` — the innings quota.
///
/// Every limited-overs format has one and it is not a detail: four in a T20,
/// ten in a fifty-over game, two in the eight-over tennis-ball preset. It is
/// the rule that stops a side bowling its two best bowlers from both ends for
/// a whole innings.
///
/// It was offered to organizers as the fourth field in the cricket Rules sheet
/// and read by nothing. `bowlerMustChangeEachOver` stopped consecutive overs,
/// so two bowlers could alternate through all twenty and the pad took every
/// ball. The innings that came out was not legal under any playing condition,
/// and it fed Glicko, career bowling figures and the wicket leaderboards
/// exactly like a real one.
void main() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix, int n) => [
        for (var i = 1; i <= n; i++)
          MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
      ];

  ScoringContext ctxWith({int cap = 2, int overs = 8, bool mustChange = true}) =>
      ScoringContext(
        entrantAName: 'Warangal',
        entrantBName: 'Nizamabad',
        config: {
          'oversPerInnings': overs,
          'ballsPerOver': 6,
          'playersPerTeam': 11,
          'battingFirst': 'a',
          'maxOversPerBowler': cap,
          'bowlerMustChangeEachOver': mustChange,
        },
        lineupA: squad('A', 11),
        lineupB: squad('B', 11),
      );

  ScoreAction runs(int n) => ScoreAction(type: 'runs', payload: {'runs': n});

  Map<String, dynamic> apply(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    final r = cricket.apply(state, action, ctx);
    expect(r.isAccepted, isTrue,
        reason: 'rejected "${action.type}": ${r.rejection}');
    return r.state;
  }

  /// Bowls [overs] complete overs of dot balls, naming a bowler each time.
  Map<String, dynamic> bowl(
    Map<String, dynamic> state,
    ScoringContext ctx,
    List<String> bowlerOrder,
  ) {
    var s = state;
    for (final who in bowlerOrder) {
      if (s['innings'][0]['bowler'] == null) {
        s = apply(s, ScoreAction(type: 'new_bowler', payload: {'playerId': who}),
            ctx);
      }
      for (var b = 0; b < 6; b++) {
        s = apply(s, runs(0), ctx);
      }
    }
    return s;
  }

  Map<String, dynamic> opened(ScoringContext ctx, {String bowler = 'B1'}) {
    final fresh = cricket.initialState(ctx);
    return apply(
      fresh,
      ScoreAction(
        type: 'open',
        payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': bowler},
      ),
      ctx,
    );
  }

  group('the quota is enforced', () {
    test('refuses a bowler who has already bowled their overs', () {
      final ctx = ctxWith(cap: 2);
      // B1 and B2 alternate for four overs, so both reach the cap and B2 is
      // the one who bowled last. Asking for B1 therefore hits the QUOTA and
      // not the no-consecutive-overs rule — which is the distinction this test
      // exists to make, and which an order ending on B1 would have hidden.
      var s = opened(ctx);
      s = bowl(s, ctx, ['B1', 'B2', 'B1', 'B2']);

      final r = cricket.apply(
        s,
        const ScoreAction(type: 'new_bowler', payload: {'playerId': 'B1'}),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('bowled their 2 overs'));
    });

    test('a third bowler is still fine', () {
      final ctx = ctxWith(cap: 2);
      var s = opened(ctx);
      s = bowl(s, ctx, ['B1', 'B2', 'B1', 'B2']);
      final r = cricket.apply(
        s,
        const ScoreAction(type: 'new_bowler', payload: {'playerId': 'B3'}),
        ctx,
      );
      expect(r.isAccepted, isTrue);
    });

    test('a bowler mid-over always finishes it', () {
      // The law limits COMPLETED overs. Cutting somebody off after four balls
      // would leave an over nobody can finish.
      final ctx = ctxWith(cap: 1);
      var s = opened(ctx);
      for (var b = 0; b < 5; b++) {
        s = apply(s, runs(0), ctx);
      }
      // Five balls in, already at the cap's worth of balls but not of overs.
      final r = cricket.apply(s, runs(0), ctx);
      expect(r.isAccepted, isTrue, reason: r.rejection);
    });

    test('holds even when the change-every-over rule is off', () {
      // The path that made the cap unreachable: with `mustChange` false the
      // bowler is never cleared, `new_bowler` is never called, and the only
      // remaining check is the one on the delivery itself.
      final ctx = ctxWith(cap: 1, mustChange: false);
      var s = opened(ctx);
      for (var b = 0; b < 6; b++) {
        s = apply(s, runs(0), ctx);
      }
      expect(s['innings'][0]['bowler'], 'B1',
          reason: 'with mustChange off the bowler should still be named');

      final r = cricket.apply(s, runs(0), ctx);
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('bowled their 1 over'));
    });

    test('a cap of zero means no limit', () {
      // Not every format has a quota, and a hard-coded default of four would
      // impose a T20 rule on a format that has none.
      final ctx = ctxWith(cap: 0, mustChange: false);
      var s = opened(ctx);
      for (var over = 0; over < 5; over++) {
        for (var b = 0; b < 6; b++) {
          s = apply(s, runs(0), ctx);
        }
      }
      expect(s['innings'][0]['bowling']['B1']['balls'], 30);
    });
  });

  _boundaryTests();

  group('the pad only offers eligible bowlers', () {
    test('a bowler at their quota is not in the list', () {
      final ctx = ctxWith(cap: 2);
      var s = opened(ctx);
      s = bowl(s, ctx, ['B1', 'B2', 'B1', 'B2']);

      // End of the fourth over: the pad is asking for the next bowler.
      final groups = cricket.controls(s, ctx);
      final prompt = groups
          .expand((g) => g.controls)
          .firstWhere((c) => c.action == 'new_bowler')
          .prompts
          .single;

      expect(prompt.only, isNotNull);
      // Both openers are out of overs; everybody else is available.
      expect(prompt.only, isNot(contains('B1')));
      expect(prompt.only, isNot(contains('B2')));
      expect(prompt.only, contains('B3'));
    });

    test('nobody eligible is shown as nobody, not as a free choice', () {
      // Two bowlers, one over each, and a cap of one. The side genuinely
      // cannot bowl the next over; offering a name would be a lie.
      final ctx = ScoringContext(
        entrantAName: 'Warangal',
        entrantBName: 'Nizamabad',
        config: const {
          'oversPerInnings': 8,
          'ballsPerOver': 6,
          'playersPerTeam': 11,
          'battingFirst': 'a',
          'maxOversPerBowler': 1,
        },
        lineupA: squad('A', 11),
        lineupB: squad('B', 2),
      );
      var s = opened(ctx);
      s = bowl(s, ctx, ['B1', 'B2']);

      final prompt = cricket
          .controls(s, ctx)
          .expand((g) => g.controls)
          .firstWhere((c) => c.action == 'new_bowler')
          .prompts
          .single;
      expect(prompt.only, isEmpty);
    });
  });
}

/// `boundary` — a four RUN is not a four.
///
/// The fours and sixes columns count boundaries. Counting every four-run
/// scoring shot as one overstates them, which then overstates the boundary
/// percentage a batting card shows and a scout reads. Rare for a four and
/// effectively impossible for a six, so the default is that it WAS a boundary
/// and the pad says otherwise when the scorer does.
void _boundaryTests() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix, int n) => [
        for (var i = 1; i <= n; i++)
          MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
      ];

  final ctx = ScoringContext(
    entrantAName: 'Warangal',
    entrantBName: 'Nizamabad',
    config: const {
      'oversPerInnings': 8,
      'ballsPerOver': 6,
      'playersPerTeam': 11,
      'battingFirst': 'a',
    },
    lineupA: squad('A', 11),
    lineupB: squad('B', 11),
  );

  Map<String, dynamic> opened() {
    final r = cricket.apply(
      cricket.initialState(ctx),
      const ScoreAction(
        type: 'open',
        payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
      ),
      ctx,
    );
    expect(r.isAccepted, isTrue, reason: r.rejection);
    return r.state;
  }

  Map<String, dynamic> hit(Map<String, dynamic> s, Map<String, Object> payload) {
    final r = cricket.apply(s, ScoreAction(type: 'runs', payload: payload), ctx);
    expect(r.isAccepted, isTrue, reason: r.rejection);
    return r.state;
  }

  group('boundaries', () {
    test('a four with no flag is counted as a boundary', () {
      // The default has to stay as it was: every existing pad button, and
      // every event already in a match log, carries no flag.
      final s = hit(opened(), {'runs': 4});
      expect(s['innings'][0]['batting']['A1']['fours'], 1);
      expect(s['innings'][0]['batting']['A1']['runs'], 4);
    });

    test('four RUN scores four and counts no boundary', () {
      final s = hit(opened(), {'runs': 4, 'boundary': false});
      expect(s['innings'][0]['batting']['A1']['fours'], 0,
          reason: 'four runs run is not a four');
      // Everything else about the delivery is identical.
      expect(s['innings'][0]['batting']['A1']['runs'], 4);
      expect(s['innings'][0]['batting']['A1']['balls'], 1);
      expect(s['innings'][0]['runs'], 4);
      expect(s['innings'][0]['bowling']['B1']['runs'], 4);
    });

    test('a six off a no-ball still counts as a six', () {
      final s = cricket.apply(
        opened(),
        const ScoreAction(type: 'no_ball', payload: {'runs': 6}),
        ctx,
      );
      expect(s.isAccepted, isTrue, reason: s.rejection);
      expect(s.state['innings'][0]['batting']['A1']['sixes'], 1);
    });

    test('runs run off a no-ball count no boundary', () {
      final s = cricket.apply(
        opened(),
        const ScoreAction(
          type: 'no_ball',
          payload: {'runs': 4, 'boundary': false},
        ),
        ctx,
      );
      expect(s.isAccepted, isTrue, reason: s.rejection);
      expect(s.state['innings'][0]['batting']['A1']['fours'], 0);
      expect(s.state['innings'][0]['batting']['A1']['runs'], 4);
    });

    test('the pad offers both, and they differ only in the flag', () {
      final runsGroup = cricket
          .controls(opened(), ctx)
          .firstWhere((g) => g.title == 'Runs off the bat');
      final four = runsGroup.controls.firstWhere((c) => c.label == '4');
      final fourRun = runsGroup.controls.firstWhere((c) => c.label == '4 run');
      expect(four.payload['runs'], 4);
      expect(fourRun.payload['runs'], 4);
      expect(fourRun.payload['boundary'], false);
    });
  });
}
