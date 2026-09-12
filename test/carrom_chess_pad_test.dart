import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/scoring/plugins/carrom_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/chess_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Two pads that had a full set of buttons and could not score a match.
///
/// Both failures were the same shape and neither was visible from the code
/// that broke: an engine read a payload key, and no control ever declared a
/// prompt that would put one there. Nothing threw, nothing was rejected, and
/// the pad looked exactly like a working one — which is why these are pinned
/// here rather than left to `scoring_prompts_test.dart`. That test proves a
/// button is not REFUSED; it cannot prove the button did anything.
void main() {
  ScoringContext ctxWith(Map<String, dynamic> config) => ScoringContext(
        entrantAName: 'Anil',
        entrantBName: 'Bhaskar',
        config: config,
        lineupA: const [MatchPlayer(id: 'a1', name: 'Anil', uid: 'a1')],
        lineupB: const [MatchPlayer(id: 'b1', name: 'Bhaskar', uid: 'b1')],
      );

  group('carrom scores the board it was told about', () {
    // The ICF preset, which is what a club gets by default.
    final ctx = ctxWith(const {
      'matchTarget': 29,
      'maxBoards': 8,
      'queenPoints': 3,
      'queenMustBeCovered': true,
      'coinPoints': 1,
      'coinsPerSide': 9,
      'maxBoardPoints': 25,
      'queenCountsOnlyBelowPoints': 22,
      'foulPenalty': 1,
    });
    const plugin = CarromPlugin();

    test('the board control asks for the coin count and the queen', () {
      final controls = plugin.controls(plugin.initialState(ctx), ctx);
      final board = controls
          .expand((g) => g.controls)
          .firstWhere((c) => c.action == 'board');

      // The regression itself. Without these two declarations the pad sends
      // "side A won" and nothing else, the engine defaults the coin count to
      // zero, and the board is worth zero points.
      expect(
        board.values.map((v) => v.key),
        contains('opponentCoinsLeft'),
        reason: 'a carrom board is worth the loser\'s remaining coins, so the '
            'pad has to collect them',
      );
      expect(board.choices.map((c) => c.key), contains('queen'));
      expect(board.needsInput, isTrue);
    });

    test('a board with five coins left and the queen covered is worth 8', () {
      final after = plugin.apply(
        plugin.initialState(ctx),
        const ScoreAction(
          type: 'board',
          side: Side.a,
          payload: {
            'playerId': 'a1',
            'opponentCoinsLeft': 5,
            'queen': 'covered',
          },
        ),
        ctx,
      );

      expect(after.rejection, isNull);
      final state = after.state;
      expect(state['a'], 8); // 5 coins + 3 for the queen
      expect(state['b'], 0);
      expect(state['complete'], isNot(true));
      expect(plugin.headline(state, ctx), '8 - 0');
    });

    test('the queen counts nothing when it was not covered', () {
      final after = plugin.apply(
        plugin.initialState(ctx),
        const ScoreAction(
          type: 'board',
          side: Side.a,
          payload: {
            'playerId': 'a1',
            'opponentCoinsLeft': 5,
            'queen': 'uncovered',
          },
        ),
        ctx,
      );
      expect(after.state['a'], 5);
    });

    test('the winner is credited with the board, the points and the coins', () {
      final state = plugin
          .apply(
            plugin.initialState(ctx),
            const ScoreAction(
              type: 'board',
              side: Side.a,
              payload: {
                'playerId': 'a1',
                'opponentCoinsLeft': 4,
                'queen': 'covered',
              },
            ),
            ctx,
          )
          .state;

      final tally = (state[PlayerTally.stateKey] as Map)['a1'] as Map;
      expect(tally['boardsWon'], 1);
      expect(tally['pointsScored'], 7);
      expect(tally['coinsPocketed'], 5); // 9 on the side, 4 left
      expect(tally['queensCovered'], 1);
    });

    test('a best-of-three club match reaches a real result, not 0-0', () {
      // The bug as a scorer met it: three boards played, every one of them
      // recorded, and a finished match with no winner and no score.
      final club = ctxWith(const {
        'matchTarget': 0,
        'maxBoards': 3,
        'queenPoints': 3,
        'queenMustBeCovered': true,
        'coinPoints': 1,
        'coinsPerSide': 9,
        'maxBoardPoints': 25,
        'queenCountsOnlyBelowPoints': 22,
        'foulPenalty': 1,
      });

      var state = plugin.initialState(club);
      for (final (side, coins) in const [
        (Side.a, 6),
        (Side.b, 2),
        (Side.a, 3),
      ]) {
        final result = plugin.apply(
          state,
          ScoreAction(
            type: 'board',
            side: side,
            payload: {
              'playerId': side == Side.a ? 'a1' : 'b1',
              'opponentCoinsLeft': coins,
              'queen': 'none',
            },
          ),
          club,
        );
        expect(result.rejection, isNull);
        state = result.state;
      }

      expect(state['a'], 9);
      expect(state['b'], 2);
      expect(state['complete'], isTrue);
      expect(state['draw'], isFalse);
      expect(state['winner'], 'a');
      expect(plugin.outcome(state, club).winnerSide, Side.a);
    });

    test('the old boolean payload still reads the same way', () {
      // Boards recorded before the prompt existed carry `queen: true` plus
      // `queenCovered: true`, and must not change value now.
      final after = plugin.apply(
        plugin.initialState(ctx),
        const ScoreAction(
          type: 'board',
          side: Side.b,
          payload: {
            'opponentCoinsLeft': 2,
            'queen': true,
            'queenCovered': true,
          },
        ),
        ctx,
      );
      expect(after.state['b'], 5);
    });
  });

  group('chess records who played and what they played', () {
    // The classical preset, which turns move recording on.
    final ctx = ctxWith(const {
      'timeControl': 'classical',
      'winPoints': 1.0,
      'drawPoints': 0.5,
      'lossPoints': 0.0,
      'recordMoves': true,
      'boards': 1,
    });
    const plugin = ChessPlugin();

    ScoreControl controlFor(String action, Map<String, dynamic> state) => plugin
        .controls(state, ctx)
        .expand((g) => g.controls)
        .firstWhere((c) => c.action == action);

    test('a move can actually be entered, not only taken back', () {
      // The whole Moves group used to be one Take back button over a list
      // nothing could add to.
      final move = controlFor('move', plugin.initialState(ctx));
      expect(move.texts.map((t) => t.key), contains('san'));
      expect(move.needsInput, isTrue);
    });

    test('moves accumulate and take back removes the last one', () {
      var state = plugin.initialState(ctx);
      for (final san in const ['e4', 'e5', 'Nf3']) {
        final result = plugin.apply(
          state,
          ScoreAction(type: 'move', payload: {'san': san}),
          ctx,
        );
        expect(result.rejection, isNull);
        state = result.state;
      }
      expect(plugin.movesOf(state), ['e4', 'e5', 'Nf3']);

      state = plugin
          .apply(state, const ScoreAction(type: 'takeback'), ctx)
          .state;
      expect(plugin.movesOf(state), ['e4', 'e5']);
      expect(ChessPlugin.pgnOf(plugin.movesOf(state)), '1. e4 e5');
    });

    test('a board result names White and Black', () {
      final win = controlFor('result', plugin.initialState(ctx));
      final keys = win.prompts.map((p) => p.key).toSet();
      expect(keys, containsAll(['whitePlayerId', 'blackPlayerId']));

      // Required, which is what makes the pad enforce that they are two
      // different people — see the comment on the prompts themselves.
      expect(win.prompts.every((p) => !p.optional), isTrue);

      // Drawn from either side: a board result is not evidence of colour.
      expect(
        win.prompts.every((p) => p.from == PromptSource.eitherSide),
        isTrue,
      );
    });

    test('a win credits the players it named, on both sides of the board', () {
      final state = plugin
          .apply(
            plugin.initialState(ctx),
            const ScoreAction(
              type: 'result',
              side: Side.a,
              payload: {
                'result': 'a',
                'whitePlayerId': 'a1',
                'blackPlayerId': 'b1',
                'reason': 'checkmate',
              },
            ),
            ctx,
          )
          .state;

      final tallies = state[PlayerTally.stateKey] as Map;
      final white = tallies['a1'] as Map;
      final black = tallies['b1'] as Map;

      expect(white['wins'], 1);
      expect(white['points'], 1.0);
      expect(white['whiteGames'], 1);
      expect(black['losses'], 1);
      expect(black['blackGames'], 1);
      expect(black['points'], 0.0);

      // And the board itself keeps how it ended, which was previously always
      // 'unknown' because nothing ever asked.
      final board = (state['results'] as List).single as Map;
      expect(board['reason'], 'checkmate');
      expect(state['complete'], isTrue);
      expect(state['winner'], 'a');
    });

    test('a draw is half a point each', () {
      final state = plugin
          .apply(
            plugin.initialState(ctx),
            const ScoreAction(
              type: 'result',
              payload: {
                'result': 'draw',
                'whitePlayerId': 'a1',
                'blackPlayerId': 'b1',
                'reason': 'stalemate',
              },
            ),
            ctx,
          )
          .state;

      expect(state['a'], 0.5);
      expect(state['b'], 0.5);
      expect(state['draw'], isTrue);
      expect(plugin.headline(state, ctx), '0.5 - 0.5');

      final tallies = state[PlayerTally.stateKey] as Map;
      expect((tallies['a1'] as Map)['draws'], 1);
      expect((tallies['b1'] as Map)['points'], 0.5);
    });

    test('blitz offers no move controls at all', () {
      // Nothing to add and nothing to take back, rather than half a group.
      final blitz = ctxWith(const {
        'timeControl': 'blitz',
        'recordMoves': false,
        'boards': 1,
      });
      final actions = plugin
          .controls(plugin.initialState(blitz), blitz)
          .expand((g) => g.controls)
          .map((c) => c.action)
          .toSet();
      expect(actions, isNot(contains('move')));
      expect(actions, isNot(contains('takeback')));
    });
  });
}
