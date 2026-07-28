import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/basketball_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/kabaddi_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

List<MatchPlayer> _squad(String prefix, int n) => [
      for (var i = 1; i <= n; i++)
        MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
    ];

void main() {
  // ==========================================================================
  // Basketball
  // ==========================================================================
  group('Basketball', () {
    const bball = BasketballPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Hyderabad',
      entrantBName: 'Warangal',
      config: const {'periods': 4, 'foulOutAt': 5},
      lineupA: _squad('A', 10),
      lineupB: _squad('B', 10),
    );

    Map<String, dynamic> play(List<ScoreAction> actions) {
      var s = bball.initialState(ctx);
      for (final a in actions) {
        final r = bball.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    ScoreAction shot(String player, int value, bool made, {String? assist}) =>
        ScoreAction(
          type: 'shot',
          side: Side.a,
          payload: {
            'playerId': player,
            'value': value,
            'made': made,
            if (assist != null) 'assistId': assist,
          },
        );

    test('points come from the shot value', () {
      final s = play([shot('A1', 3, true), shot('A2', 2, true), shot('A1', 1, true)]);
      expect(s['a'], 6);
      final box = bball.boxScore(s, ctx, Side.a);
      expect(box.players.firstWhere((p) => p.playerId == 'A1')['points'], 4);
      expect(box.players.firstWhere((p) => p.playerId == 'A2')['points'], 2);
    });

    test('free throws are excluded from field goal percentage', () {
      // 1 of 2 from the field, plus 4 free throws which must not count.
      final s = play([
        shot('A1', 2, true),
        shot('A1', 2, false),
        shot('A1', 1, true),
        shot('A1', 1, true),
        shot('A1', 1, true),
        shot('A1', 1, false),
      ]);
      final line =
          bball.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A1');

      expect(line['fgAttempted'], 2, reason: 'free throws are not field goals');
      expect(line['fgMade'], 1);
      final fg = BasketballPlugin.columns.firstWhere((c) => c.key == 'fgPct');
      expect(fg.valueFrom(line.tally), 0.5);

      final ft = BasketballPlugin.columns.firstWhere((c) => c.key == 'ftPct');
      expect(line['ftAttempted'], 4);
      expect(ft.valueFrom(line.tally), 0.75);
    });

    test('a three counts in BOTH the three column and field goals', () {
      final s = play([shot('A1', 3, true), shot('A1', 3, false)]);
      final line =
          bball.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A1');

      expect(line['threeAttempted'], 2);
      expect(line['threeMade'], 1);
      // Threes are field goals too — omitting them understates every shooter.
      expect(line['fgAttempted'], 2);
      expect(line['fgMade'], 1);
    });

    test('an assist only exists on a made basket', () {
      final s = play([
        shot('A1', 2, true, assist: 'A2'),
        shot('A1', 2, false, assist: 'A3'),
      ]);
      final box = bball.boxScore(s, ctx, Side.a);
      expect(box.players.firstWhere((p) => p.playerId == 'A2')['assists'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A3')['assists'], 0);
    });

    test('rebounds split offensive and defensive but total together', () {
      final s = play([
        const ScoreAction(
          type: 'rebound',
          side: Side.a,
          payload: {'playerId': 'A5', 'offensive': true},
        ),
        const ScoreAction(
          type: 'rebound',
          side: Side.a,
          payload: {'playerId': 'A5'},
        ),
      ]);
      final line =
          bball.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A5');
      final reb =
          BasketballPlugin.columns.firstWhere((c) => c.key == 'rebounds');
      expect(reb.valueFrom(line.tally), 2);
    });

    test('a player fouls out at the configured limit and cannot play on', () {
      final s = play([
        for (var n = 0; n < 5; n++)
          const ScoreAction(
            type: 'foul',
            side: Side.a,
            payload: {'playerId': 'A4'},
          ),
      ]);
      final blocked = bball.apply(s, shot('A4', 2, true), ctx);
      expect(blocked.isAccepted, isFalse);
      expect(blocked.rejection, contains('fouled out'));
    });

    test('basketball cannot end level', () {
      final s = play([shot('A1', 2, true)]);
      var r = bball.apply(s, const ScoreAction(type: 'finish'), ctx);
      expect(r.isAccepted, isTrue); // 2-0, fine

      final level = bball.initialState(ctx);
      r = bball.apply(level, const ScoreAction(type: 'finish'), ctx);
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('cannot end drawn'));
    });

    test('shot coordinates are kept for a chart', () {
      final s = play([
        const ScoreAction(
          type: 'shot',
          side: Side.a,
          payload: {
            'playerId': 'A1',
            'value': 3,
            'made': true,
            'x': 0.82,
            'y': 0.31,
          },
        ),
      ]);
      final chart = bball.shotChart(s, side: Side.a);
      expect(chart.single['x'], 0.82);
      expect(chart.single['made'], isTrue);
      expect(chart.single['value'], 3);
    });
  });

  // ==========================================================================
  // Kabaddi
  // ==========================================================================
  group('Kabaddi', () {
    const kabaddi = KabaddiPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Nizamabad',
      entrantBName: 'Karimnagar',
      config: const {
        'periods': 2,
        'playersOnCourt': 7,
        'bonusMinDefenders': 6,
        'superTackleMaxDefenders': 3,
        'superRaidPoints': 3,
      },
      lineupA: _squad('A', 12),
      lineupB: _squad('B', 12),
    );

    Map<String, dynamic> play(List<ScoreAction> actions) {
      var s = kabaddi.initialState(ctx);
      for (final a in actions) {
        final r = kabaddi.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    ScoreAction raid(
      String player, {
      int touched = 0,
      bool bonus = false,
      bool raiderOut = false,
      Side side = Side.a,
    }) =>
        ScoreAction(
          type: 'raid',
          side: side,
          payload: {
            'playerId': player,
            'touched': touched,
            'bonus': bonus,
            'raiderOut': raiderOut,
          },
        );

    test('a raid scores one point per defender touched', () {
      final s = play([raid('A1', touched: 2)]);
      expect(s['a'], 2);
      expect(s['onCourtB'], 5, reason: 'two defenders went out');
      final line = kabaddi
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A1');
      expect(line['raidPoints'], 2);
    });

    test('three or more points in one raid is a super raid', () {
      final s = play([raid('A1', touched: 3)]);
      final line = kabaddi
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A1');
      expect(line['superRaids'], 1);
    });

    test('a bonus point needs a near-full defence', () {
      // Knock the defence down to five, then try for a bonus.
      var s = play([raid('A1', touched: 2)]);
      final r = kabaddi.apply(s, raid('A2', bonus: true), ctx);
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('at least 6 defenders'));

      // With a full defence it is allowed.
      s = play([raid('A1', bonus: true)]);
      expect(s['a'], 1);
    });

    test('cannot touch more defenders than are on the mat', () {
      final r = kabaddi.apply(
        kabaddi.initialState(ctx),
        raid('A1', touched: 9),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });

    test('two empty raids make the third do-or-die', () {
      var s = play([raid('A1'), raid('A2')]);
      expect(kabaddi.isDoOrDie(s, Side.a), isTrue);
      expect(kabaddi.isDoOrDie(s, Side.b), isFalse);

      // Failing it puts the raider out and gives the defence a point.
      final before = (s['b'] as num).toInt();
      s = play([raid('A1'), raid('A2'), raid('A3')]);
      expect(s['b'], before + 1);
      expect(s['onCourtA'], 6);
    });

    test('scoring resets the empty-raid count', () {
      final s = play([raid('A1'), raid('A2', touched: 1)]);
      expect(kabaddi.isDoOrDie(s, Side.a), isFalse);
    });

    test('a tackle against a depleted defence is a super tackle', () {
      // Reduce side B to three on the mat: A touches four across two raids.
      var s = play([raid('A1', touched: 2), raid('A2', touched: 2)]);
      expect(s['onCourtB'], 3);

      // Now B tackles A's raider — with three defenders that is a super tackle.
      final r = kabaddi.apply(
        s,
        const ScoreAction(
          type: 'tackle',
          side: Side.b,
          payload: {'defenderIds': ['B1', 'B2']},
        ),
        ctx,
      );
      expect(r.isAccepted, isTrue);
      s = r.state;
      expect(s['b'], 2, reason: 'super tackle is worth two');

      final box = kabaddi.boxScore(s, ctx, Side.b);
      // Shared between the two defenders involved.
      expect(box.teamTotals['tacklePoints'], closeTo(2, 0.001));
    });

    test('emptying the mat is an all-out worth two, and revives everyone', () {
      // Seven defenders out across four raids.
      final s = play([
        raid('A1', touched: 2),
        raid('A2', touched: 2),
        raid('A3', touched: 2),
        raid('A4', touched: 1),
      ]);
      // 7 raid points, plus 2 for the all-out.
      expect(s['a'], 9);
      expect(s['onCourtB'], 7, reason: 'the side is revived after an all-out');
      expect(s['allOutsA'], 1);
    });

    test('Super 10 and High 5 are derived, as kabaddi reports them', () {
      // Ten raid points, respecting how many defenders are actually left:
      // 3 (B down to 4), 3 (down to 1), 1 (all-out, B revived to 7), 3.
      final s = play([
        raid('A1', touched: 3),
        raid('A1', touched: 3),
        raid('A1', touched: 1),
        raid('A1', touched: 3),
      ]);
      final line = kabaddi
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A1');
      final super10 =
          KabaddiPlugin.columns.firstWhere((c) => c.key == 'super10');
      expect(line['raidPoints'], greaterThanOrEqualTo(10));
      expect(super10.valueFrom(line.tally), 1);
    });

    test('both sides return to full strength at half time', () {
      var s = play([raid('A1', touched: 3)]);
      expect(s['onCourtB'], 4);
      s = play([raid('A1', touched: 3), const ScoreAction(type: 'next_period')]);
      expect(s['onCourtA'], 7);
      expect(s['onCourtB'], 7);
      expect(kabaddi.isDoOrDie(s, Side.a), isFalse);
    });

    test('a scripted match replays identically', () {
      final script = [
        raid('A1', touched: 2),
        raid('B1', touched: 1, side: Side.b),
        raid('A2'),
        raid('A3', bonus: false),
        const ScoreAction(type: 'finish'),
      ];
      final direct = play(script);
      final replayed = kabaddi.replay(script, ctx);
      expect(replayed['a'], direct['a']);
      expect(replayed['b'], direct['b']);
      expect(replayed['onCourtA'], direct['onCourtA']);
    });
  });
}
