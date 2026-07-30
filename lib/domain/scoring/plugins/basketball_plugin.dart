import '../player_stats.dart';
import '../scoring_plugin.dart';

/// Basketball, with a full box score and shot chart.
///
/// The spec asks for PTS, REB, AST, STL, BLK, TO, FG%, 3P%, FT% and +/−. All
/// of those except points are impossible from a side-total engine, and the
/// percentages are the ones most often got wrong: field-goal percentage must
/// EXCLUDE free throws, and three-point attempts count inside field goals as
/// well as in their own column. Getting that wrong inflates every shooter.
///
/// Shots carry optional normalised court coordinates so a shot chart can be
/// drawn later without re-deriving anything from the event log.
class BasketballPlugin extends ScoringPlugin {
  const BasketballPlugin();

  static const pluginKey = 'basketball';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Basketball';

  static const _points = 'points';
  static const _fgMade = 'fgMade';
  static const _fgAttempted = 'fgAttempted';
  static const _threeMade = 'threeMade';
  static const _threeAttempted = 'threeAttempted';
  static const _ftMade = 'ftMade';
  static const _ftAttempted = 'ftAttempted';
  static const _offRebounds = 'offRebounds';
  static const _defRebounds = 'defRebounds';
  static const _assists = 'assists';
  static const _steals = 'steals';
  static const _blocks = 'blocks';
  static const _turnovers = 'turnovers';
  static const _fouls = 'fouls';
  static const _technicals = 'technicals';

  int _periods(ScoringContext ctx) => ctx.intConfig('periods', 4);

  /// FIBA fouls out at 5, the NBA at 6. Configurable, never assumed.
  int _foulLimit(ScoringContext ctx) => ctx.intConfig('foulOutAt', 5);

  /// What each kind of basket is worth.
  ///
  /// 3×3 is the reason these are configuration rather than the constants
  /// 1/2/3: under FIBA 3×3 an ordinary basket is worth 1 and a shot from
  /// behind the arc is worth 2, so the point value alone cannot tell you what
  /// kind of shot it was.
  int _ftPoints(ScoringContext ctx) => ctx.intConfig('freeThrowPoints', 1);
  int _fgPoints(ScoringContext ctx) => ctx.intConfig('fieldGoalPoints', 2);
  int _threePoints(ScoringContext ctx) => ctx.intConfig('threePointPoints', 3);

  /// 3×3 is first-to-21 as well as time-limited. Zero means "no target".
  int _targetScore(ScoringContext ctx) => ctx.intConfig('targetScore', 0);

  /// Classifies a shot. Modern logs carry an explicit `kind`; older ones only
  /// have a point value, so fall back to inferring it the way the engine
  /// originally did rather than mis-reading historic matches.
  String _shotKind(Map<String, dynamic> payload, ScoringContext ctx) {
    final explicit = payload['kind'];
    if (explicit == 'ft' || explicit == 'fg' || explicit == 'three') {
      return explicit as String;
    }
    final value = (payload['value'] as num?)?.toInt() ?? _fgPoints(ctx);
    if (value == 1) return 'ft';
    if (value == 3) return 'three';
    return 'fg';
  }

  int _pointsForKind(String kind, ScoringContext ctx) => switch (kind) {
        'ft' => _ftPoints(ctx),
        'three' => _threePoints(ctx),
        _ => _fgPoints(ctx),
      };

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        'period': 1,
        'complete': false,
        'winner': null,
        'draw': false,
        'fouledOut': <String>[],
        'shots': <Map<String, dynamic>>[],
        PlayerTally.stateKey: <String, dynamic>{},
      };

  List<String> _fouledOut(Map<String, dynamic> state) =>
      (state['fouledOut'] as List?)?.whereType<String>().toList() ?? const [];

  /// 3×3 ends the moment a side reaches the target, without waiting for the
  /// clock. A target of zero (the full-court presets) leaves the match open
  /// until the scorer finalises it.
  Map<String, dynamic> _settleTarget(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final target = _targetScore(ctx);
    if (target <= 0) return state;
    final a = (state['a'] as num?)?.toInt() ?? 0;
    final b = (state['b'] as num?)?.toInt() ?? 0;
    if (a < target && b < target) return state;
    return mutate(state, (s) {
      s['complete'] = true;
      s['draw'] = false;
      s['winner'] = a >= target ? 'a' : 'b';
    });
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

    final player = action.payload['playerId'] as String?;
    if (player != null && _fouledOut(state).contains(player)) {
      return ScoringResult.rejected(
        '${ctx.playerName(player)} has fouled out and cannot take part.',
      );
    }

    int score(String side) => (state[side] as num?)?.toInt() ?? 0;

    switch (action.type) {
      case 'shot':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('A shot needs a side.');
        }
        if (player == null) {
          return const ScoringResult.rejected('Who took the shot?');
        }
        final kind = _shotKind(action.payload, ctx);
        final value = _pointsForKind(kind, ctx);
        final made = action.payload['made'] == true;
        final assist = action.payload['assistId'] as String?;
        final isFreeThrow = kind == 'ft';
        final isThree = kind == 'three';

        final deltas = <String, num>{
          if (made) _points: value,
          // Free throws are NOT field goals. Counting them inside FG% is the
          // most common way a shooting percentage ends up flattering.
          if (!isFreeThrow) _fgAttempted: 1,
          if (!isFreeThrow && made) _fgMade: 1,
          // A three counts in BOTH the three column and the field-goal column.
          if (isThree) _threeAttempted: 1,
          if (isThree && made) _threeMade: 1,
          if (isFreeThrow) _ftAttempted: 1,
          if (isFreeThrow && made) _ftMade: 1,
        };

        var next = PlayerTally.addAll(state, player, deltas);
        if (made) {
          next = mutate(next, (s) {
            s[action.side.wire] = score(action.side.wire) + value;
          });
          // An assist only exists on a made basket.
          if (assist != null && assist != player && !isFreeThrow) {
            next = PlayerTally.add(next, assist, _assists, 1);
          }
        }

        // Coordinates are optional; when present they make a shot chart
        // possible without replaying and re-deriving the log.
        final x = action.payload['x'];
        final y = action.payload['y'];
        if (x is num && y is num) {
          final shots = copyList(next['shots'])
            ..add({
              'playerId': player,
              'side': action.side.wire,
              'value': value,
              'made': made,
              'x': x.toDouble(),
              'y': y.toDouble(),
              'period': next['period'] ?? 1,
            });
          next = {...next, 'shots': shots};
        }
        return ScoringResult.ok(_settleTarget(next, ctx));

      case 'rebound':
        if (player == null) {
          return const ScoringResult.rejected('Who got the rebound?');
        }
        final offensive = action.payload['offensive'] == true;
        return ScoringResult.ok(PlayerTally.add(
          state,
          player,
          offensive ? _offRebounds : _defRebounds,
          1,
        ));

      case 'steal':
        if (player == null) {
          return const ScoringResult.rejected('Who stole it?');
        }
        return ScoringResult.ok(PlayerTally.add(state, player, _steals, 1));

      case 'block':
        if (player == null) {
          return const ScoringResult.rejected('Who blocked it?');
        }
        return ScoringResult.ok(PlayerTally.add(state, player, _blocks, 1));

      case 'turnover':
        if (player == null) {
          return const ScoringResult.rejected('Who turned it over?');
        }
        return ScoringResult.ok(PlayerTally.add(state, player, _turnovers, 1));

      case 'foul':
        if (player == null) {
          return const ScoringResult.rejected('Who committed the foul?');
        }
        final technical = action.payload['technical'] == true;
        var next = PlayerTally.addAll(state, player, {
          _fouls: 1,
          if (technical) _technicals: 1,
        });
        // Fouling out is arithmetic the engine should do, not the scorer.
        final total = (PlayerTally.of(next, player)[_fouls] ?? 0).toInt();
        if (total >= _foulLimit(ctx)) {
          next = {
            ...next,
            'fouledOut': [..._fouledOut(next), player],
          };
        }
        return ScoringResult.ok(next);

      case 'next_period':
        final period = (state['period'] as num?)?.toInt() ?? 1;
        if (period >= _periods(ctx)) {
          return ScoringResult.rejected(
            'This match has only ${_periods(ctx)} periods. '
            'Use "End match" to finish.',
          );
        }
        return ScoringResult.ok(
          mutate(state, (s) => s['period'] = period + 1),
        );

      case 'finish':
        final a = score('a');
        final b = score('b');
        // Basketball does not draw. A level score means overtime, and
        // recording it as a draw would be a result that cannot happen.
        if (a == b) {
          return const ScoringResult.rejected(
            'Scores are level — basketball cannot end drawn. Play overtime, '
            'then record the result.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = false;
          s['winner'] = a > b ? 'a' : 'b';
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  static double _pct(num made, num attempted) =>
      attempted == 0 ? 0 : made / attempted;

  static List<StatColumn> get columns => [
        const StatColumn(key: _points, label: 'Points', shortLabel: 'PTS'),
        StatColumn(
          key: 'rebounds',
          label: 'Rebounds',
          shortLabel: 'REB',
          derive: (t) =>
              ((t[_offRebounds] ?? 0) + (t[_defRebounds] ?? 0)).toDouble(),
        ),
        const StatColumn(key: _assists, label: 'Assists', shortLabel: 'AST'),
        const StatColumn(key: _steals, label: 'Steals', shortLabel: 'STL'),
        const StatColumn(key: _blocks, label: 'Blocks', shortLabel: 'BLK'),
        const StatColumn(key: _turnovers, label: 'Turnovers', shortLabel: 'TO'),
        StatColumn(
          key: 'fgPct',
          label: 'Field goal %',
          shortLabel: 'FG%',
          isPercentage: true,
          decimals: 1,
          derive: (t) => _pct(t[_fgMade] ?? 0, t[_fgAttempted] ?? 0),
        ),
        StatColumn(
          key: 'threePct',
          label: 'Three point %',
          shortLabel: '3P%',
          isPercentage: true,
          decimals: 1,
          derive: (t) => _pct(t[_threeMade] ?? 0, t[_threeAttempted] ?? 0),
        ),
        StatColumn(
          key: 'ftPct',
          label: 'Free throw %',
          shortLabel: 'FT%',
          isPercentage: true,
          decimals: 1,
          derive: (t) => _pct(t[_ftMade] ?? 0, t[_ftAttempted] ?? 0),
        ),
        const StatColumn(key: _fouls, label: 'Fouls', shortLabel: 'PF'),
      ];

  BoxScore boxScore(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      PlayerTally.boxScore(
        state: state,
        ctx: ctx,
        side: side,
        columns: columns,
      );

  /// Every recorded shot with coordinates, for the chart.
  List<Map<String, dynamic>> shotChart(
    Map<String, dynamic> state, {
    Side? side,
  }) {
    final all = copyList(state['shots']);
    if (side == null) return all;
    return all.where((s) => s['side'] == side.wire).toList();
  }

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) =>
      '${state['a'] ?? 0} - ${state['b'] ?? 0}';

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) =>
      headline(state, ctx);

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return 'Final';
    final label = ctx.config['periodLabel'] as String? ?? 'Quarter';
    return '$label ${state['period'] ?? 1} of ${_periods(ctx)}';
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = (state['a'] as num?)?.toInt() ?? 0;
    final b = (state['b'] as num?)?.toInt() ?? 0;
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
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

    // Labels follow the ruleset: a 3×3 pad reads +1 / +2, a full-court pad
    // reads +2 / +3, and neither is baked into the widget layer.
    final fg = _fgPoints(ctx);
    final three = _threePoints(ctx);
    final ft = _ftPoints(ctx);

    List<ScoreControl> forSide(Side side, List<String> keys) => [
          ScoreControl(
            action: 'shot',
            label: '+$fg',
            side: side,
            style: ControlStyle.primary,
            payload: {'kind': 'fg', 'value': fg, 'made': true},
            shortcut: keys[0],
          ),
          ScoreControl(
            action: 'shot',
            label: '+$three',
            side: side,
            style: ControlStyle.primary,
            payload: {'kind': 'three', 'value': three, 'made': true},
            shortcut: keys[1],
          ),
          ScoreControl(
            action: 'shot',
            label: 'FT',
            side: side,
            payload: {'kind': 'ft', 'value': ft, 'made': true},
            shortcut: keys[2],
          ),
          ScoreControl(
            action: 'shot',
            label: 'Miss',
            side: side,
            style: ControlStyle.subtle,
            payload: {'kind': 'fg', 'value': fg, 'made': false},
          ),
          ScoreControl(action: 'rebound', label: 'Reb', side: side),
          ScoreControl(action: 'assist', label: 'Ast', side: side),
          ScoreControl(
            action: 'foul',
            label: 'Foul',
            side: side,
            style: ControlStyle.danger,
          ),
        ];

    return [
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: forSide(Side.a, ['a', 's', 'd']),
      ),
      ScoreControlGroup(
        title: ctx.entrantBName,
        controls: forSide(Side.b, ['j', 'k', 'l']),
      ),
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
