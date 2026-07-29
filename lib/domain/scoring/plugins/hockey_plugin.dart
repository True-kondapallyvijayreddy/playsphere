import '../player_stats.dart';
import '../scoring_plugin.dart';

/// Field hockey.
///
/// Structurally close to football, with one thing that is entirely its own:
/// **how a goal was scored matters as much as who scored it**. A field goal, a
/// penalty corner and a penalty stroke are different achievements, and penalty
/// corner conversion is the statistic hockey coaches actually plan around —
/// a side can dominate possession and lose because it converted one corner
/// from nine.
///
/// Cards are three-tier rather than two: green (a warning, two minutes),
/// yellow (temporary suspension) and red. Collapsing green into yellow, as a
/// football-shaped engine would, loses the distinction between a caution and
/// a suspension.
class HockeyPlugin extends ScoringPlugin {
  const HockeyPlugin();

  static const pluginKey = 'hockey';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Hockey';

  static const _goals = 'goals';
  static const _fieldGoals = 'fieldGoals';
  static const _pcGoals = 'pcGoals';
  static const _psGoals = 'psGoals';
  static const _assists = 'assists';
  static const _saves = 'saves';
  static const _greens = 'greenCards';
  static const _yellows = 'yellowCards';
  static const _reds = 'redCards';

  int _periods(ScoringContext ctx) => ctx.intConfig('periods', 4);
  bool _allowDraw(ScoringContext ctx) => ctx.boolConfig('allowDraw', true);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        'period': 1,
        'complete': false,
        'winner': null,
        'draw': false,
        // Penalty corners awarded, per side — the denominator of conversion.
        'pcAwardedA': 0,
        'pcAwardedB': 0,
        'suspended': <String>[],
        PlayerTally.stateKey: <String, dynamic>{},
      };

  List<String> _suspended(Map<String, dynamic> state) =>
      (state['suspended'] as List?)?.whereType<String>().toList() ?? const [];

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

    final player = action.payload['playerId'] as String?;
    if (player != null && _suspended(state).contains(player)) {
      return ScoringResult.rejected(
        '${ctx.playerName(player)} has been sent off and cannot take part.',
      );
    }

    int v(String k) => ((state[k] as num?) ?? 0).toInt();

    switch (action.type) {
      case 'goal':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('A goal needs a side.');
        }
        if (player == null) {
          return const ScoringResult.rejected('Who scored?');
        }
        // How it was scored is the point of hockey statistics.
        final how = action.payload['how'] as String? ?? 'field';
        final assist = action.payload['assistId'] as String?;

        var next = mutate(state, (s) {
          s[action.side.wire] = v(action.side.wire) + 1;
        });
        next = PlayerTally.addAll(next, player, {
          _goals: 1,
          if (how == 'field') _fieldGoals: 1,
          if (how == 'penalty_corner') _pcGoals: 1,
          if (how == 'penalty_stroke') _psGoals: 1,
        });
        // An assist is a field-goal notion; a stroke has none.
        if (assist != null && assist != player && how != 'penalty_stroke') {
          next = PlayerTally.add(next, assist, _assists, 1);
        }
        return ScoringResult.ok(next);

      case 'penalty_corner':
        // Awarded, not necessarily converted. Recording the award is what
        // makes conversion rate computable at all.
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Which side won the corner?');
        }
        final key = action.side == Side.a ? 'pcAwardedA' : 'pcAwardedB';
        return ScoringResult.ok(mutate(state, (s) => s[key] = v(key) + 1));

      case 'save':
        if (player == null) {
          return const ScoringResult.rejected('Which goalkeeper?');
        }
        return ScoringResult.ok(PlayerTally.add(state, player, _saves, 1));

      case 'card':
        if (player == null) {
          return const ScoringResult.rejected('Who was carded?');
        }
        final colour = action.payload['colour'] as String? ?? 'green';
        var next = PlayerTally.add(
          state,
          player,
          switch (colour) {
            'red' => _reds,
            'yellow' => _yellows,
            _ => _greens,
          },
          1,
        );
        // Only a red removes a player permanently. A yellow is a temporary
        // suspension the scorer manages on the clock, and a green is a
        // warning — treating either as a sending-off would be wrong.
        if (colour == 'red') {
          next = {...next, 'suspended': [..._suspended(next), player]};
        }
        return ScoringResult.ok(next);

      case 'next_period':
        final period = v('period');
        if (period >= _periods(ctx)) {
          return ScoringResult.rejected(
            'This match has only ${_periods(ctx)} quarters. '
            'Use "End match" to finish.',
          );
        }
        return ScoringResult.ok(
          mutate(state, (s) => s['period'] = period + 1),
        );

      case 'finish':
        final a = v('a');
        final b = v('b');
        if (a == b && !_allowDraw(ctx)) {
          return const ScoringResult.rejected(
            'Scores are level and this competition does not allow draws — '
            'play a shootout, then record the result.',
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

  /// Penalty corner conversion for a side — goals from corners over corners
  /// awarded. The statistic hockey is actually coached around.
  double pcConversion(Map<String, dynamic> state, ScoringContext ctx, Side side) {
    final awarded =
        ((state[side == Side.a ? 'pcAwardedA' : 'pcAwardedB'] as num?) ?? 0)
            .toInt();
    if (awarded == 0) return 0;
    final scored = PlayerTally.boxScore(
      state: state,
      ctx: ctx,
      side: side,
      columns: columns,
    ).teamTotals[_pcGoals] ??
        0;
    return scored / awarded;
  }

  static List<StatColumn> get columns => [
        const StatColumn(key: _goals, label: 'Goals', shortLabel: 'G'),
        const StatColumn(
          key: _fieldGoals,
          label: 'Field goals',
          shortLabel: 'FG',
        ),
        const StatColumn(
          key: _pcGoals,
          label: 'Penalty corner goals',
          shortLabel: 'PC',
        ),
        const StatColumn(
          key: _psGoals,
          label: 'Penalty stroke goals',
          shortLabel: 'PS',
        ),
        const StatColumn(key: _assists, label: 'Assists', shortLabel: 'A'),
        const StatColumn(key: _saves, label: 'Saves', shortLabel: 'Sv'),
        const StatColumn(key: _greens, label: 'Green cards', shortLabel: 'GC'),
        const StatColumn(key: _yellows, label: 'Yellow cards', shortLabel: 'YC'),
        const StatColumn(key: _reds, label: 'Red cards', shortLabel: 'RC'),
      ];

  BoxScore boxScore(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      PlayerTally.boxScore(
          state: state, ctx: ctx, side: side, columns: columns);

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) =>
      '${state['a'] ?? 0} - ${state['b'] ?? 0}';

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) =>
      headline(state, ctx);

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return state['draw'] == true ? 'Full time · drawn' : 'Full time';
    }
    return 'Quarter ${state['period'] ?? 1} of ${_periods(ctx)}';
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = ((state['a'] as num?) ?? 0).toInt();
    final b = ((state['b'] as num?) ?? 0).toInt();
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
      isDraw: state['draw'] == true,
      winnerSide: state['winner'] == null
          ? null
          : Side.fromWire(state['winner'] as String),
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

    List<ScoreControl> forSide(Side side, String key) => [
          ScoreControl(
            action: 'goal',
            label: 'Field goal',
            side: side,
            style: ControlStyle.primary,
            payload: const {'how': 'field'},
            shortcut: key,
          ),
          ScoreControl(
            action: 'goal',
            label: 'PC goal',
            side: side,
            style: ControlStyle.primary,
            payload: const {'how': 'penalty_corner'},
          ),
          ScoreControl(
            action: 'goal',
            label: 'Stroke',
            side: side,
            payload: const {'how': 'penalty_stroke'},
          ),
          ScoreControl(
            action: 'penalty_corner',
            label: 'PC awarded',
            side: side,
            style: ControlStyle.secondary,
          ),
          ScoreControl(action: 'save', label: 'Save', side: side),
          ScoreControl(
            action: 'card',
            label: 'Green',
            side: side,
            payload: const {'colour': 'green'},
            style: ControlStyle.subtle,
          ),
          ScoreControl(
            action: 'card',
            label: 'Red',
            side: side,
            payload: const {'colour': 'red'},
            style: ControlStyle.danger,
          ),
        ];

    return [
      ScoreControlGroup(title: ctx.entrantAName, controls: forSide(Side.a, 'a')),
      ScoreControlGroup(title: ctx.entrantBName, controls: forSide(Side.b, 'l')),
      const ScoreControlGroup(
        title: 'Match',
        controls: [
          ScoreControl(
            action: 'next_period',
            label: 'Next quarter',
            style: ControlStyle.secondary,
            shortcut: 'n',
          ),
          ScoreControl(
            action: 'finish',
            label: 'End match',
            style: ControlStyle.danger,
            shortcut: 'f',
          ),
        ],
      ),
    ];
  }
}
