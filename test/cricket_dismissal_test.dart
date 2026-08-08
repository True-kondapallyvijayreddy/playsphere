import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Dismissal detail — the half of the cricket engine the pad could not reach.
///
/// The engine has always known how to credit a catch, refuse a bowler the
/// wicket for a run-out, and debit the right batter when the non-striker goes.
/// None of it was reachable: the pad rendered ONE "Wicket" button carrying an
/// empty payload, so every dismissal in every match arrived as the default —
/// `bowled`, striker out, no fielder. The consequences were all silent:
///
///  * every scorecard read "b bowler", because `_dismissalText` fell back to
///    the literal word when no bowler id was supplied;
///  * catches, stumpings and run-outs were permanently zero on every career
///    profile, though §7.1 lists them as first-class fielding statistics;
///  * every run-out was credited to the bowler — the exact error §7.1 names;
///  * a non-striker run-out was impossible to record at all.
///
/// These tests drive the engine through the payloads the pad now actually
/// sends, so the controls and the reducer cannot drift apart again.
void main() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  final ctx = ScoringContext(
    entrantAName: 'Warangal',
    entrantBName: 'Nizamabad',
    config: const {
      'oversPerInnings': 20,
      'ballsPerOver': 6,
      'playersPerTeam': 11,
      'battingFirst': 'a',
    },
    lineupA: squad('A'),
    lineupB: squad('B'),
  );

  Map<String, dynamic> play(
    Map<String, dynamic> state,
    List<ScoreAction> actions,
  ) {
    var s = state;
    for (final a in actions) {
      final r = cricket.apply(s, a, ctx);
      expect(r.isAccepted, isTrue,
          reason: 'rejected "${a.type}": ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  const open = ScoreAction(
    type: 'open',
    payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
  );

  Map<String, dynamic> inningsOf(Map<String, dynamic> s) =>
      (s['innings'] as List).first as Map<String, dynamic>;

  Map<String, num> tallyOf(Map<String, dynamic> s, String id) =>
      PlayerTally.of(s, id);

  // -------------------------------------------------------------------------
  // The controls the pad renders
  // -------------------------------------------------------------------------

  group('the pad can actually describe a dismissal', () {
    test('every dismissal type is offered once a match is under way', () {
      final s = play(cricket.initialState(ctx), [open]);
      final wicketGroup = cricket
          .controls(s, ctx)
          .firstWhere((g) => g.title == 'Wicket');
      final types = {
        for (final c in wicketGroup.controls) c.payload['type'] as String?,
      };

      expect(
        types,
        containsAll(<String>[
          'bowled',
          'caught',
          'lbw',
          'stumped',
          'run_out',
          'hit_wicket',
          'retired',
        ]),
        reason: 'a single generic Wicket button records none of these',
      );
    });

    test('a catch asks who took it, from the fielding side', () {
      final s = play(cricket.initialState(ctx), [open]);
      final caught = cricket
          .controls(s, ctx)
          .firstWhere((g) => g.title == 'Wicket')
          .controls
          .firstWhere((c) => c.payload['type'] == 'caught');

      expect(caught.needsInput, isTrue);
      final prompt = caught.prompts.single;
      expect(prompt.key, 'fielder');
      // The control's side is the BATTING side, so `opposingSide` resolves to
      // the fielders — the same trick the opening and bowler controls use.
      expect(prompt.from, PromptSource.opposingSide);
      expect(caught.side, Side.a);
    });

    test('a run-out asks which batter went', () {
      final s = play(cricket.initialState(ctx), [open]);
      final runOut = cricket
          .controls(s, ctx)
          .firstWhere((g) => g.title == 'Wicket')
          .controls
          .firstWhere((c) => c.payload['type'] == 'run_out');

      expect(runOut.prompts.map((p) => p.key), contains('playerId'));
      expect(
        runOut.prompts.firstWhere((p) => p.key == 'playerId').from,
        PromptSource.actingSide,
      );
    });

    test('the bowler is carried on the control, so the card can name them', () {
      final s = play(cricket.initialState(ctx), [open]);
      final bowled = cricket
          .controls(s, ctx)
          .firstWhere((g) => g.title == 'Wicket')
          .controls
          .firstWhere((c) => c.payload['type'] == 'bowled');

      expect(bowled.payload['bowler'], 'B1');
    });

    test('a free hit still offers a run-out and nothing else', () {
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'no_ball', payload: {'runs': 0}),
      ]);
      expect(s['freeHit'], isTrue);

      final controls = cricket
          .controls(s, ctx)
          .firstWhere((g) => g.title == 'Wicket')
          .controls;
      expect(controls, hasLength(1));
      expect(controls.single.payload['type'], 'run_out');
    });
  });

  // -------------------------------------------------------------------------
  // What the engine then records
  // -------------------------------------------------------------------------

  group('fielding credit', () {
    test('a catch credits the catcher and the bowler', () {
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'caught',
          'bowler': 'B1',
          'fielder': 'B7',
        }),
      ]);

      expect(tallyOf(s, 'B7')['catches'], 1);
      expect(tallyOf(s, 'B1')['wickets'], 1);
      expect(
        (inningsOf(s)['batting'] as Map)['A1']['dismissal'],
        'c B Player 7 b B Player 1',
        reason: 'the scorecard read "b bowler" for every wicket ever recorded',
      );
    });

    test('a stumping credits the keeper', () {
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'stumped',
          'bowler': 'B1',
          'keeper': 'B2',
        }),
      ]);

      expect(tallyOf(s, 'B2')['stumpings'], 1);
      expect(tallyOf(s, 'B1')['wickets'], 1);
    });

    test('a run-out is NOT the bowler\'s wicket', () {
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'run_out',
          'playerId': 'A1',
          'fielder': 'B4',
          'assist': 'B9',
        }),
      ]);

      expect(tallyOf(s, 'B4')['runOuts'], 1);
      expect(tallyOf(s, 'B9')['runOutAssists'], 1);
      expect(tallyOf(s, 'B1')['wickets'], isNull,
          reason: '§7.1: a run-out is never credited to the bowler');
      // The innings still lost a wicket.
      expect(inningsOf(s)['wickets'], 1);
    });

    test('a retirement is nobody\'s wicket', () {
      // The type existed in the dismissal text from the beginning, but the
      // only question `apply` asked was "is this a run-out" — so a retirement
      // quietly inflated the bowler's figures and their average with them.
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'retired',
          'playerId': 'A1',
        }),
      ]);

      expect(tallyOf(s, 'B1')['wickets'], isNull);
      expect(inningsOf(s)['wickets'], 1);
    });
  });

  group('who actually went', () {
    test('a non-striker run-out debits the non-striker', () {
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'run_out',
          'playerId': 'A2',
          'fielder': 'B4',
        }),
      ]);

      final batting = inningsOf(s)['batting'] as Map;
      expect(batting['A2']['out'], isTrue);
      expect(batting['A1']['out'], isFalse,
          reason: 'debiting the striker corrupts their average and every '
              'fall-of-wicket line after it');

      // The striker stays where they are; the OTHER end needs filling.
      expect(inningsOf(s)['striker'], 'A1');
      expect(inningsOf(s)['nonStriker'], isNull);
    });

    test('a striker dismissal leaves the striker\'s end open', () {
      final s = play(cricket.initialState(ctx), [
        open,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'bowled',
          'bowler': 'B1',
        }),
      ]);

      expect(inningsOf(s)['striker'], isNull);
      expect(inningsOf(s)['nonStriker'], 'A2');
    });

    test('a dismissal naming somebody not at the crease is refused', () {
      final s = play(cricket.initialState(ctx), [open]);
      final r = cricket.apply(
        s,
        const ScoreAction(type: 'wicket', payload: {
          'type': 'run_out',
          'playerId': 'A7',
        }),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });
  });
}
