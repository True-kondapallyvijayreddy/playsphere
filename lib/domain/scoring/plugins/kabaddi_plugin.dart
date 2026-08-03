import '../match_flow.dart';
import '../player_stats.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';

/// Kabaddi, scored properly.
///
/// This is the sport the spec singles out as whitespace: it is in Telangana's
/// fourteen priority sports, it is played in every village in the state, and
/// no existing product scores it beyond a running total. Doing it properly
/// means modelling the raid as the unit of play, because everything
/// interesting in kabaddi — bonus points, super raids, super tackles,
/// do-or-die, all-outs, revivals — follows from it.
///
/// Rules encoded, all configurable because leagues differ:
///
///  * **A raid scores one point per defender touched.** A bonus point is
///    additional, and only available when the defending side has at least six
///    players on the mat.
///  * **Three or more points in a single raid is a super raid.**
///  * **A tackle scores one point, or two as a super tackle** when the
///    defending side is down to three or fewer players.
///  * **Two consecutive empty raids by a side make the third do-or-die**: it
///    must score or the raider is out.
///  * **An all-out is worth two points and revives the whole side.**
///  * **Players out are revived in the order they went out**, one per point
///    scored — which is why the engine tracks a queue rather than a count.
class KabaddiPlugin extends ScoringPlugin
    with PeriodedMatch, TeamTimeouts, MatchReviews {
  const KabaddiPlugin();

  /// Deliberately no [SquadRotation]. Kabaddi's mat count is driven by outs
  /// and revivals rather than by a coach's bench — a side goes from seven to
  /// three because three raiders got them out, and comes back to seven on an
  /// all-out. Layering a substitution model over that would give the mat two
  /// disagreeing sources of truth for the same number.

  static const pluginKey = 'kabaddi';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Kabaddi';

  static const _raidPoints = 'raidPoints';
  static const _tacklePoints = 'tacklePoints';
  static const _bonusPoints = 'bonusPoints';
  static const _superRaids = 'superRaids';
  static const _superTackles = 'superTackles';
  static const _raids = 'raids';
  static const _emptyRaids = 'emptyRaids';
  static const _timesOut = 'timesOut';

  int _onCourt(ScoringContext ctx) => ctx.intConfig('playersOnCourt', 7);
  @override
  int periodCount(ScoringContext ctx) => ctx.intConfig('periods', 2);

  @override
  String periodNoun(ScoringContext ctx) =>
      ctx.stringConfig('periodLabel', 'Half');

  /// A bonus point is only available when the defence is at full-ish strength.
  int _bonusThreshold(ScoringContext ctx) =>
      ctx.intConfig('bonusMinDefenders', 6);

  /// A super tackle is worth extra when the defence is depleted.
  int _superTackleAt(ScoringContext ctx) =>
      ctx.intConfig('superTackleMaxDefenders', 3);

  int _superRaidAt(ScoringContext ctx) => ctx.intConfig('superRaidPoints', 3);

  /// What a single touch is worth. Configurable because circle-style and
  /// amateur rulesets do not all award one point per defender touched.
  int _touchPoints(ScoringContext ctx) =>
      ctx.intConfig('touchPointsPerDefender', 1);

  int _bonusValue(ScoringContext ctx) => ctx.intConfig('bonusPoints', 1);

  int _tackleValue(ScoringContext ctx) => ctx.intConfig('tacklePoints', 1);

  int _superTackleValue(ScoringContext ctx) =>
      ctx.intConfig('superTacklePoints', 2);

  int _allOutBonus(ScoringContext ctx) => ctx.intConfig('allOutBonus', 2);

  /// How many consecutive empty raids force a do-or-die.
  int _doOrDieAfter(ScoringContext ctx) =>
      ctx.intConfig('doOrDieAfterEmptyRaids', 2);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) {
    final n = _onCourt(ctx);
    return {
      'a': 0,
      'b': 0,
      'period': 1,
      'complete': false,
      'winner': null,
      'draw': false,
      // How many of each side are currently on the mat.
      'onCourtA': n,
      'onCourtB': n,
      // Consecutive empty raids, per side. Two makes the next do-or-die.
      'emptyA': 0,
      'emptyB': 0,
      'allOutsA': 0,
      'allOutsB': 0,
      PlayerTally.stateKey: <String, dynamic>{},
      ...periodInitialState(ctx),
      ...timeoutInitialState(ctx),
      ...reviewInitialState(ctx),
    };
  }

  String _sideKey(Side s) => s == Side.a ? 'a' : 'b';
  String _courtKey(Side s) => s == Side.a ? 'onCourtA' : 'onCourtB';
  String _emptyKey(Side s) => s == Side.a ? 'emptyA' : 'emptyB';

  /// True when this side's next raid must produce a point.
  ///
  /// [ctx] is optional so a caller that only has state — a summary line, a
  /// spectator view — can still ask, falling back to the standard two raids.
  bool isDoOrDie(
    Map<String, dynamic> state,
    Side raidingSide, [
    ScoringContext? ctx,
  ]) {
    final threshold = ctx == null ? 2 : _doOrDieAfter(ctx);
    return ((state[_emptyKey(raidingSide)] as num?)?.toInt() ?? 0) >= threshold;
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

    final shared = applyTimeoutAction(state, action, ctx) ??
        applyReviewAction(state, action, ctx);
    if (shared != null) return shared;

    final n = _onCourt(ctx);
    int val(String k) => (state[k] as num?)?.toInt() ?? 0;

    switch (action.type) {
      case 'raid':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Which side is raiding?');
        }
        final raider = action.payload['playerId'] as String?;
        if (raider == null) {
          return const ScoringResult.rejected('Who raided?');
        }

        final raiding = action.side;
        final defending = raiding.opposite;
        final touched = (action.payload['touched'] as num?)?.toInt() ?? 0;
        final bonus = action.payload['bonus'] == true;
        final raiderOut = action.payload['raiderOut'] == true;

        final defendersOnCourt = val(_courtKey(defending));

        // The bonus line is only worth a point against a near-full defence.
        if (bonus &&
            _bonusThreshold(ctx) > 0 &&
            defendersOnCourt < _bonusThreshold(ctx)) {
          return ScoringResult.rejected(
            'A bonus point needs at least ${_bonusThreshold(ctx)} defenders '
            'on the mat — there are $defendersOnCourt.',
          );
        }
        if (touched > defendersOnCourt) {
          return ScoringResult.rejected(
            'Cannot touch $touched defenders when only $defendersOnCourt are '
            'on the mat.',
          );
        }

        final scored =
            touched * _touchPoints(ctx) + (bonus ? _bonusValue(ctx) : 0);
        final wasDoOrDie = isDoOrDie(state, raiding, ctx);

        var next = Map<String, dynamic>.from(state);

        // Points to the raiding side; touched defenders leave the mat.
        if (scored > 0) {
          next[_sideKey(raiding)] = val(_sideKey(raiding)) + scored;
          next[_courtKey(defending)] = defendersOnCourt - touched;
          // Every point revives one team-mate, oldest out first.
          next[_courtKey(raiding)] =
              (val(_courtKey(raiding)) + scored).clamp(0, n);
        }

        // The raider going out — either tackled, or failing a do-or-die.
        final outNow = raiderOut || (wasDoOrDie && scored == 0);
        if (outNow) {
          next[_courtKey(raiding)] =
              (val(_courtKey(raiding)) - 1).clamp(0, n);
          if (!raiderOut) {
            // Failed do-or-die: the point goes to the defence.
            next[_sideKey(defending)] = val(_sideKey(defending)) + 1;
            next[_courtKey(defending)] =
                (defendersOnCourt + 1).clamp(0, n);
          }
        }

        // Consecutive empty raids drive do-or-die.
        next[_emptyKey(raiding)] = scored == 0 && !outNow
            ? val(_emptyKey(raiding)) + 1
            : 0;

        next = PlayerTally.addAll(next, raider, {
          _raids: 1,
          if (scored > 0) _raidPoints: scored,
          if (bonus) _bonusPoints: 1,
          if (scored >= _superRaidAt(ctx)) _superRaids: 1,
          if (scored == 0 && !outNow) _emptyRaids: 1,
          if (outNow) _timesOut: 1,
        });

        return ScoringResult.ok(_settleAllOut(next, ctx));

      case 'tackle':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Which side made the tackle?');
        }
        final defending = action.side;
        final raiding = defending.opposite;
        final defenders =
            (action.payload['defenderIds'] as List?)?.whereType<String>().toList() ??
                const <String>[];
        if (defenders.isEmpty) {
          return const ScoringResult.rejected('Who made the tackle?');
        }

        final defendersOnCourt = val(_courtKey(defending));
        // A depleted defence stopping a raider is worth double.
        final isSuper = _superTackleAt(ctx) > 0 &&
            defendersOnCourt <= _superTackleAt(ctx);
        final points =
            isSuper ? _superTackleValue(ctx) : _tackleValue(ctx);

        var next = Map<String, dynamic>.from(state);
        next[_sideKey(defending)] = val(_sideKey(defending)) + points;
        // The raider is out; the defence revives that many players.
        next[_courtKey(raiding)] = (val(_courtKey(raiding)) - 1).clamp(0, n);
        next[_courtKey(defending)] =
            (defendersOnCourt + points).clamp(0, n);
        next[_emptyKey(raiding)] = 0;

        for (final d in defenders) {
          next = PlayerTally.addAll(next, d, {
            // Shared between everyone involved in the tackle, which is how
            // kabaddi credits it.
            _tacklePoints: points / defenders.length,
            if (isSuper) _superTackles: 1 / defenders.length,
          });
        }

        return ScoringResult.ok(_settleAllOut(next, ctx));

      case 'next_period':
        // The shared mixin owns the period number, the clock and the refusal
        // to run past the last half; kabaddi adds what only kabaddi does at
        // the break — both sides come back to full strength.
        final crossed = applyPeriodAction(state, action, ctx);
        if (crossed == null || !crossed.isAccepted) {
          return crossed ?? const ScoringResult.rejected('Unknown action.');
        }
        return ScoringResult.ok(
          mutate(refillIfScoped(crossed, ctx).state, (s) {
            s['onCourtA'] = n;
            s['onCourtB'] = n;
            s['emptyA'] = 0;
            s['emptyB'] = 0;
          }),
        );

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

  /// An emptied mat is an all-out: two bonus points and the side comes back.
  Map<String, dynamic> _settleAllOut(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final n = _onCourt(ctx);
    final bonus = _allOutBonus(ctx);
    var next = Map<String, dynamic>.from(state);
    int val(String k) => (next[k] as num?)?.toInt() ?? 0;

    if (val('onCourtA') <= 0) {
      next['b'] = val('b') + bonus;
      next['allOutsB'] = val('allOutsB') + 1;
      next['onCourtA'] = n;
      next['onCourtB'] = n;
    } else if (val('onCourtB') <= 0) {
      next['a'] = val('a') + bonus;
      next['allOutsA'] = val('allOutsA') + 1;
      next['onCourtB'] = n;
      next['onCourtA'] = n;
    }
    return next;
  }

  static List<StatColumn> get columns => columnsFor();

  /// Stat columns for a given ruleset. Super-10 and High-5 are milestones
  /// defined by the league, not by the sport, so their thresholds are read
  /// from the same config the engine scored under.
  static List<StatColumn> columnsFor([RuleConfig? rules]) {
    final superTenAt = rules?.getInt('superTenAt', 10) ?? 10;
    final highFiveAt = rules?.getInt('highFiveAt', 5) ?? 5;
    return [
        const StatColumn(key: _raidPoints, label: 'Raid points', shortLabel: 'RP'),
        const StatColumn(
          key: _tacklePoints,
          label: 'Tackle points',
          shortLabel: 'TP',
          decimals: 1,
        ),
        const StatColumn(key: _bonusPoints, label: 'Bonus', shortLabel: 'BP'),
        StatColumn(
          key: 'total',
          label: 'Total points',
          shortLabel: 'PTS',
          decimals: 1,
          derive: (t) =>
              ((t[_raidPoints] ?? 0) + (t[_tacklePoints] ?? 0)).toDouble(),
        ),
        const StatColumn(key: _raids, label: 'Raids', shortLabel: 'R'),
        const StatColumn(
          key: _superRaids,
          label: 'Super raids',
          shortLabel: 'SR',
        ),
        const StatColumn(
          key: _superTackles,
          label: 'Super tackles',
          shortLabel: 'ST',
          decimals: 1,
        ),
        StatColumn(
          key: 'super10',
          label: 'Super 10',
          shortLabel: 'S10',
          // Ten raid points in a match is kabaddi's headline individual
          // achievement, the way a century is in cricket.
          derive: (t) => (t[_raidPoints] ?? 0) >= superTenAt ? 1 : 0,
        ),
        StatColumn(
          key: 'high5',
          label: 'High 5',
          shortLabel: 'H5',
          derive: (t) => (t[_tacklePoints] ?? 0) >= highFiveAt ? 1 : 0,
        ),
      ];
  }

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
        columns: columnsFor(ctx.rules),
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
      return state['draw'] == true ? 'Full time · tied' : 'Full time';
    }
    final parts = <String>[
      periodStatus(state, ctx),
      '${state['onCourtA'] ?? 0} v ${state['onCourtB'] ?? 0} on the mat',
    ];
    if (isDoOrDie(state, Side.a, ctx)) {
      parts.add('${ctx.entrantAName}: DO OR DIE');
    }
    if (isDoOrDie(state, Side.b, ctx)) {
      parts.add('${ctx.entrantBName}: DO OR DIE');
    }
    return parts.join(' · ');
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

    // Every raid names its raider — the engine rejects one that does not
    // ("Who raided?") — and until the controls declared it the pad never
    // asked, so no kabaddi match could record a single point.
    const raider = [PlayerPrompt(key: 'playerId', label: 'Who raided?')];

    // The tackle button's side is the side that MADE the tackle, so the
    // tackler comes from that side's own list.
    // `defenderIds`, plural, and a multi-select. A raider is routinely held
    // by three or four defenders and the engine splits the tackle points
    // between all of them — asking for one would hand a super-tackle to a
    // single player and quietly falsify everyone's High 5 count.
    const tackler = [
      PlayerPrompt(
        key: 'defenderIds',
        label: 'Who made the tackle?',
        multiple: true,
      ),
    ];

    List<ScoreControl> raidControls(Side side) => [
          ScoreControl(
            action: 'raid',
            label: 'Touch 1',
            side: side,
            style: ControlStyle.primary,
            payload: const {'touched': 1},
            prompts: raider,
          ),
          ScoreControl(
            action: 'raid',
            label: 'Touch 2',
            side: side,
            style: ControlStyle.primary,
            payload: const {'touched': 2},
            prompts: raider,
          ),
          ScoreControl(
            action: 'raid',
            label: 'Bonus',
            side: side,
            payload: const {'touched': 0, 'bonus': true},
            prompts: raider,
          ),
          ScoreControl(
            action: 'raid',
            label: 'Empty',
            side: side,
            style: ControlStyle.subtle,
            payload: const {'touched': 0},
            prompts: raider,
          ),
          ScoreControl(
            action: 'raid',
            label: 'Raider out',
            side: side,
            style: ControlStyle.danger,
            payload: const {'touched': 0, 'raiderOut': true},
            prompts: raider,
          ),
        ];

    return [
      ScoreControlGroup(
        title: '${ctx.entrantAName} raiding',
        controls: raidControls(Side.a),
      ),
      ScoreControlGroup(
        title: '${ctx.entrantBName} raiding',
        controls: raidControls(Side.b),
      ),
      ScoreControlGroup(
        title: 'Tackles',
        controls: [
          ScoreControl(
            action: 'tackle',
            label: '${ctx.entrantAName} tackle',
            side: Side.a,
            style: ControlStyle.secondary,
            prompts: tackler,
          ),
          ScoreControl(
            action: 'tackle',
            label: '${ctx.entrantBName} tackle',
            side: Side.b,
            style: ControlStyle.secondary,
            prompts: tackler,
          ),
        ],
      ),
      ScoreControlGroup(
        title: 'Match',
        controls: [
          nextPeriodControl(ctx),
          const ScoreControl(
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
