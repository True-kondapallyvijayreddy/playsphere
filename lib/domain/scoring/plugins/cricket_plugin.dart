import '../../../core/models/fixture.dart' show MatchEvent;
import '../player_stats.dart';
import '../scoring_plugin.dart';
import 'cricket_scorecard.dart';

/// Ball-by-ball limited-overs cricket, with player-level statistics.
///
/// Benchmarked on CricHeroes, per the spec. Every delivery names a striker, a
/// non-striker and a bowler, which is what makes a scorecard, batting figures,
/// bowling figures and net run rate possible at all. An engine that only
/// tracks a team total can show a score; it cannot show a career.
///
/// The rules encoded here are the ones naive implementations get wrong, and
/// each is a result-changing error rather than a cosmetic one:
///
///  * **Wides and no-balls are not legal deliveries.** If the ball counter
///    increments on them, every over ends early and an innings finishes
///    several overs short. This is the single most common cricket scoring bug.
///  * **Balls faced includes no-balls but excludes wides.** The batter had a
///    chance to play a no-ball; on a wide they did not.
///  * **A no-ball grants a free hit**, on which only a run-out is possible.
///  * **Byes and leg-byes are extras that DO consume a delivery** — the exact
///    opposite of a wide — and are charged to neither batter nor bowler.
///  * **Runs conceded excludes byes and leg-byes** but includes wides and
///    no-balls. Charging byes to the bowler is how amateur figures go wrong.
///  * **A run-out is not credited to the bowler.**
///  * **A chase ends the instant the target is passed**, mid-over.
///  * **Levelling the target is a tie, not a win.**
///  * **Overs are decimalised by balls/6.** 47.2 overs is 47.333, never 47.4 —
///    get this wrong and every net run rate in the table is wrong.
class CricketPlugin extends ScoringPlugin {
  const CricketPlugin();

  static const pluginKey = 'cricket';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Cricket (ball by ball)';

  @override
  List<String> get headlineStats => const [_runsScored, _wickets];

  // Per-player tally keys.
  //
  // Cricket keeps its authoritative figures inside the innings records, which
  // is what the scorecard renders from. These are a mirror of the same facts
  // in the shared shape every other sport uses, so that the career aggregator
  // and the rating service — neither of which knows anything about innings —
  // can read cricket at all. Without this mirror the flagship sport
  // contributes nothing to a player's lifelong record.
  static const _runsScored = 'runsScored';
  static const _ballsFaced = 'ballsFaced';
  static const _fours = 'fours';
  static const _sixes = 'sixes';
  static const _dismissed = 'dismissed';
  static const _wickets = 'wickets';
  static const _ballsBowled = 'ballsBowled';
  static const _runsConceded = 'runsConceded';
  static const _maidens = 'maidens';
  static const _catches = 'catches';
  static const _stumpings = 'stumpings';
  static const _runOuts = 'runOuts';
  static const _runOutAssists = 'runOutAssists';

  int _ballsPerOver(ScoringContext ctx) => ctx.intConfig('ballsPerOver', 6);

  /// How many deliveries the strip remembers.
  ///
  /// Seven overs of a six-ball format, which is comfortably more than the
  /// "last ten balls" a pad shows and leaves room for the wides and no-balls
  /// that make an over longer than its name. The cost of a larger number is
  /// paid by every spectator's device on every ball, because the timeline
  /// rides on the fixture document that all of them are listening to.
  static const _timelineCap = 42;
  int _overs(ScoringContext ctx) => ctx.intConfig('oversPerInnings', 20);
  int _wicketsAllowed(ScoringContext ctx) =>
      ctx.intConfig('playersPerTeam', 11) - 1;

  /// The penalty for a wide. Two under most tennis-ball and gully rules, one
  /// under the ICC playing conditions.
  int _wideRuns(ScoringContext ctx) => ctx.intConfig('wideRuns', 1);
  int _noBallRuns(ScoringContext ctx) => ctx.intConfig('noBallRuns', 1);

  /// Whether a no-ball grants a free hit. Off in most non-limited-overs and
  /// tennis-ball formats.
  bool _freeHitEnabled(ScoringContext ctx) =>
      ctx.boolConfig('freeHitOnNoBall', true);

  /// Whether the bowler must change at the end of every over.
  ///
  /// True everywhere the game is played to its own laws: no bowler may bowl
  /// two overs in succession. It is configurable only because a handful of
  /// short indoor and single-wicket formats drop the rule, not because a
  /// scorer should be able to switch it off to save a tap.
  bool _enforceBowlerChange(ScoringContext ctx) =>
      ctx.boolConfig('bowlerMustChangeEachOver', true);

  int _boundaryFour(ScoringContext ctx) => ctx.intConfig('boundaryFour', 4);
  int _boundarySix(ScoringContext ctx) => ctx.intConfig('boundarySix', 6);

  /// Who gets credit in the field for a dismissal, and for what.
  ///
  /// The spec asks for catches, stumpings and run-outs as first-class fielding
  /// statistics. Before this they existed only inside the dismissal *string*
  /// ("c Reddy b Sharma"), which reads correctly on a scorecard and is
  /// invisible to a career record.
  Map<String, Map<String, num>> _fieldingCredits(
    ScoreAction action,
    bool isRunOut,
  ) {
    final type = action.payload['type'] as String? ??
        (isRunOut ? 'run_out' : 'bowled');
    final fielder = action.payload['fielder'] as String?;
    final keeper = action.payload['keeper'] as String?;
    final credits = <String, Map<String, num>>{};

    void give(String? id, String key) {
      if (id == null || id.isEmpty) return;
      credits[id] = {...?credits[id], key: (credits[id]?[key] ?? 0) + 1};
    }

    switch (type) {
      case 'caught':
        // A caught-behind is a catch to the keeper, not a stumping.
        give(fielder ?? keeper, _catches);
      case 'stumped':
        give(keeper ?? fielder, _stumpings);
      case 'run_out':
        give(fielder, _runOuts);
        // A second name on a run-out is the assist — the throw, where the
        // first name took the bails off.
        final assist = action.payload['assist'] as String?;
        give(assist, _runOutAssists);
    }
    return credits;
  }

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
      PlayerTally.stateKey: <String, dynamic>{},
    };
  }

  static Map<String, dynamic> _newInnings(String battingSide) => {
        'battingSide': battingSide,
        'runs': 0,
        'wickets': 0,
        'legalBalls': 0,
        'extras': {'wide': 0, 'noBall': 0, 'bye': 0, 'legBye': 0},
        'closed': false,
        'striker': null,
        'nonStriker': null,
        'bowler': null,
        'batting': <String, dynamic>{},
        'bowling': <String, dynamic>{},
        'fow': <Map<String, dynamic>>[],
        // Ball by ball, oldest first — what the pad's recent-deliveries strip
        // is drawn from, and the only record of "what have the last six balls
        // been" that survives a reopened app.
        //
        // On the projection rather than derived from the event log at read
        // time, because the pad renders the projection and nothing else: a
        // strip fed from the log would need a fetch per repaint on a device
        // chosen for its camera rather than its signal, and would be empty
        // for the whole of the first frame after every tap.
        //
        // Bounded — see [_timelineCap]. An innings is a few hundred balls and
        // the fixture document is read by every spectator watching.
        'timeline': <Map<String, dynamic>>[],
        // Runs conceded by the current bowler in the over in progress, used
        // only to decide whether it was a maiden.
        'overRuns': 0,
      };

  static Map<String, dynamic> _newBatting() => {
        'runs': 0,
        'balls': 0,
        'fours': 0,
        'sixes': 0,
        'out': false,
        'dismissal': null,
        'battedYet': true,
      };

  static Map<String, dynamic> _newBowling() => {
        'balls': 0,
        'runs': 0,
        'wickets': 0,
        'maidens': 0,
        'wides': 0,
        'noBalls': 0,
      };

  Map<String, dynamic> _current(Map<String, dynamic> state) {
    final innings = copyList(state['innings']);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    if (idx < innings.length) return innings[idx];
    return _newInnings('a');
  }

  // -------------------------------------------------------------------------
  // Reducer
  // -------------------------------------------------------------------------

  @override
  ScoringResult apply(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    if (state['locked'] == true) {
      return const ScoringResult.rejected(
        'This match is locked by the organizer and cannot be modified.',
      );
    }

    if (state['complete'] == true &&
        action.type != 'reopen' &&
        action.type != 'lock_match' &&
        action.type != 'start_super_over') {
      return const ScoringResult.rejected(
        'This match is already finished. Reopen it to make a correction.',
      );
    }

    if (action.type == 'start_super_over') {
      final innings = copyList(state['innings']);
      // Add Super Over Innings 3 (Team A or B, 1-over max)
      final sideA = innings.first['battingSide'] as String? ?? 'a';
      final sideB = sideA == 'a' ? 'b' : 'a';
      innings.add(_newInnings(sideB));
      return ScoringResult.ok(mutate(state, (s) {
        s['complete'] = false;
        s['tie'] = false;
        s['superOver'] = true;
        s['innings'] = innings;
        s['inningsIndex'] = 2;
        s['target'] = null;
      }));
    }

    if (action.type == 'lock_match') {
      return ScoringResult.ok(mutate(state, (s) => s['locked'] = true));
    }

    if (action.type == 'reopen') {
      // Reopening must also unclose the innings, otherwise the very next
      // action settles the match again and the correction is impossible.
      final innings = copyList(state['innings']);
      final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
      if (idx < innings.length) {
        innings[idx] = {...innings[idx], 'closed': false};
      }
      return ScoringResult.ok(mutate(state, (s) {
        s['innings'] = innings;
        s['complete'] = false;
        s['winner'] = null;
        s['tie'] = false;
      }));
    }

    final innings = copyList(state['innings']);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    if (idx >= innings.length) {
      return const ScoringResult.rejected('No innings in progress.');
    }

    final cur = Map<String, dynamic>.from(innings[idx]);
    final extras = Map<String, dynamic>.from(cur['extras'] as Map? ?? {});
    final batting = Map<String, dynamic>.from(cur['batting'] as Map? ?? {});
    final bowling = Map<String, dynamic>.from(cur['bowling'] as Map? ?? {});
    final fow = copyList(cur['fow']);
    final timeline = copyList(cur['timeline']);
    final freeHit = state['freeHit'] == true;
    final perOver = _ballsPerOver(ctx);

    int i(Object? v) => (v as num?)?.toInt() ?? 0;

    // --- opening and personnel changes -----------------------------------

    switch (action.type) {
      case 'open':
        final striker = action.payload['striker'] as String?;
        final nonStriker = action.payload['nonStriker'] as String?;
        final bowler = action.payload['bowler'] as String?;
        if (striker == null || nonStriker == null || bowler == null) {
          return const ScoringResult.rejected(
            'Choose both batters and the bowler before the first ball.',
          );
        }
        if (striker == nonStriker) {
          return const ScoringResult.rejected(
            'The same player cannot be on strike and at the other end.',
          );
        }
        batting[striker] = batting[striker] ?? _newBatting();
        batting[nonStriker] = batting[nonStriker] ?? _newBatting();
        bowling[bowler] = bowling[bowler] ?? _newBowling();
        cur
          ..['striker'] = striker
          ..['nonStriker'] = nonStriker
          ..['bowler'] = bowler
          ..['batting'] = batting
          ..['bowling'] = bowling;
        innings[idx] = cur;
        return ScoringResult.ok(mutate(state, (s) => s['innings'] = innings));

      case 'new_batter':
        final who = action.payload['playerId'] as String?;
        if (who == null) {
          return const ScoringResult.rejected('Choose the incoming batter.');
        }
        if (cur['striker'] != null) {
          return const ScoringResult.rejected(
            'There is already a batter on strike.',
          );
        }
        if ((batting[who] as Map?)?['out'] == true) {
          return const ScoringResult.rejected(
            'That batter is already out.',
          );
        }
        batting[who] = batting[who] ?? _newBatting();
        cur
          ..['striker'] = who
          ..['batting'] = batting;
        innings[idx] = cur;
        return ScoringResult.ok(mutate(state, (s) => s['innings'] = innings));

      case 'new_bowler':
        final who = action.payload['playerId'] as String?;
        if (who == null) {
          return const ScoringResult.rejected('Choose the next bowler.');
        }
        // No bowler may bowl two overs in succession. Caught here rather than
        // left to the scorer, because the person tapping is watching the game
        // and the app is the only thing counting.
        if (_enforceBowlerChange(ctx) && who == cur['lastBowler']) {
          return ScoringResult.rejected(
            '${ctx.playerName(who, 'That bowler')} bowled the last over. '
            'Somebody else has to bowl this one.',
          );
        }
        bowling[who] = bowling[who] ?? _newBowling();
        cur
          ..['bowler'] = who
          ..['bowling'] = bowling;
        // `overRuns` is NOT reset here, and that is the fix rather than an
        // omission. It counts what has been conceded in the over in progress,
        // and it is reset where an over actually ends — below, at the ball
        // boundary. Clearing it on every bowler change meant a bowler brought
        // on mid-over (an injury, a scorer correcting the wrong name) started
        // from zero, so two dot balls at the end of somebody else's expensive
        // over were recorded as a maiden.
        innings[idx] = cur;
        return ScoringResult.ok(mutate(state, (s) => s['innings'] = innings));

      case 'swap_strike':
        final s1 = cur['striker'];
        cur
          ..['striker'] = cur['nonStriker']
          ..['nonStriker'] = s1;
        innings[idx] = cur;
        return ScoringResult.ok(mutate(state, (s) => s['innings'] = innings));

      case 'end_innings':
        cur['closed'] = true;
        innings[idx] = cur;
        return ScoringResult.ok(
          _settle(mutate(state, (s) => s['innings'] = innings), ctx),
        );
    }

    // --- deliveries -------------------------------------------------------
    //
    // Everything below needs someone on strike and someone bowling. Scoring a
    // delivery with nobody named would produce a total that no scorecard can
    // account for, which is precisely the state this engine exists to prevent.

    final striker = cur['striker'] as String?;
    final bowler = cur['bowler'] as String?;
    if (striker == null || bowler == null) {
      return const ScoringResult.rejected(
        'Set the batters and bowler before scoring a delivery.',
      );
    }

    final bat = Map<String, dynamic>.from(batting[striker] as Map? ?? _newBatting());
    final bowl = Map<String, dynamic>.from(bowling[bowler] as Map? ?? _newBowling());

    var legalDelivery = false;
    var runsThisBall = 0; // for strike rotation
    var nextFreeHit = false;
    var wicketFell = false;
    // Whether the batter who went was the one on strike. A non-striker
    // run-out leaves the striker where they are.
    var wicketWasStriker = true;
    String? dismissedPlayerId;
    // Catches, stumpings and run-outs to credit to the fielding side.
    var fielderCredits = const <String, Map<String, num>>{};

    switch (action.type) {
      case 'runs':
        final r = i(action.payload['runs']);
        if (r < 0 || r > 8) {
          return const ScoringResult.rejected('Runs off a ball must be 0-8.');
        }
        cur['runs'] = i(cur['runs']) + r;
        bat['runs'] = i(bat['runs']) + r;
        bat['balls'] = i(bat['balls']) + 1;
        if (r == _boundaryFour(ctx)) bat['fours'] = i(bat['fours']) + 1;
        if (r == _boundarySix(ctx)) bat['sixes'] = i(bat['sixes']) + 1;
        bowl['runs'] = i(bowl['runs']) + r;
        cur['overRuns'] = i(cur['overRuns']) + r;
        legalDelivery = true;
        runsThisBall = r;

      case 'wide':
        // Penalty run plus anything run. Not a legal delivery, and the batter
        // faced nothing — so no ball is added to their tally. Does not clear
        // an existing free hit.
        final extra = i(action.payload['runs']);
        final total = _wideRuns(ctx) + extra;
        cur['runs'] = i(cur['runs']) + total;
        extras['wide'] = i(extras['wide']) + total;
        bowl['runs'] = i(bowl['runs']) + total;
        bowl['wides'] = i(bowl['wides']) + 1;
        cur['overRuns'] = i(cur['overRuns']) + total;
        nextFreeHit = freeHit;
        runsThisBall = extra;

      case 'no_ball':
        // Penalty plus runs off the bat. Not a legal delivery, but the batter
        // did face it, so it counts as a ball faced and the runs are theirs.
        final offBat = i(action.payload['runs']);
        final penalty = _noBallRuns(ctx);
        cur['runs'] = i(cur['runs']) + penalty + offBat;
        extras['noBall'] = i(extras['noBall']) + penalty;
        bat['runs'] = i(bat['runs']) + offBat;
        bat['balls'] = i(bat['balls']) + 1;
        if (offBat == _boundaryFour(ctx)) bat['fours'] = i(bat['fours']) + 1;
        if (offBat == _boundarySix(ctx)) bat['sixes'] = i(bat['sixes']) + 1;
        bowl['runs'] = i(bowl['runs']) + penalty + offBat;
        bowl['noBalls'] = i(bowl['noBalls']) + 1;
        cur['overRuns'] = i(cur['overRuns']) + penalty + offBat;
        nextFreeHit = _freeHitEnabled(ctx);
        runsThisBall = offBat;

      case 'bye':
      case 'leg_bye':
        final r = i(action.payload['runs']) == 0 ? 1 : i(action.payload['runs']);
        if (r <= 0) {
          return const ScoringResult.rejected('Byes must be at least 1 run.');
        }
        cur['runs'] = i(cur['runs']) + r;
        extras[action.type == 'bye' ? 'bye' : 'legBye'] =
            i(extras[action.type == 'bye' ? 'bye' : 'legBye']) + r;
        // The batter faced it, so it is a ball faced — but the runs are the
        // team's, not theirs, and the bowler is NOT charged.
        bat['balls'] = i(bat['balls']) + 1;
        legalDelivery = true;
        runsThisBall = r;

      case 'wicket':
        final dismissalType = action.payload['type'] as String? ??
            (action.payload['runOut'] == true ? 'run_out' : 'bowled');
        final isRunOut = dismissalType == 'run_out';
        // Which dismissals belong to the bowler's figures.
        //
        // A run-out never has, and §7.1 says so. A retirement does not either
        // — nobody got the batter out — and while the type existed in
        // `_dismissalText` from the beginning, the only check here was "is it
        // a run-out", so a retirement quietly inflated the bowler's wickets
        // and their bowling average with it.
        final creditsBowler = !isRunOut && dismissalType != 'retired';
        if (freeHit && !isRunOut) {
          return const ScoringResult.rejected(
            'Free hit — the batter can only be run out on this delivery.',
          );
        }
        if (i(cur['wickets']) >= _wicketsAllowed(ctx)) {
          return const ScoringResult.rejected('All out already.');
        }

        // A dismissal can happen off an illegal delivery: a batter can be
        // stumped off a wide, or run out off a no-ball. When it does, the
        // delivery keeps its own legality and its own penalty run — treating
        // every wicket as a legal ball loses both.
        final onDelivery =
            action.payload['delivery'] as String? ?? 'legal';
        final offWide = onDelivery == 'wide';
        final offNoBall = onDelivery == 'no_ball';

        // Who actually went. A non-striker run out is the case a naive engine
        // gets wrong: it debits the striker, corrupting their average and the
        // fall-of-wicket line for the rest of the innings.
        final dismissedId = action.payload['playerId'] as String? ?? striker;
        final nonStrikerId = cur['nonStriker'] as String?;
        final dismissedIsStriker = dismissedId == striker;
        if (!dismissedIsStriker && dismissedId != nonStrikerId) {
          return const ScoringResult.rejected(
            'The dismissed player must be one of the two batters at the '
            'crease.',
          );
        }

        final dismissed = dismissedIsStriker
            ? bat
            : Map<String, dynamic>.from(
                batting[dismissedId] as Map? ?? _newBatting(),
              );

        final withRuns = i(action.payload['runs']);
        if (offWide) {
          // Penalty plus anything run; nothing to the batter.
          final total = _wideRuns(ctx) + withRuns;
          cur['runs'] = i(cur['runs']) + total;
          extras['wide'] = i(extras['wide']) + total;
          bowl['runs'] = i(bowl['runs']) + total;
          bowl['wides'] = i(bowl['wides']) + 1;
          cur['overRuns'] = i(cur['overRuns']) + total;
        } else if (offNoBall) {
          final total = _noBallRuns(ctx) + withRuns;
          cur['runs'] = i(cur['runs']) + total;
          extras['noBall'] = i(extras['noBall']) + _noBallRuns(ctx);
          bat['runs'] = i(bat['runs']) + withRuns;
          bat['balls'] = i(bat['balls']) + 1;
          bowl['runs'] = i(bowl['runs']) + total;
          bowl['noBalls'] = i(bowl['noBalls']) + 1;
          cur['overRuns'] = i(cur['overRuns']) + total;
        } else {
          if (withRuns > 0) {
            cur['runs'] = i(cur['runs']) + withRuns;
            bat['runs'] = i(bat['runs']) + withRuns;
            bowl['runs'] = i(bowl['runs']) + withRuns;
            cur['overRuns'] = i(cur['overRuns']) + withRuns;
          }
          // Only a legal delivery is a ball faced by the striker.
          bat['balls'] = i(bat['balls']) + 1;
        }

        dismissed['out'] = true;
        dismissed['dismissal'] = _dismissalText(action, ctx);
        cur['wickets'] = i(cur['wickets']) + 1;
        // A run-out is not the bowler's wicket, nor is a retirement, and a
        // wicket off a wide can only ever be a run-out or a stumping.
        if (creditsBowler) bowl['wickets'] = i(bowl['wickets']) + 1;

        if (!dismissedIsStriker) batting[dismissedId] = dismissed;

        legalDelivery = !offWide && !offNoBall;
        // A no-ball still grants the free hit even when a run-out falls off it.
        nextFreeHit = offNoBall && _freeHitEnabled(ctx);
        wicketFell = true;
        wicketWasStriker = dismissedIsStriker;
        dismissedPlayerId = dismissedId;
        fielderCredits = _fieldingCredits(action, isRunOut);
        runsThisBall = withRuns;

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }

    // A legal delivery counts against the bowler's over as well as the
    // innings. Byes and leg-byes count here too: the bowler still bowled the
    // ball, they simply are not charged the runs.
    if (legalDelivery) {
      bowl['balls'] = i(bowl['balls']) + 1;
      cur['legalBalls'] = i(cur['legalBalls']) + 1;
    }

    batting[striker] = bat;
    bowling[bowler] = bowl;

    // The delivery, as the strip will draw it. Recorded here rather than in
    // each `case` above because what a ball WAS is only settled once the
    // wicket branch has had its say: a run-out off a no-ball is both, and the
    // strip has to show the dismissal.
    timeline.add(_chip(action, ctx, wicketFell: wicketFell));
    if (timeline.length > _timelineCap) {
      timeline.removeRange(0, timeline.length - _timelineCap);
    }

    if (wicketFell) {
      fow.add({
        'n': i(cur['wickets']),
        'runs': i(cur['runs']),
        'balls': i(cur['legalBalls']),
        'playerId': dismissedPlayerId ?? striker,
      });
      // The crease the dismissed batter left is the one that needs filling.
      // A non-striker run-out leaves the striker exactly where they were.
      if (wicketWasStriker) {
        cur['striker'] = null;
      } else {
        cur['nonStriker'] = null;
      }
    } else if (runsThisBall.isOdd) {
      // Odd runs put the other batter on strike.
      final s1 = cur['striker'];
      cur['striker'] = cur['nonStriker'];
      cur['nonStriker'] = s1;
    }

    // End of over: strike rotates, the bowler must change, and a maiden is
    // recorded if nothing at all was conceded.
    if (legalDelivery && i(cur['legalBalls']) % perOver == 0) {
      // What turns a row of numbers into overs. A scorer, a captain and a
      // commentator all think in overs, never in "the last nine deliveries".
      timeline.last['over'] = true;
      if (i(cur['overRuns']) == 0) {
        bowl['maidens'] = i(bowl['maidens']) + 1;
        bowling[bowler] = bowl;
      }
      cur['overRuns'] = 0;
      final s1 = cur['striker'];
      cur['striker'] = cur['nonStriker'];
      cur['nonStriker'] = s1;

      // Clearing the bowler is what actually enforces the change. The comment
      // above said the bowler must change while the code let the same one keep
      // going over after over, so a full innings could be recorded against one
      // name — wrong figures for every bowler in the match, and an over count
      // no scorecard could account for. A null bowler makes the next delivery
      // impossible to score until somebody is named, and `controls` asks.
      if (_enforceBowlerChange(ctx)) {
        cur['lastBowler'] = bowler;
        cur['bowler'] = null;
      }
    }

    cur
      ..['extras'] = extras
      ..['batting'] = batting
      ..['bowling'] = bowling
      ..['fow'] = fow
      ..['timeline'] = timeline;
    innings[idx] = cur;

    var next = mutate(state, (s) {
      s['innings'] = innings;
      s['freeHit'] = nextFreeHit;
    });

    next = _mirrorToTally(
      next,
      striker: striker,
      bowler: bowler,
      dismissedId: dismissedPlayerId,
      fielderCredits: fielderCredits,
      innings: innings,
    );

    return ScoringResult.ok(_settle(next, ctx));
  }

  /// Rewrites the shared per-player tally from the innings records.
  ///
  /// Recomputed from the authoritative innings rather than incremented
  /// alongside them. Two counters maintained in parallel drift the moment any
  /// path updates one and not the other — and the whole reason this mirror
  /// exists is that a career record has to agree with the scorecard.
  Map<String, dynamic> _mirrorToTally(
    Map<String, dynamic> state, {
    required String striker,
    required String bowler,
    String? dismissedId,
    required Map<String, Map<String, num>> fielderCredits,
    required List<Map<String, dynamic>> innings,
  }) {
    // Fielding credits accumulate — they are not derivable from the innings
    // records, which only hold batting and bowling.
    final existing = Map<String, dynamic>.from(
      state[PlayerTally.stateKey] as Map? ?? const <String, dynamic>{},
    );
    final fielding = <String, Map<String, num>>{};
    for (final entry in existing.entries) {
      final t = entry.value as Map? ?? const {};
      final keep = <String, num>{};
      for (final k in [_catches, _stumpings, _runOuts, _runOutAssists]) {
        final v = t[k];
        if (v is num && v != 0) keep[k] = v;
      }
      if (keep.isNotEmpty) fielding[entry.key] = keep;
    }
    for (final entry in fielderCredits.entries) {
      final merged = Map<String, num>.from(fielding[entry.key] ?? const {});
      for (final d in entry.value.entries) {
        merged[d.key] = (merged[d.key] ?? 0) + d.value;
      }
      fielding[entry.key] = merged;
    }

    final tally = <String, dynamic>{};
    void put(String id, String key, num value) {
      if (value == 0) return;
      final mine = Map<String, dynamic>.from(
        tally[id] as Map? ?? const <String, dynamic>{},
      );
      mine[key] = (mine[key] as num? ?? 0) + value;
      tally[id] = mine;
    }

    for (final inn in innings) {
      final bat = inn['batting'] as Map? ?? const {};
      for (final e in bat.entries) {
        final id = e.key.toString();
        final r = e.value as Map? ?? const {};
        put(id, _runsScored, (r['runs'] as num?) ?? 0);
        put(id, _ballsFaced, (r['balls'] as num?) ?? 0);
        put(id, _fours, (r['fours'] as num?) ?? 0);
        put(id, _sixes, (r['sixes'] as num?) ?? 0);
        if (r['out'] == true) put(id, _dismissed, 1);
      }

      final bowl = inn['bowling'] as Map? ?? const {};
      for (final e in bowl.entries) {
        final id = e.key.toString();
        final r = e.value as Map? ?? const {};
        put(id, _wickets, (r['wickets'] as num?) ?? 0);
        put(id, _ballsBowled, (r['balls'] as num?) ?? 0);
        put(id, _runsConceded, (r['runs'] as num?) ?? 0);
        put(id, _maidens, (r['maidens'] as num?) ?? 0);
      }
    }

    for (final entry in fielding.entries) {
      for (final d in entry.value.entries) {
        put(entry.key, d.key, d.value);
      }
    }

    return {...state, PlayerTally.stateKey: tally};
  }

  String _dismissalText(ScoreAction action, ScoringContext ctx) {
    final type = action.payload['type'] as String? ??
        (action.payload['runOut'] == true ? 'run_out' : 'bowled');
    final fielder = ctx.player(action.payload['fielder'] as String?)?.name;
    return switch (type) {
      'bowled' => 'b ${_bowlerName(action, ctx)}',
      'lbw' => 'lbw b ${_bowlerName(action, ctx)}',
      'caught' => fielder == null
          ? 'c & b ${_bowlerName(action, ctx)}'
          : 'c $fielder b ${_bowlerName(action, ctx)}',
      'stumped' => fielder == null
          ? 'st b ${_bowlerName(action, ctx)}'
          : 'st $fielder b ${_bowlerName(action, ctx)}',
      'run_out' => fielder == null ? 'run out' : 'run out ($fielder)',
      'hit_wicket' => 'hit wicket b ${_bowlerName(action, ctx)}',
      'retired' => 'retired',
      _ => type,
    };
  }

  String _bowlerName(ScoreAction action, ScoringContext ctx) =>
      ctx.playerName(action.payload['bowler'] as String?, 'bowler');

  // -------------------------------------------------------------------------
  // Settlement
  // -------------------------------------------------------------------------

  Map<String, dynamic> _settle(Map<String, dynamic> state, ScoringContext ctx) {
    final innings = copyList(state['innings']);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    final cur = Map<String, dynamic>.from(innings[idx]);

    final runs = (cur['runs'] as num?)?.toInt() ?? 0;
    final wickets = (cur['wickets'] as num?)?.toInt() ?? 0;
    final legalBalls = (cur['legalBalls'] as num?)?.toInt() ?? 0;
    final isSuperOver = state['superOver'] == true && idx >= 2;
    // Super Over innings are 1 over; regular innings use the configured value.
    final effectiveOvers = isSuperOver ? 1 : _overs(ctx);
    final maxBalls = effectiveOvers * _ballsPerOver(ctx);
    final target = (state['target'] as num?)?.toInt();
    // In a regular match the chasing innings is idx 1. In a Super Over the
    // batting-first SO is idx 2 (even) and the chasing SO is idx 3 (odd).
    // The pattern generalises: even indices bat first, odd indices chase.
    final isChasingInnings = idx.isOdd;

    // A chase ends the moment the target is passed, mid-over.
    final chaseWon = isChasingInnings && target != null && runs >= target;

    // Super Over wickets: only 2 wickets per side (1 wicket in some formats),
    // but we reuse _wicketsAllowed for the regular match. For Super Over,
    // the innings ends on all-out (all available batters) or overs exhausted.
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

    if (!isChasingInnings) {
      final battingFirst = cur['battingSide'] as String? ?? 'a';
      final chasingSide = battingFirst == 'a' ? 'b' : 'a';
      innings.add(_newInnings(chasingSide));
      return mutate(state, (s) {
        s['innings'] = innings;
        s['inningsIndex'] = idx + 1;
        s['target'] = runs + 1;
        s['freeHit'] = false;
      });
    }

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

  // -------------------------------------------------------------------------
  // Projections
  // -------------------------------------------------------------------------

  /// The full card for one innings — the thing a player screenshots.
  InningsCard? card(
    Map<String, dynamic> state,
    ScoringContext ctx, {
    int? inningsIndex,
  }) {
    final innings = copyList(state['innings']);
    final idx = inningsIndex ?? ((state['inningsIndex'] as num?)?.toInt() ?? 0);
    if (idx >= innings.length) return null;
    final inn = innings[idx];
    final perOver = _ballsPerOver(ctx);

    int i(Object? v) => (v as num?)?.toInt() ?? 0;

    final battingSide = Side.fromWire(inn['battingSide'] as String?);
    final battingMap = Map<String, dynamic>.from(inn['batting'] as Map? ?? {});
    final bowlingMap = Map<String, dynamic>.from(inn['bowling'] as Map? ?? {});

    // The batting side's whole squad appears, so a player who did not bat is
    // shown as "did not bat" rather than being silently missing.
    final squad = ctx.lineupFor(battingSide);
    final batting = <BattingLine>[];
    for (final p in squad) {
      final b = battingMap[p.id] as Map?;
      batting.add(BattingLine(
        playerId: p.id,
        name: p.name,
        runs: i(b?['runs']),
        balls: i(b?['balls']),
        fours: i(b?['fours']),
        sixes: i(b?['sixes']),
        isOut: b?['out'] == true,
        battedYet: b != null,
        dismissal: b?['dismissal'] as String?,
      ));
    }
    // Anyone who batted but is not in the recorded squad — a late substitute —
    // must still appear.
    for (final entry in battingMap.entries) {
      if (squad.any((p) => p.id == entry.key)) continue;
      final b = Map<String, dynamic>.from(entry.value as Map);
      batting.add(BattingLine(
        playerId: entry.key,
        name: ctx.playerName(entry.key),
        runs: i(b['runs']),
        balls: i(b['balls']),
        fours: i(b['fours']),
        sixes: i(b['sixes']),
        isOut: b['out'] == true,
        battedYet: true,
        dismissal: b['dismissal'] as String?,
      ));
    }

    final bowling = [
      for (final entry in bowlingMap.entries)
        BowlingLine(
          playerId: entry.key,
          name: ctx.playerName(entry.key),
          legalBalls: i((entry.value as Map)['balls']),
          runsConceded: i((entry.value as Map)['runs']),
          wickets: i((entry.value as Map)['wickets']),
          maidens: i((entry.value as Map)['maidens']),
          wides: i((entry.value as Map)['wides']),
          noBalls: i((entry.value as Map)['noBalls']),
          ballsPerOver: perOver,
        ),
    ];

    final fow = [
      for (final f in copyList(inn['fow']))
        FallOfWicket(
          wicketNumber: i(f['n']),
          runs: i(f['runs']),
          legalBalls: i(f['balls']),
          playerId: _asId(f['playerId']),
          name: ctx.playerName(f['playerId'] as String?),
          ballsPerOver: perOver,
        ),
    ];

    final extrasRaw = Map<String, dynamic>.from(inn['extras'] as Map? ?? {});

    return InningsCard(
      battingSide: battingSide,
      runs: i(inn['runs']),
      wickets: i(inn['wickets']),
      legalBalls: i(inn['legalBalls']),
      ballsPerOver: perOver,
      extras: {for (final e in extrasRaw.entries) e.key: i(e.value)},
      batting: batting,
      bowling: bowling,
      fallOfWickets: fow,
      isClosed: inn['closed'] == true,
    );
  }

  static String _asId(Object? v) => v is String ? v : '';

  /// Bowling figures need the bowler's balls; batting needs the striker's.
  /// Both are already on the card, so this is just a convenience for callers
  /// that want every innings at once.
  List<InningsCard> allCards(Map<String, dynamic> state, ScoringContext ctx) {
    final count = copyList(state['innings']).length;
    return [
      for (var n = 0; n < count; n++)
        if (card(state, ctx, inningsIndex: n) case final c?) c,
    ];
  }

  /// One delivery, reduced to what a strip of them needs: what to print, and
  /// what kind of thing it was. See [BallChip].
  ///
  /// A wicket prints as a wicket whatever else the ball was — a run-out off a
  /// no-ball is, to everybody watching, the ball somebody got out on.
  Map<String, dynamic> _chip(
    ScoreAction action,
    ScoringContext ctx, {
    required bool wicketFell,
  }) {
    if (wicketFell) return {'l': 'W', 'k': 'wicket'};
    final runs = (action.payload['runs'] as num?)?.toInt() ?? 0;
    return switch (action.type) {
      'wide' => {'l': runs == 0 ? 'Wd' : 'Wd+$runs', 'k': 'extra'},
      'no_ball' => {'l': runs == 0 ? 'Nb' : 'Nb+$runs', 'k': 'extra'},
      'bye' => {'l': '${runs == 0 ? 1 : runs}B', 'k': 'extra'},
      'leg_bye' => {'l': '${runs == 0 ? 1 : runs}Lb', 'k': 'extra'},
      // Runs off the bat. A dot is drawn as a dot, not as a nought, because
      // that is the mark a scorer's eye counts down a scorebook column.
      _ when runs == 0 => {'l': '•', 'k': 'dot'},
      _ when runs == _boundaryFour(ctx) => {'l': '4', 'k': 'four'},
      _ when runs == _boundarySix(ctx) => {'l': '6', 'k': 'six'},
      _ => {'l': '$runs', 'k': 'runs'},
    };
  }

  static BallKind _kindFromWire(Object? wire) => switch (wire) {
        'dot' => BallKind.dot,
        'four' => BallKind.boundary,
        'six' => BallKind.maximum,
        'wicket' => BallKind.wicket,
        'extra' => BallKind.extra,
        _ => BallKind.runs,
      };

  /// A rate, to one decimal, or an em dash.
  ///
  /// Zero is the wrong answer for "no balls faced yet": a batter on 0 off 0 is
  /// not striking at 0.0, they have not struck at all, and a pad that prints
  /// 0.0 tells a captain their opener is failing before the first ball is
  /// bowled.
  static String _rate(num numerator, num denominator) =>
      denominator <= 0 ? '—' : (numerator / denominator).toStringAsFixed(1);

  @override
  PadLayout get padLayout => PadLayout.crease;

  @override
  CreaseBoard? creaseBoard(Map<String, dynamic> state, ScoringContext ctx) {
    final cur = _current(state);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    final perOver = _ballsPerOver(ctx);
    final isSuperOver = state['superOver'] == true && idx >= 2;
    final effectiveOvers = isSuperOver ? 1 : _overs(ctx);

    final runs = (cur['runs'] as num?)?.toInt() ?? 0;
    final wickets = (cur['wickets'] as num?)?.toInt() ?? 0;
    final legalBalls = (cur['legalBalls'] as num?)?.toInt() ?? 0;

    final extrasMap = cur['extras'] as Map? ?? const {};
    var extras = 0;
    for (final v in extrasMap.values) {
      extras += (v as num?)?.toInt() ?? 0;
    }

    final batting = cur['batting'] as Map? ?? const {};
    CreaseBatter? batter(Object? id, {required bool onStrike}) {
      if (id is! String) return null;
      final b = batting[id] as Map? ?? const {};
      int f(String k) => (b[k] as num?)?.toInt() ?? 0;
      final faced = f('balls');
      return CreaseBatter(
        name: ctx.playerName(id, 'Batter'),
        runs: f('runs'),
        balls: faced,
        fours: f('fours'),
        sixes: f('sixes'),
        strikeRate: _rate(f('runs') * 100, faced),
        onStrike: onStrike,
      );
    }

    final bowlerId = cur['bowler'];
    final bowlingMap = cur['bowling'] as Map? ?? const {};
    CreaseBowler? bowler;
    if (bowlerId is String) {
      final b = bowlingMap[bowlerId] as Map? ?? const {};
      int f(String k) => (b[k] as num?)?.toInt() ?? 0;
      final bowled = f('balls');
      bowler = CreaseBowler(
        name: ctx.playerName(bowlerId, 'Bowler'),
        overs: _oversText(bowled, ctx),
        maidens: f('maidens'),
        runs: f('runs'),
        wickets: f('wickets'),
        // Per OVER, not per ball — the one place the six has to be divided
        // back out, and the reason this is computed here and not in the pad.
        economy: _rate(f('runs') * perOver, bowled),
      );
    }

    // The chase, when there is one. Even innings bat first and odd ones
    // chase — the pattern holds through a Super Over, where the chasing
    // innings is index 3.
    final target = (state['target'] as num?)?.toInt();
    String? chaseLine;
    String? chaseNeed;
    if (target != null && idx.isOdd && state['complete'] != true) {
      final ballsLeft = effectiveOvers * perOver - legalBalls;
      final needed = target - runs;
      chaseLine =
          'Target $target  ·  Req ${_rate(needed * perOver, ballsLeft)}';
      chaseNeed = needed <= 0
          ? 'Target passed'
          : 'Need $needed run${needed == 1 ? '' : 's'} off $ballsLeft '
              'ball${ballsLeft == 1 ? '' : 's'}';
    }

    return CreaseBoard(
      battingTeam: ctx.nameFor(Side.fromWire(cur['battingSide'] as String?)),
      inningsLabel: isSuperOver
          ? 'Super Over'
          : (idx == 0 ? '1st Innings' : '2nd Innings'),
      score: '$runs-$wickets',
      overs: _oversText(legalBalls, ctx),
      oversOf: '$effectiveOvers',
      extras: extras,
      runRate: _rate(runs * perOver, legalBalls),
      chaseLine: chaseLine,
      chaseNeed: chaseNeed,
      batters: [
        if (batter(cur['striker'], onStrike: true) case final b?) b,
        if (batter(cur['nonStriker'], onStrike: false) case final b?) b,
      ],
      bowler: bowler,
      timeline: [
        for (final entry in copyList(cur['timeline']))
          BallChip(
            label: entry['l'] as String? ?? '?',
            kind: _kindFromWire(entry['k']),
            endsOver: entry['over'] == true,
          ),
      ],
      notes: [
        if (isSuperOver) 'SUPER OVER',
        if (state['freeHit'] == true) 'FREE HIT',
        if (cur['striker'] == null) 'NEW BATTER',
        if (cur['bowler'] == null && cur['nonStriker'] != null) 'NEW BOWLER',
      ],
    );
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
    return innings.map((inn) {
      final runs = (inn['runs'] as num?)?.toInt() ?? 0;
      final wkts = (inn['wickets'] as num?)?.toInt() ?? 0;
      final balls = (inn['legalBalls'] as num?)?.toInt() ?? 0;
      final side =
          inn['battingSide'] == 'a' ? ctx.entrantAName : ctx.entrantBName;
      return '$side $runs/$wkts (${_oversText(balls, ctx)})';
    }).join('  ·  ');
  }

  /// Cricket's own words for its own events.
  ///
  /// This switch used to live in `spectator_screen.dart`, which is a screen
  /// that serves thirteen sports and knew the vocabulary of exactly one: every
  /// badminton match's commentary read `point` forty times in a column because
  /// the screen had no cricket-shaped word for it and no way to ask. The sport
  /// owns its vocabulary — see [MatchEventLine].
  @override
  MatchEventLine? describeEvent(MatchEvent event, ScoringContext ctx) {
    final side = Side.fromWire(event.payload['side'] as String?);
    final batter = event.payload['playerId'] as String?;
    final who = batter == null ? null : ctx.playerName(batter);

    final text = switch (event.type) {
      'runs' => switch ((event.payload['runs'] as num?)?.toInt() ?? 0) {
          0 => 'Dot ball',
          4 => 'FOUR',
          6 => 'SIX',
          final r => '$r run${r == 1 ? '' : 's'}',
        },
      'wicket' => 'WICKET',
      'wide' => 'Wide',
      'no_ball' => 'No ball — free hit',
      'bye' => 'Bye',
      'leg_bye' => 'Leg bye',
      _ => null,
    };
    if (text == null) return super.describeEvent(event, ctx);

    return MatchEventLine(
      text: who == null ? text : '$text · $who',
      side: side,
      // A wicket is the break in a cricket timeline the way a set is in a
      // rally one: it is what a reader scrolls to find.
      isMilestone: event.type == 'wicket',
    );
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      if (state['tie'] == true) return 'Match tied';
      final w = state['winner'];
      if (w is String) return '${ctx.nameFor(Side.fromWire(w))} won';
      return 'Final';
    }

    final cur = _current(state);
    final idx = (state['inningsIndex'] as num?)?.toInt() ?? 0;
    final isSuperOver = state['superOver'] == true && idx >= 2;
    final effectiveOvers = isSuperOver ? 1 : _overs(ctx);
    final balls = (cur['legalBalls'] as num?)?.toInt() ?? 0;
    final parts = <String>['${_oversText(balls, ctx)} / $effectiveOvers ov'];

    if (isSuperOver) parts.insert(0, 'SUPER OVER');
    if (cur['striker'] == null) parts.add('NEW BATTER');
    if (state['freeHit'] == true) parts.add('FREE HIT');

    final target = (state['target'] as num?)?.toInt();
    if (target != null && idx.isOdd) {
      final runs = (cur['runs'] as num?)?.toInt() ?? 0;
      final ballsLeft = effectiveOvers * _ballsPerOver(ctx) - balls;
      parts.add('need ${target - runs} off $ballsLeft');
    }
    return parts.join(' · ');
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] != true) return MatchOutcome.inProgress;
    final innings = copyList(state['innings']);
    var runsA = 0;
    var runsB = 0;
    for (final inn in innings) {
      final r = (inn['runs'] as num?)?.toInt() ?? 0;
      if (inn['battingSide'] == 'a') {
        runsA += r;
      } else {
        runsB += r;
      }
    }
    return MatchOutcome(
      isComplete: true,
      isDraw: state['tie'] == true,
      winnerSide: state['winner'] == null
          ? null
          : Side.fromWire(state['winner'] as String),
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
      final isLocked = state['locked'] == true;
      final isTie = state['tie'] == true;
      if (isLocked) {
        return const [
          ScoreControlGroup(
            title: 'Match finished & locked',
            controls: [],
          ),
        ];
      }
      return [
        ScoreControlGroup(
          title: isTie ? 'Match tied!' : 'Match finished',
          controls: [
            if (isTie)
              const ScoreControl(
                action: 'start_super_over',
                label: 'Start Super Over ⚡',
                style: ControlStyle.primary,
                tooltip: 'Run a 1-over tiebreaker innings to decide the winner.',
              ),
            const ScoreControl(
              action: 'reopen',
              label: 'Reopen to correct',
              style: ControlStyle.subtle,
              shortcut: 'r',
            ),
            const ScoreControl(
              action: 'lock_match',
              label: 'Lock Match & Scores',
              style: ControlStyle.danger,
              tooltip: 'Permanently lock scores against further edits.',
            ),
          ],
        ),
      ];
    }

    final cur = _current(state);

    // The pad refuses to offer a delivery until it knows who is involved.
    // Offering runs with nobody on strike is how a total ends up belonging to
    // no one, which no scorecard can then explain.
    // `side` is set to whichever side is BATTING, and it is load-bearing
    // rather than decorative: the pad resolves a prompt's candidates relative
    // to the control's side, so this is what makes "on strike" offer the
    // batting line-up and "bowling" offer the other one — and keeps doing so
    // after the innings break, when the two swap over. `apply` ignores
    // `action.side` for all three of these, so setting it costs nothing.
    final battingSide = Side.fromWire(cur['battingSide'] as String?);

    // A wicket clears the striker and leaves everything else standing, so
    // "somebody is out" and "the innings has not started" are different
    // states that both have a null striker. They were treated as one, and the
    // scorer was sent back through the full opening dialog after every
    // wicket — re-picking a non-striker who was already at the crease, which
    // `apply` then rejects the moment they pick the same name twice.
    final resuming = cur['bowler'] != null && cur['nonStriker'] != null;

    // The over just ended and nobody has been named to bowl the next one.
    //
    // Asked before the incoming batter below, because when a wicket falls off
    // the last ball of an over both are outstanding at once and the bowler is
    // the one the fielding captain settles first. Once a bowler is named this
    // falls through to the batter prompt on the very next build.
    //
    // `nonStriker != null` is what separates this from the start of an
    // innings, where nobody is named yet and the full opening dialog belongs.
    if (cur['bowler'] == null && cur['nonStriker'] != null) {
      final last = cur['lastBowler'] as String?;
      return [
        ScoreControlGroup(
          title: 'End of over',
          controls: [
            ScoreControl(
              action: 'new_bowler',
              label: 'Choose the next bowler',
              style: ControlStyle.primary,
              side: battingSide,
              tooltip: last == null
                  ? null
                  : '${ctx.playerName(last, 'The last bowler')} cannot bowl '
                      'two overs in a row.',
              prompts: const [
                PlayerPrompt(
                  key: 'playerId',
                  label: 'Next bowler',
                  from: PromptSource.opposingSide,
                ),
              ],
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

    if (cur['striker'] == null && resuming) {
      return [
        ScoreControlGroup(
          title: 'Next batter in',
          controls: [
            ScoreControl(
              action: 'new_batter',
              label: 'Choose the incoming batter',
              style: ControlStyle.primary,
              side: battingSide,
              prompts: const [
                PlayerPrompt(key: 'playerId', label: 'Incoming batter'),
              ],
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

    if (cur['striker'] == null || cur['bowler'] == null) {
      return [
        ScoreControlGroup(
          title: 'Who is playing?',
          controls: [
            ScoreControl(
              action: 'open',
              label: 'Choose batters and bowler',
              style: ControlStyle.primary,
              side: battingSide,
              prompts: const [
                PlayerPrompt(key: 'striker', label: 'On strike'),
                PlayerPrompt(key: 'nonStriker', label: 'Non-striker'),
                PlayerPrompt(
                  key: 'bowler',
                  label: 'Bowling',
                  from: PromptSource.opposingSide,
                ),
              ],
            ),
          ],
        ),
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
          // Four buttons, not twenty.
          //
          // The full ladder is still here and still complete — wides run
          // +0..+4 and no-balls +0..+6, because those are the values that
          // actually occur and each one is a run that has to go somewhere.
          // What changed is where they sit. Flat, they were twenty tiles of
          // identical weight and the plain wide, which is the overwhelming
          // majority of every innings ever scored, took the same search as
          // Wd+3. So the common delivery is the button and the graded ones
          // are behind it — see [ScoreControl.variants], and `CreasePad` for
          // the `+` tile that opens them.
          ScoreControl(
            action: 'wide',
            label: 'WD',
            shortcut: 'd',
            tooltip: '1 penalty run.',
            variants: [
              ScoreControl(
                action: 'wide',
                label: 'Wd+1',
                payload: {'runs': 1},
                tooltip: '1 wide + 1 run taken.',
              ),
              ScoreControl(
                action: 'wide',
                label: 'Wd+2',
                payload: {'runs': 2},
                tooltip: '1 wide + 2 runs taken.',
              ),
              ScoreControl(
                action: 'wide',
                label: 'Wd+3',
                payload: {'runs': 3},
                tooltip: '1 wide + 3 runs taken.',
              ),
              ScoreControl(
                action: 'wide',
                label: 'Wd+4',
                payload: {'runs': 4},
                tooltip: '1 wide + 4 boundary runs.',
              ),
            ],
          ),
          ScoreControl(
            action: 'no_ball',
            label: 'NB',
            shortcut: 'n',
            tooltip: '1 penalty run + free hit next ball.',
            variants: [
              ScoreControl(
                action: 'no_ball',
                label: 'NB+1',
                payload: {'runs': 1},
                tooltip: '1 no ball + 1 run off bat.',
              ),
              ScoreControl(
                action: 'no_ball',
                label: 'NB+2',
                payload: {'runs': 2},
                tooltip: '1 no ball + 2 runs off bat.',
              ),
              ScoreControl(
                action: 'no_ball',
                label: 'NB+3',
                payload: {'runs': 3},
                tooltip: '1 no ball + 3 runs off bat.',
              ),
              ScoreControl(
                action: 'no_ball',
                label: 'NB+4',
                payload: {'runs': 4},
                tooltip: '1 no ball + 4 runs off bat.',
              ),
              ScoreControl(
                action: 'no_ball',
                label: 'NB+5',
                payload: {'runs': 5},
                tooltip: '1 no ball + 5 runs off bat (overthrow).',
              ),
              ScoreControl(
                action: 'no_ball',
                label: 'NB+6',
                payload: {'runs': 6},
                tooltip: '1 no ball + 6 runs off bat.',
              ),
            ],
          ),
          ScoreControl(
            action: 'bye',
            label: 'BYE',
            payload: {'runs': 1},
            style: ControlStyle.subtle,
            shortcut: 'b',
            tooltip: '1 bye — the batter did not touch it.',
            variants: [
              ScoreControl(
                action: 'bye',
                label: 'Bye 2',
                payload: {'runs': 2},
                style: ControlStyle.subtle,
              ),
              ScoreControl(
                action: 'bye',
                label: 'Bye 3',
                payload: {'runs': 3},
                style: ControlStyle.subtle,
              ),
              ScoreControl(
                action: 'bye',
                label: 'Bye 4',
                payload: {'runs': 4},
                style: ControlStyle.subtle,
              ),
            ],
          ),
          ScoreControl(
            action: 'leg_bye',
            label: 'LB',
            payload: {'runs': 1},
            style: ControlStyle.subtle,
            shortcut: 'g',
            tooltip: '1 leg bye — off the body, not the bat.',
            variants: [
              ScoreControl(
                action: 'leg_bye',
                label: 'Leg bye 2',
                payload: {'runs': 2},
                style: ControlStyle.subtle,
              ),
              ScoreControl(
                action: 'leg_bye',
                label: 'Leg bye 3',
                payload: {'runs': 3},
                style: ControlStyle.subtle,
              ),
              ScoreControl(
                action: 'leg_bye',
                label: 'Leg bye 4',
                payload: {'runs': 4},
                style: ControlStyle.subtle,
              ),
            ],
          ),
        ],
      ),
      // Wickets, one control per dismissal type.
      //
      // A single "Wicket" button with an empty payload was not a shortcut, it
      // was a data loss. `apply` defaults an unnamed dismissal to `bowled` and
      // the striker, so every wicket in every match was recorded as bowled;
      // `_dismissalText` fell back to the literal word and printed "b bowler"
      // on every scorecard; `_fieldingCredits` never fired, so the catches,
      // stumpings and run-outs §7.1 asks for were permanently zero; and
      // because nothing ever set `type: run_out`, every run-out was credited
      // to the bowler — the exact error §7.1 names.
      //
      // The engine could do all of it. The pad simply never asked. It asks
      // now, declaratively, through the same `PlayerPrompt` mechanism every
      // other sport uses — so this stays a plugin change and the screen still
      // knows nothing about cricket.
      ScoreControlGroup(
        title: 'Wicket',
        controls: freeHit
            // On a free hit a run-out is the only dismissal available, so
            // there is nothing to choose between.
            ? [
                ScoreControl(
                  action: 'wicket',
                  label: 'Run out',
                  style: ControlStyle.danger,
                  // The batting side, so "who was out" offers batters and the
                  // fielder prompts offer the opposition.
                  side: battingSide,
                  payload: const {'type': 'run_out'},
                  shortcut: 'w',
                  tooltip: 'Free hit — only a run out is allowed.',
                  prompts: const [
                    PlayerPrompt(key: 'playerId', label: 'Who was out'),
                    PlayerPrompt(
                      key: 'fielder',
                      label: 'Fielder',
                      from: PromptSource.opposingSide,
                      optional: true,
                    ),
                    PlayerPrompt(
                      key: 'assist',
                      label: 'Throw (assist)',
                      from: PromptSource.opposingSide,
                      optional: true,
                    ),
                  ],
                ),
              ]
            : [
                ScoreControl(
                  action: 'wicket',
                  label: 'Bowled',
                  style: ControlStyle.danger,
                  side: battingSide,
                  payload: {'type': 'bowled', 'bowler': cur['bowler']},
                  shortcut: 'w',
                ),
                ScoreControl(
                  action: 'wicket',
                  label: 'Caught',
                  style: ControlStyle.danger,
                  side: battingSide,
                  payload: {'type': 'caught', 'bowler': cur['bowler']},
                  shortcut: 'c',
                  prompts: const [
                    PlayerPrompt(
                      key: 'fielder',
                      label: 'Caught by',
                      from: PromptSource.opposingSide,
                    ),
                  ],
                ),
                ScoreControl(
                  action: 'wicket',
                  label: 'LBW',
                  style: ControlStyle.danger,
                  side: battingSide,
                  payload: {'type': 'lbw', 'bowler': cur['bowler']},
                  shortcut: 'l',
                ),
                ScoreControl(
                  action: 'wicket',
                  label: 'Stumped',
                  style: ControlStyle.danger,
                  side: battingSide,
                  payload: {'type': 'stumped', 'bowler': cur['bowler']},
                  prompts: const [
                    PlayerPrompt(
                      key: 'keeper',
                      label: 'Stumped by',
                      from: PromptSource.opposingSide,
                    ),
                  ],
                ),
                ScoreControl(
                  action: 'wicket',
                  label: 'Run out',
                  style: ControlStyle.danger,
                  side: battingSide,
                  payload: const {'type': 'run_out'},
                  shortcut: 'o',
                  // The only dismissal where WHICH batter went is a real
                  // question: a non-striker run-out leaves the striker where
                  // they are, and debiting the wrong one corrupts an average
                  // and every fall-of-wicket line after it.
                  prompts: const [
                    PlayerPrompt(key: 'playerId', label: 'Who was out'),
                    PlayerPrompt(
                      key: 'fielder',
                      label: 'Fielder',
                      from: PromptSource.opposingSide,
                      optional: true,
                    ),
                    PlayerPrompt(
                      key: 'assist',
                      label: 'Throw (assist)',
                      from: PromptSource.opposingSide,
                      optional: true,
                    ),
                  ],
                ),
                ScoreControl(
                  action: 'wicket',
                  label: 'Hit wicket',
                  style: ControlStyle.danger,
                  side: battingSide,
                  payload: {'type': 'hit_wicket', 'bowler': cur['bowler']},
                ),
                ScoreControl(
                  action: 'wicket',
                  label: 'Retired',
                  style: ControlStyle.subtle,
                  side: battingSide,
                  payload: const {'type': 'retired'},
                  prompts: const [
                    PlayerPrompt(key: 'playerId', label: 'Who retired'),
                  ],
                ),
              ],
      ),
      ScoreControlGroup(
        title: 'Match',
        controls: [
          const ScoreControl(
            action: 'swap_strike',
            label: 'Swap strike',
            style: ControlStyle.subtle,
            shortcut: 's',
          ),
          ScoreControl(
            action: 'new_bowler',
            label: 'Change bowler',
            style: ControlStyle.secondary,
            // Same trick as the opening control: the side is the BATTING
            // side, so the bowler is drawn from the opposition and stays
            // correct after the innings break.
            side: battingSide,
            prompts: const [
              PlayerPrompt(
                key: 'playerId',
                label: 'Next bowler',
                from: PromptSource.opposingSide,
              ),
            ],
          ),
          const ScoreControl(
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
