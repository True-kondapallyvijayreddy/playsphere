import '../player_stats.dart';
import '../scoring_plugin.dart';

/// Kho-kho, in the modern Ultimate Kho Kho shape.
///
/// The other sport the research identifies as whitespace, and the harder of
/// the two: kho-kho's scoring changed materially between Ultimate Kho Kho
/// seasons and differs again from KKFI-aligned rulesets. A regular tag is
/// worth two points in one ruleset and three in another; the dream-run
/// threshold is three minutes in one and two and a half in another.
///
/// **Every point value here is configuration.** Hard-coding any of them would
/// make the engine wrong for whichever league is not the one it was written
/// against, and the spec is explicit that these must be per-season presets.
///
/// Structure: two innings, each of an attacking turn and a defending turn.
/// Defenders enter in batches of three; clearing a whole batch is what a
/// dream run and an all-out are measured against.
class KhoKhoPlugin extends ScoringPlugin {
  const KhoKhoPlugin();

  static const pluginKey = 'kho_kho';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Kho Kho';

  @override
  List<String> get headlineStats => const [_touchPoints];

  static const _touchPoints = 'touchPoints';
  static const _poleDives = 'poleDives';
  static const _skyDives = 'skyDives';
  static const _tags = 'tags';
  static const _khos = 'khos';
  static const _dreamRunPoints = 'dreamRunPoints';
  static const _timesOut = 'timesOut';
  static const _secondsSurvived = 'secondsSurvived';

  // Every one of these is a default, overridable per league and season.
  int _tagPoints(ScoringContext ctx) => ctx.intConfig('tagPoints', 2);
  int _poleDivePoints(ScoringContext ctx) => ctx.intConfig('poleDivePoints', 2);
  int _skyDivePoints(ScoringContext ctx) => ctx.intConfig('skyDivePoints', 2);
  int _allOutBonus(ScoringContext ctx) => ctx.intConfig('allOutBonus', 4);
  int _batchSize(ScoringContext ctx) => ctx.intConfig('batchSize', 3);
  int _turnsPerInnings(ScoringContext ctx) => ctx.intConfig('turnsPerInnings', 2);

  /// Seconds a defender must survive before the dream run starts paying, and
  /// the interval it pays at thereafter.
  int _dreamRunAfter(ScoringContext ctx) =>
      ctx.intConfig('dreamRunAfterSeconds', 180);
  int _dreamRunEvery(ScoringContext ctx) =>
      ctx.intConfig('dreamRunEverySeconds', 30);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        // Turn 1 = side A attacking. Turns alternate.
        'turn': 1,
        'attackingSide': 'a',
        'defendersOut': 0,
        'batchNumber': 1,
        'complete': false,
        'winner': null,
        'draw': false,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  Side _attacking(Map<String, dynamic> state) =>
      Side.fromWire(state['attackingSide'] as String? ?? 'a');

  /// Points a defender earns for surviving, per the configured schedule.
  ///
  /// Exposed so a caller can show the running value on the pad — a dream run
  /// is the most exciting thing in kho-kho and a scorer needs to see it build.
  int dreamRunPointsFor(int secondsSurvived, ScoringContext ctx) {
    final after = _dreamRunAfter(ctx);
    if (secondsSurvived < after) return 0;
    return 1 + (secondsSurvived - after) ~/ _dreamRunEvery(ctx);
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

    final attacking = _attacking(state);
    final defending = attacking.opposite;
    int val(String k) => (state[k] as num?)?.toInt() ?? 0;

    switch (action.type) {
      case 'tag':
        // An attacker puts a defender out. The skill used decides the value,
        // and every value is configuration.
        final attacker = action.payload['playerId'] as String?;
        final defender = action.payload['defenderId'] as String?;
        if (attacker == null) {
          return const ScoringResult.rejected('Who made the tag?');
        }
        final skill = action.payload['skill'] as String? ?? 'regular';
        final points = switch (skill) {
          'pole_dive' => _poleDivePoints(ctx),
          'sky_dive' => _skyDivePoints(ctx),
          _ => _tagPoints(ctx),
        };

        var next = mutate(state, (s) {
          s[attacking.wire] = val(attacking.wire) + points;
          s['defendersOut'] = val('defendersOut') + 1;
        });

        next = PlayerTally.addAll(next, attacker, {
          _touchPoints: points,
          _tags: 1,
          if (skill == 'pole_dive') _poleDives: 1,
          if (skill == 'sky_dive') _skyDives: 1,
        });

        if (defender != null) {
          // A defender who was out has their survival credited before they go.
          final survived = (action.payload['survivedSeconds'] as num?)?.toInt() ?? 0;
          final dream = dreamRunPointsFor(survived, ctx);
          next = PlayerTally.addAll(next, defender, {
            _timesOut: 1,
            _secondsSurvived: survived,
            if (dream > 0) _dreamRunPoints: dream,
          });
          // A dream run pays the DEFENDING side, which is what makes surviving
          // worth doing rather than merely delaying the inevitable.
          if (dream > 0) {
            next = mutate(next, (s) {
              s[defending.wire] = ((s[defending.wire] as num?)?.toInt() ?? 0) + dream;
            });
          }
        }

        return ScoringResult.ok(_settleBatch(next, ctx));

      case 'kho':
        final attacker = action.payload['playerId'] as String?;
        if (attacker == null) {
          return const ScoringResult.rejected('Who gave the kho?');
        }
        return ScoringResult.ok(PlayerTally.add(state, attacker, _khos, 1));

      case 'batch_entry':
        // A fresh batch of defenders comes on.
        return ScoringResult.ok(mutate(state, (s) {
          s['defendersOut'] = 0;
          s['batchNumber'] = val('batchNumber') + 1;
        }));

      case 'end_turn':
        final turn = val('turn');
        if (turn >= _turnsPerInnings(ctx) * 2) {
          return const ScoringResult.rejected(
            'Both innings are complete. Use "End match" to finish.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['turn'] = turn + 1;
          // Sides swap: the defenders now attack.
          s['attackingSide'] = defending.wire;
          s['defendersOut'] = 0;
          s['batchNumber'] = 1;
        }));

      case 'finish':
        final a = val('a');
        final b = val('b');
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

  /// Clearing a whole batch is an all-out — "Lona" — and carries a bonus.
  Map<String, dynamic> _settleBatch(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final out = (state['defendersOut'] as num?)?.toInt() ?? 0;
    if (out < _batchSize(ctx)) return state;

    final attacking = _attacking(state);
    return mutate(state, (s) {
      s[attacking.wire] =
          ((s[attacking.wire] as num?)?.toInt() ?? 0) + _allOutBonus(ctx);
      s['defendersOut'] = 0;
      s['batchNumber'] = ((s['batchNumber'] as num?)?.toInt() ?? 1) + 1;
    });
  }

  static List<StatColumn> get columns => [
        const StatColumn(
          key: _touchPoints,
          label: 'Touch points',
          shortLabel: 'TP',
        ),
        const StatColumn(key: _tags, label: 'Tags', shortLabel: 'T'),
        const StatColumn(
          key: _poleDives,
          label: 'Pole dives',
          shortLabel: 'PD',
        ),
        const StatColumn(key: _skyDives, label: 'Sky dives', shortLabel: 'SD'),
        const StatColumn(key: _khos, label: 'Khos given', shortLabel: 'KHO'),
        const StatColumn(
          key: _dreamRunPoints,
          label: 'Dream run points',
          shortLabel: 'DR',
        ),
        StatColumn(
          key: 'survivalMinutes',
          label: 'Time survived',
          shortLabel: 'MIN',
          decimals: 1,
          derive: (t) => (t[_secondsSurvived] ?? 0) / 60,
        ),
      ];

  @override
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

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) =>
      '${state['a'] ?? 0} - ${state['b'] ?? 0}';

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) =>
      headline(state, ctx);

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return state['draw'] == true ? 'Match tied' : 'Final';
    }
    final attacking = _attacking(state);
    return 'Turn ${state['turn'] ?? 1} · ${ctx.nameFor(attacking)} attacking · '
        'batch ${state['batchNumber'] ?? 1}, '
        '${state['defendersOut'] ?? 0}/${_batchSize(ctx)} out';
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = (state['a'] as num?)?.toInt() ?? 0;
    final b = (state['b'] as num?)?.toInt() ?? 0;
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

    final attacking = _attacking(state);

    return [
      ScoreControlGroup(
        title: '${ctx.nameFor(attacking)} attacking',
        controls: [
          // A tag is two people: the attacker who made it, from the attacking
          // batch, and the defender who went out, from the other side. The
          // engine rejects it without the attacker ("Who made the tag?") and
          // credits the defender's survival time when named — and neither was
          // ever asked for, so every tag in every kho-kho match was refused.
          //
          // The defender is optional rather than required because a scorer
          // watching a dive knows who dived long before they can say which of
          // three runners it was; forcing the second name would stall the pad
          // in the middle of the point.
          for (final (label, skill, key) in const [
            ('Tag', 'regular', 't'),
            ('Pole dive', 'pole_dive', 'p'),
            ('Sky dive', 'sky_dive', 'k'),
          ])
            ScoreControl(
              action: 'tag',
              label: label,
              side: attacking,
              style: ControlStyle.primary,
              payload: {'skill': skill},
              shortcut: key,
              prompts: const [
                PlayerPrompt(key: 'playerId', label: 'Who made the tag?'),
                PlayerPrompt(
                  key: 'defenderId',
                  label: 'Who went out?',
                  from: PromptSource.opposingSide,
                  optional: true,
                ),
              ],
            ),
          ScoreControl(
            action: 'kho',
            label: 'Kho',
            side: attacking,
            style: ControlStyle.subtle,
            shortcut: 'o',
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who gave the kho?'),
            ],
          ),
        ],
      ),
      const ScoreControlGroup(
        title: 'Turn',
        controls: [
          ScoreControl(
            action: 'batch_entry',
            label: 'New batch',
            style: ControlStyle.secondary,
          ),
          ScoreControl(
            action: 'end_turn',
            label: 'End turn',
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
