import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/football_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Football at player level. The cases below are the ones that decide whether
/// a season's statistics are usable or quietly wrong.
void main() {
  const football = FootballPlugin();

  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  final ctx = ScoringContext(
    entrantAName: 'Warangal FC',
    entrantBName: 'Nizamabad FC',
    config: const {'periods': 2, 'allowDraw': true},
    lineupA: squad('A'),
    lineupB: squad('B'),
  );

  Map<String, dynamic> play(List<ScoreAction> actions, {ScoringContext? c}) {
    var s = football.initialState(c ?? ctx);
    for (final a in actions) {
      final r = football.apply(s, a, c ?? ctx);
      expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  group('goals and assists', () {
    test('a goal credits the scorer and the assister separately', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'assistId': 'A10'},
        ),
      ]);
      final box = football.boxScore(s, ctx, Side.a);

      expect(box.players.firstWhere((p) => p.playerId == 'A9')['goals'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A10')['assists'], 1);
      // A goal is also a shot on target.
      expect(box.players.firstWhere((p) => p.playerId == 'A9')['shotsOnTarget'], 1);
      expect(s['a'], 1);
    });

    test('a goal must name a scorer', () {
      final r = football.apply(
        football.initialState(ctx),
        const ScoreAction(type: 'goal', side: Side.a),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('Who scored'));
    });

    test('a player cannot assist their own goal', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'assistId': 'A9'},
        ),
      ]);
      final line = football
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A9');
      expect(line['goals'], 1);
      expect(line['assists'], 0);
    });
  });

  group('own goals', () {
    test('count for the opposition but against the player, never as a goal', () {
      // B4 puts it into their own net; the goal counts for side A.
      final s = play([
        const ScoreAction(
          type: 'own_goal',
          side: Side.a,
          payload: {'playerId': 'B4'},
        ),
      ]);

      expect(s['a'], 1);
      expect(s['b'], 0);

      final b4 = football
          .boxScore(s, ctx, Side.b)
          .players
          .firstWhere((p) => p.playerId == 'B4');
      expect(b4['ownGoals'], 1);
      // The error that turns a defender into a league top-scorer.
      expect(b4['goals'], 0);
    });
  });

  group('cards', () {
    test('a second yellow is automatically a red', () {
      final s = play([
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A5', 'colour': 'yellow'},
        ),
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A5', 'colour': 'yellow'},
        ),
      ]);
      final a5 = football
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A5');

      expect(a5['yellows'], 2);
      expect(a5['reds'], 1, reason: 'two yellows must produce a red');
    });

    test('a sent-off player can take no further part', () {
      final s = play([
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A5', 'colour': 'red'},
        ),
      ]);
      final later = football.apply(
        s,
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A5'},
        ),
        ctx,
      );
      expect(later.isAccepted, isFalse);
      expect(later.rejection, contains('sent off'));
    });

    test('a second yellow also removes the player from the match', () {
      final s = play([
        for (var n = 0; n < 2; n++)
          const ScoreAction(
            type: 'card',
            side: Side.a,
            payload: {'playerId': 'A5', 'colour': 'yellow'},
          ),
      ]);
      final later = football.apply(
        s,
        const ScoreAction(type: 'shot', side: Side.a, payload: {'playerId': 'A5'}),
        ctx,
      );
      expect(later.isAccepted, isFalse);
    });
  });

  group('derived statistics', () {
    test('shot accuracy is computed, never accumulated', () {
      final s = play([
        const ScoreAction(
          type: 'shot',
          side: Side.a,
          payload: {'playerId': 'A7', 'onTarget': true},
        ),
        const ScoreAction(
          type: 'shot',
          side: Side.a,
          payload: {'playerId': 'A7', 'onTarget': false},
        ),
        const ScoreAction(
          type: 'shot',
          side: Side.a,
          payload: {'playerId': 'A7', 'onTarget': false},
        ),
        const ScoreAction(
          type: 'shot',
          side: Side.a,
          payload: {'playerId': 'A7', 'onTarget': true},
        ),
      ]);
      final line = football
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A7');
      final column =
          FootballPlugin.columns.firstWhere((c) => c.key == 'accuracy');

      expect(line['shots'], 4);
      expect(line['shotsOnTarget'], 2);
      expect(column.valueFrom(line.tally), 0.5);
      expect(column.format(line.tally), '50%');
    });

    test('a player who took no shots has 0% rather than a crash', () {
      final s = play([]);
      final line = football
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A3');
      final column =
          FootballPlugin.columns.firstWhere((c) => c.key == 'accuracy');
      expect(column.valueFrom(line.tally), 0);
    });
  });

  group('team totals', () {
    test('sum from the players, so the sheet always adds up', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'assistId': 'A10'},
        ),
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A11'},
        ),
      ]);
      final box = football.boxScore(s, ctx, Side.a);
      expect(box.teamTotals['goals'], 2);
      expect(box.teamTotals['assists'], 1);
      // And the team total agrees with the scoreboard.
      expect(box.teamTotals['goals'], s['a']);
    });

    test('a squad member who never touched the ball did not play', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9'},
        ),
      ]);
      final box = football.boxScore(s, ctx, Side.a);
      expect(box.players.firstWhere((p) => p.playerId == 'A9').appeared, isTrue);
      expect(box.players.firstWhere((p) => p.playerId == 'A2').appeared, isFalse);
      expect(box.appeared.length, 1);
    });
  });

  group('clean sheets and settlement', () {
    test('a clean sheet is only true once the match is over', () {
      var s = play([
        const ScoreAction(type: 'goal', side: Side.a, payload: {'playerId': 'A9'}),
      ]);
      expect(football.cleanSheet(s, Side.a), isFalse, reason: 'not finished yet');

      s = play([
        const ScoreAction(type: 'goal', side: Side.a, payload: {'playerId': 'A9'}),
        const ScoreAction(type: 'finish'),
      ]);
      expect(football.cleanSheet(s, Side.a), isTrue);
      expect(football.cleanSheet(s, Side.b), isFalse);
    });

    test('a level score cannot be finished when draws are disallowed', () {
      final noDraws = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: const {'periods': 2, 'allowDraw': false},
        lineupA: squad('A'),
        lineupB: squad('B'),
      );
      final s = football.initialState(noDraws);
      final r = football.apply(s, const ScoreAction(type: 'finish'), noDraws);
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('does not allow draws'));
    });

    test('penalties are tracked separately from open play', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'penalty': true},
        ),
        const ScoreAction(
          type: 'penalty_missed',
          side: Side.a,
          payload: {'playerId': 'A10'},
        ),
      ]);
      final box = football.boxScore(s, ctx, Side.a);
      expect(
        box.players.firstWhere((p) => p.playerId == 'A9')['penaltiesScored'],
        1,
      );
      expect(
        box.players.firstWhere((p) => p.playerId == 'A10')['penaltiesMissed'],
        1,
      );
    });
  });

  group('replay', () {
    test('a scripted match replays to the same box score', () {
      final script = <ScoreAction>[
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'assistId': 'A10'},
        ),
        const ScoreAction(
          type: 'card',
          side: Side.b,
          payload: {'playerId': 'B4', 'colour': 'yellow'},
        ),
        const ScoreAction(
          type: 'own_goal',
          side: Side.a,
          payload: {'playerId': 'B3'},
        ),
        const ScoreAction(type: 'save', side: Side.b, payload: {'playerId': 'B1'}),
        const ScoreAction(type: 'finish'),
      ];

      final direct = play(script);
      final replayed = football.replay(script, ctx);

      expect(replayed['a'], direct['a']);
      expect(replayed['complete'], direct['complete']);
      expect(
        football.boxScore(replayed, ctx, Side.a).teamTotals['goals'],
        football.boxScore(direct, ctx, Side.a).teamTotals['goals'],
      );
    });
  });
}
