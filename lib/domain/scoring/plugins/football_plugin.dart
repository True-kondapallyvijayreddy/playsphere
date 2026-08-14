import '../match_flow.dart';
import '../player_stats.dart';
import '../scoring_plugin.dart';

/// Football, with per-player statistics.
///
/// Replaces the generic goal counter for football specifically. A goal that
/// does not name a scorer is a number on a board; a goal that names a scorer
/// and an assister is a career. The spec asks for goals, assists, minutes,
/// cards, saves, clean sheets and shots, none of which a side-total engine can
/// produce.
///
/// Rules encoded, all configurable per competition:
///
///  * **An own goal counts for the opposition but against the scorer.** It is
///    recorded on the conceding player's line as an own goal, never as a goal
///    — crediting it as a goal is the error that turns a defender into a
///    league top-scorer.
///  * **A second yellow is a red.** The engine tracks card counts and refuses
///    to keep a player on the pitch after two yellows, because a scorer under
///    pressure will not do that arithmetic reliably.
///  * **A sent-off player cannot be involved in anything afterwards.**
///  * **A clean sheet belongs to the goalkeeper who finished the match**, and
///    is derived at full time rather than tracked as it goes.
///  * **Five substitutions, and nobody comes back.** Both come from the shared
///    rotation mixin, so the minutes-played column is computed the same way it
///    is in hockey and basketball rather than three times over.
class FootballPlugin extends ScoringPlugin
    with PeriodedMatch, SquadRotation, TeamTimeouts, MatchReviews {
  const FootballPlugin();

  static const pluginKey = 'football';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Football';

  @override
  List<String> get headlineStats => const [_goals];

  // Stat keys, shared with the box score definition below.
  static const _goals = 'goals';
  static const _assists = 'assists';
  static const _ownGoals = 'ownGoals';
  static const _shots = 'shots';
  static const _shotsOnTarget = 'shotsOnTarget';
  static const _saves = 'saves';
  static const _yellows = 'yellows';
  static const _reds = 'reds';
  static const _fouls = 'fouls';
  static const _penaltiesScored = 'penaltiesScored';
  static const _penaltiesMissed = 'penaltiesMissed';

  bool _allowDraw(ScoringContext ctx) => ctx.boolConfig('allowDraw', true);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        'complete': false,
        'winner': null,
        'draw': false,
        'timeline': <Map<String, dynamic>>[],
        'sentOff': <String>[],
        PlayerTally.stateKey: <String, dynamic>{},
        ...periodInitialState(ctx),
        ...rotationInitialState(ctx),
        ...timeoutInitialState(ctx),
        ...reviewInitialState(ctx),
      };

  List<String> _sentOff(Map<String, dynamic> state) =>
      (state['sentOff'] as List?)?.whereType<String>().toList() ?? const [];

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

    // Any event may carry the minute it happened at, and the clock follows it
    // before anything else reads it. A red card in the 20th minute has to move
    // the clock first, or the player it removes is credited with whatever was
    // banked at the last timed event — zero, for a dismissal early on.
    state = withMinuteFrom(state, action);

    final player = action.payload['playerId'] as String?;
    final sentOff = _sentOff(state);

    // Anyone sent off is out of the match. Letting them score afterwards is
    // the kind of nonsense that makes a scorecard indefensible in a protest.
    if (player != null && sentOff.contains(player)) {
      return ScoringResult.rejected(
        '${ctx.playerName(player)} has been sent off and cannot take part.',
      );
    }
    // ...and cannot be sent back on as a substitute. The rotation mixin knows
    // about benches, not about red cards, so the sport that issues them says
    // so here.
    final comingOn = action.payload['playerOnId'] as String?;
    if (comingOn != null && sentOff.contains(comingOn)) {
      return ScoringResult.rejected(
        '${ctx.playerName(comingOn)} has been sent off and cannot come on. '
        'A side that goes down to ten plays on with ten.',
      );
    }

    // Periods, substitutions, timeouts and reviews are match mechanics rather
    // than football ones; each mixin claims what it recognises and declines
    // the rest by returning null.
    final crossed = applyPeriodAction(state, action, ctx);
    if (crossed != null) return refillIfScoped(crossed, ctx);

    final shared = applyRotationAction(state, action, ctx) ??
        applyTimeoutAction(state, action, ctx) ??
        applyReviewAction(state, action, ctx);
    if (shared != null) return shared;

    int score(String side) => (state[side] as num?)?.toInt() ?? 0;

    Map<String, dynamic> withTimeline(
      Map<String, dynamic> next,
      String type, {
      String? playerId,
      String? secondaryId,
    }) {
      final line = copyList(next['timeline'])
        ..add({
          'type': type,
          'side': action.side.wire,
          'period': next['period'] ?? 1,
          'playerId': playerId,
          'secondaryId': secondaryId,
        });
      return {...next, 'timeline': line};
    }

    switch (action.type) {
      case 'goal':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('A goal needs a side.');
        }
        if (player == null) {
          return const ScoringResult.rejected('Who scored?');
        }
        final assist = action.payload['assistId'] as String?;
        final isPenalty = action.payload['penalty'] == true;

        var next = mutate(state, (s) {
          s[action.side.wire] = score(action.side.wire) + 1;
        });
        next = PlayerTally.addAll(next, player, {
          _goals: 1,
          _shots: 1,
          _shotsOnTarget: 1,
          if (isPenalty) _penaltiesScored: 1,
        });
        if (assist != null && assist != player) {
          next = PlayerTally.add(next, assist, _assists, 1);
        }
        return ScoringResult.ok(
          withTimeline(next, isPenalty ? 'penalty_scored' : 'goal',
              playerId: player, secondaryId: assist),
        );

      case 'own_goal':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected(
            'Which side does the own goal count FOR?',
          );
        }
        if (player == null) {
          return const ScoringResult.rejected('Who put it in their own net?');
        }
        // The goal counts for the opposition; the player is charged an own
        // goal, never a goal. Crediting it as a goal is what turns a defender
        // into a league top-scorer.
        var next = mutate(state, (s) {
          s[action.side.wire] = score(action.side.wire) + 1;
        });
        next = PlayerTally.add(next, player, _ownGoals, 1);
        return ScoringResult.ok(
          withTimeline(next, 'own_goal', playerId: player),
        );

      case 'penalty_missed':
        if (player == null) {
          return const ScoringResult.rejected('Who took it?');
        }
        final next = PlayerTally.addAll(state, player, {
          _penaltiesMissed: 1,
          _shots: 1,
        });
        return ScoringResult.ok(
          withTimeline(next, 'penalty_missed', playerId: player),
        );

      case 'shot':
        if (player == null) {
          return const ScoringResult.rejected('Who had the shot?');
        }
        final onTarget = action.payload['onTarget'] == true;
        final next = PlayerTally.addAll(state, player, {
          _shots: 1,
          if (onTarget) _shotsOnTarget: 1,
        });
        return ScoringResult.ok(next);

      case 'save':
        if (player == null) {
          return const ScoringResult.rejected('Which keeper?');
        }
        return ScoringResult.ok(PlayerTally.add(state, player, _saves, 1));

      case 'foul':
        if (player == null) {
          return const ScoringResult.rejected('Who committed it?');
        }
        return ScoringResult.ok(PlayerTally.add(state, player, _fouls, 1));

      case 'card':
        if (player == null) {
          return const ScoringResult.rejected('Who was booked?');
        }
        final colour = action.payload['colour'] as String? ?? 'yellow';
        final tally = PlayerTally.of(state, player);
        final yellows = (tally[_yellows] ?? 0).toInt();

        if (colour == 'red') {
          var next = PlayerTally.add(state, player, _reds, 1);
          next = {...next, 'sentOff': [...sentOff, player]};
          // Their afternoon ends here, and so does their minutes column.
          next = removeFromField(next, player);
          return ScoringResult.ok(
            withTimeline(next, 'red_card', playerId: player),
          );
        }

        // A second yellow IS a red. The engine does this arithmetic because a
        // scorer watching a match will not do it reliably, and a player left
        // on the pitch after two yellows invalidates everything after it.
        var next = PlayerTally.add(state, player, _yellows, 1);
        if (yellows + 1 >= 2) {
          next = PlayerTally.add(next, player, _reds, 1);
          next = {...next, 'sentOff': [...sentOff, player]};
          next = removeFromField(next, player);
          return ScoringResult.ok(
            withTimeline(next, 'second_yellow', playerId: player),
          );
        }
        return ScoringResult.ok(
          withTimeline(next, 'yellow_card', playerId: player),
        );

      case 'finish':
        final a = score('a');
        final b = score('b');
        if (a == b && !_allowDraw(ctx)) {
          return const ScoringResult.rejected(
            'Scores are level and this competition does not allow draws — '
            'play extra time or a shootout, then record the result.',
          );
        }
        // Run the clock out to full time before banking anyone's minutes,
        // otherwise everyone who was not substituted is credited only to the
        // last event that happened to name a minute.
        var settled = closePlayingTime(atFullTime(state, ctx));
        return ScoringResult.ok(mutate(settled, (s) {
          s['complete'] = true;
          s['draw'] = a == b;
          s['winner'] = a == b ? null : (a > b ? 'a' : 'b');
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(reopenPlayingTime(state), (s) {
          s['complete'] = false;
          s['winner'] = null;
          s['draw'] = false;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  /// Columns for the box score, in the order a football sheet reads.
  static List<StatColumn> get columns => [
        SquadRotation.minutesColumn,
        const StatColumn(key: _goals, label: 'Goals', shortLabel: 'G'),
        const StatColumn(key: _assists, label: 'Assists', shortLabel: 'A'),
        const StatColumn(key: _shots, label: 'Shots', shortLabel: 'Sh'),
        const StatColumn(
          key: _shotsOnTarget,
          label: 'On target',
          shortLabel: 'SoT',
        ),
        StatColumn(
          key: 'accuracy',
          label: 'Shot accuracy',
          shortLabel: 'Acc',
          isPercentage: true,
          // Derived, never stored: a percentage that is accumulated drifts
          // away from the counts it claims to summarise.
          derive: (t) {
            final shots = (t[_shots] ?? 0).toDouble();
            return shots == 0 ? 0 : (t[_shotsOnTarget] ?? 0) / shots;
          },
        ),
        const StatColumn(key: _saves, label: 'Saves', shortLabel: 'Sv'),
        const StatColumn(key: _fouls, label: 'Fouls', shortLabel: 'F'),
        const StatColumn(key: _yellows, label: 'Yellow cards', shortLabel: 'YC'),
        const StatColumn(key: _reds, label: 'Red cards', shortLabel: 'RC'),
        const StatColumn(
          key: _ownGoals,
          label: 'Own goals',
          shortLabel: 'OG',
        ),
      ];

  @override
  BoxScore boxScore(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      PlayerTally.boxScore(
        state: forDisplay(state),
        ctx: ctx,
        side: side,
        columns: columns,
      );

  /// Whether the side kept a clean sheet. Derived at the end rather than
  /// tracked, because a clean sheet is only true once the match is over.
  bool cleanSheet(Map<String, dynamic> state, Side side) {
    if (state['complete'] != true) return false;
    final conceded = side == Side.a ? state['b'] : state['a'];
    return ((conceded as num?)?.toInt() ?? 0) == 0;
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
    return periodStatus(state, ctx);
  }

  @override
  String periodNoun(ScoringContext ctx) =>
      ctx.stringConfig('periodLabel', 'Half');

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

    // Every one of these reads a `playerId` and refuses the event without it
    // — "Who scored?", "Who was booked?". Until the controls declared their
    // prompts the pad never asked, so every button on this pad returned a
    // rejection and a football match could not be scored at all.
    List<ScoreControl> forSide(Side side, String goalKey) {
      // Nulls here are the ruleset speaking: no bench, no sub button; a
      // competition with no timeouts or reviews shows neither.
      final starters = startersControl(state, ctx, side);
      final sub = substitutionControl(state, ctx, side);
      final timeout = timeoutControl(state, ctx, side);

      return [
          ScoreControl(
            action: 'goal',
            label: 'Goal',
            side: side,
            style: ControlStyle.primary,
            shortcut: goalKey,
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who scored?'),
              // Optional, and it has to be: most goals have no assist, and a
              // picker that will not close without one teaches the scorer to
              // name whoever was nearest.
              PlayerPrompt(
                key: 'assistId',
                label: 'Assisted by',
                optional: true,
              ),
            ],
          ),
          ScoreControl(
            action: 'shot',
            label: 'Shot',
            side: side,
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who had the shot?'),
            ],
          ),
          ScoreControl(
            action: 'save',
            label: 'Save',
            side: side,
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Which keeper?'),
            ],
          ),
          ScoreControl(
            action: 'card',
            label: 'Yellow',
            side: side,
            payload: const {'colour': 'yellow'},
            style: ControlStyle.secondary,
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who was booked?'),
            ],
          ),
          ScoreControl(
            action: 'card',
            label: 'Red',
            side: side,
            payload: const {'colour': 'red'},
            style: ControlStyle.danger,
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who was sent off?'),
            ],
          ),
          if (starters != null) starters,
          if (sub != null) sub,
          if (timeout != null) timeout,
          ...reviewControls(state, ctx, side),
        ];
    }

    return [
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: forSide(Side.a, 'a'),
      ),
      ScoreControlGroup(
        title: ctx.entrantBName,
        controls: forSide(Side.b, 'l'),
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
