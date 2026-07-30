import '../player_stats.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';

/// Athletics — track and field, plus swimming.
///
/// This is the one archetype in the catalogue that is not a contest between
/// two sides. There is no "side A" and no running score: there is a field of
/// athletes, each producing a mark, and a ranking derived from those marks.
/// Scoring it with the versus engine — which is what the catalogue did before
/// — meant a school sports day could not be recorded at all.
///
/// Two disciplines share one engine because their bookkeeping is the same
/// shape and only the comparison flips:
///
///  * **Track** (and swimming): a time, lower is better, recorded to the
///    configured precision. Lanes, heats, false starts and wind readings all
///    belong to the mark.
///  * **Field**: a series of attempts, higher is better, and the athlete's
///    result is their best legal attempt. Fouls are recorded rather than
///    discarded, because "three fouls, no mark" is itself a result.
///
/// Marks are held as doubles in a single canonical unit — seconds for track,
/// metres for field — so a personal best is comparable across meets without
/// re-parsing whatever the scorer typed.
class AthleticsPlugin extends ScoringPlugin {
  const AthleticsPlugin();

  static const pluginKey = 'athletics';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Athletics';

  static const _attempts = 'attempts';
  static const _fouls = 'fouls';
  static const _best = 'best';

  /// 'track' compares ascending, 'field' descending.
  String discipline(ScoringContext ctx) =>
      ctx.stringConfig('discipline', 'track');

  bool _lowerIsBetter(ScoringContext ctx) =>
      ctx.boolConfig('lowerIsBetter', discipline(ctx) == 'track');

  int _lanes(ScoringContext ctx) => ctx.intConfig('lanes', 8);
  int _attemptsAllowed(ScoringContext ctx) => ctx.intConfig('attempts', 6);
  int _decimals(ScoringContext ctx) => ctx.intConfig('precisionDecimals', 2);
  bool _recordWind(ScoringContext ctx) => ctx.boolConfig('recordWind', false);

  bool _falseStartDisqualifies(ScoringContext ctx) =>
      ctx.boolConfig('falseStartDisqualifies', true);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        // Marks, keyed by athlete id. Each is a record of every attempt plus
        // the derived best.
        'marks': <String, dynamic>{},
        'heat': 1,
        'round': 'heats',
        'complete': false,
        // Present so the shared plumbing (outcome, standings) has something
        // to read; a performance event has no side score.
        'a': 0,
        'b': 0,
        'winner': null,
        'draw': false,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  // --- Mark bookkeeping -----------------------------------------------------

  Map<String, dynamic> _marks(Map<String, dynamic> state) =>
      Map<String, dynamic>.from(
        state['marks'] as Map? ?? const <String, dynamic>{},
      );

  Map<String, dynamic> _markFor(Map<String, dynamic> state, String athleteId) =>
      Map<String, dynamic>.from(
        _marks(state)[athleteId] as Map? ?? const <String, dynamic>{},
      );

  /// Every attempt an athlete has recorded, in order.
  List<Map<String, dynamic>> attemptsOf(
    Map<String, dynamic> state,
    String athleteId,
  ) =>
      copyList(_markFor(state, athleteId)['attempts']);

  /// The athlete's result: their best legal attempt, or null for no mark.
  double? bestOf(
    Map<String, dynamic> state,
    String athleteId,
    ScoringContext ctx,
  ) {
    final legal = attemptsOf(state, athleteId)
        .where((a) => a['foul'] != true && a['value'] is num)
        .map((a) => (a['value'] as num).toDouble())
        .toList();
    if (legal.isEmpty) return null;
    legal.sort();
    return _lowerIsBetter(ctx) ? legal.first : legal.last;
  }

  bool isDisqualified(Map<String, dynamic> state, String athleteId) =>
      _markFor(state, athleteId)['disqualified'] == true;

  @override
  ScoringResult apply(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (state['complete'] == true && action.type != 'reopen') {
      return const ScoringResult.rejected(
        'This event is already finished. Reopen it to make a correction.',
      );
    }

    switch (action.type) {
      case 'mark':
        return _recordMark(state, action, ctx);

      case 'foul':
        return _recordMark(state, action, ctx, foul: true);

      case 'false_start':
        final athlete = action.payload['athleteId'] as String?;
        if (athlete == null) {
          return const ScoringResult.rejected('Who false-started?');
        }
        final mark = _markFor(state, athlete);
        final count = ((mark['falseStarts'] as num?) ?? 0).toInt() + 1;
        mark['falseStarts'] = count;
        if (_falseStartDisqualifies(ctx)) {
          mark['disqualified'] = true;
          mark['reason'] = 'False start';
        }
        return ScoringResult.ok(_withMark(state, athlete, mark));

      case 'disqualify':
        final athlete = action.payload['athleteId'] as String?;
        if (athlete == null) {
          return const ScoringResult.rejected('Who is disqualified?');
        }
        final mark = _markFor(state, athlete)
          ..['disqualified'] = true
          ..['reason'] = action.payload['reason'] ?? 'Disqualified';
        return ScoringResult.ok(_withMark(state, athlete, mark));

      case 'reinstate':
        final athlete = action.payload['athleteId'] as String?;
        if (athlete == null) {
          return const ScoringResult.rejected('Who is reinstated?');
        }
        final mark = _markFor(state, athlete)
          ..remove('disqualified')
          ..remove('reason');
        return ScoringResult.ok(_withMark(state, athlete, mark));

      case 'next_heat':
        return ScoringResult.ok(mutate(state, (s) {
          s['heat'] = ((s['heat'] as num?) ?? 1).toInt() + 1;
        }));

      case 'set_round':
        final round = action.payload['round'] as String?;
        if (round == null || round.isEmpty) {
          return const ScoringResult.rejected('Which round?');
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['round'] = round;
          s['heat'] = 1;
        }));

      case 'finish':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = false;
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  ScoringResult _recordMark(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx, {
    bool foul = false,
  }) {
    final athlete = action.payload['athleteId'] as String?;
    if (athlete == null) {
      return const ScoringResult.rejected('Which athlete?');
    }
    if (isDisqualified(state, athlete)) {
      return ScoringResult.rejected(
        '${ctx.playerName(athlete)} is disqualified from this event.',
      );
    }

    final raw = action.payload['value'];
    final value = raw is num ? raw.toDouble() : null;
    if (!foul && value == null) {
      return const ScoringResult.rejected(
        'A mark needs a time or a distance.',
      );
    }
    if (value != null && value <= 0) {
      return const ScoringResult.rejected(
        'A mark must be greater than zero.',
      );
    }

    final existing = attemptsOf(state, athlete);
    final allowed = _attemptsAllowed(ctx);
    // Track events are a single run; field events allow a configured series.
    final limit = discipline(ctx) == 'track' ? 1 : allowed;
    if (limit > 0 && existing.length >= limit) {
      return ScoringResult.rejected(
        limit == 1
            ? '${ctx.playerName(athlete)} has already recorded a time. '
                'Correct it rather than adding another.'
            : '${ctx.playerName(athlete)} has used all $limit attempts.',
      );
    }

    final attempt = <String, dynamic>{
      'index': existing.length + 1,
      'foul': foul,
      if (value != null) 'value': value,
      if (action.payload['lane'] is num)
        'lane': (action.payload['lane'] as num).toInt(),
      if (_recordWind(ctx) && action.payload['wind'] is num)
        'wind': (action.payload['wind'] as num).toDouble(),
      'heat': state['heat'] ?? 1,
      'round': state['round'] ?? 'heats',
    };

    final mark = _markFor(state, athlete);
    mark['attempts'] = [...existing, attempt];
    if (action.payload['lane'] is num) {
      mark['lane'] = (action.payload['lane'] as num).toInt();
    }

    var next = _withMark(state, athlete, mark);

    // Recompute the best from the attempt list rather than comparing against
    // a stored best: a corrected attempt must be able to lower a record, and
    // an incrementally-maintained best cannot go backwards.
    final best = bestOf(next, athlete, ctx);
    final updated = _markFor(next, athlete);
    if (best != null) {
      updated['best'] = best;
    } else {
      updated.remove('best');
    }
    next = _withMark(next, athlete, updated);

    next = PlayerTally.addAll(next, athlete, {
      _attempts: 1,
      if (foul) _fouls: 1,
    });
    if (best != null) {
      // Stored rather than accumulated so the career aggregator can read a
      // personal best without replaying the meet.
      final all = Map<String, dynamic>.from(
        next[PlayerTally.stateKey] as Map? ?? const <String, dynamic>{},
      );
      final mine = Map<String, dynamic>.from(
        all[athlete] as Map? ?? const <String, dynamic>{},
      );
      mine[_best] = best;
      all[athlete] = mine;
      next = {...next, PlayerTally.stateKey: all};
    }

    return ScoringResult.ok(next);
  }

  Map<String, dynamic> _withMark(
    Map<String, dynamic> state,
    String athleteId,
    Map<String, dynamic> mark,
  ) {
    final marks = _marks(state);
    marks[athleteId] = mark;
    return {...state, 'marks': marks};
  }

  // --- Ranking --------------------------------------------------------------

  /// The field, ordered best-first. Disqualified athletes and those with no
  /// legal mark sort last, in that order, because a DQ and a no-mark are
  /// different results and a results sheet has to distinguish them.
  List<AthleticsPlacing> standings(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final ids = <String>{
      ..._marks(state).keys.map((k) => k.toString()),
      ...ctx.lineupA.map((p) => p.id),
      ...ctx.lineupB.map((p) => p.id),
    };

    final rows = <AthleticsPlacing>[];
    for (final id in ids) {
      rows.add(AthleticsPlacing(
        athleteId: id,
        name: ctx.playerName(id),
        best: bestOf(state, id, ctx),
        disqualified: isDisqualified(state, id),
        attempts: attemptsOf(state, id).length,
        lane: (_markFor(state, id)['lane'] as num?)?.toInt(),
      ));
    }

    final lower = _lowerIsBetter(ctx);
    rows.sort((x, y) {
      if (x.disqualified != y.disqualified) return x.disqualified ? 1 : -1;
      final a = x.best;
      final b = y.best;
      if (a == null && b == null) return x.name.compareTo(y.name);
      if (a == null) return 1;
      if (b == null) return -1;
      final cmp = lower ? a.compareTo(b) : b.compareTo(a);
      return cmp != 0 ? cmp : x.name.compareTo(y.name);
    });

    // Equal marks share a place, and the next place is skipped — 1, 2, 2, 4.
    var place = 0;
    double? previous;
    var previousDq = false;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final ranked = r.best != null && !r.disqualified;
      if (!ranked) {
        rows[i] = r.withPlace(null);
        continue;
      }
      if (previous == null || r.best != previous || previousDq) {
        place = i + 1;
      }
      rows[i] = r.withPlace(place);
      previous = r.best;
      previousDq = r.disqualified;
    }
    return rows;
  }

  /// Formats a mark the way the discipline expects: a time as mm:ss.xx once
  /// it passes a minute, a distance as plain metres.
  String formatMark(double? value, ScoringContext ctx) {
    if (value == null) return '—';
    final dp = _decimals(ctx);
    if (discipline(ctx) != 'track') return value.toStringAsFixed(dp);
    if (value < 60) return value.toStringAsFixed(dp);
    final minutes = value ~/ 60;
    final seconds = value - minutes * 60;
    final padded = seconds < 10 ? '0${seconds.toStringAsFixed(dp)}' : seconds.toStringAsFixed(dp);
    return '$minutes:$padded';
  }

  // --- Presentation ---------------------------------------------------------

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    final table = standings(state, ctx);
    final leader = table.where((r) => r.place == 1).toList();
    if (leader.isEmpty) return '—';
    return '${leader.first.name} ${formatMark(leader.first.best, ctx)}';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final table = standings(state, ctx).where((r) => r.place != null).take(3);
    if (table.isEmpty) return 'No marks yet';
    return table
        .map((r) => '${r.place}. ${r.name} ${formatMark(r.best, ctx)}')
        .join(' • ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return 'Final';
    final parts = <String>[];
    final round = state['round'];
    if (round is String && round.isNotEmpty) parts.add(round);
    final heat = ((state['heat'] as num?) ?? 1).toInt();
    if (round == 'heats') parts.add('Heat $heat');
    if (discipline(ctx) == 'track') {
      parts.add('${_lanes(ctx)} lanes');
    } else {
      parts.add('${_attemptsAllowed(ctx)} attempts');
    }
    return parts.join(' • ');
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    // A performance event has a ranking, not a winning side. It reports
    // complete so the fixture can be finalised, but never a winner side.
    return MatchOutcome(isComplete: state['complete'] == true);
  }

  @override
  List<ScoreControlGroup> controls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    if (state['complete'] == true) {
      return const [
        ScoreControlGroup(title: 'Event finished', controls: [
          ScoreControl(
            action: 'reopen',
            label: 'Reopen to correct',
            style: ControlStyle.subtle,
            shortcut: 'r',
          ),
        ]),
      ];
    }

    final isTrack = discipline(ctx) == 'track';
    return [
      ScoreControlGroup(
        title: isTrack ? 'Record a time' : 'Record an attempt',
        controls: [
          ScoreControl(
            action: 'mark',
            label: isTrack ? 'Time' : 'Mark',
            style: ControlStyle.primary,
            shortcut: 'm',
            tooltip: isTrack
                ? 'Enter a finishing time'
                : 'Enter a distance or height',
          ),
          if (!isTrack)
            const ScoreControl(
              action: 'foul',
              label: 'Foul',
              style: ControlStyle.danger,
              shortcut: 'x',
              tooltip: 'A failed attempt still counts as an attempt',
            ),
        ],
      ),
      ScoreControlGroup(
        title: 'Officials',
        controls: [
          if (isTrack)
            const ScoreControl(
              action: 'false_start',
              label: 'False start',
              style: ControlStyle.danger,
            ),
          const ScoreControl(
            action: 'disqualify',
            label: 'Disqualify',
            style: ControlStyle.danger,
          ),
          const ScoreControl(
            action: 'reinstate',
            label: 'Reinstate',
            style: ControlStyle.subtle,
          ),
        ],
      ),
      const ScoreControlGroup(
        title: 'Progression',
        controls: [
          ScoreControl(
            action: 'next_heat',
            label: 'Next heat',
            style: ControlStyle.secondary,
            shortcut: 'h',
          ),
          ScoreControl(
            action: 'set_round',
            label: 'To final',
            style: ControlStyle.secondary,
            payload: {'round': 'final'},
            shortcut: 'f',
          ),
        ],
      ),
    ];
  }

  static List<StatColumn> get columns => columnsFor();

  static List<StatColumn> columnsFor([RuleConfig? rules]) {
    final dp = rules?.getInt('precisionDecimals', 2) ?? 2;
    return [
      StatColumn(
        key: _best,
        label: 'Best mark',
        shortLabel: 'BEST',
        decimals: dp,
      ),
      const StatColumn(key: _attempts, label: 'Attempts', shortLabel: 'ATT'),
      const StatColumn(key: _fouls, label: 'Fouls', shortLabel: 'X'),
    ];
  }

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
}

/// One athlete's line in a results sheet.
class AthleticsPlacing {
  const AthleticsPlacing({
    required this.athleteId,
    required this.name,
    required this.best,
    required this.disqualified,
    required this.attempts,
    this.lane,
    this.place,
  });

  final String athleteId;
  final String name;

  /// Best legal mark, or null for no mark.
  final double? best;

  final bool disqualified;
  final int attempts;
  final int? lane;

  /// Finishing place, or null for a DQ or no mark.
  final int? place;

  AthleticsPlacing withPlace(int? p) => AthleticsPlacing(
        athleteId: athleteId,
        name: name,
        best: best,
        disqualified: disqualified,
        attempts: attempts,
        lane: lane,
        place: p,
      );
}
