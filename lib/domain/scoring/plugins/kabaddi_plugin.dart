import '../../../core/models/fixture.dart' show MatchEvent;
import '../match_flow.dart';
import '../player_stats.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';

/// Kabaddi, scored the way a raid actually happens.
///
/// This is the sport the spec singles out as whitespace: it is in Telangana's
/// fourteen priority sports, it is played in every village in the state, and
/// no existing product scores it beyond a running total. Doing it properly
/// means modelling the raid as the unit of play, because everything
/// interesting in kabaddi — bonus points, super raids, super tackles,
/// do-or-die, all-outs, revivals — follows from it.
///
/// ## Score first, details second, the match never stops
///
/// The design constraint that shapes every decision below is that a raid
/// lasts thirty seconds and the next one starts immediately. A pad that
/// stops to ask "who raided?" before it will accept a point is a pad that
/// loses the next raid, and the scorer's answer to that is to stop using it.
/// So **every scoring action applies with no names at all**. What the scorer
/// did not have time to say is pushed onto [pendingOf] — a queue of unfinished
/// details that can be completed at a timeout, at half time, or after the
/// match, through the `attribute` action. Team totals are always correct;
/// player attribution catches up.
///
/// That is why the team breakdown ([raidPointsFor], [tacklePointsFor] and the
/// rest) is tracked at side level rather than summed out of the player
/// tallies. A scorecard that could only be built from attributed events would
/// read 18-16 as 4-2 for the hour before anyone had time to name a raider.
///
/// ## What is authoritative, and what is best effort
///
/// `onCourtA` / `onCourtB` — the number of players on the mat — is
/// authoritative and always exact: it is what the bonus threshold, the
/// super-tackle threshold and all-out detection are decided from, and every
/// action moves it whether or not anyone was named. `outA` / `outB` are the
/// *named* revival queue, and are a subset: they hold the players the scorer
/// had time to identify, oldest out first, so revivals restore the right
/// people in the right order when the names exist and simply restore the
/// count when they do not.
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
///    must score or the raider is out and the point goes to the defence.
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
  /// disagreeing sources of truth for the same number, so the substitution
  /// this sport does need is handled by `substitute` below, which moves a name
  /// and never the count.

  static const pluginKey = 'kabaddi';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Kabaddi';

  @override
  List<String> get headlineStats => const [_raidPoints, _tacklePoints];

  // --- Player tally keys ---------------------------------------------------

  static const _raidPoints = 'raidPoints';
  static const _tacklePoints = 'tacklePoints';
  static const _bonusPoints = 'bonusPoints';
  static const _superRaids = 'superRaids';
  static const _superTackles = 'superTackles';
  static const _raids = 'raids';
  static const _emptyRaids = 'emptyRaids';
  static const _timesOut = 'timesOut';

  // --- State keys ----------------------------------------------------------

  /// Side-level point breakdown. The five of these sum to the side's score,
  /// which is the invariant [_award] maintains on every point it books.
  static const _breakdownKeys = [
    'raidPts',
    'tacklePts',
    'bonusPts',
    'allOutPts',
    'techPts',
  ];

  static const historyKey = 'history';
  static const pendingKey = 'pending';

  // --- Rule accessors ------------------------------------------------------

  int _onCourt(ScoringContext ctx) => ctx.intConfig('playersOnCourt', 7);

  @override
  int periodCount(ScoringContext ctx) => ctx.intConfig('periods', 2);

  @override
  String periodNoun(ScoringContext ctx) =>
      ctx.stringConfig('periodLabel', 'Half');

  /// Kabaddi's presets name the half length `halfLengthMinutes`, which is what
  /// an organizer setting up a match is asked for. Without this override the
  /// shared mixin looked for `periodMinutes`, found nothing, and reported the
  /// match as untimed — so the pad showed "Half 1 of 2" and never a clock, in
  /// the one sport whose raid is governed by one.
  @override
  int periodMinutes(ScoringContext ctx) => ctx.rules.has('periodMinutes')
      ? ctx.intConfig('periodMinutes', 0)
      : ctx.intConfig('halfLengthMinutes', 0);

  /// How long a raider has. Read by the pad, which runs the countdown; the
  /// engine stays pure and keeps no wall clock.
  int raidClockSeconds(ScoringContext ctx) =>
      ctx.intConfig('raidClockSeconds', 30);

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

  /// A technical point: awarded by the referee for a boot over the line, an
  /// illegal hold, dissent. One point, and it belongs to no player — which is
  /// why it has a side counter and no tally key.
  int _technicalValue(ScoringContext ctx) =>
      ctx.intConfig('technicalPoints', 1);

  /// How many consecutive empty raids force a do-or-die.
  int _doOrDieAfter(ScoringContext ctx) =>
      ctx.intConfig('doOrDieAfterEmptyRaids', 2);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) {
    final n = _onCourt(ctx);
    return {
      'a': 0,
      'b': 0,
      for (final k in _breakdownKeys) ...{'${k}A': 0, '${k}B': 0},
      'period': 1,
      'complete': false,
      'winner': null,
      'draw': false,
      // How many of each side are currently on the mat. Authoritative.
      'onCourtA': n,
      'onCourtB': n,
      // The NAMED revival queue, oldest out first. Best effort: a subset of
      // what the count says is out, holding whoever the scorer identified.
      'outA': <Map<String, dynamic>>[],
      'outB': <Map<String, dynamic>>[],
      // Who has been substituted out of the match altogether. Distinct from
      // being out on the mat — a substituted player does not come back on a
      // revival.
      'benchedA': <String>[],
      'benchedB': <String>[],
      // Consecutive empty raids, per side. Two makes the next do-or-die.
      'emptyA': 0,
      'emptyB': 0,
      'allOutsA': 0,
      'allOutsB': 0,
      // Whose turn it is to raid. The toss decides the first one.
      'raidingSide': ctx.startingSide.wire,
      'raiderId': null,
      'nextRaiderId': null,
      'raidNo': 0,
      historyKey: <Map<String, dynamic>>[],
      pendingKey: <Map<String, dynamic>>[],
      PlayerTally.stateKey: <String, dynamic>{},
      ...periodInitialState(ctx),
      ...timeoutInitialState(ctx),
      ...reviewInitialState(ctx),
    };
  }

  // --- State readers, shared with the pad ----------------------------------

  static String _s(Side s) => s == Side.a ? 'A' : 'B';

  String _sideKey(Side s) => s == Side.a ? 'a' : 'b';
  String _courtKey(Side s) => 'onCourt${_s(s)}';
  String _emptyKey(Side s) => 'empty${_s(s)}';
  String _outKey(Side s) => 'out${_s(s)}';

  static int _int(Map<String, dynamic> state, String key) =>
      (state[key] as num?)?.toInt() ?? 0;

  /// Players on the mat for [side], by count. Always exact.
  int onCourt(Map<String, dynamic> state, Side side) =>
      _int(state, 'onCourt${_s(side)}');

  int raidPointsFor(Map<String, dynamic> state, Side side) =>
      _int(state, 'raidPts${_s(side)}');

  int tacklePointsFor(Map<String, dynamic> state, Side side) =>
      _int(state, 'tacklePts${_s(side)}');

  int bonusPointsFor(Map<String, dynamic> state, Side side) =>
      _int(state, 'bonusPts${_s(side)}');

  int allOutPointsFor(Map<String, dynamic> state, Side side) =>
      _int(state, 'allOutPts${_s(side)}');

  int technicalPointsFor(Map<String, dynamic> state, Side side) =>
      _int(state, 'techPts${_s(side)}');

  int scoreFor(Map<String, dynamic> state, Side side) =>
      _int(state, _sideKey(side));

  int allOutsFor(Map<String, dynamic> state, Side side) =>
      _int(state, 'allOuts${_s(side)}');

  /// Whose raid it is now.
  Side raidingSide(Map<String, dynamic> state) =>
      Side.fromWire(state['raidingSide'] as String?) == Side.b
          ? Side.b
          : Side.a;

  String? raiderId(Map<String, dynamic> state) => state['raiderId'] as String?;

  String? nextRaiderId(Map<String, dynamic> state) =>
      state['nextRaiderId'] as String?;

  int raidNumber(Map<String, dynamic> state) => _int(state, 'raidNo');

  /// The named revival queue for [side], oldest out first.
  List<String> outQueue(Map<String, dynamic> state, Side side) => [
        for (final e in copyList(state[_outKey(side)]))
          if (e['id'] is String) e['id'] as String,
      ];

  /// Who has been substituted out of the match for [side].
  List<String> benchedFor(Map<String, dynamic> state, Side side) => [
        for (final e in (state['benched${_s(side)}'] as List? ?? const []))
          if (e is String) e,
      ];

  /// Players known to be on the mat: the line-up, less the named outs and
  /// anyone substituted out. Empty when no line-up was entered, in which case
  /// only [onCourt] is meaningful.
  List<String> matFor(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) {
    final out = outQueue(state, side).toSet();
    final benched = benchedFor(state, side).toSet();
    return [
      for (final p in ctx.lineupFor(side))
        if (!out.contains(p.id) && !benched.contains(p.id)) p.id,
    ];
  }

  /// The raid ledger, oldest first.
  static List<Map<String, dynamic>> historyOf(Map<String, dynamic> state) =>
      copyList(state[historyKey]);

  /// Details the scorer skipped, oldest first. Each entry carries the tally
  /// it will apply once somebody is named — see [_pend].
  static List<Map<String, dynamic>> pendingOf(Map<String, dynamic> state) =>
      copyList(state[pendingKey]);

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
    return _int(state, _emptyKey(raidingSide)) >= threshold;
  }

  /// Whether a tackle right now would be a super tackle. The pad reads this to
  /// label the button with what it will actually award, rather than making the
  /// scorer count defenders under time pressure.
  bool isSuperTackleNow(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side defendingSide,
  ) =>
      _superTackleAt(ctx) > 0 &&
      onCourt(state, defendingSide) <= _superTackleAt(ctx);

  /// Whether the bonus line is live for the raiding side right now.
  bool isBonusAvailable(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side raiding,
  ) {
    final threshold = _bonusThreshold(ctx);
    return threshold <= 0 || onCourt(state, raiding.opposite) >= threshold;
  }

  // --- Reducer -------------------------------------------------------------

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

    switch (action.type) {
      case 'raid':
        return _applyRaid(state, action, ctx);
      case 'tackle':
        return _applyTackle(state, action, ctx);
      case 'technical':
        return _applyTechnical(state, action, ctx);
      case 'all_out':
        return _applyManualAllOut(state, action, ctx);
      case 'attribute':
        return _applyAttribute(state, action, ctx);
      case 'set_raider':
        return _applySetRaider(state, action, ctx);
      case 'substitute':
        return _applySubstitute(state, action, ctx);

      case 'next_period':
        // The shared mixin owns the period number, the clock and the refusal
        // to run past the last half; kabaddi adds what only kabaddi does at
        // the break — both sides come back to full strength, and the side
        // that did not raid first opens the second half.
        final crossed = applyPeriodAction(state, action, ctx);
        if (crossed == null || !crossed.isAccepted) {
          return crossed ?? const ScoringResult.rejected('Unknown action.');
        }
        final n = _onCourt(ctx);
        return ScoringResult.ok(
          mutate(refillIfScoped(crossed, ctx).state, (s) {
            s['onCourtA'] = n;
            s['onCourtB'] = n;
            s['outA'] = <Map<String, dynamic>>[];
            s['outB'] = <Map<String, dynamic>>[];
            s['emptyA'] = 0;
            s['emptyB'] = 0;
            s['raidingSide'] = ctx.startingSide.opposite.wire;
            s['raiderId'] = null;
            s['nextRaiderId'] = null;
          }),
        );

      case 'finish':
        final a = _int(state, 'a');
        final b = _int(state, 'b');
        return ScoringResult.ok(mutate(atFullTime(state, ctx), (s) {
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

  // --- Raid ----------------------------------------------------------------

  ScoringResult _applyRaid(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side is raiding?');
    }
    final n = _onCourt(ctx);
    final raiding = action.side;
    final defending = raiding.opposite;

    final touched = (action.payload['touched'] as num?)?.toInt() ?? 0;
    final bonus = action.payload['bonus'] == true;
    final raiderOut = action.payload['raiderOut'] == true;

    // Optional, and that is the whole point — see the class doc. A raid with
    // nobody named still scores; the name becomes a pending detail.
    final raider =
        action.payload['playerId'] as String? ?? raiderId(state);
    final namedDefenders = _ids(action.payload['defenderIds']);

    final defendersOnCourt = onCourt(state, defending);

    // The bonus line is only worth a point against a near-full defence.
    if (bonus && !isBonusAvailable(state, ctx, raiding)) {
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
    if (namedDefenders.length > touched) {
      return ScoringResult.rejected(
        'Named ${namedDefenders.length} defenders out but the raid touched '
        '$touched.',
      );
    }

    final touchPts = touched * _touchPoints(ctx);
    final bonusPts = bonus ? _bonusValue(ctx) : 0;
    final scored = touchPts + bonusPts;
    final wasDoOrDie = isDoOrDie(state, raiding, ctx);

    var next = Map<String, dynamic>.from(state);

    if (scored > 0) {
      next = _award(next, raiding, raidPts: touchPts, bonusPts: bonusPts);
      // Touched defenders leave the mat; the ones the scorer named join the
      // revival queue in order, and the rest move only the count.
      next[_courtKey(defending)] = defendersOnCourt - touched;
      next = _pushOut(next, defending, namedDefenders, _int(next, 'raidNo') + 1);
      // Every point revives one team-mate, oldest out first.
      next = _revive(next, raiding, scored, n);
    }

    // The raider going out — either tackled, or failing a do-or-die.
    final failedDoOrDie = wasDoOrDie && scored == 0;
    final outNow = raiderOut || failedDoOrDie;
    if (outNow) {
      next[_courtKey(raiding)] =
          (onCourt(next, raiding) - 1).clamp(0, n);
      next = _pushOut(next, raiding, [if (raider != null) raider],
          _int(next, 'raidNo') + 1);
      if (failedDoOrDie && !raiderOut) {
        // The point for a failed do-or-die belongs to the defence, and counts
        // as a tackle point the way the rulebook records it.
        next = _award(next, defending, tacklePts: 1);
        next = _revive(next, defending, 1, n);
      }
    }

    // Consecutive empty raids drive do-or-die. An empty raid that ends with
    // the raider out resets it — the turnover has already been paid for.
    next[_emptyKey(raiding)] =
        scored == 0 && !outNow ? _int(next, _emptyKey(raiding)) + 1 : 0;

    final tally = <String, num>{
      _raids: 1,
      // Raid points are touches AND the bonus, which is how kabaddi counts a
      // raider's contribution and how a Super 10 is arrived at.
      if (scored > 0) _raidPoints: scored,
      if (bonusPts > 0) _bonusPoints: 1,
      if (scored >= _superRaidAt(ctx)) _superRaids: 1,
      if (scored == 0 && !outNow) _emptyRaids: 1,
      if (outNow) _timesOut: 1,
    };

    final result = _describeRaid(
      touched: touched,
      bonus: bonus,
      scored: scored,
      raiderOut: raiderOut,
      failedDoOrDie: failedDoOrDie,
      superRaid: scored >= _superRaidAt(ctx),
    );

    next = _record(
      next,
      ctx,
      side: raiding,
      actorId: raider,
      result: result,
      points: scored,
      tally: tally,
      // The raider is a pending detail when nobody was named; the defenders
      // are one when fewer were named than the raid put out.
      needs: [
        if (raider == null) 'raider',
        if (namedDefenders.length < touched) 'defenders',
      ],
      defendersMissing: touched - namedDefenders.length,
      defendingSide: defending,
    );

    // The raid is over: hand the mat to whoever is named next, and pass the
    // raid to the other side.
    next['raiderId'] = null;
    next['raidingSide'] = defending.wire;
    next['nextRaiderId'] = null;

    return ScoringResult.ok(_settleAllOut(next, ctx));
  }

  // --- Tackle --------------------------------------------------------------

  ScoringResult _applyTackle(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side made the tackle?');
    }
    final n = _onCourt(ctx);
    final defending = action.side;
    final raiding = defending.opposite;

    // Optional. A tackle by an unnamed defence still scores and still puts the
    // raider out; who held him becomes a pending detail.
    final defenders = _ids(action.payload['defenderIds']);

    // A depleted defence stopping a raider is worth double. The pad can force
    // the call either way — a referee's ruling beats the count — but by
    // default the engine decides it from the mat, which is what the rulebook
    // says and what the scorer should not have to remember.
    final isSuper = action.payload['super'] as bool? ??
        isSuperTackleNow(state, ctx, defending);
    final points = isSuper ? _superTackleValue(ctx) : _tackleValue(ctx);

    final raider =
        action.payload['playerId'] as String? ?? raiderId(state);

    var next = Map<String, dynamic>.from(state);
    next = _award(next, defending, tacklePts: points);
    // The raider is out; the defence revives one player per point.
    next[_courtKey(raiding)] = (onCourt(next, raiding) - 1).clamp(0, n);
    next = _pushOut(next, raiding, [if (raider != null) raider],
        _int(next, 'raidNo') + 1);
    next = _revive(next, defending, points, n);
    next[_emptyKey(raiding)] = 0;

    next = _record(
      next,
      ctx,
      side: defending,
      actorId: defenders.length == 1 ? defenders.first : null,
      result: isSuper ? 'Super Tackle' : 'Tackle',
      points: points,
      // Shared between everyone involved, which is how kabaddi credits a
      // tackle: a raider held by three defenders did not lose to one of them.
      tally: {
        _tacklePoints: points,
        if (isSuper) _superTackles: 1,
      },
      splitAcross: defenders,
      needs: [if (defenders.isEmpty) 'tackler'],
    );

    next['raiderId'] = null;
    next['raidingSide'] = defending.wire;
    next['nextRaiderId'] = null;

    return ScoringResult.ok(_settleAllOut(next, ctx));
  }

  // --- Technical, manual all-out, raider, substitution ---------------------

  ScoringResult _applyTechnical(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side gets the point?');
    }
    var next = _award(state, action.side, techPts: _technicalValue(ctx));
    next = _revive(next, action.side, _technicalValue(ctx), _onCourt(ctx));
    next = _record(
      next,
      ctx,
      side: action.side,
      actorId: null,
      result: 'Technical point',
      points: _technicalValue(ctx),
      tally: const {},
      // A technical point is the referee's, not a player's. Nothing to chase.
      needs: const [],
      countsAsRaid: false,
    );
    return ScoringResult.ok(_settleAllOut(next, ctx));
  }

  /// An all-out called by hand.
  ///
  /// [_settleAllOut] catches every all-out the engine can see, and on a
  /// correctly scored match this button is never needed. It exists because the
  /// engine can only see what it was told: a scorer who joined the match late,
  /// or who was catching up through a burst of raids, can be looking at an
  /// empty mat the state does not know about. Refusing them a way to say so
  /// would mean the only route back to a correct score is unpicking the log.
  ScoringResult _applyManualAllOut(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side got the all-out?');
    }
    final n = _onCourt(ctx);
    final scoring = action.side;
    var next = Map<String, dynamic>.from(state);
    next[_courtKey(scoring.opposite)] = 0;
    return ScoringResult.ok(_settleAllOut(next, ctx, forced: scoring, size: n));
  }

  ScoringResult _applySetRaider(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    final playerId = action.payload['playerId'] as String?;
    if (playerId == null) {
      return const ScoringResult.rejected('Who is raiding?');
    }
    final side = action.side == Side.neutral ? raidingSide(state) : action.side;
    final isNext = action.payload['next'] == true;
    return ScoringResult.ok(mutate(state, (s) {
      if (isNext) {
        s['nextRaiderId'] = playerId;
      } else {
        s['raiderId'] = playerId;
        s['raidingSide'] = side.wire;
      }
    }));
  }

  /// Swaps a named player for one off the bench.
  ///
  /// Moves names only, never the count: a substitution does not change how
  /// many people are on the mat, and letting it do so is exactly the two
  /// disagreeing sources of truth the class doc refuses.
  ScoringResult _applySubstitute(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side is substituting?');
    }
    final off = action.payload['offId'] as String?;
    final on = action.payload['onId'] as String?;
    if (off == null || on == null) {
      return const ScoringResult.rejected('Name who comes off and who comes on.');
    }
    if (off == on) {
      return const ScoringResult.rejected(
        'A player cannot be substituted for themselves.',
      );
    }
    final benched = benchedFor(state, action.side);
    if (benched.contains(off)) {
      return ScoringResult.rejected(
        '${ctx.playerName(off)} is already off.',
      );
    }
    if (!benched.contains(on) &&
        !matFor(state, ctx, action.side).contains(on) &&
        ctx.player(on) == null) {
      return ScoringResult.rejected('${ctx.playerName(on)} is not in the squad.');
    }

    var next = mutate(state, (s) {
      s['benched${_s(action.side)}'] = [...benched, off]
        ..removeWhere((id) => id == on);
    });
    // Coming on clears any record of having been out: the player on the mat
    // now is a different person from the one in the revival queue.
    next = mutate(next, (s) {
      s[_outKey(action.side)] = [
        for (final e in copyList(next[_outKey(action.side)]))
          if (e['id'] != on && e['id'] != off) e,
      ];
    });
    return ScoringResult.ok(_record(
      next,
      ctx,
      side: action.side,
      actorId: on,
      result: '${ctx.playerName(on)} on for ${ctx.playerName(off)}',
      points: 0,
      tally: const {},
      needs: const [],
      countsAsRaid: false,
    ));
  }

  // --- Completing a skipped detail ----------------------------------------

  /// Attaches the names a scorer had no time for to an event already scored.
  ///
  /// This is the second half of "score first, details second". The team score
  /// does not move — it was right the moment the button was pressed — and what
  /// changes is that the tally the pending entry has been carrying since is
  /// finally applied to the people it belongs to.
  ScoringResult _applyAttribute(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    final id = action.payload['id'] as String?;
    if (id == null) {
      return const ScoringResult.rejected('Which detail is being completed?');
    }
    final pending = pendingOf(state);
    final entry = pending.where((e) => e['id'] == id).firstOrNull;
    if (entry == null) {
      return const ScoringResult.rejected(
        'That detail has already been completed.',
      );
    }

    final actor = action.payload['playerId'] as String?;
    final others = _ids(action.payload['defenderIds']);
    if (actor == null && others.isEmpty) {
      return const ScoringResult.rejected('Name at least one player.');
    }

    final needs = _ids(entry['needs']);
    var next = Map<String, dynamic>.from(state);

    // The actor's tally — a raider's raid, a tackle split across whoever is
    // named — was computed when the event was scored and parked here.
    final tally = <String, num>{
      for (final e in (entry['tally'] as Map? ?? const {}).entries)
        if (e.value is num) e.key.toString(): e.value as num,
    };

    if (needs.contains('raider') && actor != null) {
      next = PlayerTally.addAll(next, actor, tally);
      next = _relabelHistory(next, entry['no'], actorId: actor);
    } else if (needs.contains('tackler')) {
      final tacklers = [if (actor != null) actor, ...others];
      for (final t in tacklers) {
        next = PlayerTally.addAll(next, t, {
          for (final e in tally.entries) e.key: e.value / tacklers.length,
        });
      }
      next = _relabelHistory(next, entry['no'],
          actorId: tacklers.length == 1 ? tacklers.first : null);
    }

    if (needs.contains('defenders')) {
      final side = Side.fromWire(entry['defendingSide'] as String?);
      final outs = [if (needs.contains('raider')) ...others else ...[
        if (actor != null) actor,
        ...others,
      ]];
      for (final d in outs) {
        next = PlayerTally.addAll(next, d, const {_timesOut: 1});
      }
      if (side != Side.neutral) {
        next = _pushOut(next, side, outs, (entry['no'] as num?)?.toInt() ?? 0);
      }
    }

    next[pendingKey] = [
      for (final e in pending)
        if (e['id'] != id) e,
    ];
    return ScoringResult.ok(next);
  }

  // --- Internal bookkeeping ------------------------------------------------

  static List<String> _ids(Object? raw) => raw is List
      ? [for (final e in raw) if (e is String && e.isNotEmpty) e]
      : const [];

  /// Adds points to a side's breakdown and keeps its total in step.
  ///
  /// The total is written here rather than derived on read because `a` and `b`
  /// are what every other part of the app — the league table, the fixture
  /// list, the share card — already reads off a match.
  Map<String, dynamic> _award(
    Map<String, dynamic> state,
    Side side, {
    int raidPts = 0,
    int tacklePts = 0,
    int bonusPts = 0,
    int allOutPts = 0,
    int techPts = 0,
  }) {
    final suffix = _s(side);
    return mutate(state, (s) {
      s['raidPts$suffix'] = _int(state, 'raidPts$suffix') + raidPts;
      s['tacklePts$suffix'] = _int(state, 'tacklePts$suffix') + tacklePts;
      s['bonusPts$suffix'] = _int(state, 'bonusPts$suffix') + bonusPts;
      s['allOutPts$suffix'] = _int(state, 'allOutPts$suffix') + allOutPts;
      s['techPts$suffix'] = _int(state, 'techPts$suffix') + techPts;
      s[_sideKey(side)] = _int(state, _sideKey(side)) +
          raidPts +
          tacklePts +
          bonusPts +
          allOutPts +
          techPts;
    });
  }

  /// Adds named players to a side's revival queue, in raid order.
  ///
  /// Guarded against over-filling: the queue may never claim more people are
  /// out than the authoritative count says. That guard is what makes a name
  /// supplied late safe — if the count says everyone the scorer skipped has
  /// already been revived, the late name is credited in the stats and not put
  /// back into a queue it has left.
  Map<String, dynamic> _pushOut(
    Map<String, dynamic> state,
    Side side,
    List<String> ids,
    int raidNo,
  ) {
    if (ids.isEmpty) return state;
    final queue = copyList(state[_outKey(side)]);
    final known = {for (final e in queue) e['id']};
    for (final id in ids) {
      if (known.contains(id)) continue;
      queue.add({'id': id, 'no': raidNo});
    }
    queue.sort((x, y) =>
        ((x['no'] as num?) ?? 0).compareTo((y['no'] as num?) ?? 0));
    return mutate(state, (s) => s[_outKey(side)] = queue);
  }

  /// Brings [count] players back, oldest out first, and moves the mat count.
  Map<String, dynamic> _revive(
    Map<String, dynamic> state,
    Side side,
    int count,
    int size,
  ) {
    if (count <= 0) return state;
    final current = onCourt(state, side);
    final target = (current + count).clamp(0, size);
    final queue = copyList(state[_outKey(side)]);
    // Never leave the queue claiming more are out than the count allows.
    final maxOut = size - target;
    while (queue.length > maxOut && queue.isNotEmpty) {
      queue.removeAt(0);
    }
    return mutate(state, (s) {
      s[_courtKey(side)] = target;
      s[_outKey(side)] = queue;
    });
  }

  /// Writes one line into the raid ledger, applies or parks the player tally,
  /// and bumps the raid number.
  Map<String, dynamic> _record(
    Map<String, dynamic> state,
    ScoringContext ctx, {
    required Side side,
    required String? actorId,
    required String result,
    required int points,
    required Map<String, num> tally,
    required List<String> needs,
    List<String> splitAcross = const [],
    int defendersMissing = 0,
    Side? defendingSide,
    bool countsAsRaid = true,
  }) {
    var next = Map<String, dynamic>.from(state);
    final no = countsAsRaid ? _int(next, 'raidNo') + 1 : _int(next, 'raidNo');
    if (countsAsRaid) next['raidNo'] = no;

    // Credit whoever was named. A tackle splits across everybody who held the
    // raider; a raid has one raider.
    final named = splitAcross.isNotEmpty
        ? splitAcross
        : [if (actorId != null) actorId];
    if (tally.isNotEmpty && named.isNotEmpty) {
      for (final p in named) {
        next = PlayerTally.addAll(next, p, {
          for (final e in tally.entries) e.key: e.value / named.length,
        });
      }
    }

    next[historyKey] = [
      ...historyOf(next),
      {
        'no': no,
        // Whether this line is a raid or something between raids — a technical
        // point, an all-out, a substitution. The ledger numbers raids, so a
        // non-raid line borrows the number of the raid it followed and the pad
        // needs to know not to print it as one.
        'kind': countsAsRaid ? 'raid' : 'event',
        'at': matchMinute(next),
        'period': currentPeriod(next),
        'side': side.wire,
        'actorId': actorId ?? (named.length == 1 ? named.first : null),
        'result': result,
        'points': points,
        'a': _int(next, 'a'),
        'b': _int(next, 'b'),
      },
    ];

    if (needs.isNotEmpty) {
      next = _pend(
        next,
        no: no,
        side: side,
        result: result,
        points: points,
        // Parked, not lost: this is applied to whoever is named later.
        tally: named.isEmpty ? tally : const {},
        needs: needs,
        defendersMissing: defendersMissing,
        defendingSide: defendingSide,
      );
    }
    return next;
  }

  /// Parks an unfinished detail on the queue.
  Map<String, dynamic> _pend(
    Map<String, dynamic> state, {
    required int no,
    required Side side,
    required String result,
    required int points,
    required Map<String, num> tally,
    required List<String> needs,
    required int defendersMissing,
    Side? defendingSide,
  }) =>
      mutate(state, (s) => s[pendingKey] = [
            ...pendingOf(state),
            {
              'id': 'p$no',
              'no': no,
              'at': matchMinute(state),
              'side': side.wire,
              'result': result,
              'points': points,
              'tally': tally,
              'needs': needs,
              'defendersMissing': defendersMissing,
              if (defendingSide != null) 'defendingSide': defendingSide.wire,
            },
          ]);

  /// Names the actor on an already-written ledger line, once they are known.
  Map<String, dynamic> _relabelHistory(
    Map<String, dynamic> state,
    Object? no, {
    String? actorId,
  }) {
    if (actorId == null) return state;
    return mutate(state, (s) => s[historyKey] = [
          for (final line in historyOf(state))
            if (line['no'] == no) {...line, 'actorId': actorId} else line,
        ]);
  }

  String _describeRaid({
    required int touched,
    required bool bonus,
    required int scored,
    required bool raiderOut,
    required bool failedDoOrDie,
    required bool superRaid,
  }) {
    if (failedDoOrDie) return 'Do-or-Die failed';
    if (scored == 0) return raiderOut ? 'Raider out' : 'Empty Raid';
    final parts = <String>[
      if (superRaid) 'Super Raid',
      if (touched > 0 && !superRaid) 'Touch $touched',
      if (bonus) 'Bonus',
    ];
    final base = parts.isEmpty ? 'Raid' : parts.join(' + ');
    return raiderOut ? '$base, raider out' : base;
  }

  /// An emptied mat is an all-out: bonus points and the side comes back.
  Map<String, dynamic> _settleAllOut(
    Map<String, dynamic> state,
    ScoringContext ctx, {
    Side? forced,
    int? size,
  }) {
    final n = size ?? _onCourt(ctx);
    final bonus = _allOutBonus(ctx);
    var next = Map<String, dynamic>.from(state);

    final scoring = forced ??
        (onCourt(next, Side.a) <= 0
            ? Side.b
            : onCourt(next, Side.b) <= 0
                ? Side.a
                : null);
    if (scoring == null) return next;

    next = _award(next, scoring, allOutPts: bonus);
    next = mutate(next, (s) {
      s['allOuts${_s(scoring)}'] = _int(next, 'allOuts${_s(scoring)}') + 1;
      // Both sides return to full strength, and neither has anyone waiting.
      s['onCourtA'] = n;
      s['onCourtB'] = n;
      s['outA'] = <Map<String, dynamic>>[];
      s['outB'] = <Map<String, dynamic>>[];
    });
    return _record(
      next,
      ctx,
      side: scoring,
      actorId: null,
      result: 'All Out',
      points: bonus,
      tally: const {},
      needs: const [],
      countsAsRaid: false,
    );
  }

  // --- Statistics ----------------------------------------------------------

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
      '${onCourt(state, Side.a)} v ${onCourt(state, Side.b)} on the mat',
    ];
    if (isDoOrDie(state, Side.a, ctx)) {
      parts.add('${ctx.entrantAName}: DO OR DIE');
    }
    if (isDoOrDie(state, Side.b, ctx)) {
      parts.add('${ctx.entrantBName}: DO OR DIE');
    }
    final pending = pendingOf(state).length;
    if (pending > 0) parts.add('$pending detail${pending == 1 ? '' : 's'} pending');
    return parts.join(' · ');
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = _int(state, 'a');
    final b = _int(state, 'b');
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

    final raiding = raidingSide(state);
    final defending = raiding.opposite;
    final bonusLive = isBonusAvailable(state, ctx, raiding);
    final superNow = isSuperTackleNow(state, ctx, defending);
    final n = _onCourt(ctx);

    // No player prompts on any of these, and that is the design rather than an
    // omission — see the class doc. Naming the raider is a separate, optional
    // action ("Change"), and everything the scorer skips is recoverable from
    // the pending queue.
    return [
      ScoreControlGroup(
        title: '${ctx.nameFor(raiding)} raiding',
        controls: [
          ScoreControl(
            action: 'raid',
            label: 'Touch 1',
            side: raiding,
            style: ControlStyle.primary,
            payload: const {'touched': 1},
            shortcut: '1',
            tooltip: '+${_touchPoints(ctx)}',
          ),
          ScoreControl(
            action: 'raid',
            label: 'Touch 2',
            side: raiding,
            style: ControlStyle.primary,
            payload: const {'touched': 2},
            shortcut: '2',
            tooltip: '+${2 * _touchPoints(ctx)}',
          ),
          ScoreControl(
            action: 'raid',
            label: 'Touch 3',
            side: raiding,
            style: ControlStyle.primary,
            payload: const {'touched': 3},
            shortcut: '3',
            tooltip: 'Super raid — +${3 * _touchPoints(ctx)}',
          ),
          if (bonusLive)
            ScoreControl(
              action: 'raid',
              label: 'Bonus',
              side: raiding,
              style: ControlStyle.primary,
              payload: const {'touched': 0, 'bonus': true},
              shortcut: 'b',
              tooltip: '+${_bonusValue(ctx)}',
            ),
          if (bonusLive)
            ScoreControl(
              action: 'raid',
              label: 'Touch + Bonus',
              side: raiding,
              payload: const {'touched': 1, 'bonus': true},
              tooltip: '+${_touchPoints(ctx) + _bonusValue(ctx)}',
            ),
          ScoreControl(
            action: 'raid',
            label: 'Empty raid',
            side: raiding,
            style: ControlStyle.subtle,
            payload: const {'touched': 0},
            shortcut: 'e',
            tooltip: isDoOrDie(state, raiding, ctx)
                ? 'Do-or-Die — the raider goes out and the point goes to '
                    '${ctx.nameFor(defending)}'
                : 'No points',
          ),
          ScoreControl(
            action: 'raid',
            label: 'Raider out',
            side: raiding,
            style: ControlStyle.danger,
            payload: const {'touched': 0, 'raiderOut': true},
            tooltip: 'Out without a tackle being credited',
          ),
        ],
      ),
      ScoreControlGroup(
        title: '${ctx.nameFor(defending)} defending',
        controls: [
          ScoreControl(
            action: 'tackle',
            label: superNow ? 'Super Tackle' : 'Tackle',
            side: defending,
            style: ControlStyle.primary,
            shortcut: 't',
            tooltip: superNow
                ? '+${_superTackleValue(ctx)} — ${onCourt(state, defending)} '
                    'defenders on the mat'
                : '+${_tackleValue(ctx)}',
          ),
          // Offered explicitly as well, because the referee's ruling beats the
          // count: a defender stepping back over the line at the moment of the
          // hold changes what the tackle was worth, and the engine cannot see
          // that.
          if (!superNow)
            ScoreControl(
              action: 'tackle',
              label: 'Super Tackle',
              side: defending,
              payload: const {'super': true},
              tooltip: '+${_superTackleValue(ctx)}',
            ),
        ],
      ),
      ScoreControlGroup(
        title: 'Referee',
        controls: [
          for (final side in [Side.a, Side.b])
            ScoreControl(
              action: 'technical',
              label: 'Technical — ${ctx.nameFor(side)}',
              side: side,
              style: ControlStyle.secondary,
              tooltip: '+${_technicalValue(ctx)}',
            ),
          for (final side in [Side.a, Side.b])
            if (onCourt(state, side.opposite) > 0 &&
                onCourt(state, side.opposite) <= n)
              ScoreControl(
                action: 'all_out',
                label: 'All Out — ${ctx.nameFor(side)}',
                side: side,
                style: ControlStyle.secondary,
                tooltip: '+${_allOutBonus(ctx)} and both sides come back',
              ),
        ],
      ),
      // The other half of "score first, details second". These are the points
      // already on the board that nobody has been named for yet, and they are
      // controls rather than a panel so that EVERY pad can clear the queue —
      // see [attributeControl].
      if (pendingOf(state).isNotEmpty)
        ScoreControlGroup(
          title: 'Details pending',
          controls: [
            // The oldest first, and only a handful: the tray has room for
            // about six, and a scorer catching up works from the back of the
            // queue anyway.
            for (final d in pendingOf(state).take(6))
              attributeControl(
                d,
                label: '#${d['no']} ${_pendingQuestion(d)}',
              ),
          ],
        ),
      ScoreControlGroup(
        title: 'Match',
        controls: [
          for (final side in [Side.a, Side.b])
            if (timeoutControl(state, ctx, side) case final c?) c,
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

  // --- The board -----------------------------------------------------------

  @override
  PadLayout get padLayout => PadLayout.mat;

  @override
  MatBoard? matBoard(Map<String, dynamic> state, ScoringContext ctx) {
    final raiding = raidingSide(state);
    final n = _onCourt(ctx);
    final minutes = periodMinutes(ctx);

    return MatBoard(
      a: _matSide(state, ctx, Side.a, raiding, n),
      b: _matSide(state, ctx, Side.b, raiding, n),
      periodLabel: '${_ordinal(currentPeriod(state))} ${periodNoun(ctx)}',
      // Minutes, not minutes and seconds. The engine's clock only advances
      // when an event carries one, so printing "12:34" would be inventing a
      // precision the record does not have — and a scoreboard that invents
      // its own numbers is the thing a disputed result cannot be settled
      // against.
      clock: minutes <= 0 ? null : "${matchMinute(state)}'",
      clockOf: minutes <= 0 ? null : "of ${minutes * periodCount(ctx)}'",
      actionClockSeconds: raidClockSeconds(ctx),
      actionClockLabel: 'RAID TIMER',
      turn: state['complete'] == true ? null : _turn(state, ctx, raiding),
      history: [
        for (final h in historyOf(state))
          MatPlay(
            no: (h['no'] as num?)?.toInt() ?? 0,
            side: Side.fromWire(h['side'] as String?),
            result: h['result'] as String? ?? '',
            points: (h['points'] as num?)?.toInt() ?? 0,
            scoreA: (h['a'] as num?)?.toInt() ?? 0,
            scoreB: (h['b'] as num?)?.toInt() ?? 0,
            at: minutes <= 0 ? null : "${(h['at'] as num?)?.toInt() ?? 0}'",
            actor: h['actorId'] == null
                ? null
                : ctx.player(h['actorId'] as String)?.name,
            isTurn: h['kind'] != 'event',
          ),
      ],
      pending: [
        for (final d in pendingOf(state)) _detail(d, ctx),
      ],
      scorecardColumns: const [
        'Raid Pts',
        'Tackle Pts',
        'Bonus',
        'All Out',
        'Tech',
        'Total',
      ],
      scorecard: [
        for (final side in [Side.a, Side.b])
          MatTotals(
            side: side,
            name: ctx.nameFor(side),
            values: [
              raidPointsFor(state, side),
              tacklePointsFor(state, side),
              bonusPointsFor(state, side),
              allOutPointsFor(state, side),
              technicalPointsFor(state, side),
              scoreFor(state, side),
            ],
          ),
      ],
      status: statusLine(state, ctx),
    );
  }

  MatSide _matSide(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
    Side raiding,
    int n,
  ) {
    final actor = raiderId(state);
    MatPlayerChip chip(String id) {
      final p = ctx.player(id);
      return MatPlayerChip(
        id: id,
        name: p?.name ?? 'Player',
        number: p?.jerseyNumber,
        isActor: id == actor && side == raiding,
      );
    }

    return MatSide(
      name: ctx.nameFor(side),
      score: scoreFor(state, side),
      chips: [
        MatChip('Raid Pts', '${raidPointsFor(state, side)}'),
        MatChip('Tackle Pts', '${tacklePointsFor(state, side)}'),
      ],
      active: [for (final id in matFor(state, ctx, side)) chip(id)],
      out: [for (final id in outQueue(state, side)) chip(id)],
      strength: onCourt(state, side),
      fullStrength: n,
      onTheAttack: side == raiding && state['complete'] != true,
      // The one thing the scorer must not have to work out for themselves:
      // this side's next raid has to score or the raider is gone.
      alert: isDoOrDie(state, side, ctx) ? 'DO OR DIE' : null,
    );
  }

  MatTurn _turn(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side raiding,
  ) {
    final actor = ctx.player(raiderId(state));
    final next = ctx.player(nextRaiderId(state));
    return MatTurn(
      side: raiding,
      title: 'CURRENT RAIDER',
      actorName: actor?.name,
      actorNumber: actor?.jerseyNumber,
      counterLabel: 'DEFENDERS ON MAT',
      counterValue: onCourt(state, raiding.opposite),
      nextTitle: '${ctx.nameFor(raiding.opposite)} raid next',
      nextName: next?.name,
      // Offered, never required. Naming the raider is the detail; the point
      // is the score, and the score never waits for it.
      change: ctx.lineupFor(raiding).isEmpty
          ? null
          : ScoreControl(
              action: 'set_raider',
              label: actor == null ? 'Name raider' : 'Change',
              side: raiding,
              style: ControlStyle.subtle,
              prompts: const [
                PlayerPrompt(key: 'playerId', label: 'Who is raiding?'),
              ],
            ),
    );
  }

  MatDetail _detail(Map<String, dynamic> d, ScoringContext ctx) => MatDetail(
        id: d['id'] as String? ?? '',
        title: _pendingTitle(d),
        question: _pendingQuestion(d),
        side: Side.fromWire(d['side'] as String?),
        complete: attributeControl(d, label: 'Add'),
      );

  static String _pendingTitle(Map<String, dynamic> d) {
    final no = (d['no'] as num?)?.toInt() ?? 0;
    final points = (d['points'] as num?)?.toInt() ?? 0;
    return 'Raid #$no — ${d['result']}${points > 0 ? ' (+$points)' : ''}';
  }

  static String _pendingQuestion(Map<String, dynamic> d) {
    final needs = _ids(d['needs']);
    return [
      if (needs.contains('raider')) 'Raider?',
      if (needs.contains('tackler')) 'Tackler?',
      if (needs.contains('defenders')) 'Players out?',
    ].join(' · ');
  }

  /// The control that completes one parked detail, asking exactly the
  /// questions that detail is still missing.
  ///
  /// Public and built here rather than inside the board, because a kabaddi
  /// match must be completable from the ORDINARY pad too. A pad that only
  /// offered this on the mat layout would mean a queue that could be filled
  /// and never emptied on any screen that fell back to the stacked one — and
  /// a detail that can only be entered is not a detail, it is a leak.
  ScoreControl attributeControl(
    Map<String, dynamic> d, {
    required String label,
  }) {
    final side = Side.fromWire(d['side'] as String?);
    final needs = _ids(d['needs']);
    final missing = (d['defendersMissing'] as num?)?.toInt() ?? 0;

    return ScoreControl(
      action: 'attribute',
      label: label,
      side: side,
      style: ControlStyle.secondary,
      payload: {'id': d['id']},
      prompts: [
          if (needs.contains('raider'))
            const PlayerPrompt(key: 'playerId', label: 'Who raided?'),
          if (needs.contains('tackler'))
            const PlayerPrompt(
              key: 'defenderIds',
              label: 'Who made the tackle?',
              multiple: true,
            ),
          if (needs.contains('defenders'))
            PlayerPrompt(
              // The defenders belong to the side that did NOT score, which is
              // what `opposingSide` means relative to this control's side.
              // Always the plural key: the raid's own raider is asked for
              // under `playerId` above, and a multi-select writing a list
              // into a single-id key is how a prompt silently fails.
              key: 'defenderIds',
              label: missing == 1
                  ? 'Which defender went out?'
                  : 'Which $missing defenders went out?',
              from: PromptSource.opposingSide,
              multiple: true,
            ),
      ],
    );
  }

  static String _ordinal(int n) => switch (n) {
        1 => '1st',
        2 => '2nd',
        3 => '3rd',
        _ => '${n}th',
      };

  @override
  MatchEventLine? describeEvent(MatchEvent event, ScoringContext ctx) {
    final side = Side.fromWire(event.payload['side'] as String?);
    switch (event.type) {
      case 'raid':
        final touched = (event.payload['touched'] as num?)?.toInt() ?? 0;
        final text = _describeRaid(
          touched: touched,
          bonus: event.payload['bonus'] == true,
          scored: touched,
          raiderOut: event.payload['raiderOut'] == true,
          failedDoOrDie: false,
          superRaid: false,
        );
        return MatchEventLine(text: '${ctx.nameFor(side)} — $text', side: side);
      case 'tackle':
        return MatchEventLine(
          text: '${ctx.nameFor(side)} — tackle',
          side: side,
        );
      case 'technical':
        return MatchEventLine(
          text: '${ctx.nameFor(side)} — technical point',
          side: side,
        );
      case 'all_out':
        return MatchEventLine(
          text: '${ctx.nameFor(side)} — all out',
          side: side,
          isMilestone: true,
        );
      case 'attribute':
      case 'set_raider':
        // Bookkeeping. Real entries in the ledger, noise in a human's reading
        // of the match.
        return null;
      default:
        return super.describeEvent(event, ctx);
    }
  }
}
