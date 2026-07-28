import '../scoring_plugin.dart';

/// Set/game based scoring for badminton, volleyball, tennis and table tennis.
///
/// The rules that actually matter and that naive implementations get wrong:
///
///  * **Win by two.** At 20-20 badminton does not end at 21; play continues
///    until someone leads by two.
///  * **The hard cap.** Badminton stops the win-by-two rule at 30 — the first
///    to 30 takes the game even at 30-29. Without the cap a rally can never
///    end, and a scorer is left unable to finish the match.
///  * **The deciding set is different.** Volleyball plays the fifth set to 15,
///    not 25. Scoring it to 25 produces a wrong result in exactly the match
///    that matters most.
///
/// All three are configuration, not hard-coded constants, so one plugin
/// serves every set-based sport a school might run.
class SetBasedPlugin extends ScoringPlugin {
  const SetBasedPlugin();

  static const pluginKey = 'set_based';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Sets and games';

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'currentA': 0,
        'currentB': 0,
        'setsA': 0,
        'setsB': 0,
        'completedSets': <Map<String, dynamic>>[],
        'complete': false,
        'winner': null,
      };

  int _pointsForSet(Map<String, dynamic> state, ScoringContext ctx) {
    final setsToWin = ctx.intConfig('setsToWin', 2);
    final normal = ctx.intConfig('pointsPerSet', 21);
    final deciding = ctx.intConfig('decidingSetPoints', normal);
    final setsA = (state['setsA'] as num?)?.toInt() ?? 0;
    final setsB = (state['setsB'] as num?)?.toInt() ?? 0;
    final isDecider = setsA == setsToWin - 1 && setsB == setsToWin - 1;
    return isDecider ? deciding : normal;
  }

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

    switch (action.type) {
      case 'point':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Point needs a side.');
        }
        final key = action.side == Side.a ? 'currentA' : 'currentB';
        var next = mutate(state, (s) {
          s[key] = ((s[key] as num?)?.toInt() ?? 0) + 1;
        });
        return ScoringResult.ok(_settleSet(next, ctx));

      case 'correct':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correction needs a side.');
        }
        final key = action.side == Side.a ? 'currentA' : 'currentB';
        final current = (state[key] as num?)?.toInt() ?? 0;
        if (current == 0) {
          return const ScoringResult.rejected(
            'Cannot go below zero in the current set.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) => s[key] = current - 1));

      case 'retire':
        // A player retiring hurt or being disqualified mid-match still needs
        // a recorded winner — the other side.
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Retirement needs a side.');
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['winner'] = action.side.opposite.wire;
          s['retired'] = action.side.wire;
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
          s.remove('retired');
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  /// Closes the current set when it has been legitimately won, then closes
  /// the match if someone has taken enough sets.
  Map<String, dynamic> _settleSet(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final target = _pointsForSet(state, ctx);
    final cap = ctx.intConfig('hardCap', 0);
    final winBy = ctx.intConfig('winBy', 2);
    final setsToWin = ctx.intConfig('setsToWin', 2);

    final a = (state['currentA'] as num?)?.toInt() ?? 0;
    final b = (state['currentB'] as num?)?.toInt() ?? 0;
    final high = a > b ? a : b;
    final margin = (a - b).abs();

    final reachedTargetWithMargin = high >= target && margin >= winBy;
    final reachedHardCap = cap > 0 && high >= cap;
    if (!reachedTargetWithMargin && !reachedHardCap) return state;

    final aWonSet = a > b;
    final completed = copyList(state['completedSets'])
      ..add({'a': a, 'b': b});

    final setsA = ((state['setsA'] as num?)?.toInt() ?? 0) + (aWonSet ? 1 : 0);
    final setsB = ((state['setsB'] as num?)?.toInt() ?? 0) + (aWonSet ? 0 : 1);

    final matchOver = setsA >= setsToWin || setsB >= setsToWin;

    return mutate(state, (s) {
      s['completedSets'] = completed;
      s['setsA'] = setsA;
      s['setsB'] = setsB;
      s['currentA'] = 0;
      s['currentB'] = 0;
      if (matchOver) {
        s['complete'] = true;
        s['winner'] = setsA > setsB ? 'a' : 'b';
      }
    });
  }

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return '${state['setsA'] ?? 0} - ${state['setsB'] ?? 0}';
    }
    return '${state['currentA'] ?? 0} - ${state['currentB'] ?? 0}';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final sets = copyList(state['completedSets'])
        .map((s) => '${s['a']}-${s['b']}')
        .toList();
    final inPlay = (state['complete'] != true)
        ? '${state['currentA'] ?? 0}-${state['currentB'] ?? 0}*'
        : null;
    final parts = [...sets, if (inPlay != null) inPlay];
    return parts.isEmpty ? '0-0' : parts.join(', ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      final retired = state['retired'];
      if (retired is String) {
        return '${ctx.nameFor(Side.fromWire(retired))} retired';
      }
      return 'Final · sets ${state['setsA']}-${state['setsB']}';
    }
    final setNumber = copyList(state['completedSets']).length + 1;
    final target = _pointsForSet(state, ctx);
    final a = (state['currentA'] as num?)?.toInt() ?? 0;
    final b = (state['currentB'] as num?)?.toInt() ?? 0;
    final winBy = ctx.intConfig('winBy', 2);
    final atDeuce = a >= target - 1 && b >= target - 1 && (a - b).abs() < winBy;
    return atDeuce
        ? 'Set $setNumber · deuce, win by $winBy'
        : 'Set $setNumber · to $target';
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] != true) return MatchOutcome.inProgress;
    final setsA = (state['setsA'] as num?)?.toInt() ?? 0;
    final setsB = (state['setsB'] as num?)?.toInt() ?? 0;
    return MatchOutcome(
      isComplete: true,
      winnerSide:
          state['winner'] == null ? null : Side.fromWire(state['winner'] as String),
      scoreForA: setsA,
      scoreForB: setsB,
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
      const ScoreControlGroup(
        title: 'Match',
        controls: [
          ScoreControl(
            action: 'retire',
            label: 'A retires',
            side: Side.a,
            style: ControlStyle.danger,
          ),
          ScoreControl(
            action: 'retire',
            label: 'B retires',
            side: Side.b,
            style: ControlStyle.danger,
          ),
        ],
      ),
    ];
  }
}
