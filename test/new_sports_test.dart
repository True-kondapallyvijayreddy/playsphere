import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/athletics_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/carrom_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/chess_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Drives a plugin through a script of actions, asserting nothing is rejected
/// unless the script says so.
Map<String, dynamic> play(
  ScoringPlugin plugin,
  ScoringContext ctx,
  List<ScoreAction> script, {
  Map<String, dynamic>? from,
}) {
  var state = from ?? plugin.initialState(ctx);
  for (final action in script) {
    final result = plugin.apply(state, action, ctx);
    expect(
      result.isAccepted,
      isTrue,
      reason: 'action "${action.type}" was rejected: ${result.rejection}',
    );
    state = result.state;
  }
  return state;
}

ScoringContext ctxFor(
  String sportId, {
  String? presetId,
  Map<String, dynamic>? overrides,
  List<MatchPlayer> a = const [],
  List<MatchPlayer> b = const [],
}) =>
    ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      lineupA: a,
      lineupB: b,
      config: RulePresets.resolve(
        sportId: sportId,
        presetId: presetId,
        overrides: overrides,
      ).toMap(),
    );

void main() {
  // ==========================================================================
  group('Badminton', () {
    const badminton = BadmintonPlugin();

    const smith = MatchPlayer(id: 'p1', name: 'Smith', uid: 'u1');
    const jones = MatchPlayer(id: 'p2', name: 'Jones', uid: 'u2');
    const pandey = MatchPlayer(id: 'p3', name: 'Pandey', uid: 'u3');

    ScoreAction rally(Side side, {String? by, bool ace = false}) => ScoreAction(
          type: 'rally',
          side: side,
          payload: {
            if (by != null) 'playerId': by,
            if (ace) 'ace': true,
          },
        );

    test('a game is to 21 and must be won by two', () {
      final ctx = ctxFor('badminton');
      // 20-20, then two in a row takes it 22-20.
      final script = <ScoreAction>[];
      for (var i = 0; i < 20; i++) {
        script..add(rally(Side.a))..add(rally(Side.b));
      }
      var s = play(badminton, ctx, script);
      expect(s['currentA'], 20);
      expect(s['currentB'], 20);

      s = play(badminton, ctx, [rally(Side.a)], from: s);
      // 21-20 is not enough — the margin is one.
      expect(s['gamesA'], 0, reason: '21-20 should not end the game');

      s = play(badminton, ctx, [rally(Side.a)], from: s);
      expect(s['gamesA'], 1);
      expect((s['completedGames'] as List).first, {'a': 22, 'b': 20});
    });

    test('the hard cap at 30 ends a game without a two-point margin', () {
      final ctx = ctxFor('badminton');
      final script = <ScoreAction>[];
      for (var i = 0; i < 29; i++) {
        script..add(rally(Side.a))..add(rally(Side.b));
      }
      var s = play(badminton, ctx, script);
      expect(s['currentA'], 29);
      expect(s['currentB'], 29);

      // 30-29 takes it on the cap, one point clear.
      s = play(badminton, ctx, [rally(Side.a)], from: s);
      expect(s['gamesA'], 1);
      expect((s['completedGames'] as List).first, {'a': 30, 'b': 29});
    });

    test('the service court follows the server\'s own score', () {
      final ctx = ctxFor('badminton');
      var s = badminton.initialState(ctx);
      // A serves at 0 — even, so the right court.
      expect(badminton.serverFor(s), Side.a);
      expect(badminton.serviceCourt(s), 'right');

      // A wins the rally: 1-0, still A's serve, now from the left.
      s = play(badminton, ctx, [rally(Side.a)], from: s);
      expect(badminton.serverFor(s), Side.a);
      expect(badminton.serviceCourt(s), 'left');

      // B wins: service passes to B, who is now on 1 — so the left court.
      s = play(badminton, ctx, [rally(Side.b)], from: s);
      expect(badminton.serverFor(s), Side.b);
      expect(badminton.serviceCourt(s), 'left');

      // B wins again: 2, even, back to the right court.
      s = play(badminton, ctx, [rally(Side.b)], from: s);
      expect(badminton.serviceCourt(s), 'right');
    });

    test('a pair holding serve keeps the SAME server, and changes court', () {
      // This test used to assert the opposite — that the partner served next
      // — and the engine obliged. Both were wrong, and it is worth being
      // precise about which law they broke, because the mistake is the reason
      // the pad had to ask the scorer who won every rally in doubles.
      //
      // Law 10.4: when the serving side wins a rally, the server serves
      // AGAIN, from the alternate service court. The pair swaps courts; it
      // does not swap servers. A partner only comes to serve after a
      // side-out, and then it is whoever the new score puts in the correct
      // court. Rotating on every point held desynchronised the pad from the
      // court within three rallies, so nothing derived from it — not the
      // server, not the receiver, not the point credit — could be trusted.
      final ctx = ctxFor('badminton', a: [smith, jones], b: [pandey]);
      var s = badminton.initialState(ctx);
      expect(badminton.serverName(s, ctx), 'Smith');
      expect(badminton.serviceCourt(s), 'right', reason: 'A is on 0');

      s = play(badminton, ctx, [rally(Side.a)], from: s);
      expect(badminton.serverName(s, ctx), 'Smith',
          reason: 'holding serve does not hand it to the partner');
      expect(badminton.serviceCourt(s), 'left', reason: 'A is on 1');

      s = play(badminton, ctx, [rally(Side.a)], from: s);
      expect(badminton.serverName(s, ctx), 'Smith');
      expect(badminton.serviceCourt(s), 'right');
    });

    test('the partner comes to serve after the pair wins the serve back', () {
      final ctx = ctxFor('badminton', a: [smith, jones], b: [pandey]);
      // A serves and wins one, loses the serve, then breaks straight back.
      final s = play(badminton, ctx, [
        rally(Side.a),
        rally(Side.b),
        rally(Side.a),
      ]);

      expect(badminton.serverFor(s), Side.a);
      // A is on 2 — even — so the right service court serves, and the pair
      // last swapped courts on the point they won at 0. That puts Jones
      // there. Nobody was asked; the score and the laws settle it.
      expect(badminton.serverName(s, ctx), 'Jones');
    });

    test('the BWF 3x15 preset plays to 15, capped at 21, best of five', () {
      final ctx = ctxFor('badminton', presetId: 'badminton_3x15');
      final script = <ScoreAction>[];
      for (var i = 0; i < 15; i++) {
        script.add(rally(Side.a));
      }
      final s = play(badminton, ctx, script);
      expect(s['gamesA'], 1, reason: '15-0 takes a game under 3x15');
      expect(s['complete'], isNot(true), reason: 'best of five needs three');
    });

    test('the interval fires at 11, and at 8 under 3x15', () {
      final classic = ctxFor('badminton');
      var s = play(
        const BadmintonPlugin(),
        classic,
        List.generate(11, (_) => rally(Side.a)),
      );
      expect(badminton.atInterval(s, classic), isTrue);

      final bwf = ctxFor('badminton', presetId: 'badminton_3x15');
      s = play(badminton, bwf, List.generate(8, (_) => rally(Side.a)));
      expect(badminton.atInterval(s, bwf), isTrue);
    });

    test('points on serve and on receive are tracked separately', () {
      final ctx = ctxFor('badminton', a: [smith], b: [jones]);
      // Smith serves first. He wins the first (on serve), loses the next two
      // to Jones (Jones' first is on receive, second on serve).
      final s = play(badminton, ctx, [
        rally(Side.a, by: 'p1'),
        rally(Side.b, by: 'p2'),
        rally(Side.b, by: 'p2'),
      ]);

      final smithTally = (s['players'] as Map)['p1'] as Map;
      expect(smithTally['pointsOnServe'], 1);
      expect(smithTally['pointsOnReceive'], null);

      final jonesTally = (s['players'] as Map)['p2'] as Map;
      expect(jonesTally['pointsOnReceive'], 1);
      expect(jonesTally['pointsOnServe'], 1);
    });

    test('replaying the log reproduces the state exactly', () {
      final ctx = ctxFor('badminton', a: [smith], b: [jones]);
      final script = [
        rally(Side.a, by: 'p1', ace: true),
        rally(Side.b, by: 'p2'),
        rally(Side.a, by: 'p1'),
        rally(Side.a, by: 'p1'),
      ];
      expect(badminton.replay(script, ctx), play(badminton, ctx, script));
    });
  });

  // ==========================================================================
  group('Chess', () {
    const chess = ChessPlugin();
    const white = MatchPlayer(id: 'w', name: 'Anand', uid: 'u1');
    const black = MatchPlayer(id: 'b', name: 'Gukesh', uid: 'u2');

    ScoreAction result(String r) => ScoreAction(
          type: 'result',
          payload: {
            'result': r,
            'whitePlayerId': 'w',
            'blackPlayerId': 'b',
            'reason': 'resignation',
          },
        );

    test('a win is one point and finishes a single-board fixture', () {
      final ctx = ctxFor('chess', a: [white], b: [black]);
      final s = play(chess, ctx, [result('a')]);
      expect(s['a'], 1.0);
      expect(s['b'], 0.0);
      expect(s['complete'], isTrue);
      expect(s['winner'], 'a');
    });

    test('a draw splits the point and is not a winner', () {
      final ctx = ctxFor('chess', a: [white], b: [black]);
      final s = play(chess, ctx, [result('draw')]);
      expect(s['a'], 0.5);
      expect(s['b'], 0.5);
      expect(s['draw'], isTrue);
      expect(s['winner'], isNull);
    });

    test('a team match runs several boards and totals them', () {
      final ctx = ctxFor(
        'chess',
        overrides: {'boards': 4},
        a: [white],
        b: [black],
      );
      final s = play(chess, ctx, [
        result('a'),
        result('draw'),
        result('b'),
        result('a'),
      ]);
      // A: 1 + 0.5 + 0 + 1 = 2.5. B: 0 + 0.5 + 1 + 0 = 1.5.
      expect(s['a'], 2.5);
      expect(s['b'], 1.5);
      expect(s['complete'], isTrue);
      expect(s['winner'], 'a');
      expect((s['results'] as List).length, 4);
    });

    test('per-player records follow the colour they played', () {
      final ctx = ctxFor('chess', overrides: {'boards': 2}, a: [white], b: [black]);
      final s = play(chess, ctx, [result('a'), result('draw')]);

      final w = (s['players'] as Map)['w'] as Map;
      expect(w['wins'], 1);
      expect(w['draws'], 1);
      expect(w['points'], 1.5);
      expect(w['whiteGames'], 2);

      final b = (s['players'] as Map)['b'] as Map;
      expect(b['losses'], 1);
      expect(b['draws'], 1);
      expect(b['points'], 0.5);
      expect(b['blackGames'], 2);
    });

    test('moves are recorded only when the time control asks for them', () {
      final classical = ctxFor('chess', presetId: 'chess_classical');
      var s = play(chess, classical, [
        const ScoreAction(type: 'move', payload: {'san': 'e4'}),
        const ScoreAction(type: 'move', payload: {'san': 'c5'}),
        const ScoreAction(type: 'move', payload: {'san': 'Nf3'}),
      ]);
      expect(chess.movesOf(s), ['e4', 'c5', 'Nf3']);

      // Blitz does not record moves, so the action is refused rather than
      // silently dropped.
      final blitz = ctxFor('chess', presetId: 'chess_blitz');
      final rejected = chess.apply(
        chess.initialState(blitz),
        const ScoreAction(type: 'move', payload: {'san': 'e4'}),
        blitz,
      );
      expect(rejected.isAccepted, isFalse);
    });

    test('a move list renders as PGN movetext', () {
      expect(
        ChessPlugin.pgnOf(['e4', 'c5', 'Nf3', 'd6']),
        '1. e4 c5 2. Nf3 d6',
      );
      expect(ChessPlugin.pgnOf(['e4']), '1. e4');
      expect(ChessPlugin.pgnOf([]), '');
    });

    test('the finished board carries its PGN, and the next starts clean', () {
      final ctx = ctxFor('chess', overrides: {'boards': 2}, a: [white], b: [black]);
      final s = play(chess, ctx, [
        const ScoreAction(type: 'move', payload: {'san': 'e4'}),
        const ScoreAction(type: 'move', payload: {'san': 'e5'}),
        result('a'),
      ]);
      expect((s['results'] as List).first['pgn'], '1. e4 e5');
      expect(chess.movesOf(s), isEmpty, reason: 'board two starts empty');
    });

    test('an unknown result is refused', () {
      final ctx = ctxFor('chess');
      final r = chess.apply(
        chess.initialState(ctx),
        const ScoreAction(type: 'result', payload: {'result': 'maybe'}),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });
  });

  // ==========================================================================
  group('Carrom', () {
    const carrom = CarromPlugin();
    const raju = MatchPlayer(id: 'p1', name: 'Raju', uid: 'u1');

    ScoreAction board(
      Side side, {
      required int coinsLeft,
      bool queen = false,
      bool covered = false,
      String? by,
    }) =>
        ScoreAction(
          type: 'board',
          side: side,
          payload: {
            'opponentCoinsLeft': coinsLeft,
            'queen': queen,
            'queenCovered': covered,
            if (by != null) 'playerId': by,
          },
        );

    test('a board is worth one point per opponent coin left', () {
      final ctx = ctxFor('carrom');
      final s = play(carrom, ctx, [board(Side.a, coinsLeft: 5)]);
      expect(s['a'], 5);
      expect(s['b'], 0);
    });

    test('the queen adds three, but only when it was covered', () {
      final ctx = ctxFor('carrom');

      final covered = play(carrom, ctx, [
        board(Side.a, coinsLeft: 4, queen: true, covered: true),
      ]);
      expect(covered['a'], 7, reason: '4 coins + 3 for a covered queen');

      final uncovered = play(carrom, ctx, [
        board(Side.a, coinsLeft: 4, queen: true, covered: false),
      ]);
      expect(uncovered['a'], 4, reason: 'an uncovered queen scores nothing');
    });

    test('the queen stops counting once the winner is on 22 or more', () {
      final ctx = ctxFor('carrom');
      // Get A to 22 first: 9 + 9 + 4.
      var s = play(carrom, ctx, [
        board(Side.a, coinsLeft: 9),
        board(Side.a, coinsLeft: 9),
        board(Side.a, coinsLeft: 4),
      ]);
      expect(s['a'], 22);

      // On 22, a covered queen is worth nothing extra.
      s = play(carrom, ctx, [
        board(Side.a, coinsLeft: 2, queen: true, covered: true),
      ], from: s);
      expect(s['a'], 24, reason: '22 + 2 coins, no queen bonus above 21');
    });

    test('a board is capped at 25 points', () {
      final ctx = ctxFor('carrom', overrides: {'coinsPerSide': 30});
      final s = play(carrom, ctx, [
        board(Side.a, coinsLeft: 30, queen: true, covered: true),
      ]);
      expect(s['a'], 25);
    });

    test('the match ends at 29 points', () {
      final ctx = ctxFor('carrom');
      final s = play(carrom, ctx, [
        board(Side.a, coinsLeft: 9),
        board(Side.a, coinsLeft: 9),
        board(Side.a, coinsLeft: 9),
        board(Side.a, coinsLeft: 9),
      ]);
      expect(s['a'], 36);
      expect(s['complete'], isTrue);
      expect(s['winner'], 'a');
    });

    test('the club preset ends after a fixed number of boards instead', () {
      final ctx = ctxFor('carrom', presetId: 'carrom_club');
      final s = play(carrom, ctx, [
        board(Side.a, coinsLeft: 3),
        board(Side.b, coinsLeft: 2),
        board(Side.a, coinsLeft: 1),
      ]);
      expect(s['complete'], isTrue, reason: 'best of three boards');
      expect(s['a'], 4);
      expect(s['b'], 2);
      expect(s['winner'], 'a');
    });

    test('a foul costs a point but never drives a total below zero', () {
      final ctx = ctxFor('carrom');
      final s = play(carrom, ctx, [
        const ScoreAction(type: 'foul', side: Side.a),
        const ScoreAction(type: 'foul', side: Side.a),
      ]);
      expect(s['a'], 0);
    });

    test('an impossible coin count is refused', () {
      final ctx = ctxFor('carrom');
      final r = carrom.apply(
        carrom.initialState(ctx),
        board(Side.a, coinsLeft: 40),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });

    test('player records follow the board winner', () {
      final ctx = ctxFor('carrom', a: [raju]);
      final s = play(carrom, ctx, [
        board(Side.a, coinsLeft: 3, queen: true, covered: true, by: 'p1'),
      ]);
      final tally = (s['players'] as Map)['p1'] as Map;
      expect(tally['boardsWon'], 1);
      expect(tally['pointsScored'], 6);
      expect(tally['coinsPocketed'], 6, reason: '9 coins less the 3 left');
      expect(tally['queensCovered'], 1);
    });
  });

  // ==========================================================================
  group('Athletics', () {
    const athletics = AthleticsPlugin();
    const asha = MatchPlayer(id: 'a1', name: 'Asha', uid: 'u1');
    const bhavna = MatchPlayer(id: 'a2', name: 'Bhavna', uid: 'u2');
    const chitra = MatchPlayer(id: 'a3', name: 'Chitra', uid: 'u3');

    ScoreAction mark(String id, double value, {int? lane}) => ScoreAction(
          type: 'mark',
          payload: {
            'athleteId': id,
            'value': value,
            if (lane != null) 'lane': lane,
          },
        );

    test('on the track the fastest time wins', () {
      final ctx = ctxFor(
        'athletics_sprint',
        a: [asha, bhavna, chitra],
      );
      final s = play(athletics, ctx, [
        mark('a1', 12.44, lane: 4),
        mark('a2', 12.10, lane: 5),
        mark('a3', 13.02, lane: 3),
      ]);

      final table = athletics.standings(s, ctx);
      expect(table.map((r) => r.name).toList(), ['Bhavna', 'Asha', 'Chitra']);
      expect(table.first.place, 1);
      expect(table.first.best, 12.10);
    });

    test('in the field the longest mark wins, and best-of-attempts applies', () {
      final ctx = ctxFor('athletics_field', a: [asha, bhavna]);
      final s = play(athletics, ctx, [
        mark('a1', 5.20),
        mark('a1', 5.65),
        mark('a1', 5.41),
        mark('a2', 5.55),
      ]);

      expect(athletics.bestOf(s, 'a1', ctx), 5.65);
      final table = athletics.standings(s, ctx);
      expect(table.first.name, 'Asha');
      expect(table.first.best, 5.65);
    });

    test('a foul counts as an attempt but never as a mark', () {
      final ctx = ctxFor('athletics_field', a: [asha]);
      final s = play(athletics, ctx, [
        const ScoreAction(type: 'foul', payload: {'athleteId': 'a1'}),
        mark('a1', 4.80),
        const ScoreAction(type: 'foul', payload: {'athleteId': 'a1'}),
      ]);

      expect(athletics.attemptsOf(s, 'a1').length, 3);
      expect(athletics.bestOf(s, 'a1', ctx), 4.80);
      final tally = (s['players'] as Map)['a1'] as Map;
      expect(tally['attempts'], 3);
      expect(tally['fouls'], 2);
    });

    test('three fouls and no mark leaves the athlete unranked, not last', () {
      final ctx = ctxFor('athletics_field', a: [asha, bhavna]);
      final s = play(athletics, ctx, [
        const ScoreAction(type: 'foul', payload: {'athleteId': 'a1'}),
        const ScoreAction(type: 'foul', payload: {'athleteId': 'a1'}),
        const ScoreAction(type: 'foul', payload: {'athleteId': 'a1'}),
        mark('a2', 4.00),
      ]);

      final table = athletics.standings(s, ctx);
      final ashaRow = table.firstWhere((r) => r.name == 'Asha');
      expect(ashaRow.best, isNull);
      expect(ashaRow.place, isNull, reason: 'no mark is not a placing');
      expect(table.first.name, 'Bhavna');
      expect(table.first.place, 1);
    });

    test('a false start disqualifies, and a DQ sorts behind every finisher',
        () {
      final ctx = ctxFor('athletics_sprint', a: [asha, bhavna]);
      var s = play(athletics, ctx, [
        mark('a1', 11.90),
        mark('a2', 12.50),
      ]);
      s = play(athletics, ctx, [
        const ScoreAction(type: 'false_start', payload: {'athleteId': 'a1'}),
      ], from: s);

      expect(athletics.isDisqualified(s, 'a1'), isTrue);
      final table = athletics.standings(s, ctx);
      expect(table.last.name, 'Asha');
      expect(table.last.place, isNull);
      expect(table.first.name, 'Bhavna', reason: 'the DQ vacates first place');
    });

    test('a disqualification can be reversed on appeal', () {
      final ctx = ctxFor('athletics_sprint', a: [asha]);
      var s = play(athletics, ctx, [
        mark('a1', 11.90),
        const ScoreAction(type: 'disqualify', payload: {'athleteId': 'a1'}),
      ]);
      expect(athletics.isDisqualified(s, 'a1'), isTrue);

      s = play(athletics, ctx, [
        const ScoreAction(type: 'reinstate', payload: {'athleteId': 'a1'}),
      ], from: s);
      expect(athletics.isDisqualified(s, 'a1'), isFalse);
      expect(athletics.standings(s, ctx).first.place, 1);
    });

    test('a track athlete cannot record two times for one race', () {
      final ctx = ctxFor('athletics_sprint', a: [asha]);
      final s = play(athletics, ctx, [mark('a1', 12.0)]);
      final second = athletics.apply(s, mark('a1', 11.0), ctx);
      expect(second.isAccepted, isFalse);
    });

    test('equal marks share a place and the next place is skipped', () {
      final ctx = ctxFor('athletics_sprint', a: [asha, bhavna, chitra]);
      final s = play(athletics, ctx, [
        mark('a1', 12.00),
        mark('a2', 12.00),
        mark('a3', 12.50),
      ]);
      final table = athletics.standings(s, ctx);
      expect(table[0].place, 1);
      expect(table[1].place, 1);
      expect(table[2].place, 3, reason: 'a shared first skips second place');
    });

    test('times format as mm:ss.xx once past a minute', () {
      final ctx = ctxFor('athletics_sprint');
      expect(athletics.formatMark(12.44, ctx), '12.44');
      expect(athletics.formatMark(63.20, ctx), '1:03.20');
      expect(athletics.formatMark(125.06, ctx), '2:05.06');
      expect(athletics.formatMark(null, ctx), '—');
    });

    test('wind is captured on the attempt when the event records it', () {
      final ctx = ctxFor('athletics_sprint', a: [asha]);
      final s = play(athletics, ctx, [
        const ScoreAction(
          type: 'mark',
          payload: {'athleteId': 'a1', 'value': 11.2, 'wind': 1.4, 'lane': 4},
        ),
      ]);
      final attempt = athletics.attemptsOf(s, 'a1').first;
      expect(attempt['wind'], 1.4);
      expect(attempt['lane'], 4);
    });

    test('replaying the log reproduces the state exactly', () {
      final ctx = ctxFor('athletics_field', a: [asha, bhavna]);
      final script = [
        mark('a1', 5.10),
        const ScoreAction(type: 'foul', payload: {'athleteId': 'a2'}),
        mark('a1', 5.55),
        mark('a2', 5.30),
      ];
      expect(athletics.replay(script, ctx), play(athletics, ctx, script));
    });
  });

  // ==========================================================================
  group('RuleConfig', () {
    test('typed reads coerce what Firestore actually returns', () {
      const c = RuleConfig({
        'a': 21,
        'b': '30',
        'c': 2.5,
        'd': true,
        'e': 'false',
        'f': 1,
      });
      expect(c.getInt('a', 0), 21);
      expect(c.getInt('b', 0), 30, reason: 'numeric strings coerce');
      expect(c.getDouble('c', 0), 2.5);
      expect(c.getBool('d', false), isTrue);
      expect(c.getBool('e', true), isFalse, reason: '"false" is false');
      expect(c.getBool('f', false), isTrue, reason: '1 is truthy');
      expect(c.getInt('missing', 7), 7);
    });

    test('merging layers overrides without mutating either side', () {
      const base = RuleConfig({'x': 1, 'y': 2});
      final merged = base.merge({'y': 99, 'z': 3});
      expect(merged.getInt('x', 0), 1);
      expect(merged.getInt('y', 0), 99);
      expect(merged.getInt('z', 0), 3);
      expect(base.getInt('y', 0), 2, reason: 'the base is untouched');
    });

    test('every sport with presets has exactly one default', () {
      final sportIds = RulePresets.all.map((p) => p.sportId).toSet();
      for (final id in sportIds) {
        final defaults =
            RulePresets.forSport(id).where((p) => p.isDefault).toList();
        expect(
          defaults.length,
          1,
          reason: '$id should have exactly one default preset',
        );
      }
    });

    test('preset ids are unique', () {
      final ids = RulePresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('resolve falls back to the sport default when no preset is named', () {
      final resolved = RulePresets.resolve(sportId: 'badminton');
      expect(resolved.getInt('pointsPerSet', 0), 21);

      final named =
          RulePresets.resolve(sportId: 'badminton', presetId: 'badminton_3x15');
      expect(named.getInt('pointsPerSet', 0), 15);
    });

    test('kho-kho ships both the UKK and the federation rulesets', () {
      final ukk = RulePresets.resolve(presetId: 'kho_kho_ukk_s2');
      final kkfi = RulePresets.resolve(presetId: 'kho_kho_kkfi');
      // The spec calls this out: dive values differ between the two.
      expect(ukk.getInt('poleDivePoints', 0), 2);
      expect(kkfi.getInt('poleDivePoints', 0), 3);
    });
  });
}
