import 'player_stats.dart';
import 'scoring_plugin.dart';

/// The mechanics that ten sports share and none of them own.
///
/// Periods, a match clock, substitutions, timeouts and reviews are not
/// football rules or basketball rules — they are *match* rules, worn slightly
/// differently by each sport. Before this file every engine that needed one
/// wrote its own, and the arithmetic showed it: five plugins carried the same
/// twelve-line `next_period` block, and the three things nobody had written
/// twice were simply absent everywhere.
///
/// Substitution was the expensive absence. Without it a scorer cannot record
/// that a player came off at 63 minutes, so **minutes played is uncomputable**
/// in football, hockey, basketball, volleyball and every other rolling-squad
/// sport. Minutes played is not a garnish on a career profile; it is the
/// denominator. "14 goals" means one thing in 900 minutes and another in 200,
/// and a platform whose promise is a lifelong verified record cannot answer
/// which. One framework here fixes that for every sport at once, which is why
/// it comes before any per-sport depth.
///
/// Everything below operates on the plugin state map and returns new maps.
/// Purity is not a style choice: the same code runs on the scorer's phone, in
/// a replay that rebuilds a disputed match from its event log, and later on
/// the server, and all three must agree exactly.

// ---------------------------------------------------------------------------
// Periods and the match clock
// ---------------------------------------------------------------------------

/// Matches divided into halves, quarters or timed periods.
///
/// Carries a **match minute** as well as a period number, because a period
/// index alone cannot answer "how long was he on the pitch". The minute is
/// deliberately *scorer-supplied and monotonic* rather than read from the
/// device clock: a wall clock in state would make a replay produce different
/// answers than the live match did, and a match scored in airplane mode on a
/// phone whose time is wrong would be silently wrong forever. A number written
/// into the event log is the only version that survives being rebuilt.
mixin PeriodedMatch on ScoringPlugin {
  static const periodKey = 'period';
  static const minuteKey = 'minute';

  /// The payload key a scorer's minute arrives under.
  static const minutePayloadKey = 'minute';

  int periodCount(ScoringContext ctx) => ctx.intConfig('periods', 2);

  /// "Half", "Quarter", "Period" — whatever this sport calls one.
  String periodNoun(ScoringContext ctx) =>
      ctx.stringConfig('periodLabel', 'Period');

  /// Scheduled length of one period. Zero means untimed, in which case the
  /// clock only ever moves when a scorer supplies a minute.
  int periodMinutes(ScoringContext ctx) => ctx.intConfig('periodMinutes', 0);

  Map<String, dynamic> periodInitialState(ScoringContext ctx) => {
        periodKey: 1,
        minuteKey: 0,
      };

  int currentPeriod(Map<String, dynamic> state) =>
      (state[periodKey] as num?)?.toInt() ?? 1;

  int matchMinute(Map<String, dynamic> state) =>
      (state[minuteKey] as num?)?.toInt() ?? 0;

  bool isFinalPeriod(Map<String, dynamic> state, ScoringContext ctx) =>
      currentPeriod(state) >= periodCount(ctx);

  /// Advances the clock to a minute an action carried, if it carried one.
  ///
  /// Monotonic on purpose. A scorer catching up — recording the 58th-minute
  /// substitution at 61 minutes — must not rewind the clock, because a stint
  /// that ends before it began produces negative minutes played, and a
  /// negative appears in a career total forever.
  Map<String, dynamic> withMinuteFrom(
    Map<String, dynamic> state,
    ScoreAction action,
  ) {
    final supplied = (action.payload[minutePayloadKey] as num?)?.toInt();
    if (supplied == null) return state;
    final now = matchMinute(state);
    if (supplied <= now) return state;
    return mutate(state, (s) => s[minuteKey] = supplied);
  }

  /// Handles `next_period`, or returns null when the action is not ours.
  ///
  /// The pattern throughout this file: a mixin claims the actions it knows and
  /// declines everything else by returning null, so a plugin's `apply` can
  /// offer each mixin the action in turn before reaching its own switch.
  ScoringResult? applyPeriodAction(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.type != 'next_period') return null;

    final period = currentPeriod(state);
    if (period >= periodCount(ctx)) {
      return ScoringResult.rejected(
        'This match has only ${periodCount(ctx)} '
        '${periodNoun(ctx).toLowerCase()}s. Use "End match" to finish.',
      );
    }

    // Ending a period moves the clock to that period's scheduled end unless
    // the match has already run past it. Injury time is real and a scorer who
    // supplies a minute is believed over the timetable.
    final scheduled = periodMinutes(ctx) * period;
    var next = withMinuteFrom(state, action);
    final now = matchMinute(next);
    return ScoringResult.ok(mutate(next, (s) {
      s[periodKey] = period + 1;
      if (scheduled > now) s[minuteKey] = scheduled;
    }));
  }

  /// "Half 2 of 2", plus the clock when the sport keeps one.
  String periodStatus(Map<String, dynamic> state, ScoringContext ctx) {
    final base = '${periodNoun(ctx)} ${currentPeriod(state)} '
        'of ${periodCount(ctx)}';
    if (periodMinutes(ctx) <= 0) return base;
    return "$base · ${matchMinute(state)}'";
  }

  /// Advances the clock to the end of the last period. Call from `finish`,
  /// before banking playing time.
  ///
  /// Without it the clock stops at whatever the last event stamped, so a match
  /// whose second half contained no substitutions ends showing 45 minutes and
  /// every player who lasted the whole game is credited with half of it.
  Map<String, dynamic> atFullTime(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final scheduled = periodMinutes(ctx) * periodCount(ctx);
    if (scheduled <= matchMinute(state)) return state;
    return mutate(state, (s) => s[minuteKey] = scheduled);
  }

  /// Deliberately carries no minute prompt. The timetable already knows when a
  /// half ends, and making a scorer type 45 to say so would put a dialog in
  /// front of one of the pad's most-pressed buttons. Injury time reaches the
  /// clock through the events that need it — a substitution names its minute.
  /// Offered from the moment the final period starts.
  ///
  /// Every sport that mixes this in has the same shape — a fixed number of
  /// periods, and a result that is whatever the score says when the last one
  /// ends — so the answer is the same for all of them and is written once
  /// here rather than five times. See [ScoringPlugin.finishControl].
  @override
  ScoreControl? finishControl(Map<String, dynamic> state, ScoringContext ctx) =>
      isFinalPeriod(state, ctx) ? endMatchControl : null;

  /// The control that records the final whistle. Danger-styled because it is
  /// the one press on the pad that cannot be taken back with an undo.
  static const endMatchControl = ScoreControl(
    action: 'finish',
    label: 'End match',
    style: ControlStyle.danger,
    shortcut: 'f',
  );

  ScoreControl nextPeriodControl(ScoringContext ctx) => ScoreControl(
        action: 'next_period',
        label: 'Next ${periodNoun(ctx).toLowerCase()}',
        style: ControlStyle.secondary,
        shortcut: 'n',
      );
}

// ---------------------------------------------------------------------------
// Substitutions and playing time
// ---------------------------------------------------------------------------

/// Squads where players come off and others come on.
///
/// Models who is *currently on* rather than only who was named, which is the
/// distinction that makes minutes played, "on the pitch at the time", and a
/// legal-substitution check all possible from the same state.
///
/// Two rules differ enough between sports to be configuration rather than
/// code, and getting either wrong invalidates a team sheet:
///
///  * **How many substitutions a side gets.** Five in football, unlimited in
///    hockey and basketball, six per set in volleyball.
///  * **Whether a substituted player may return.** Football says no and hockey
///    says yes, and an engine that assumes either one is wrong for half the
///    sports it serves.
mixin SquadRotation on ScoringPlugin {
  static const onCourtKey = 'onCourt';
  static const onSinceKey = 'onSince';
  static const subsUsedKey = 'subsUsed';
  static const subbedOffKey = 'subbedOff';
  static const subLogKey = 'subLog';

  /// Tally key playing time accumulates under. Read by the box score and, in
  /// time, by the career aggregator — which is the whole point of it existing.
  static const minutesStat = 'minutesPlayed';

  /// Whether playing time is worth accumulating for this sport.
  ///
  /// False for volleyball: rotations and substitutions there are counted per
  /// set and the match has no running clock, so a minutes column would be a
  /// number nobody at the venue could check.
  bool get tracksPlayingTime => true;

  /// How many of a squad are on the field at once. Zero means the whole named
  /// squad starts — right for a five-a-side kickabout where eleven turned up
  /// and all eleven play.
  int squadOnField(ScoringContext ctx) {
    for (final key in const ['squadSize', 'playersOnCourt', 'playersPerTeam']) {
      if (ctx.rules.has(key)) return ctx.intConfig(key, 0);
    }
    return 0;
  }

  /// Substitutions allowed per side. Zero means unlimited.
  int substitutionAllowance(ScoringContext ctx) =>
      ctx.intConfig('maxSubstitutions', 0);

  /// Whether a player who has come off may go back on.
  bool allowsReturn(ScoringContext ctx) =>
      ctx.boolConfig('allowReturn', false);

  /// The clock substitutions are stamped against.
  ///
  /// Defaults to the match minute [PeriodedMatch] maintains, so a plugin that
  /// mixes both gets playing time for free. A sport without a clock overrides
  /// this — volleyball stamps the set number — and simply reports no minutes.
  int rotationClock(Map<String, dynamic> state) =>
      (state[PeriodedMatch.minuteKey] as num?)?.toInt() ?? 0;

  /// Writes the clock. The counterpart of [rotationClock]; a sport that
  /// overrides one overrides both.
  Map<String, dynamic> withRotationClock(
    Map<String, dynamic> state,
    int value,
  ) =>
      mutate(state, (s) => s[PeriodedMatch.minuteKey] = value);

  /// Moves the clock to a minute the scorer supplied with this action.
  ///
  /// Deliberately not delegated to [PeriodedMatch]: volleyball substitutes
  /// without any notion of a period, and constraining this mixin to that one
  /// would make a set-based sport declare halves it does not play. Both write
  /// the same state key, and both refuse to move it backwards — a stint that
  /// ends before it began produces negative minutes, and a negative in a
  /// career total is permanent.
  Map<String, dynamic> adoptClock(
    Map<String, dynamic> state,
    ScoreAction action,
  ) {
    final supplied =
        (action.payload[PeriodedMatch.minutePayloadKey] as num?)?.toInt();
    if (supplied == null || supplied <= rotationClock(state)) return state;
    return withRotationClock(state, supplied);
  }

  /// Who takes the field at the start.
  ///
  /// The first N of the team sheet. That is a convention rather than a
  /// declaration — the line-up editor names a squad, it does not yet pick a
  /// starting XI — so `set_starters` exists to correct it before kick-off, and
  /// until someone does, a bench player's minutes are the one thing here that
  /// can be wrong. Wrong-and-correctable beats absent: today the number cannot
  /// be produced at all.
  List<String> startersFor(ScoringContext ctx, Side side) {
    final squad = ctx.lineupFor(side).map((p) => p.id).toList();
    final n = squadOnField(ctx);
    if (n <= 0 || squad.length <= n) return squad;
    return squad.sublist(0, n);
  }

  Map<String, dynamic> rotationInitialState(ScoringContext ctx) {
    final start = <String, int>{};
    for (final side in const [Side.a, Side.b]) {
      for (final id in startersFor(ctx, side)) {
        start[id] = 0;
      }
    }
    return {
      onCourtKey: {
        'a': startersFor(ctx, Side.a),
        'b': startersFor(ctx, Side.b),
      },
      // When each player's current stint began, by the rotation clock.
      onSinceKey: start,
      subsUsedKey: {'a': 0, 'b': 0},
      // Everyone who has been taken off, so a no-return ruleset can enforce it.
      subbedOffKey: <String>[],
      subLogKey: <Map<String, dynamic>>[],
    };
  }

  List<String> onCourt(Map<String, dynamic> state, Side side) {
    final all = state[onCourtKey] as Map? ?? const {};
    final mine = all[side.wire] as List? ?? const [];
    return mine.whereType<String>().toList();
  }

  bool isOnCourt(Map<String, dynamic> state, String playerId) =>
      onCourt(state, Side.a).contains(playerId) ||
      onCourt(state, Side.b).contains(playerId);

  /// Named in the squad and not currently on.
  List<String> benchFor(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) {
    final playing = onCourt(state, side).toSet();
    return [
      for (final p in ctx.lineupFor(side))
        if (!playing.contains(p.id)) p.id,
    ];
  }

  int substitutionsUsed(Map<String, dynamic> state, Side side) {
    final used = state[subsUsedKey] as Map? ?? const {};
    return (used[side.wire] as num?)?.toInt() ?? 0;
  }

  List<String> _subbedOff(Map<String, dynamic> state) =>
      (state[subbedOffKey] as List?)?.whereType<String>().toList() ?? const [];

  Map<String, int> _onSince(Map<String, dynamic> state) {
    final raw = state[onSinceKey] as Map? ?? const {};
    return {
      for (final e in raw.entries)
        e.key.toString(): ((e.value as num?) ?? 0).toInt(),
    };
  }

  /// Playing time so far, including the stint in progress.
  ///
  /// Derived rather than only accumulated, so the number a scorer sees during
  /// the match and the number on the finished card come from the same place.
  num playingTimeFor(Map<String, dynamic> state, String playerId) {
    final banked = PlayerTally.of(state, playerId)[minutesStat] ?? 0;
    final since = _onSince(state)[playerId];
    if (since == null) return banked;
    final live = rotationClock(state) - since;
    return banked + (live > 0 ? live : 0);
  }

  /// Handles `substitution` and `set_starters`, or returns null.
  ScoringResult? applyRotationAction(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    switch (action.type) {
      case 'set_starters':
        return _applyStarters(state, action, ctx);
      case 'substitution':
        return _applySubstitution(state, action, ctx);
      default:
        return null;
    }
  }

  ScoringResult _applyStarters(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side is this line-up for?');
    }
    // Once the match has moved, changing who started would rewrite minutes
    // already banked. A substitution is the honest way to change the eleven
    // after kick-off, and it leaves a trail.
    if (rotationClock(state) > 0 ||
        substitutionsUsed(state, action.side) > 0) {
      return const ScoringResult.rejected(
        'The starting line-up can only be set before the match begins. '
        'Substitute instead — it keeps the change on the record.',
      );
    }

    final raw = action.payload['starters'];
    final ids = raw is List ? raw.whereType<String>().toList() : const <String>[];
    if (ids.isEmpty) {
      return const ScoringResult.rejected('Who is starting?');
    }

    final squad = ctx.lineupFor(action.side).map((p) => p.id).toSet();
    for (final id in ids) {
      if (!squad.contains(id)) {
        return ScoringResult.rejected(
          '${ctx.playerName(id)} is not in this squad.',
        );
      }
    }
    final limit = squadOnField(ctx);
    if (limit > 0 && ids.length > limit) {
      return ScoringResult.rejected(
        'Only $limit can be on at once — that is ${ids.length}.',
      );
    }

    final court = Map<String, dynamic>.from(state[onCourtKey] as Map? ?? {});
    court[action.side.wire] = ids;

    // Everybody previously marked as starting for this side stops being so.
    final since = _onSince(state)
      ..removeWhere((id, _) => squad.contains(id));
    for (final id in ids) {
      since[id] = 0;
    }

    return ScoringResult.ok({
      ...state,
      onCourtKey: court,
      onSinceKey: since,
    });
  }

  ScoringResult _applySubstitution(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side is substituting?');
    }
    final side = action.side;
    final off = action.payload['playerOffId'] as String?;
    final on = action.payload['playerOnId'] as String?;
    if (off == null) return const ScoringResult.rejected('Who comes off?');
    if (on == null) return const ScoringResult.rejected('Who comes on?');
    if (off == on) {
      return const ScoringResult.rejected(
        'A player cannot be substituted for themselves.',
      );
    }

    final playing = onCourt(state, side);
    if (!playing.contains(off)) {
      return ScoringResult.rejected(
        '${ctx.playerName(off)} is not on — nothing to substitute.',
      );
    }
    final squad = ctx.lineupFor(side).map((p) => p.id).toSet();
    if (!squad.contains(on)) {
      return ScoringResult.rejected(
        '${ctx.playerName(on)} is not in this squad.',
      );
    }
    if (playing.contains(on)) {
      return ScoringResult.rejected(
        '${ctx.playerName(on)} is already on.',
      );
    }
    if (!allowsReturn(ctx) && _subbedOff(state).contains(on)) {
      return ScoringResult.rejected(
        '${ctx.playerName(on)} has already been substituted and cannot '
        'return under these rules.',
      );
    }

    final allowance = substitutionAllowance(ctx);
    final used = substitutionsUsed(state, side);
    if (allowance > 0 && used >= allowance) {
      return ScoringResult.rejected(
        '${ctx.nameFor(side)} has used all $allowance substitutions.',
      );
    }

    var next = adoptClock(state, action);
    final at = rotationClock(next);

    // Bank the outgoing player's stint before the clock moves on. Doing it
    // here rather than at full time is what makes the number correct for a
    // player who comes off, goes back on, and comes off again.
    if (tracksPlayingTime) {
      final since = _onSince(next)[off];
      if (since != null && at > since) {
        next = PlayerTally.add(next, off, minutesStat, at - since);
      }
    }

    final court = Map<String, dynamic>.from(next[onCourtKey] as Map? ?? {});
    court[side.wire] = [
      for (final id in playing)
        if (id != off) id,
      on,
    ];

    final since = _onSince(next)
      ..remove(off)
      ..[on] = at;

    final log = copyList(next[subLogKey])
      ..add({
        'side': side.wire,
        'off': off,
        'on': on,
        'at': at,
        'period': next[PeriodedMatch.periodKey] ?? 1,
      });

    final usedMap = Map<String, dynamic>.from(next[subsUsedKey] as Map? ?? {});
    usedMap[side.wire] = used + 1;

    return ScoringResult.ok({
      ...next,
      onCourtKey: court,
      onSinceKey: since,
      subsUsedKey: usedMap,
      subbedOffKey: [..._subbedOff(next), off],
      subLogKey: log,
    });
  }

  /// Refills the substitution allowance and clears the no-return record.
  ///
  /// For sports whose allowance is per set rather than per match — volleyball
  /// gets six a set, not six a match. Called by the plugin at the boundary,
  /// because only the plugin knows where its boundaries are.
  Map<String, dynamic> resetSubstitutions(Map<String, dynamic> state) => {
        ...state,
        subsUsedKey: {'a': 0, 'b': 0},
        subbedOffKey: <String>[],
      };

  /// Takes a player off the field for good, banking the stint they were in.
  ///
  /// A dismissal is not a substitution: no allowance is spent and nobody comes
  /// on. But it does end that player's afternoon, and if the field state does
  /// not say so, their minutes keep accruing until full time — a red card in
  /// the 20th minute would read as ninety minutes played.
  Map<String, dynamic> removeFromField(
    Map<String, dynamic> state,
    String playerId,
  ) {
    var next = state;
    final at = rotationClock(state);
    final since = _onSince(state);

    if (tracksPlayingTime && since[playerId] != null) {
      final played = at - since[playerId]!;
      if (played > 0) {
        next = PlayerTally.add(next, playerId, minutesStat, played);
      }
    }
    since.remove(playerId);

    final court = Map<String, dynamic>.from(next[onCourtKey] as Map? ?? {});
    for (final side in const [Side.a, Side.b]) {
      final playing = onCourt(next, side);
      if (playing.contains(playerId)) {
        court[side.wire] = [
          for (final id in playing)
            if (id != playerId) id,
        ];
      }
    }

    return {...next, onCourtKey: court, onSinceKey: since};
  }

  /// Banks the playing time of everyone still on. Call from `finish`.
  ///
  /// Without this the eight players who were never substituted — the majority
  /// of any team sheet — finish the match with zero minutes, which is exactly
  /// backwards: they are the ones who played the whole game.
  Map<String, dynamic> closePlayingTime(Map<String, dynamic> state) {
    if (!tracksPlayingTime) return state;
    final at = rotationClock(state);
    var next = state;
    for (final entry in _onSince(state).entries) {
      final played = at - entry.value;
      if (played > 0) {
        next = PlayerTally.add(next, entry.key, minutesStat, played);
      }
    }
    return {...next, onSinceKey: <String, int>{}};
  }

  /// Re-opens the stints of everyone on the field. Call from `reopen`, so a
  /// match corrected after full time does not leave its players frozen with
  /// the clock still running.
  Map<String, dynamic> reopenPlayingTime(Map<String, dynamic> state) {
    if (!tracksPlayingTime) return state;
    final at = rotationClock(state);
    final since = _onSince(state);
    for (final side in const [Side.a, Side.b]) {
      for (final id in onCourt(state, side)) {
        since[id] = at;
      }
    }
    return {...state, onSinceKey: since};
  }

  /// The substitution button for one side, with both pickers scoped to the
  /// people who could actually be involved: on-court for who comes off, bench
  /// for who comes on. Scoping them is not a nicety — an unscoped picker on an
  /// eighteen-player squad is how a scorer substitutes a player who is already
  /// on and only finds out from the rejection.
  ScoreControl? substitutionControl(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) {
    final allowance = substitutionAllowance(ctx);
    final used = substitutionsUsed(state, side);
    final remaining = allowance > 0 ? allowance - used : null;

    // No bench, no button. A squad of exactly eleven has nobody to bring on,
    // and offering the control there produces a picker with an empty list and
    // a scorer wondering what they did wrong.
    final available = [
      for (final id in benchFor(state, ctx, side))
        if (allowsReturn(ctx) || !_subbedOff(state).contains(id)) id,
    ];
    if (available.isEmpty || onCourt(state, side).isEmpty) return null;

    return ScoreControl(
      action: 'substitution',
      label: remaining == null ? 'Sub' : 'Sub ($remaining)',
      side: side,
      style: ControlStyle.secondary,
      tooltip: remaining == null
          ? 'Substitution'
          : '$remaining substitution${remaining == 1 ? '' : 's'} left',
      prompts: [
        PlayerPrompt(
          key: 'playerOffId',
          label: 'Who comes off?',
          only: onCourt(state, side),
        ),
        PlayerPrompt(key: 'playerOnId', label: 'Who comes on?', only: available),
      ],
      values: [
        if (tracksPlayingTime)
          const ValuePrompt(
            key: PeriodedMatch.minutePayloadKey,
            label: 'Minute',
            unit: 'minutes',
            decimals: 0,
            min: 0,
          ),
      ],
    );
  }

  /// The pre-match line-up button, shown only while it can still be used and
  /// only when the squad is bigger than the field — with eleven named for
  /// eleven places there is nothing to choose.
  ScoreControl? startersControl(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) {
    final limit = squadOnField(ctx);
    if (limit <= 0) return null;
    if (ctx.lineupFor(side).length <= limit) return null;
    if (rotationClock(state) > 0 || substitutionsUsed(state, side) > 0) {
      return null;
    }
    return ScoreControl(
      action: 'set_starters',
      label: 'Starting $limit',
      side: side,
      style: ControlStyle.subtle,
      tooltip: 'Pick who starts; the rest are substitutes',
      prompts: [
        PlayerPrompt(
          key: 'starters',
          label: 'Who starts?',
          multiple: true,
          only: [for (final p in ctx.lineupFor(side)) p.id],
        ),
      ],
    );
  }

  /// A snapshot with the stints in progress folded into the tally, for
  /// building a box score mid-match.
  ///
  /// The tally only holds *banked* minutes — a stint is added when it ends —
  /// so a card built straight from state shows zero for everyone still on the
  /// field, which during the match is everyone who matters. Same arithmetic as
  /// [closePlayingTime]; the difference is that this result is thrown away
  /// after rendering rather than stored.
  Map<String, dynamic> forDisplay(Map<String, dynamic> state) =>
      closePlayingTime(state);

  /// The minutes column, for engines that show a box score.
  static const StatColumn minutesColumn = StatColumn(
    key: minutesStat,
    label: 'Minutes played',
    shortLabel: 'MIN',
  );
}

// ---------------------------------------------------------------------------
// Timeouts
// ---------------------------------------------------------------------------

/// Sides that may stop the clock a limited number of times.
///
/// The allowance is read from whichever key the sport's preset uses, and the
/// key chosen also says when it refills: `timeoutsPerSide` lasts the match,
/// `timeoutsPerPeriod` and `timeoutsPerSet` are reset by the owning plugin at
/// the boundary. Encoding the scope in the key name means a preset states the
/// rule once, in the place an organiser edits it.
mixin TeamTimeouts on ScoringPlugin {
  static const usedKey = 'timeoutsUsed';
  static const logKey = 'timeoutLog';

  static const _scopedKeys = ['timeoutsPerPeriod', 'timeoutsPerSet'];

  int timeoutAllowance(ScoringContext ctx) {
    for (final key in const [..._scopedKeys, 'timeoutsPerSide']) {
      if (ctx.rules.has(key)) return ctx.intConfig(key, 0);
    }
    return 0;
  }

  /// Whether the allowance refills at a period or set boundary.
  bool timeoutsRefill(ScoringContext ctx) =>
      _scopedKeys.any((k) => ctx.rules.has(k));

  Map<String, dynamic> timeoutInitialState(ScoringContext ctx) => {
        usedKey: {'a': 0, 'b': 0},
        logKey: <Map<String, dynamic>>[],
      };

  int timeoutsUsed(Map<String, dynamic> state, Side side) {
    final used = state[usedKey] as Map? ?? const {};
    return (used[side.wire] as num?)?.toInt() ?? 0;
  }

  int timeoutsLeft(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      timeoutAllowance(ctx) - timeoutsUsed(state, side);

  /// Refills both sides. Call at whatever boundary [timeoutsRefill] describes.
  Map<String, dynamic> resetTimeouts(Map<String, dynamic> state) => {
        ...state,
        usedKey: {'a': 0, 'b': 0},
      };

  /// Wraps the result of crossing a period or set boundary, refilling the
  /// allowance when the ruleset says it refills there.
  ///
  /// Exists so a plugin writes `refillIfScoped(applyPeriodAction(...))` rather
  /// than re-deriving the scope rule. A side that has spent both its timeouts
  /// in the first half and is told it has none in the second is the bug this
  /// prevents, and it is the kind that is only noticed in the second half.
  ScoringResult refillIfScoped(ScoringResult result, ScoringContext ctx) {
    if (!result.isAccepted || !timeoutsRefill(ctx)) return result;
    return ScoringResult.ok(resetTimeouts(result.state));
  }

  ScoringResult? applyTimeoutAction(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.type != 'timeout') return null;
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side called it?');
    }

    final allowance = timeoutAllowance(ctx);
    if (allowance <= 0) {
      return const ScoringResult.rejected(
        'This competition does not allow timeouts.',
      );
    }
    final used = timeoutsUsed(state, action.side);
    if (used >= allowance) {
      return ScoringResult.rejected(
        '${ctx.nameFor(action.side)} has no timeouts left.',
      );
    }

    final usedMap = Map<String, dynamic>.from(state[usedKey] as Map? ?? {});
    usedMap[action.side.wire] = used + 1;

    final log = copyList(state[logKey])
      ..add({
        'side': action.side.wire,
        'period': state[PeriodedMatch.periodKey] ?? 1,
        'at': state[PeriodedMatch.minuteKey] ?? 0,
      });

    return ScoringResult.ok({...state, usedKey: usedMap, logKey: log});
  }

  /// Null when the ruleset has no timeouts, so a pad for a competition that
  /// does not use them shows no button rather than a button that always fails.
  ScoreControl? timeoutControl(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) {
    final allowance = timeoutAllowance(ctx);
    if (allowance <= 0) return null;
    final left = timeoutsLeft(state, ctx, side);
    return ScoreControl(
      action: 'timeout',
      label: 'Timeout ($left)',
      side: side,
      style: ControlStyle.subtle,
      tooltip: left == 0
          ? 'No timeouts left'
          : '$left of $allowance remaining',
    );
  }
}

// ---------------------------------------------------------------------------
// Reviews and challenges
// ---------------------------------------------------------------------------

/// Sides that may challenge an official's decision.
///
/// The rule worth encoding is the one every rulebook shares and no scorer
/// remembers under pressure: **a successful challenge is not spent.** Cricket's
/// DRS, tennis, volleyball and kabaddi all return the review when the decision
/// is overturned, and charging for it is how a side ends up with none left in
/// the last over having been right both times.
mixin MatchReviews on ScoringPlugin {
  static const usedKey = 'reviewsUsed';
  static const logKey = 'reviewLog';

  int reviewAllowance(ScoringContext ctx) =>
      ctx.intConfig('reviewsPerSide', 0);

  bool retainsReviewOnSuccess(ScoringContext ctx) =>
      ctx.boolConfig('retainReviewOnSuccess', true);

  Map<String, dynamic> reviewInitialState(ScoringContext ctx) => {
        usedKey: {'a': 0, 'b': 0},
        logKey: <Map<String, dynamic>>[],
      };

  int reviewsUsed(Map<String, dynamic> state, Side side) {
    final used = state[usedKey] as Map? ?? const {};
    return (used[side.wire] as num?)?.toInt() ?? 0;
  }

  int reviewsLeft(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      reviewAllowance(ctx) - reviewsUsed(state, side);

  Map<String, dynamic> resetReviews(Map<String, dynamic> state) => {
        ...state,
        usedKey: {'a': 0, 'b': 0},
      };

  ScoringResult? applyReviewAction(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (action.type != 'review') return null;
    if (action.side == Side.neutral) {
      return const ScoringResult.rejected('Which side asked for the review?');
    }

    final allowance = reviewAllowance(ctx);
    if (allowance <= 0) {
      return const ScoringResult.rejected(
        'This competition does not use reviews.',
      );
    }
    final used = reviewsUsed(state, action.side);
    if (used >= allowance) {
      return ScoringResult.rejected(
        '${ctx.nameFor(action.side)} has no reviews left.',
      );
    }

    final upheld = action.payload['upheld'] == true;
    final spends = !(upheld && retainsReviewOnSuccess(ctx));

    final usedMap = Map<String, dynamic>.from(state[usedKey] as Map? ?? {});
    if (spends) usedMap[action.side.wire] = used + 1;

    final log = copyList(state[logKey])
      ..add({
        'side': action.side.wire,
        'upheld': upheld,
        'period': state[PeriodedMatch.periodKey] ?? 1,
        'at': state[PeriodedMatch.minuteKey] ?? 0,
      });

    return ScoringResult.ok({...state, usedKey: usedMap, logKey: log});
  }

  /// Two buttons rather than one, because the outcome is what decides whether
  /// the review is spent, and asking afterwards is a question the scorer will
  /// answer wrong once the game has moved on.
  List<ScoreControl> reviewControls(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) {
    if (reviewAllowance(ctx) <= 0) return const [];
    final left = reviewsLeft(state, ctx, side);
    return [
      ScoreControl(
        action: 'review',
        label: 'Review upheld ($left)',
        side: side,
        style: ControlStyle.subtle,
        payload: const {'upheld': true},
        tooltip: retainsReviewOnSuccess(ctx)
            ? 'Decision overturned — the review is kept'
            : 'Decision overturned',
      ),
      ScoreControl(
        action: 'review',
        label: 'Review lost',
        side: side,
        style: ControlStyle.subtle,
        payload: const {'upheld': false},
        tooltip: 'Decision stands — the review is spent',
      ),
    ];
  }
}
