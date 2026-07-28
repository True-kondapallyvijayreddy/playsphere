import '../scoring_plugin.dart';

/// Ball-by-ball limited-overs cricket.
///
/// The rules below are the ones that separate a real scoring app from a
/// counter with a cricket label on it, and every one of them is a bug that
/// naive implementations ship:
///
///  * **Wides and no-balls do not consume a legal delivery.** If the ball
///    counter increments on a wide, every over ends early and the innings
///    finishes several overs short. This is the single most common cricket
///    scoring bug in existence.
///  * **A no-ball grants a free hit**, on which the batter cannot be bowled or
///    caught out — only run out. Recording a normal dismissal there produces
///    a wicket that did not happen.
///  * **Byes and leg-byes are extras but DO consume a delivery**, which is the
///    exact opposite of a wide, and is why they cannot share one code path.
///  * **A chase ends the instant the target is passed** — not at the end of
///    the over. Continuing to score afterwards fabricates runs.
///  * **Levelling the target is a tie, not a win.** Off-by-one here decides
///    matches wrongly.
class CricketPlugin extends ScoringPlugin {
  const CricketPlugin();

  static const pluginKey = 'cricket';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Cricket (limited overs)';

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) {
    final battingFirst = ctx.config['battingFirst'] as String? ?? 'a';
    return {
      'inningsIndex': 0,
      'innings': [_newInnings(battingFirst)],
      'freeHit': false,
      'target': null,
      'complete': false,
      'winner': null,
      'tie': false,
    };
  }

  static Map<String, dynamic> _newInnings(String battingSide) => {
        'battingSide': battingSide,
        'runs': 0,
        'wickets': 0,
        'legalBalls': 0,
        'extras': {'wide': 0, 'noBall': 0, 'bye': 0, 'legBye': 0},
        'closed': false,
      };

  int _ballsPerOver(ScoringContext ctx) => ctx.intConfig('ballsPerOver', 6);
  int _overs(ScoringContext ctx) => ctx.intConfig('oversPerInnings', 20);
  int _wicketsAllowed(ScoringContext ctx) =>
      ctx.intConfig('playersPerTeam', 11) - 1;

  Map<String, dynamic> _current(Map<String, dynamic> state) {
    final innings = copyList(state['innings']);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    if (idx < innings.length) return innings[idx];
    return _newInnings('a');
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

    final innings = copyList(state['innings']);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    if (idx >= innings.length) {
      return const ScoringResult.rejected('No innings in progress.');
    }
    final cur = Map<String, dynamic>.from(innings[idx]);
    final extras = Map<String, dynamic>.from(cur['extras'] as Map? ?? {});
    final freeHit = state['freeHit'] == true;

    int runs() => (cur['runs'] as num?)?.toInt() ?? 0;
    int balls() => (cur['legalBalls'] as num?)?.toInt() ?? 0;
    int wickets() => (cur['wickets'] as num?)?.toInt() ?? 0;

    var nextFreeHit = false;

    switch (action.type) {
      case 'runs':
        final r = (action.payload['runs'] as num?)?.toInt() ?? 0;
        if (r < 0 || r > 8) {
          return const ScoringResult.rejected('Runs off a ball must be 0-8.');
        }
        cur['runs'] = runs() + r;
        cur['legalBalls'] = balls() + 1;

      case 'wicket':
        final isRunOut = action.payload['runOut'] == true;
        if (freeHit && !isRunOut) {
          return const ScoringResult.rejected(
            'Free hit — the batter can only be run out on this delivery.',
          );
        }
        if (wickets() >= _wicketsAllowed(ctx)) {
          return const ScoringResult.rejected('All out already.');
        }
        cur['wickets'] = wickets() + 1;
        cur['legalBalls'] = balls() + 1;
        // Runs completed before a run-out still count.
        final withRuns = (action.payload['runs'] as num?)?.toInt() ?? 0;
        if (withRuns > 0) cur['runs'] = runs() + withRuns;

      case 'wide':
        // Penalty run plus any runs actually run. Does NOT count as a ball,
        // and does not clear an existing free hit.
        final extra = (action.payload['runs'] as num?)?.toInt() ?? 0;
        final total = 1 + extra;
        cur['runs'] = runs() + total;
        extras['wide'] = ((extras['wide'] as num?)?.toInt() ?? 0) + total;
        nextFreeHit = freeHit;

      case 'no_ball':
        // Penalty run plus runs off the bat. Does NOT count as a ball, and
        // grants a free hit on the next delivery.
        final offBat = (action.payload['runs'] as num?)?.toInt() ?? 0;
        cur['runs'] = runs() + 1 + offBat;
        extras['noBall'] = ((extras['noBall'] as num?)?.toInt() ?? 0) + 1;
        nextFreeHit = true;

      case 'bye':
      case 'leg_bye':
        final r = (action.payload['runs'] as num?)?.toInt() ?? 1;
        if (r <= 0) {
          return const ScoringResult.rejected('Byes must be at least 1 run.');
        }
        cur['runs'] = runs() + r;
        final field = action.type == 'bye' ? 'bye' : 'legBye';
        extras[field] = ((extras[field] as num?)?.toInt() ?? 0) + r;
        cur['legalBalls'] = balls() + 1;

      case 'end_innings':
        cur['closed'] = true;

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
          s['tie'] = false;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }

    cur['extras'] = extras;
    innings[idx] = cur;

    var next = mutate(state, (s) {
      s['innings'] = innings;
      s['freeHit'] = nextFreeHit;
    });

    return ScoringResult.ok(_settle(next, ctx));
  }

  /// Closes the innings and the match at the correct moments.
  Map<String, dynamic> _settle(Map<String, dynamic> state, ScoringContext ctx) {
    final innings = copyList(state['innings']);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    final cur = Map<String, dynamic>.from(innings[idx]);

    final runs = (cur['runs'] as num?)?.toInt() ?? 0;
    final wickets = (cur['wickets'] as num?)?.toInt() ?? 0;
    final legalBalls = (cur['legalBalls'] as num?)?.toInt() ?? 0;
    final maxBalls = _overs(ctx) * _ballsPerOver(ctx);
    final target = (state['target'] as num?)?.toInt();
    final isSecondInnings = idx == 1;

    // A chase ends the moment the target is passed, mid-over.
    final chaseWon = isSecondInnings && target != null && runs >= target;

    final inningsOver = cur['closed'] == true ||
        wickets >= _wicketsAllowed(ctx) ||
        legalBalls >= maxBalls ||
        chaseWon;

    if (!inningsOver) {
      innings[idx] = cur;
      return mutate(state, (s) => s['innings'] = innings);
    }

    cur['closed'] = true;
    innings[idx] = cur;

    if (!isSecondInnings) {
      // Start the chase. Target is one more than what was set.
      final battingFirst = cur['battingSide'] as String? ?? 'a';
      final chasingSide = battingFirst == 'a' ? 'b' : 'a';
      innings.add(_newInnings(chasingSide));
      return mutate(state, (s) {
        s['innings'] = innings;
        s['inningsIndex'] = 1;
        s['target'] = runs + 1;
        s['freeHit'] = false;
      });
    }

    // Second innings finished — decide the match.
    final chasingSide = cur['battingSide'] as String? ?? 'b';
    final defendingSide = chasingSide == 'a' ? 'b' : 'a';
    final t = target ?? 0;

    String? winner;
    var tie = false;
    if (runs >= t) {
      winner = chasingSide;
    } else if (runs == t - 1) {
      tie = true;
    } else {
      winner = defendingSide;
    }

    return mutate(state, (s) {
      s['innings'] = innings;
      s['complete'] = true;
      s['winner'] = winner;
      s['tie'] = tie;
      s['freeHit'] = false;
    });
  }

  String _oversText(int legalBalls, ScoringContext ctx) {
    final per = _ballsPerOver(ctx);
    return '${legalBalls ~/ per}.${legalBalls % per}';
  }

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    final cur = _current(state);
    final runs = (cur['runs'] as num?)?.toInt() ?? 0;
    final wickets = (cur['wickets'] as num?)?.toInt() ?? 0;
    return '$runs/$wickets';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final innings = copyList(state['innings']);
    return innings.map((i) {
      final runs = (i['runs'] as num?)?.toInt() ?? 0;
      final wkts = (i['wickets'] as num?)?.toInt() ?? 0;
      final balls = (i['legalBalls'] as num?)?.toInt() ?? 0;
      final side = i['battingSide'] == 'a' ? ctx.entrantAName : ctx.entrantBName;
      return '$side $runs/$wkts (${_oversText(balls, ctx)})';
    }).join('  ·  ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      if (state['tie'] == true) return 'Match tied';
      final w = state['winner'];
      if (w is String) {
        return '${ctx.nameFor(Side.fromWire(w))} won';
      }
      return 'Final';
    }

    final cur = _current(state);
    final balls = (cur['legalBalls'] as num?)?.toInt() ?? 0;
    final overs = _oversText(balls, ctx);
    final maxOvers = _overs(ctx);
    final parts = <String>['$overs / $maxOvers ov'];

    if (state['freeHit'] == true) parts.add('FREE HIT');

    final target = (state['target'] as num?)?.toInt();
    if (target != null && (state['inningsIndex'] as num?)?.toInt() == 1) {
      final runs = (cur['runs'] as num?)?.toInt() ?? 0;
      final need = target - runs;
      final ballsLeft = _overs(ctx) * _ballsPerOver(ctx) - balls;
      parts.add('need $need off $ballsLeft');
    }
    return parts.join(' · ');
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] != true) return MatchOutcome.inProgress;
    final innings = copyList(state['innings']);
    var runsA = 0;
    var runsB = 0;
    for (final i in innings) {
      final r = (i['runs'] as num?)?.toInt() ?? 0;
      if (i['battingSide'] == 'a') {
        runsA += r;
      } else {
        runsB += r;
      }
    }
    return MatchOutcome(
      isComplete: true,
      isDraw: state['tie'] == true,
      winnerSide:
          state['winner'] == null ? null : Side.fromWire(state['winner'] as String),
      scoreForA: runsA,
      scoreForB: runsB,
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

    final freeHit = state['freeHit'] == true;

    return [
      const ScoreControlGroup(
        title: 'Runs off the bat',
        controls: [
          ScoreControl(action: 'runs', label: '0', payload: {'runs': 0}, shortcut: '0'),
          ScoreControl(action: 'runs', label: '1', payload: {'runs': 1}, style: ControlStyle.primary, shortcut: '1'),
          ScoreControl(action: 'runs', label: '2', payload: {'runs': 2}, style: ControlStyle.primary, shortcut: '2'),
          ScoreControl(action: 'runs', label: '3', payload: {'runs': 3}, shortcut: '3'),
          ScoreControl(action: 'runs', label: '4', payload: {'runs': 4}, style: ControlStyle.primary, shortcut: '4'),
          ScoreControl(action: 'runs', label: '6', payload: {'runs': 6}, style: ControlStyle.primary, shortcut: '6'),
        ],
      ),
      const ScoreControlGroup(
        title: 'Extras',
        controls: [
          ScoreControl(
            action: 'wide',
            label: 'Wide',
            style: ControlStyle.secondary,
            shortcut: 'd',
            tooltip: 'One penalty run. Does not count as a ball.',
          ),
          ScoreControl(
            action: 'no_ball',
            label: 'No ball',
            style: ControlStyle.secondary,
            shortcut: 'n',
            tooltip: 'One penalty run, free hit next delivery, not a ball.',
          ),
          ScoreControl(
            action: 'bye',
            label: 'Bye',
            payload: {'runs': 1},
            style: ControlStyle.subtle,
            shortcut: 'b',
          ),
          ScoreControl(
            action: 'leg_bye',
            label: 'Leg bye',
            payload: {'runs': 1},
            style: ControlStyle.subtle,
            shortcut: 'g',
          ),
        ],
      ),
      ScoreControlGroup(
        title: 'Wicket',
        controls: [
          ScoreControl(
            action: 'wicket',
            label: freeHit ? 'Run out only' : 'Wicket',
            style: ControlStyle.danger,
            payload: freeHit ? const {'runOut': true} : const {},
            shortcut: 'w',
            tooltip: freeHit
                ? 'Free hit — only a run out is allowed.'
                : 'Bowled, caught, lbw, stumped or run out.',
          ),
        ],
      ),
      const ScoreControlGroup(
        title: 'Innings',
        controls: [
          ScoreControl(
            action: 'end_innings',
            label: 'End innings',
            style: ControlStyle.danger,
            shortcut: 'e',
          ),
        ],
      ),
    ];
  }
}
