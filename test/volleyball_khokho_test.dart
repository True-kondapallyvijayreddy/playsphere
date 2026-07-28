import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/kho_kho_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/volleyball_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

List<MatchPlayer> _squad(String prefix, int n) => [
      for (var i = 1; i <= n; i++)
        MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
    ];

void main() {
  // ==========================================================================
  // Volleyball
  // ==========================================================================
  group('Volleyball', () {
    const vb = VolleyballPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Adilabad',
      entrantBName: 'Khammam',
      config: const {
        'pointsPerSet': 25,
        'decidingSetPoints': 15,
        'setsToWin': 3,
        'winBy': 2,
      },
      lineupA: _squad('A', 12),
      lineupB: _squad('B', 12),
    );

    Map<String, dynamic> play(List<ScoreAction> actions, [Map<String, dynamic>? from]) {
      var s = from ?? vb.initialState(ctx);
      for (final a in actions) {
        final r = vb.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    ScoreAction point(Side side, String how, {String? player, String? assist}) =>
        ScoreAction(
          type: 'point',
          side: side,
          payload: {
            'how': how,
            if (player != null) 'playerId': player,
            if (assist != null) 'assistId': assist,
          },
        );

    /// Wins [n] points for [side] via kills, to move a set along.
    List<ScoreAction> rally(Side side, int n, String player) =>
        [for (var i = 0; i < n; i++) point(side, 'attack', player: player)];

    test('how a point was won decides whose statistic it is', () {
      final s = play([
        point(Side.a, 'attack', player: 'A5', assist: 'A2'),
        point(Side.a, 'block', player: 'A7'),
        point(Side.a, 'ace', player: 'A1'),
      ]);
      final box = vb.boxScore(s, ctx, Side.a);

      expect(box.players.firstWhere((p) => p.playerId == 'A5')['kills'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A2')['assists'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A7')['blocks'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A1')['aces'], 1);
      expect(s['currentA'], 3);
    });

    test('a scoring point must name whoever won it', () {
      final r = vb.apply(
        vb.initialState(ctx),
        const ScoreAction(type: 'point', side: Side.a, payload: {'how': 'block'}),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });

    test('an opponent error scores without crediting a winner', () {
      final s = play([
        point(Side.a, 'opponent_error'),
      ]);
      expect(s['currentA'], 1);
      // Nobody on side A gained a statistic from it.
      expect(vb.boxScore(s, ctx, Side.a).appeared, isEmpty);
    });

    test('an opponent error can still be charged to whoever made it', () {
      final s = play([
        const ScoreAction(
          type: 'point',
          side: Side.a,
          payload: {
            'how': 'opponent_error',
            'errorById': 'B4',
            'errorType': 'service',
          },
        ),
      ]);
      final b4 = vb
          .boxScore(s, ctx, Side.b)
          .players
          .firstWhere((p) => p.playerId == 'B4');
      expect(b4['serviceErrors'], 1);
    });

    test('a dig is recorded but scores nothing', () {
      final s = play([
        const ScoreAction(type: 'dig', side: Side.a, payload: {'playerId': 'A9'}),
      ]);
      expect(s['currentA'], 0);
      expect(
        vb.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A9')['digs'],
        1,
      );
    });

    test('a set needs 25 AND a two point lead — there is no cap', () {
      // 24-24, then a single point is not enough.
      var s = play([...rally(Side.a, 24, 'A5'), ...rally(Side.b, 24, 'B5')]);
      s = play(rally(Side.a, 1, 'A5'), s);
      expect(s['setsA'], 0, reason: '25-24 does not win a volleyball set');

      // Volleyball has no ceiling: 33-31 is legal. Trading points one for one
      // keeps the margin at or below one, so the set cannot end.
      for (var i = 0; i < 7; i++) {
        s = play(rally(Side.b, 1, 'B5'), s);
        s = play(rally(Side.a, 1, 'A5'), s);
      }
      expect(s['currentA'], 32);
      expect(s['currentB'], 31);
      expect(s['setsA'], 0, reason: 'still only a one point lead');

      s = play(rally(Side.a, 1, 'A5'), s);
      expect(s['setsA'], 1, reason: '33-31 takes the set');
    });

    test('the deciding set is played to 15, not 25', () {
      // Two sets each.
      var s = vb.initialState(ctx);
      for (var i = 0; i < 2; i++) {
        s = play(rally(Side.a, 25, 'A5'), s);
        s = play(rally(Side.b, 25, 'B5'), s);
      }
      expect(s['setsA'], 2);
      expect(s['setsB'], 2);
      expect(vb.targetForCurrentSet(s, ctx), 15,
          reason: 'the fifth set is shorter');

      s = play(rally(Side.a, 15, 'A5'), s);
      expect(s['complete'], isTrue);
      expect(s['winner'], 'a');
    });

    test('points won is derived from kills, blocks and aces', () {
      final s = play([
        point(Side.a, 'attack', player: 'A5'),
        point(Side.a, 'block', player: 'A5'),
        point(Side.a, 'ace', player: 'A5'),
      ]);
      final line = vb
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A5');
      final pts = VolleyballPlugin.columns.firstWhere((c) => c.key == 'points');
      expect(pts.valueFrom(line.tally), 3);
    });
  });

  // ==========================================================================
  // Kho-kho
  // ==========================================================================
  group('Kho-kho', () {
    const kk = KhoKhoPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Medak',
      entrantBName: 'Siddipet',
      config: const {
        'tagPoints': 2,
        'poleDivePoints': 2,
        'skyDivePoints': 2,
        'allOutBonus': 4,
        'batchSize': 3,
        'turnsPerInnings': 2,
        'dreamRunAfterSeconds': 180,
        'dreamRunEverySeconds': 30,
      },
      lineupA: _squad('A', 12),
      lineupB: _squad('B', 12),
    );

    Map<String, dynamic> play(List<ScoreAction> actions, [Map<String, dynamic>? from]) {
      var s = from ?? kk.initialState(ctx);
      for (final a in actions) {
        final r = kk.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    ScoreAction tag(String attacker, {String skill = 'regular', String? defender, int survived = 0}) =>
        ScoreAction(
          type: 'tag',
          side: Side.a,
          payload: {
            'playerId': attacker,
            'skill': skill,
            if (defender != null) 'defenderId': defender,
            'survivedSeconds': survived,
          },
        );

    test('a tag scores the configured value, not a hardcoded one', () {
      final s = play([tag('A1')]);
      expect(s['a'], 2);

      // The same action under a different league's rules scores differently.
      final threePointCtx = ScoringContext(
        entrantAName: 'Medak',
        entrantBName: 'Siddipet',
        config: const {'tagPoints': 3, 'batchSize': 3, 'allOutBonus': 4},
        lineupA: _squad('A', 12),
        lineupB: _squad('B', 12),
      );
      final other = kk.apply(kk.initialState(threePointCtx), tag('A1'), threePointCtx);
      expect(other.state['a'], 3,
          reason: 'point values are per-league configuration');
    });

    test('dive types are recorded separately from regular tags', () {
      final s = play([
        tag('A1'),
        tag('A1', skill: 'pole_dive'),
        tag('A2', skill: 'sky_dive'),
      ]);
      final box = kk.boxScore(s, ctx, Side.a);
      final a1 = box.players.firstWhere((p) => p.playerId == 'A1');
      expect(a1['tags'], 2);
      expect(a1['poleDives'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A2')['skyDives'], 1);
    });

    test('clearing a batch of three is an all-out with a bonus', () {
      final s = play([tag('A1'), tag('A1'), tag('A1')]);
      // Three tags at 2 each, plus the all-out bonus of 4.
      expect(s['a'], 10);
      expect(s['defendersOut'], 0, reason: 'a new batch comes on');
      expect(s['batchNumber'], 2);
    });

    test('a dream run pays the DEFENDING side, on the configured schedule', () {
      // Nothing before three minutes.
      expect(kk.dreamRunPointsFor(179, ctx), 0);
      // One point at three minutes, then one per further thirty seconds.
      expect(kk.dreamRunPointsFor(180, ctx), 1);
      expect(kk.dreamRunPointsFor(210, ctx), 2);
      expect(kk.dreamRunPointsFor(240, ctx), 3);

      final s = play([tag('A1', defender: 'B4', survived: 240)]);
      // Attacker got 2 for the tag; the defender's side got 3 for surviving.
      expect(s['a'], 2);
      expect(s['b'], 3);
      final b4 = kk
          .boxScore(s, ctx, Side.b)
          .players
          .firstWhere((p) => p.playerId == 'B4');
      expect(b4['dreamRunPoints'], 3);
      expect(b4['timesOut'], 1);
    });

    test('time survived reads in minutes on the sheet', () {
      final s = play([tag('A1', defender: 'B4', survived: 150)]);
      final line = kk
          .boxScore(s, ctx, Side.b)
          .players
          .firstWhere((p) => p.playerId == 'B4');
      final col =
          KhoKhoPlugin.columns.firstWhere((c) => c.key == 'survivalMinutes');
      expect(col.valueFrom(line.tally), closeTo(2.5, 0.01));
    });

    test('ending a turn swaps who is attacking', () {
      var s = play([tag('A1')]);
      expect(s['attackingSide'], 'a');
      s = play([const ScoreAction(type: 'end_turn')], s);
      expect(s['attackingSide'], 'b');
      expect(s['turn'], 2);
      expect(s['defendersOut'], 0);
    });

    test('khos are counted', () {
      final s = play([
        const ScoreAction(type: 'kho', side: Side.a, payload: {'playerId': 'A3'}),
        const ScoreAction(type: 'kho', side: Side.a, payload: {'playerId': 'A3'}),
      ]);
      expect(
        kk.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A3')['khos'],
        2,
      );
    });

    test('a scripted turn replays identically', () {
      final script = [
        tag('A1'),
        tag('A2', skill: 'sky_dive', defender: 'B2', survived: 200),
        const ScoreAction(type: 'kho', side: Side.a, payload: {'playerId': 'A3'}),
        const ScoreAction(type: 'end_turn'),
        const ScoreAction(type: 'finish'),
      ];
      final direct = play(script);
      final replayed = kk.replay(script, ctx);
      expect(replayed['a'], direct['a']);
      expect(replayed['b'], direct['b']);
      expect(replayed['turn'], direct['turn']);
    });
  });
}
