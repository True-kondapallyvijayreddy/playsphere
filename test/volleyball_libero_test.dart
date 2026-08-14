import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/volleyball_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

void main() {
  const plugin = VolleyballPlugin();
  // 7 a side: 6 starters plus a specialist libero on the bench — the
  // realistic squad shape a libero swap needs. A 6-of-6 squad would make the
  // "libero" just another starter, which is not the scenario being tested.
  final lineupA = List.generate(
    7,
    (i) => MatchPlayer(id: 'a$i', name: 'A$i'),
  );
  final lineupB = List.generate(
    7,
    (i) => MatchPlayer(id: 'b$i', name: 'B$i'),
  );
  final ctx = ScoringContext(
    entrantAName: 'A',
    entrantBName: 'B',
    lineupA: lineupA,
    lineupB: lineupB,
    config: const {'squadSize': 6},
  );

  group('Volleyball libero', () {
    test('cannot swap in before a libero is named', () {
      final state = plugin.initialState(ctx);
      final result = plugin.apply(
        state,
        const ScoreAction(
          type: 'libero_swap',
          side: Side.a,
          payload: {'forId': 'a0'},
        ),
        ctx,
      );
      expect(result.isAccepted, isFalse);
    });

    test('swap on replaces the named player on court, swap off restores '
        'them — and it never touches the regular substitution count', () {
      var state = plugin.initialState(ctx);

      state = plugin
          .apply(
            state,
            const ScoreAction(
              type: 'set_libero',
              side: Side.a,
              payload: {'playerId': 'a6'},
            ),
            ctx,
          )
          .state;

      // a6 is the designated libero, starting on the bench — starters are
      // the first 6 (a0..a5). Swap them on for a1.
      final beforeSwap = plugin.apply(
        state,
        const ScoreAction(
          type: 'libero_swap',
          side: Side.a,
          payload: {'forId': 'a1'},
        ),
        ctx,
      );
      expect(beforeSwap.isAccepted, isTrue);
      state = beforeSwap.state;

      final onCourt =
          (state['onCourt'] as Map)['a'] as List;
      expect(onCourt.contains('a6'), isTrue);
      expect(onCourt.contains('a1'), isFalse);

      // The regular substitution counter must be untouched — a libero swap
      // is not a substitution and must never eat into the allowance.
      expect((state['subsUsed'] as Map)['a'], 0);

      // Swap back off.
      final afterSwap = plugin.apply(
        state,
        const ScoreAction(type: 'libero_swap', side: Side.a),
        ctx,
      );
      expect(afterSwap.isAccepted, isTrue);
      state = afterSwap.state;

      final restoredCourt = (state['onCourt'] as Map)['a'] as List;
      expect(restoredCourt.contains('a1'), isTrue);
      expect(restoredCourt.contains('a6'), isFalse);
      expect((state['subsUsed'] as Map)['a'], 0);
    });

    test('the libero cannot replace themselves', () {
      var state = plugin.initialState(ctx);
      state = plugin
          .apply(
            state,
            const ScoreAction(
              type: 'set_libero',
              side: Side.a,
              payload: {'playerId': 'a2'},
            ),
            ctx,
          )
          .state;

      final result = plugin.apply(
        state,
        const ScoreAction(
          type: 'libero_swap',
          side: Side.a,
          payload: {'forId': 'a2'},
        ),
        ctx,
      );
      expect(result.isAccepted, isFalse);
    });

    test('the ordinary substitution control cannot sub out an on-court '
        'libero — that would spend a substitution credit a libero swap must '
        'never touch', () {
      var state = plugin.initialState(ctx);
      state = plugin
          .apply(
            state,
            const ScoreAction(
              type: 'set_libero',
              side: Side.a,
              payload: {'playerId': 'a6'},
            ),
            ctx,
          )
          .state;
      state = plugin
          .apply(
            state,
            const ScoreAction(
              type: 'libero_swap',
              side: Side.a,
              payload: {'forId': 'a1'},
            ),
            ctx,
          )
          .state;

      // a6 (the libero) is on for a1. Try to sub a6 off through the
      // ORDINARY control rather than libero_swap.
      final result = plugin.apply(
        state,
        const ScoreAction(
          type: 'substitution',
          side: Side.a,
          payload: {'playerOffId': 'a6', 'playerOnId': 'a1'},
        ),
        ctx,
      );
      expect(result.isAccepted, isFalse);
      // Untouched — the rejected attempt must not have spent anything.
      expect((state['subsUsed'] as Map)['a'], 0);
    });

    test('the ordinary substitution control cannot bring on the player a '
        'libero is currently standing in for — that would put them on court '
        'twice once the libero swaps back off', () {
      var state = plugin.initialState(ctx);
      state = plugin
          .apply(
            state,
            const ScoreAction(
              type: 'set_libero',
              side: Side.a,
              payload: {'playerId': 'a6'},
            ),
            ctx,
          )
          .state;
      state = plugin
          .apply(
            state,
            const ScoreAction(
              type: 'libero_swap',
              side: Side.a,
              payload: {'forId': 'a1'},
            ),
            ctx,
          )
          .state;

      // a1 is off court only because a6 (the libero) is standing in for
      // them. Bringing a1 on for some unrelated on-court player (a2) through
      // the ordinary control must be refused.
      final result = plugin.apply(
        state,
        const ScoreAction(
          type: 'substitution',
          side: Side.a,
          payload: {'playerOffId': 'a2', 'playerOnId': 'a1'},
        ),
        ctx,
      );
      expect(result.isAccepted, isFalse);

      // And the libero swap-off still works cleanly afterwards — the
      // rejected attempt must not have left the state any different.
      final swapOff = plugin.apply(
        state,
        const ScoreAction(type: 'libero_swap', side: Side.a),
        ctx,
      );
      expect(swapOff.isAccepted, isTrue);
      final restoredCourt = (swapOff.state['onCourt'] as Map)['a'] as List;
      expect(restoredCourt.contains('a1'), isTrue);
      expect(restoredCourt.contains('a6'), isFalse);
      // a1 appears exactly once — not doubled up.
      expect(restoredCourt.where((id) => id == 'a1').length, 1);
    });

    test('a libero swap replays identically through rebuild', () {
      final actions = [
        const ScoreAction(
          type: 'set_libero',
          side: Side.a,
          payload: {'playerId': 'a6'},
        ),
        const ScoreAction(
          type: 'libero_swap',
          side: Side.a,
          payload: {'forId': 'a1'},
        ),
        point(Side.a, how: 'ace', playerId: 'a6'),
      ];
      var state = plugin.initialState(ctx);
      for (final a in actions) {
        final r = plugin.apply(state, a, ctx);
        expect(r.isAccepted, isTrue, reason: r.rejection);
        state = r.state;
      }

      final replayed = plugin.replay(actions, ctx);
      expect(replayed['currentA'], state['currentA']);
      expect((replayed['onCourt'] as Map)['a'], (state['onCourt'] as Map)['a']);
    });
  });
}

ScoreAction point(Side side, {required String how, required String playerId}) =>
    ScoreAction(
      type: 'point',
      side: side,
      payload: {'how': how, 'playerId': playerId},
    );
