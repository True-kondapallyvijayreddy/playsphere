import '../scoring_plugin.dart';

/// Straight point-for-point scoring with an optional target.
///
/// Covers table tennis single games, carrom, chess (as a 1/0/½ decision),
/// tug of war, and every "we just need to count points" case a school sports
/// day throws up. It is intentionally the simplest possible plugin and is the
/// default when a sport has no dedicated implementation, so an organizer can
/// always run *something* rather than being blocked by a missing rule set.
class SimplePointsPlugin extends ScoringPlugin {
  const SimplePointsPlugin();

  static const pluginKey = 'simple_points';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Simple points';

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        'complete': false,
        'winner': null,
        'draw': false,
      };

  @override
  ScoringResult apply(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (state['complete'] == true && action.type != 'reopen') {
      return const ScoringResult.rejected(
        'This match is already finished. Reopen it to make a correction.',
      );
    }

    final target = ctx.intConfig('target', 0);
    final winBy = ctx.intConfig('winBy', 1);
    final allowDraw = ctx.boolConfig('allowDraw', true);

    switch (action.type) {
      case 'point':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Point needs a side.');
        }
        final amount = (action.payload['amount'] as num?)?.toInt() ?? 1;
        final key = action.side.wire;
        final next = mutate(state, (s) {
          s[key] = ((s[key] as num?)?.toInt() ?? 0) + amount;
        });
        return ScoringResult.ok(_maybeFinish(next, target, winBy));

      case 'correct':
        // Decrementing is a correction, not a score. Never allow it to drive
        // a total below zero, which is the most common fat-finger outcome.
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correction needs a side.');
        }
        final key = action.side.wire;
        final current = (state[key] as num?)?.toInt() ?? 0;
        if (current == 0) {
          return const ScoringResult.rejected('Score is already zero.');
        }
        return ScoringResult.ok(mutate(state, (s) => s[key] = current - 1));

      case 'declare_draw':
        if (!allowDraw) {
          return const ScoringResult.rejected(
            'This competition does not allow draws.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = true;
          s['winner'] = null;
        }));

      case 'finish':
        final a = (state['a'] as num?)?.toInt() ?? 0;
        final b = (state['b'] as num?)?.toInt() ?? 0;
        if (a == b && !allowDraw) {
          return const ScoringResult.rejected(
            'Scores are level and draws are not allowed here.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = a == b;
          s['winner'] = a == b ? null : (a > b ? 'a' : 'b');
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
          s['draw'] = false;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  Map<String, dynamic> _maybeFinish(
    Map<String, dynamic> state,
    int target,
    int winBy,
  ) {
    if (target <= 0) return state;
    final a = (state['a'] as num?)?.toInt() ?? 0;
    final b = (state['b'] as num?)?.toInt() ?? 0;
    final leader = a >= b ? 'a' : 'b';
    final high = a > b ? a : b;
    final margin = (a - b).abs();
    if (high >= target && margin >= winBy) {
      return mutate(state, (s) {
        s['complete'] = true;
        s['winner'] = leader;
        s['draw'] = false;
      });
    }
    return state;
  }

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) =>
      '${state['a'] ?? 0} - ${state['b'] ?? 0}';

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) =>
      headline(state, ctx);

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    final target = ctx.intConfig('target', 0);
    if (state['complete'] == true) {
      return state['draw'] == true ? 'Drawn' : 'Final';
    }
    return target > 0 ? 'First to $target' : null;
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = (state['a'] as num?)?.toInt() ?? 0;
    final b = (state['b'] as num?)?.toInt() ?? 0;
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
      isDraw: state['draw'] == true,
      winnerSide: state['winner'] == null ? null : Side.fromWire(state['winner'] as String),
      scoreForA: a,
      scoreForB: b,
    );
  }

  @override
  List<ScoreControlGroup> controls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    if (state['complete'] == true) {
      return const [
        ScoreControlGroup(title: 'Match finished', controls: [
          ScoreControl(
            action: 'reopen',
            label: 'Reopen to correct',
            style: ControlStyle.subtle,
            shortcut: 'r',
          ),
        ]),
      ];
    }

    final allowDraw = ctx.boolConfig('allowDraw', true);
    return [
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: const [
          ScoreControl(
            action: 'point',
            label: '+1',
            side: Side.a,
            style: ControlStyle.primary,
            shortcut: 'a',
          ),
          ScoreControl(
            action: 'correct',
            label: '−1',
            side: Side.a,
            style: ControlStyle.subtle,
            shortcut: 'z',
          ),
        ],
      ),
      ScoreControlGroup(
        title: ctx.entrantBName,
        controls: const [
          ScoreControl(
            action: 'point',
            label: '+1',
            side: Side.b,
            style: ControlStyle.primary,
            shortcut: 'l',
          ),
          ScoreControl(
            action: 'correct',
            label: '−1',
            side: Side.b,
            style: ControlStyle.subtle,
            shortcut: 'm',
          ),
        ],
      ),
      ScoreControlGroup(
        title: 'Finish',
        controls: [
          const ScoreControl(
            action: 'finish',
            label: 'End match',
            style: ControlStyle.danger,
            shortcut: 'f',
          ),
          if (allowDraw)
            const ScoreControl(
              action: 'declare_draw',
              label: 'Draw',
              style: ControlStyle.secondary,
              shortcut: 'd',
            ),
        ],
      ),
    ];
  }
}
