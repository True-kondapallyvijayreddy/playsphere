import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Golden tests for the cricket engine.
///
/// These replay an event log and assert the exact scorecard, which is the only
/// way to prove a cricket engine: the individually-plausible rules interact,
/// and every one of the cases below is a result-changing error that naive
/// implementations ship.
void main() {
  const cricket = CricketPlugin();

  // 11 a side, so 10 wickets ends an innings.
  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  final ctx = ScoringContext(
    entrantAName: 'Warangal',
    entrantBName: 'Nizamabad',
    config: const {
      'oversPerInnings': 2,
      'ballsPerOver': 6,
      'playersPerTeam': 11,
      'battingFirst': 'a',
    },
    lineupA: squad('A'),
    lineupB: squad('B'),
  );

  /// Applies actions in order, asserting each is accepted.
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

  Map<String, dynamic> started() => play(cricket.initialState(ctx), [open()]);

  group('a delivery must name the people involved', () {
    test('scoring before the openers are set is refused', () {
      final r = cricket.apply(cricket.initialState(ctx), runs(4), ctx);
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('before scoring a delivery'));
    });

    test('the same player cannot be at both ends', () {
      final r = cricket.apply(
        cricket.initialState(ctx),
        const ScoreAction(
          type: 'open',
          payload: {'striker': 'A1', 'nonStriker': 'A1', 'bowler': 'B1'},
        ),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });
  });

  group('batting figures', () {
    test('runs, balls, boundaries and strike rate credit the striker', () {
      // A1 keeps strike on even runs: 4, 2, 0, 6 = 12 off 4.
      final s = play(started(), [runs(4), runs(2), runs(0), runs(6)]);
      final card = cricket.card(s, ctx)!;
      final a1 = card.batting.firstWhere((b) => b.playerId == 'A1');

      expect(a1.runs, 12);
      expect(a1.balls, 4);
      expect(a1.fours, 1);
      expect(a1.sixes, 1);
      expect(a1.strikeRate, 300.0);
      expect(card.runs, 12);
    });

    test('an odd run rotates the strike', () {
      final s = play(started(), [runs(1), runs(4)]);
      final card = cricket.card(s, ctx)!;
      // The 4 belongs to A2, who came on strike after the single.
      expect(card.batting.firstWhere((b) => b.playerId == 'A1').runs, 1);
      expect(card.batting.firstWhere((b) => b.playerId == 'A2').runs, 4);
    });

    test('a player who never came in shows as did-not-bat, not a duck', () {
      final s = play(started(), [runs(1)]);
      final card = cricket.card(s, ctx)!;
      final a7 = card.batting.firstWhere((b) => b.playerId == 'A7');
      expect(a7.battedYet, isFalse);
      expect(a7.runs, 0);
      // And the openers are marked as having batted.
      expect(card.batting.firstWhere((b) => b.playerId == 'A1').battedYet, isTrue);
    });
  });

  group('extras and legality', () {
    test('a wide adds a run, is not a legal ball, and is not a ball faced', () {
      final s = play(started(), [const ScoreAction(type: 'wide')]);
      final card = cricket.card(s, ctx)!;

      expect(card.runs, 1);
      expect(card.legalBalls, 0);
      expect(card.extras['wide'], 1);
      // The batter had no chance to play it.
      expect(card.batting.firstWhere((b) => b.playerId == 'A1').balls, 0);
      // But the bowler is charged.
      expect(card.bowling.firstWhere((b) => b.playerId == 'B1').runsConceded, 1);
    });

    test('a no-ball is not a legal ball but IS a ball faced', () {
      final s = play(started(), [
        const ScoreAction(type: 'no_ball', payload: {'runs': 4}),
      ]);
      final card = cricket.card(s, ctx)!;

      expect(card.runs, 5); // 1 penalty + 4 off the bat
      expect(card.legalBalls, 0);
      final a1 = card.batting.firstWhere((b) => b.playerId == 'A1');
      expect(a1.runs, 4); // the penalty is not the batter's
      expect(a1.balls, 1); // they faced it
      expect(a1.fours, 1);
      expect(card.bowling.firstWhere((b) => b.playerId == 'B1').runsConceded, 5);
    });

    test('byes consume a delivery, and are charged to nobody', () {
      final s = play(started(), [
        const ScoreAction(type: 'bye', payload: {'runs': 2}),
      ]);
      final card = cricket.card(s, ctx)!;

      expect(card.runs, 2);
      expect(card.legalBalls, 1);
      expect(card.extras['bye'], 2);
      final a1 = card.batting.firstWhere((b) => b.playerId == 'A1');
      expect(a1.runs, 0); // not the batter's runs
      expect(a1.balls, 1); // but they faced the ball
      // The single most common amateur error: byes must NOT be charged to the
      // bowler.
      expect(card.bowling.firstWhere((b) => b.playerId == 'B1').runsConceded, 0);
    });

    test('an over is six LEGAL balls, wides and no-balls excluded', () {
      final s = play(started(), [
        runs(0),
        const ScoreAction(type: 'wide'),
        runs(0),
        const ScoreAction(type: 'no_ball'),
        runs(0),
        runs(0),
        runs(0),
        runs(0),
      ]);
      final card = cricket.card(s, ctx)!;
      // Six legal deliveries bowled despite eight events.
      expect(card.legalBalls, 6);
      expect(card.bowling.firstWhere((b) => b.playerId == 'B1').oversText, '1.0');
    });
  });

  group('bowling figures', () {
    test('overs read as balls out of six, and decimalise by six', () {
      final s = play(started(), [runs(1), runs(1), runs(0)]);
      final b1 = cricket.card(s, ctx)!.bowling.firstWhere((b) => b.playerId == 'B1');

      expect(b1.legalBalls, 3);
      expect(b1.oversText, '0.3');
      // 0.3 overs is half an over, not three tenths.
      expect(b1.oversDecimal, closeTo(0.5, 0.0001));
    });

    test('a wicketless bowler has no average or strike rate', () {
      final s = play(started(), [runs(4)]);
      final b1 = cricket.card(s, ctx)!.bowling.firstWhere((b) => b.playerId == 'B1');
      expect(b1.average, isNull);
      expect(b1.strikeRate, isNull);
    });

    test('a maiden is an over with nothing conceded', () {
      final s = play(started(), [
        runs(0), runs(0), runs(0), runs(0), runs(0), runs(0),
      ]);
      final b1 = cricket.card(s, ctx)!.bowling.firstWhere((b) => b.playerId == 'B1');
      expect(b1.maidens, 1);
      expect(b1.runsConceded, 0);
    });

    test('an over containing a wide is not a maiden', () {
      final s = play(started(), [
        runs(0), runs(0), const ScoreAction(type: 'wide'),
        runs(0), runs(0), runs(0), runs(0),
      ]);
      final b1 = cricket.card(s, ctx)!.bowling.firstWhere((b) => b.playerId == 'B1');
      expect(b1.maidens, 0);
    });

    test('an over of byes IS a maiden — the bowler conceded nothing', () {
      final s = play(started(), [
        runs(0), runs(0), runs(0), runs(0), runs(0),
        const ScoreAction(type: 'bye', payload: {'runs': 2}),
      ]);
      final b1 = cricket.card(s, ctx)!.bowling.firstWhere((b) => b.playerId == 'B1');
      expect(b1.maidens, 1);
      expect(b1.runsConceded, 0);
    });
  });

  group('wickets', () {
    test('a bowled dismissal credits the bowler and records the fall', () {
      final s = play(started(), [
        runs(4),
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'bowled', 'bowler': 'B1'},
        ),
      ]);
      final card = cricket.card(s, ctx)!;

      expect(card.wickets, 1);
      expect(card.bowling.firstWhere((b) => b.playerId == 'B1').wickets, 1);
      final a1 = card.batting.firstWhere((b) => b.playerId == 'A1');
      expect(a1.isOut, isTrue);
      expect(a1.dismissal, 'b B Player 1');

      expect(card.fallOfWickets.single.wicketNumber, 1);
      expect(card.fallOfWickets.single.runs, 4);
      expect(card.fallOfWickets.single.name, 'A Player 1');
    });

    test('a catch names the fielder and the bowler', () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'caught', 'fielder': 'B5', 'bowler': 'B1'},
        ),
      ]);
      final a1 = cricket.card(s, ctx)!.batting.firstWhere((b) => b.playerId == 'A1');
      expect(a1.dismissal, 'c B Player 5 b B Player 1');
    });

    test('a run-out is NOT credited to the bowler', () {
      final s = play(started(), [
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'run_out', 'fielder': 'B3'},
        ),
      ]);
      final card = cricket.card(s, ctx)!;

      expect(card.wickets, 1);
      expect(card.bowling.firstWhere((b) => b.playerId == 'B1').wickets, 0);
      expect(
        card.batting.firstWhere((b) => b.playerId == 'A1').dismissal,
        'run out (B Player 3)',
      );
    });

    test('the crease is empty until a replacement is named', () {
      final s = play(started(), [
        const ScoreAction(type: 'wicket', payload: {'type': 'bowled', 'bowler': 'B1'}),
      ]);
      // Scoring another delivery with nobody on strike must be refused.
      final blocked = cricket.apply(s, runs(1), ctx);
      expect(blocked.isAccepted, isFalse);

      final resumed = play(s, [
        const ScoreAction(type: 'new_batter', payload: {'playerId': 'A3'}),
        runs(2),
      ]);
      expect(
        cricket.card(resumed, ctx)!.batting.firstWhere((b) => b.playerId == 'A3').runs,
        2,
      );
    });

    test('on a free hit only a run out is allowed', () {
      final s = play(started(), [const ScoreAction(type: 'no_ball')]);

      final bowled = cricket.apply(
        s,
        const ScoreAction(type: 'wicket', payload: {'type': 'bowled', 'bowler': 'B1'}),
        ctx,
      );
      expect(bowled.isAccepted, isFalse);
      expect(bowled.rejection, contains('Free hit'));

      final runOut = cricket.apply(
        s,
        const ScoreAction(type: 'wicket', payload: {'type': 'run_out'}),
        ctx,
      );
      expect(runOut.isAccepted, isTrue);
    });
  });

  group('match settlement', () {
    test('the innings closes at the over limit and starts the chase', () {
      // 2 overs configured = 12 legal balls.
      final s = play(started(), [for (var n = 0; n < 12; n++) runs(1)]);

      expect(s['inningsIndex'], 1);
      expect(s['target'], 13); // 12 scored, need one more
      final second = cricket.card(s, ctx)!;
      expect(second.battingSide, Side.b);
    });

    test('a chase ends the instant the target is passed', () {
      var s = play(started(), [for (var n = 0; n < 12; n++) runs(1)]);
      s = play(s, [
        const ScoreAction(
          type: 'open',
          payload: {'striker': 'B1', 'nonStriker': 'B2', 'bowler': 'A1'},
        ),
        for (var n = 0; n < 3; n++) runs(6),
      ]);
      // 18 chasing 13 — done, without bowling out the over.
      expect(s['complete'], isTrue);
      expect(s['winner'], 'b');
      expect(cricket.outcome(s, ctx).isComplete, isTrue);
    });

    test('levelling the target is a tie, not a win', () {
      var s = play(started(), [for (var n = 0; n < 12; n++) runs(1)]);
      // Target 13; chasing side makes exactly 12.
      s = play(s, [
        const ScoreAction(
          type: 'open',
          payload: {'striker': 'B1', 'nonStriker': 'B2', 'bowler': 'A1'},
        ),
        for (var n = 0; n < 12; n++) runs(1),
      ]);
      expect(s['complete'], isTrue);
      expect(s['tie'], isTrue);
      expect(s['winner'], isNull);
      expect(cricket.outcome(s, ctx).isDraw, isTrue);
    });
  });

  group('replay reproduces the card exactly', () {
    test('a scripted innings replays to an identical scorecard', () {
      final script = <ScoreAction>[
        open(),
        runs(1),
        const ScoreAction(type: 'wide'),
        runs(4),
        const ScoreAction(type: 'no_ball', payload: {'runs': 2}),
        const ScoreAction(type: 'bye', payload: {'runs': 1}),
        runs(0),
        const ScoreAction(
          type: 'wicket',
          payload: {'type': 'caught', 'fielder': 'B4', 'bowler': 'B1'},
        ),
        const ScoreAction(type: 'new_batter', payload: {'playerId': 'A3'}),
        runs(6),
      ];

      final direct = play(cricket.initialState(ctx), script);
      final replayed = cricket.replay(script, ctx);

      final a = cricket.card(direct, ctx)!;
      final b = cricket.card(replayed, ctx)!;

      // The event log IS the match: replaying it must reproduce the card, or
      // no dispute can ever be settled from the log.
      expect(b.runs, a.runs);
      expect(b.wickets, a.wickets);
      expect(b.legalBalls, a.legalBalls);
      expect(b.extrasTotal, a.extrasTotal);
      for (final line in a.batting.where((l) => l.battedYet)) {
        final other = b.batting.firstWhere((l) => l.playerId == line.playerId);
        expect(other.runs, line.runs, reason: 'runs for ${line.playerId}');
        expect(other.balls, line.balls, reason: 'balls for ${line.playerId}');
        expect(other.isOut, line.isOut);
      }
    });
  });
}
