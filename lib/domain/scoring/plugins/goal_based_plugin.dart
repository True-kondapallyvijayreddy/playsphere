import '../scoring_plugin.dart';

/// Clock-and-period scoring for football, hockey, basketball, kabaddi,
/// netball and handball.
///
/// Score values are configurable, which is what lets one plugin serve both
/// football (every score worth 1) and basketball (1, 2 or 3), instead of
/// forcing a separate implementation for what is otherwise identical logic.
class GoalBasedPlugin extends ScoringPlugin {
  const GoalBasedPlugin();

  static const pluginKey = 'goal_based';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Goals and periods';

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        'period': 1,
        'log': <Map<String, dynamic>>[],
        'complete': false,
        'winner': null,
        'draw': false,
      };

  List<int> _scoreValues(ScoringContext ctx) {
    final raw = ctx.config['scoreValues'];
    if (raw is List && raw.isNotEmpty) {
      final values = raw.whereType<num>().map((n) => n.toInt()).toList();
      if (values.isNotEmpty) return values;
    }
    return const [1];
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

    final periods = ctx.intConfig('periods', 2);
    final allowDraw = ctx.boolConfig('allowDraw', true);

    switch (action.type) {
      case 'score':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('A score needs a side.');
        }
        final value = (action.payload['value'] as num?)?.toInt() ?? 1;
        final key = action.side.wire;
        final log = copyList(state['log'])
          ..add({
            'side': action.side.wire,
            'value': value,
            'period': state['period'] ?? 1,
          });
        return ScoringResult.ok(mutate(state, (s) {
          s[key] = ((s[key] as num?)?.toInt() ?? 0) + value;
          s['log'] = log;
        }));

      case 'correct':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correction needs a side.');
        }
        final key = action.side.wire;
        final current = (state[key] as num?)?.toInt() ?? 0;
        final value = (action.payload['value'] as num?)?.toInt() ?? 1;
        if (current < value) {
          return const ScoringResult.rejected(
            'Score cannot go below zero.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) => s[key] = current - value));

      case 'next_period':
        final period = (state['period'] as num?)?.toInt() ?? 1;
        if (period >= periods) {
          return ScoringResult.rejected(
            'This match only has $periods periods. Use "End match" to finish.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) => s['period'] = period + 1));

      case 'finish':
        final a = (state['a'] as num?)?.toInt() ?? 0;
        final b = (state['b'] as num?)?.toInt() ?? 0;
        if (a == b && !allowDraw) {
          return const ScoringResult.rejected(
            'Scores are level and this competition does not allow draws — '
            'play extra time or a shootout, then record the result.',
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
    final periods = ctx.intConfig('periods', 2);
    final label = ctx.config['periodLabel'] as String? ?? 'Period';
    return '$label ${state['period'] ?? 1} of $periods';
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = (state['a'] as num?)?.toInt() ?? 0;
    final b = (state['b'] as num?)?.toInt() ?? 0;
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
      isDraw: state['draw'] == true,
      winnerSide:
          state['winner'] == null ? null : Side.fromWire(state['winner'] as String),
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

    final values = _scoreValues(ctx);
    final aShortcuts = ['a', 's', 'd'];
    final bShortcuts = ['j', 'k', 'l'];

    List<ScoreControl> sideControls(Side side, List<String> keys) => [
          for (var i = 0; i < values.length; i++)
            ScoreControl(
              action: 'score',
              label: values.length == 1 ? 'Score' : '+${values[i]}',
              side: side,
              style: ControlStyle.primary,
              payload: {'value': values[i]},
              shortcut: i < keys.length ? keys[i] : null,
            ),
          ScoreControl(
            action: 'correct',
            label: '−1',
            side: side,
            style: ControlStyle.subtle,
            payload: const {'value': 1},
            shortcut: side == Side.a ? 'z' : 'm',
          ),
        ];

    return [
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: sideControls(Side.a, aShortcuts),
      ),
      ScoreControlGroup(
        title: ctx.entrantBName,
        controls: sideControls(Side.b, bShortcuts),
      ),
      const ScoreControlGroup(
        title: 'Match',
        controls: [
          ScoreControl(
            action: 'next_period',
            label: 'Next period',
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
