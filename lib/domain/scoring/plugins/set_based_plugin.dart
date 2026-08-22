import '../player_stats.dart';
import '../racket_rules.dart';
import '../scoring_plugin.dart';
import '../rally_timeline.dart';

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
class SetBasedPlugin extends ScoringPlugin with RallyTimeline, RacketMatch {
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

        // Credit the point to whoever won it, when the pad named somebody.
        //
        // Optional on purpose. This engine is the generic set/game scorer and
        // it serves throwball as well as anything an organizer picks it for,
        // so it cannot demand a player the way a sport-specific engine can —
        // a scorer who only wants the score must still be able to keep it.
        // But when the name IS supplied, dropping it was the whole bug:
        // throwball recorded hundreds of points and its scorecard named
        // nobody, because nothing here ever read `playerId`.
        final scorer = action.payload['playerId'] as String?;
        if (scorer != null) {
          next = PlayerTally.addAll(next, scorer, {
            _pointsWon: 1,
            _rallies: 1,
          });
        }
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

      case RacketMatch.retireAction:
        // A player retiring hurt or being disqualified mid-match still needs
        // a recorded winner — the other side — and, now, a recorded reason.
        return retireResult(state, action);

      case 'reopen':
        return reopenResult(state);

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

  /// Never raises a mid-set change of ends.
  ///
  /// This is the generic set/game engine — it serves throwball and whatever
  /// else an organizer points it at — and it does not know the court it is
  /// being played on. Sports whose laws fix a change of ends implement it in
  /// their own engine, where the number comes from the actual rulebook rather
  /// than from a guess made here.
  @override
  EndsChange? endsChangeDue(Map<String, dynamic> state, ScoringContext ctx) =>
      null;

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
      return retirementLine(state, ctx) ??
          'Final · sets ${state['setsA']}-${state['setsB']}';
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

  // The generic set/game engine gets the two-sided pad as well.
  //
  // It serves volleyball and throwball, and those are rally sports too: every
  // event is "that side won the point", forty to sixty times a set, entered by
  // somebody watching the court. The reason to give it the same pad as
  // badminton is not consistency for its own sake — it is that the alternative
  // is a row of small buttons for a job that is two big ones.
  //
  // No serve indicator: this engine deliberately knows nothing about service
  // rotation (see the note on `point`), and inventing one here would be the
  // pad asserting a fact the rules engine cannot back up.
  @override
  PadLayout get padLayout => PadLayout.duel;

  @override
  DuelBoard? duelBoard(Map<String, dynamic> state, ScoringContext ctx) {
    final done = state['complete'] == true;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final setsA = ((state['setsA'] as num?) ?? 0).toInt();
    final setsB = ((state['setsB'] as num?) ?? 0).toInt();
    final target = _pointsForSet(state, ctx);
    final winBy = ctx.intConfig('winBy', 2);
    final setsToWin = ctx.intConfig('setsToWin', 2);

    String? tagFor(int mine, int theirs, int setsMine) {
      if (done) return null;
      if (mine < target - 1 || mine - theirs < winBy - 1) return null;
      return setsMine == setsToWin - 1 ? 'Match point' : 'Set point';
    }

    final completed = copyList(state['completedSets']);
    // Sets, not points, once it is over — the point counters are zeroed when
    // each set closes.
    final winner = state['winner'];
    return DuelBoard(
      matchScore: DuelMatchScore(
        a: ((state['setsA'] as num?) ?? 0).toInt(),
        b: ((state['setsB'] as num?) ?? 0).toInt(),
        label: 'SETS WON',
      ),
      a: DuelSide(
        name: ctx.entrantAName,
        score: done ? '$setsA' : '$a',
        sub: done ? 'Sets won' : 'Sets $setsA',
        tag: done ? (winner == 'a' ? 'Won' : null) : tagFor(a, b, setsA),
        pips: done ? null : a,
      ),
      b: DuelSide(
        name: ctx.entrantBName,
        score: done ? '$setsB' : '$b',
        sub: done ? 'Sets won' : 'Sets $setsB',
        tag: done ? (winner == 'b' ? 'Won' : null) : tagFor(b, a, setsB),
        pips: done ? null : b,
      ),
      periods: [
        for (final (i, st) in completed.indexed)
          DuelPeriod(
            label: 'S${i + 1}',
            a: ((st['a'] as num?) ?? 0).toInt(),
            b: ((st['b'] as num?) ?? 0).toInt(),
          ),
        if (!done)
          DuelPeriod(
            label: 'S${completed.length + 1}',
            a: a,
            b: b,
            current: true,
          ),
      ],
      status: statusLine(state, ctx),
      pipTarget: done ? null : target,
      pointsNote: '$target points per set · best of ${setsToWin * 2 - 1}',
    );
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
            prompts: [
              PlayerPrompt(key: 'playerId', label: 'Who won the point?'),
            ],
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
            prompts: [
              PlayerPrompt(key: 'playerId', label: 'Who won the point?'),
            ],
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
      ...retireControls(ctx),
    ];
  }

  static const _pointsWon = 'pointsWon';
  static const _rallies = 'rallies';

  /// Per-player lines, so a throwball player's record is not permanently
  /// empty. Before this the engine had no box score at all: the points were
  /// tallied nowhere and displayed nowhere, and the sport's whole per-player
  /// history was a blank.
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
        columns: const [
          StatColumn(key: _pointsWon, label: 'Points won', shortLabel: 'PTS'),
          StatColumn(key: _rallies, label: 'Rallies won', shortLabel: 'R'),
        ],
      );

  // --- Rally timeline ----------------------------------------------------

  @override
  List<Map<String, dynamic>> rallyCompletedPeriods(
    Map<String, dynamic> state,
  ) =>
      copyList(state['completedSets']);

  @override
  String get rallyPeriodNoun => 'Set';
}
