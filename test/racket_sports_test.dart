import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

void main() {
  final lineupA = [const MatchPlayer(id: 'A1', name: 'Sania')];
  final lineupB = [const MatchPlayer(id: 'B1', name: 'Rohan')];

  // ==========================================================================
  // Tennis
  // ==========================================================================
  group('Tennis', () {
    const tennis = TennisPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Sania',
      entrantBName: 'Rohan',
      config: const {
        'setsToWin': 2,
        'gamesPerSet': 6,
        'tiebreakTo': 7,
        'noAd': false,
      },
      lineupA: lineupA,
      lineupB: lineupB,
    );

    ScoreAction pt(Side side) => ScoreAction(type: 'point', side: side);

    Map<String, dynamic> play(List<ScoreAction> actions, [Map<String, dynamic>? from]) {
      var s = from ?? tennis.initialState(ctx);
      for (final a in actions) {
        final r = tennis.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    List<ScoreAction> pts(Side side, int n) => [for (var i = 0; i < n; i++) pt(side)];

    test('the score is a ladder, not a count', () {
      var s = tennis.initialState(ctx);
      expect(tennis.pointLabel(s, Side.a, ctx), '0');
      s = play(pts(Side.a, 1));
      expect(tennis.pointLabel(s, Side.a, ctx), '15');
      s = play(pts(Side.a, 2));
      expect(tennis.pointLabel(s, Side.a, ctx), '30');
      s = play(pts(Side.a, 3));
      expect(tennis.pointLabel(s, Side.a, ctx), '40');
    });

    test('40-40 is deuce, and advantage shows as AD', () {
      var s = play([...pts(Side.a, 3), ...pts(Side.b, 3)]);
      expect(tennis.pointLabel(s, Side.a, ctx), '40');
      expect(tennis.pointLabel(s, Side.b, ctx), '40');

      s = play(pts(Side.a, 1), s);
      expect(tennis.pointLabel(s, Side.a, ctx), 'AD');
      expect(tennis.pointLabel(s, Side.b, ctx), '40');

      // Losing the advantage returns to deuce, not to a lost game.
      s = play(pts(Side.b, 1), s);
      expect(tennis.pointLabel(s, Side.a, ctx), '40');
      expect(s['gamesA'], 0);
      expect(s['gamesB'], 0);
    });

    test('a game needs two clear points from deuce', () {
      var s = play([...pts(Side.a, 3), ...pts(Side.b, 3)]);
      s = play(pts(Side.a, 1), s); // AD
      expect(s['gamesA'], 0);
      s = play(pts(Side.a, 1), s); // game
      expect(s['gamesA'], 1);
      expect(s['pointsA'], 0, reason: 'points reset for the next game');
    });

    test('no-ad ends the deuce on the very next point', () {
      final noAd = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: const {'setsToWin': 2, 'gamesPerSet': 6, 'noAd': true},
        lineupA: lineupA,
        lineupB: lineupB,
      );
      var s = tennis.initialState(noAd);
      for (final a in [...pts(Side.a, 3), ...pts(Side.b, 3)]) {
        s = tennis.apply(s, a, noAd).state;
      }
      s = tennis.apply(s, pt(Side.a), noAd).state;
      expect(s['gamesA'], 1, reason: 'no-ad decides at deuce');
    });

    test('service alternates every game', () {
      var s = tennis.initialState(ctx);
      expect(tennis.serverFor(s), Side.a);
      s = play(pts(Side.a, 4));
      expect(tennis.serverFor(s), Side.b);
    });

    test('a break point is when the receiver is one point from the game', () {
      // A serves. B reaches 40 with A on 30 — that is a break point.
      var s = play([...pts(Side.b, 3), ...pts(Side.a, 2)]);
      expect(tennis.serverFor(s), Side.a);
      expect(tennis.isBreakPoint(s, ctx), isTrue);

      // Level at deuce is not a break point.
      s = play(pts(Side.a, 1), s);
      expect(tennis.isBreakPoint(s, ctx), isFalse);
    });

    test('6-6 goes to a tiebreak, not a seventh game', () {
      var s = tennis.initialState(ctx);
      for (var g = 0; g < 6; g++) {
        s = play(pts(Side.a, 4), s);
        s = play(pts(Side.b, 4), s);
      }
      expect(s['gamesA'], 6);
      expect(s['gamesB'], 6);
      expect(s['inTiebreak'], isTrue);
    });

    test('the tiebreak serves one point then alternates every two', () {
      var s = tennis.initialState(ctx);
      for (var g = 0; g < 6; g++) {
        s = play(pts(Side.a, 4), s);
        s = play(pts(Side.b, 4), s);
      }
      // At 6-6 the server for the tiebreak is whoever was due to serve.
      final first = tennis.serverFor(s);
      expect(s['tiebreakPointsPlayed'], 0);

      s = play(pts(Side.a, 1), s); // 1 point played
      expect(tennis.serverFor(s), first.opposite,
          reason: 'after one point service passes over');

      s = play(pts(Side.a, 1), s); // 2 played
      expect(tennis.serverFor(s), first.opposite,
          reason: 'the second server takes two points');

      s = play(pts(Side.a, 1), s); // 3 played
      expect(tennis.serverFor(s), first);
    });

    test('a tiebreak needs seven points and a two point margin', () {
      var s = tennis.initialState(ctx);
      for (var g = 0; g < 6; g++) {
        s = play(pts(Side.a, 4), s);
        s = play(pts(Side.b, 4), s);
      }
      s = play([...pts(Side.a, 6), ...pts(Side.b, 6)], s);
      expect(s['setsA'], 0, reason: '6-6 in the tiebreak decides nothing');
      s = play(pts(Side.a, 1), s);
      expect(s['setsA'], 0, reason: '7-6 is only one clear');
      s = play(pts(Side.a, 1), s);
      expect(s['setsA'], 1, reason: '8-6 takes it');
    });

    test('aces and winners are attributed', () {
      final s = play([
        const ScoreAction(
          type: 'point',
          side: Side.a,
          payload: {'playerId': 'A1', 'how': 'ace'},
        ),
        const ScoreAction(
          type: 'point',
          side: Side.a,
          payload: {'playerId': 'A1', 'how': 'winner'},
        ),
      ]);
      final line = tennis
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A1');
      expect(line['aces'], 1);
      expect(line['winners'], 1);
      expect(line['pointsWon'], 2);
    });

    test('a double fault is charged to the server who made it', () {
      final s = play([
        const ScoreAction(
          type: 'point',
          side: Side.b,
          payload: {'playerId': 'B1', 'how': 'double_fault', 'errorById': 'A1'},
        ),
      ]);
      expect(
        tennis.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A1')['doubleFaults'],
        1,
      );
    });
  });

  // ==========================================================================
  // Table tennis
  // ==========================================================================
  group('Table tennis', () {
    const tt = TableTennisPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Sania',
      entrantBName: 'Rohan',
      config: const {'pointsPerSet': 11, 'setsToWin': 3, 'serveEvery': 2},
      lineupA: lineupA,
      lineupB: lineupB,
    );

    Map<String, dynamic> play(List<ScoreAction> actions, [Map<String, dynamic>? from]) {
      var s = from ?? tt.initialState(ctx);
      for (final a in actions) {
        final r = tt.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    List<ScoreAction> pts(Side side, int n) =>
        [for (var i = 0; i < n; i++) ScoreAction(type: 'point', side: side)];

    test('a game is to 11 with a two point margin and no cap', () {
      var s = play([...pts(Side.a, 10), ...pts(Side.b, 10)]);
      expect(s['gamesA'], 0);
      s = play(pts(Side.a, 1), s); // 11-10
      expect(s['gamesA'], 0, reason: '11-10 is not a win');
      s = play(pts(Side.a, 1), s); // 12-10
      expect(s['gamesA'], 1);
    });

    test('service alternates every two points', () {
      var s = tt.initialState(ctx);
      final first = tt.serverFor(s, ctx);
      s = play(pts(Side.a, 1));
      expect(tt.serverFor(s, ctx), first, reason: 'still the first server');
      s = play(pts(Side.a, 1), s);
      expect(tt.serverFor(s, ctx), first.opposite);
      s = play(pts(Side.a, 1), s);
      expect(tt.serverFor(s, ctx), first.opposite);
      s = play(pts(Side.a, 1), s);
      expect(tt.serverFor(s, ctx), first);
    });

    test('at deuce service changes every single point', () {
      // 10-10 reached; from here the serve alternates each point.
      var s = play([...pts(Side.a, 10), ...pts(Side.b, 10)]);
      final atDeuce = tt.serverFor(s, ctx);
      s = play(pts(Side.a, 1), s);
      expect(tt.serverFor(s, ctx), atDeuce.opposite,
          reason: 'one serve each from deuce');
      s = play(pts(Side.b, 1), s);
      expect(tt.serverFor(s, ctx), atDeuce);
    });

    test('best of five ends at three games', () {
      var s = tt.initialState(ctx);
      for (var g = 0; g < 3; g++) {
        s = play(pts(Side.a, 11), s);
      }
      expect(s['gamesA'], 3);
      expect(s['complete'], isTrue);
      expect(s['winner'], 'a');
    });

    test('points are attributed to the player', () {
      final s = play([
        const ScoreAction(
          type: 'point',
          side: Side.a,
          payload: {'playerId': 'A1', 'how': 'service_winner'},
        ),
      ]);
      final line =
          tt.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A1');
      expect(line['pointsWon'], 1);
      expect(line['serviceWinners'], 1);
    });
  });
}
