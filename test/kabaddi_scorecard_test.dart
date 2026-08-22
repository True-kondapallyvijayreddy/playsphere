import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/kabaddi_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// The kabaddi pad's contract: **score first, details second, the match never
/// stops.**
///
/// A raid lasts thirty seconds and the next one starts immediately. Every
/// assertion here exists because the pad that asks "who raided?" before it
/// will take a point is the pad a scorer abandons at the ground — so the
/// engine must take the point with nobody named, keep the team score exactly
/// right, and hold the missing name until somebody has time to supply it.
void main() {
  const kabaddi = KabaddiPlugin();

  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 7; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  final ctx = ScoringContext(
    entrantAName: 'India A',
    entrantBName: 'India B',
    config: RulePresets.resolve(sportId: 'kabaddi').toMap(),
    lineupA: squad('A'),
    lineupB: squad('B'),
  );

  Map<String, dynamic> run(
    Map<String, dynamic> state,
    List<ScoreAction> actions,
  ) {
    var s = state;
    for (final a in actions) {
      final r = kabaddi.apply(s, a, ctx);
      expect(r.isAccepted, isTrue, reason: '${a.type} was rejected: ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  ScoreAction raid(
    Side side, {
    int touched = 0,
    bool bonus = false,
    bool raiderOut = false,
    String? by,
    List<String>? out,
  }) =>
      ScoreAction(type: 'raid', side: side, payload: {
        'touched': touched,
        if (bonus) 'bonus': true,
        if (raiderOut) 'raiderOut': true,
        if (by != null) 'playerId': by,
        if (out != null) 'defenderIds': out,
      });

  ScoreAction tackle(Side side, {List<String>? by, bool? isSuper}) =>
      ScoreAction(type: 'tackle', side: side, payload: {
        if (by != null) 'defenderIds': by,
        if (isSuper != null) 'super': isSuper,
      });

  /// The one invariant the whole scorecard rests on: the five breakdown
  /// columns are the score, not an approximation of it. A scorecard whose
  /// parts do not sum to its whole cannot be argued from, and a disputed
  /// kabaddi result is argued from exactly these columns.
  void expectBreakdownSums(Map<String, dynamic> s) {
    for (final side in [Side.a, Side.b]) {
      expect(
        kabaddi.raidPointsFor(s, side) +
            kabaddi.tacklePointsFor(s, side) +
            kabaddi.bonusPointsFor(s, side) +
            kabaddi.allOutPointsFor(s, side) +
            kabaddi.technicalPointsFor(s, side),
        kabaddi.scoreFor(s, side),
        reason: 'breakdown must sum to the score for ${side.wire}',
      );
    }
  }

  group('Scoring with nobody named', () {
    test('a raid scores without a raider, and the score is exact', () {
      final s = run(kabaddi.initialState(ctx), [raid(Side.a, touched: 2)]);

      expect(kabaddi.scoreFor(s, Side.a), 2);
      expect(kabaddi.raidPointsFor(s, Side.a), 2);
      expect(kabaddi.onCourt(s, Side.b), 5);
      expectBreakdownSums(s);
    });

    test('a tackle scores without a tackler', () {
      final s = run(kabaddi.initialState(ctx), [tackle(Side.b)]);

      expect(kabaddi.scoreFor(s, Side.b), 1);
      expect(kabaddi.tacklePointsFor(s, Side.b), 1);
      expect(kabaddi.onCourt(s, Side.a), 6);
      expectBreakdownSums(s);
    });

    test('the skipped name lands on the pending queue, not on the floor', () {
      final s = run(kabaddi.initialState(ctx), [
        raid(Side.a, touched: 1),
        tackle(Side.b),
      ]);

      final pending = KabaddiPlugin.pendingOf(s);
      expect(pending, hasLength(2));
      expect(pending.first['needs'], contains('raider'));
      expect(pending.last['needs'], contains('tackler'));
      // The queue is what the pad's "3 Details Pending" badge counts.
      expect(kabaddi.statusLine(s, ctx), contains('2 details pending'));
    });

    test('naming the raider afterwards moves the stats, never the score', () {
      var s = run(kabaddi.initialState(ctx), [raid(Side.a, touched: 2)]);
      final scoreBefore = kabaddi.scoreFor(s, Side.a);
      final id = KabaddiPlugin.pendingOf(s).single['id'] as String;

      s = run(s, [
        ScoreAction(type: 'attribute', payload: {'id': id, 'playerId': 'A7'}),
      ]);

      expect(kabaddi.scoreFor(s, Side.a), scoreBefore);
      expect(KabaddiPlugin.pendingOf(s), isEmpty);

      final line = kabaddi
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A7');
      expect(line['raidPoints'], 2);
      expect(line['raids'], 1);
      // And the ledger line now carries the name it was missing.
      expect(KabaddiPlugin.historyOf(s).single['actorId'], 'A7');
    });

    test('a tackle named late is split across everyone who held the raider',
        () {
      var s = run(kabaddi.initialState(ctx), [tackle(Side.b)]);
      final id = KabaddiPlugin.pendingOf(s).single['id'] as String;

      s = run(s, [
        ScoreAction(type: 'attribute', payload: {
          'id': id,
          'defenderIds': const ['B2', 'B4'],
        }),
      ]);

      final box = kabaddi.boxScore(s, ctx, Side.b);
      for (final id in ['B2', 'B4']) {
        expect(box.players.firstWhere((p) => p.playerId == id)['tacklePoints'],
            0.5);
      }
      // Halves, so the two of them still add up to the one point the team got.
      expect(box.teamTotals['tacklePoints'], 1);
    });

    test('the same detail cannot be completed twice', () {
      var s = run(kabaddi.initialState(ctx), [raid(Side.a, touched: 1)]);
      final id = KabaddiPlugin.pendingOf(s).single['id'] as String;
      final attribute =
          ScoreAction(type: 'attribute', payload: {'id': id, 'playerId': 'A1'});

      s = run(s, [attribute]);
      expect(kabaddi.apply(s, attribute, ctx).isAccepted, isFalse);
    });
  });

  group('The mat', () {
    test('points revive team-mates in the order they went out', () {
      var s = run(kabaddi.initialState(ctx), [
        raid(Side.b, touched: 2, out: ['A3', 'A5']),
      ]);
      expect(kabaddi.outQueue(s, Side.a), ['A3', 'A5']);
      expect(kabaddi.onCourt(s, Side.a), 5);

      s = run(s, [raid(Side.a, touched: 1)]);

      // One point back, and it is the player who went out first.
      expect(kabaddi.outQueue(s, Side.a), ['A5']);
      expect(kabaddi.onCourt(s, Side.a), 6);
      expect(kabaddi.matFor(s, ctx, Side.a), isNot(contains('A5')));
      expect(kabaddi.matFor(s, ctx, Side.a), contains('A3'));
    });

    test('a raid that scores AND loses the raider keeps both effects', () {
      // The revival and the raider going out are two movements of the same
      // number in the same action, and an engine that reads the count from
      // the state it started in applies only the second — which silently
      // costs the raiding side the players its own points just brought back.
      var s = run(kabaddi.initialState(ctx), [
        tackle(Side.b),
        tackle(Side.b),
      ]);
      expect(kabaddi.onCourt(s, Side.a), 5);

      s = run(s, [raid(Side.a, touched: 2, raiderOut: true)]);

      // 5 on the mat, two points revive two, the raider then leaves: 6.
      expect(kabaddi.onCourt(s, Side.a), 6);
      expect(kabaddi.onCourt(s, Side.b), 5);
    });

    test('emptying the mat is an all-out, and it is booked as its own column',
        () {
      var s = kabaddi.initialState(ctx);
      // Seven tackles empty side A's mat — but each one revives nobody for A,
      // so the seventh triggers the all-out.
      for (var i = 0; i < 7; i++) {
        s = run(s, [tackle(Side.b)]);
      }

      expect(kabaddi.allOutsFor(s, Side.b), 1);
      expect(kabaddi.allOutPointsFor(s, Side.b), 2);
      expect(kabaddi.onCourt(s, Side.a), 7);
      expect(kabaddi.onCourt(s, Side.b), 7);
      expect(kabaddi.outQueue(s, Side.a), isEmpty);
      expectBreakdownSums(s);
    });

    test('an all-out the engine could not see can be called by hand', () {
      final s = run(kabaddi.initialState(ctx), [
        const ScoreAction(type: 'all_out', side: Side.a),
      ]);

      expect(kabaddi.allOutPointsFor(s, Side.a), 2);
      expect(kabaddi.scoreFor(s, Side.a), 2);
      expect(kabaddi.onCourt(s, Side.b), 7);
      expectBreakdownSums(s);
    });

    test('a substitution moves a name and never the count', () {
      final before = kabaddi.initialState(ctx);
      final s = run(before, [
        const ScoreAction(type: 'substitute', side: Side.a, payload: {
          'offId': 'A2',
          'onId': 'A7',
        }),
      ]);

      expect(kabaddi.onCourt(s, Side.a), kabaddi.onCourt(before, Side.a));
      expect(kabaddi.matFor(s, ctx, Side.a), isNot(contains('A2')));
      expect(kabaddi.matFor(s, ctx, Side.a), contains('A7'));
    });
  });

  group('The rules that decide a match', () {
    test('a failed do-or-die hands the point to the defence as a tackle', () {
      var s = run(kabaddi.initialState(ctx), [
        raid(Side.a),
        raid(Side.a),
      ]);
      expect(kabaddi.isDoOrDie(s, Side.a, ctx), isTrue);

      s = run(s, [raid(Side.a)]);

      expect(kabaddi.scoreFor(s, Side.b), 1);
      expect(kabaddi.tacklePointsFor(s, Side.b), 1);
      expect(kabaddi.onCourt(s, Side.a), 6);
      expect(kabaddi.isDoOrDie(s, Side.a, ctx), isFalse);
      expect(KabaddiPlugin.historyOf(s).last['result'], 'Do-or-Die failed');
      expectBreakdownSums(s);
    });

    test('a bonus is booked in its own column and still counts as a raid point',
        () {
      final s = run(kabaddi.initialState(ctx), [
        raid(Side.a, touched: 1, bonus: true, by: 'A1'),
      ]);

      expect(kabaddi.scoreFor(s, Side.a), 2);
      expect(kabaddi.bonusPointsFor(s, Side.a), 1);
      expect(kabaddi.raidPointsFor(s, Side.a), 1);
      expectBreakdownSums(s);

      // The raider's own line credits both, which is what a Super 10 counts.
      final line = kabaddi
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A1');
      expect(line['raidPoints'], 2);
      expect(line['bonusPoints'], 1);
    });

    test('a referee can call a super tackle the count does not imply', () {
      final s = run(kabaddi.initialState(ctx), [tackle(Side.b, isSuper: true)]);

      expect(kabaddi.tacklePointsFor(s, Side.b), 2);
      expect(KabaddiPlugin.historyOf(s).single['result'], 'Super Tackle');
    });

    test('a technical point belongs to the team and to no player', () {
      final s = run(kabaddi.initialState(ctx), [
        const ScoreAction(type: 'technical', side: Side.b),
      ]);

      expect(kabaddi.technicalPointsFor(s, Side.b), 1);
      expect(kabaddi.scoreFor(s, Side.b), 1);
      expect(KabaddiPlugin.pendingOf(s), isEmpty);
      expect(kabaddi.boxScore(s, ctx, Side.b).teamTotals['tacklePoints'] ?? 0, 0);
      expectBreakdownSums(s);
    });

    test('the raid passes to the other side after every turnover', () {
      var s = kabaddi.initialState(ctx);
      expect(kabaddi.raidingSide(s), Side.a);

      s = run(s, [raid(Side.a, touched: 1)]);
      expect(kabaddi.raidingSide(s), Side.b);

      s = run(s, [tackle(Side.a)]);
      expect(kabaddi.raidingSide(s), Side.a);
    });
  });

  group('The ledger', () {
    test('every line carries the running score it produced', () {
      final s = run(kabaddi.initialState(ctx), [
        raid(Side.a, touched: 2),
        tackle(Side.a),
        raid(Side.b, touched: 1),
      ]);

      final history = KabaddiPlugin.historyOf(s);
      expect(history.map((h) => [h['a'], h['b']]), [
        [2, 0],
        [3, 0],
        [3, 1],
      ]);
      expect(history.map((h) => h['no']), [1, 2, 3]);
      expect(history.last['result'], 'Touch 1');
    });

    test('a non-raid line is marked so the pad does not number it as one', () {
      final s = run(kabaddi.initialState(ctx), [
        raid(Side.a, touched: 1),
        const ScoreAction(type: 'technical', side: Side.b),
      ]);

      final history = KabaddiPlugin.historyOf(s);
      expect(history.first['kind'], 'raid');
      expect(history.last['kind'], 'event');
      expect(kabaddi.raidNumber(s), 1);
    });

    test('a scripted match replays to exactly the same state', () {
      final script = [
        raid(Side.a, touched: 2, by: 'A1', out: ['B3', 'B4']),
        tackle(Side.b, by: ['B2']),
        raid(Side.b, touched: 1, bonus: true, by: 'B5'),
        const ScoreAction(type: 'technical', side: Side.a),
        raid(Side.a),
        raid(Side.a),
        raid(Side.a),
      ];

      expect(kabaddi.replay(script, ctx), run(kabaddi.initialState(ctx), script));
    });
  });

  group('The clock', () {
    test('a kabaddi half is timed, from the length the organizer set', () {
      // The shared mixin looks for `periodMinutes`; kabaddi's presets write
      // `halfLengthMinutes`. Without the bridge the pad reported the one sport
      // governed by a raid clock as untimed.
      expect(kabaddi.periodMinutes(ctx), 20);
      expect(kabaddi.raidClockSeconds(ctx), 30);
      expect(kabaddi.statusLine(kabaddi.initialState(ctx), ctx),
          startsWith('Half 1 of 2 · 0'));
    });

    test('half time refills both mats and turns the raid over', () {
      var s = run(kabaddi.initialState(ctx), [
        tackle(Side.b),
        raid(Side.a),
      ]);
      expect(kabaddi.onCourt(s, Side.a), 6);

      s = run(s, [const ScoreAction(type: 'next_period')]);

      expect(kabaddi.onCourt(s, Side.a), 7);
      expect(kabaddi.onCourt(s, Side.b), 7);
      expect(kabaddi.outQueue(s, Side.a), isEmpty);
      expect(kabaddi.isDoOrDie(s, Side.a, ctx), isFalse);
      // Whoever did not raid first in the first half opens the second.
      expect(kabaddi.raidingSide(s), Side.b);
    });
  });
}
