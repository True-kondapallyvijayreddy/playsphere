import '../player_stats.dart';
import '../racket_rules.dart';
import '../scoring_plugin.dart';
import '../rally_timeline.dart';

/// Table tennis.
///
/// Simple to score and easy to get subtly wrong. Two rules decide whether a
/// scorer trusts the app:
///
///  * **A game is to 11, win by two, with NO cap.** 10-10 continues to 12-10,
///    13-11 and beyond. A ceiling would end a game that is still being played.
///  * **Service alternates every two points — but every ONE point from 10-10.**
///    Nothing else in the sport changes rhythm mid-game, and a scorer tracking
///    it by hand at deuce is exactly who loses count.
///
/// The engine derives whose serve it is rather than storing it, so it can
/// never drift out of step with the score it was derived from.
class TableTennisPlugin extends ScoringPlugin with RallyTimeline, RacketMatch {
  const TableTennisPlugin();

  static const pluginKey = 'table_tennis';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Table tennis';

  @override
  List<String> get headlineStats => const [_pointsWon];

  static const _pointsWon = 'pointsWon';
  static const _serviceWinners = 'serviceWinners';
  static const _errors = 'errors';

  int _gameTo(ScoringContext ctx) => ctx.intConfig('pointsPerSet', 11);
  int _gamesToWin(ScoringContext ctx) => ctx.intConfig('setsToWin', 3);

  /// Serves per turn before deuce. The ITTF number is two; some club and
  /// school ladders play five, so it is read rather than assumed.
  int _serveEvery(ScoringContext ctx) =>
      ctx.intConfig('serveEvery', ctx.intConfig('servesPerTurn', 2));

  /// Serves per turn once both sides reach the deuce threshold.
  int _serveEveryAtDeuce(ScoringContext ctx) =>
      ctx.intConfig('servesPerTurnAtDeuce', 1);

  /// The margin a game must be won by. ITTF is two.
  int _winBy(ScoringContext ctx) => ctx.intConfig('winBy', 2);

  int _gamesToWinMax(ScoringContext ctx) =>
      ctx.intConfig('maxSets', _gamesToWin(ctx) * 2 - 1);

  /// The score at which the players change ends in the DECIDING game.
  ///
  /// Five, by law. This number has been sitting in the table tennis presets
  /// as `decidingGameSwitchAt` since they were written and no engine ever
  /// read it, so the change of ends in the one game where it matters most
  /// simply never happened.
  int _decidingGameSwitchAt(ScoringContext ctx) =>
      ctx.intConfig('decidingGameSwitchAt', 5);

  /// Minutes after which the expedite system applies to a game that is still
  /// going. Zero disables it.
  int _expediteAfterMinutes(ScoringContext ctx) =>
      ctx.intConfig('expediteAfterMinutes', 10);

  /// Points already scored in a game above which expedite no longer applies —
  /// a game that has reached 18 is plainly not stalling.
  int _expediteExemptAt(ScoringContext ctx) =>
      ctx.intConfig('expediteExemptAtPoints', 18);

  bool _isDoubles(ScoringContext ctx) {
    if (ctx.config.containsKey('doubles')) {
      return ctx.boolConfig('doubles', false);
    }
    return ctx.lineupA.length > 1 || ctx.lineupB.length > 1;
  }

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'currentA': 0,
        'currentB': 0,
        'gamesA': 0,
        'gamesB': 0,
        'completedGames': <Map<String, dynamic>>[],
        // Whoever the toss gave the serve to opens the first game.
        'firstServer': ctx.startingSide.wire,
        'complete': false,
        'winner': null,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  /// Whose serve it is, derived from the score.
  ///
  /// Two points each until both reach the deuce threshold, then one each.
  /// Deriving rather than storing means the serve can never disagree with the
  /// score that produced it.
  Side serverFor(Map<String, dynamic> state, ScoringContext ctx) {
    final first = Side.fromWire(state['firstServer'] as String? ?? 'a');
    return serviceTurns(state, ctx).isEven ? first : first.opposite;
  }

  /// How many complete service turns have gone by in this game.
  ///
  /// Two points per turn until both sides reach the deuce threshold, then one
  /// per turn. Pulled out of [serverFor] because doubles needs the same count
  /// to work out which of the four players is serving and which is receiving,
  /// and two independent derivations of the same number would eventually
  /// disagree.
  int serviceTurns(Map<String, dynamic> state, ScoringContext ctx) {
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final deuceAt = _gameTo(ctx) - 1;
    final played = a + b;

    if (a >= deuceAt && b >= deuceAt) {
      // Everything before deuce in whole blocks, then the deuce rate after.
      final beforeDeuce = deuceAt * 2;
      final atDeuce = _serveEveryAtDeuce(ctx).clamp(1, 1 << 30);
      return beforeDeuce ~/ _serveEvery(ctx) +
          (played - beforeDeuce) ~/ atDeuce;
    }
    return played ~/ _serveEvery(ctx);
  }

  /// Names the player who should be serving.
  ///
  /// Doubles is the reason this is not simply "the side's first player".
  /// Table tennis fixes a four-way cycle — A1 serves to B1, then B1 to A2,
  /// then A2 to B2, then B2 to A1 — so both the server AND the receiver move
  /// on at every change of service. Playing the wrong pair member is a fault,
  /// which makes this the one thing a doubles umpire is really tracking.
  String? serverName(Map<String, dynamic> state, ScoringContext ctx) {
    final server = serverFor(state, ctx);
    final squad = ctx.lineupFor(server);
    if (squad.isEmpty) return null;
    if (squad.length == 1 || !_isDoubles(ctx)) return squad.first.name;
    final turn = serviceTurns(state, ctx);
    return squad[((turn ~/ 2) + _decidingSwapOffset(state, ctx)) % squad.length]
        .name;
  }

  /// Names the player who should be receiving.
  ///
  /// Null in singles, matching badminton: there is no receiving rotation to
  /// report when the side is one player, and naming them anyway would put a
  /// redundant clause in every status line.
  String? receiverName(Map<String, dynamic> state, ScoringContext ctx) {
    final receiving = serverFor(state, ctx).opposite;
    final squad = ctx.lineupFor(receiving);
    if (squad.length < 2 || !_isDoubles(ctx)) return null;
    final turn = serviceTurns(state, ctx);
    return squad[(((turn + 1) ~/ 2) + _decidingSwapOffset(state, ctx)) %
            squad.length]
        .name;
  }

  /// Who a point is credited to when nobody was asked.
  ///
  /// Table tennis doubles cycles the server AND the receiver — A1 to B1, B1
  /// to A2, A2 to B2, B2 to A1 — so both ends of every point are fixed by the
  /// laws and countable from the score. Which of the two partners hit the
  /// winning ball is not, and no scoresheet in the sport records it. So the
  /// point goes to whichever pair member the rally's own laws put in it,
  /// instead of to a dialog the scorer had to answer on every single point of
  /// a doubles game.
  String? _creditFor(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side winner,
  ) {
    final squad = ctx.lineupFor(winner);
    if (squad.isEmpty) return null;
    if (squad.length == 1) return squad.first.id;
    final name = serverFor(state, ctx) == winner
        ? serverName(state, ctx)
        : receiverName(state, ctx);
    if (name == null) return null;
    for (final p in squad) {
      if (p.name == name) return p.id;
    }
    return null;
  }

  /// In the deciding game, the receiving pair changes its order as soon as a
  /// side reaches the switch score. One extra step through the cycle is
  /// exactly what that means.
  int _decidingSwapOffset(Map<String, dynamic> state, ScoringContext ctx) {
    if (!_isDecidingGame(state, ctx)) return 0;
    final at = _decidingGameSwitchAt(ctx);
    if (at <= 0) return 0;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    return (a >= at || b >= at) ? 1 : 0;
  }

  bool _isDecidingGame(Map<String, dynamic> state, ScoringContext ctx) {
    final toWin = _gamesToWin(ctx);
    final a = ((state['gamesA'] as num?) ?? 0).toInt();
    final b = ((state['gamesB'] as num?) ?? 0).toInt();
    return a == toWin - 1 && b == toWin - 1;
  }

  /// Whether the expedite system would now apply, given how long this game
  /// has been going.
  ///
  /// The engine has no clock — it is a pure function of the event log — so it
  /// is told the elapsed minutes rather than measuring them. Returns false
  /// when the game has already produced enough points to be exempt.
  bool expediteApplies(
    Map<String, dynamic> state,
    ScoringContext ctx, {
    required int elapsedMinutesInGame,
  }) {
    final after = _expediteAfterMinutes(ctx);
    if (after <= 0) return false;
    if (elapsedMinutesInGame < after) return false;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    return a + b < _expediteExemptAt(ctx);
  }

  /// Ends change after every game — handled at the game boundary — and, in
  /// the deciding game only, the moment a side reaches the switch score.
  @override
  EndsChange? endsChangeDue(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return null;
    if (!_isDecidingGame(state, ctx)) return null;
    final at = _decidingGameSwitchAt(ctx);
    if (at <= 0) return null;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    if (a < at && b < at) return null;
    final gameNo = copyList(state['completedGames']).length + 1;
    return EndsChange(
      id: 'g$gameNo@$at',
      label: 'Change ends',
      detail: 'Deciding game — a side has reached $at.',
    );
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
          return const ScoringResult.rejected('A point needs a side.');
        }
        final player = action.payload['playerId'] as String? ??
            _creditFor(state, ctx, action.side);
        final how = action.payload['how'] as String?;
        final key = action.side == Side.a ? 'currentA' : 'currentB';

        var next = mutate(state, (s) {
          s[key] = ((s[key] as num?) ?? 0).toInt() + 1;
        });
        if (player != null) {
          next = PlayerTally.addAll(next, player, {
            _pointsWon: 1,
            if (how == 'service_winner') _serviceWinners: 1,
          });
        }
        final culprit = action.payload['errorById'] as String?;
        if (culprit != null) {
          next = PlayerTally.add(next, culprit, _errors, 1);
        }
        return ScoringResult.ok(_settleGame(next, ctx));

      case 'correct':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correction needs a side.');
        }
        final key = action.side == Side.a ? 'currentA' : 'currentB';
        final current = ((state[key] as num?) ?? 0).toInt();
        if (current == 0) {
          return const ScoringResult.rejected('Cannot go below zero.');
        }
        return ScoringResult.ok(mutate(state, (s) => s[key] = current - 1));

      case RacketMatch.changeEndsAction:
        return acknowledgeEndsResult(state, ctx);

      case RacketMatch.retireAction:
        // Table tennis, like tennis, previously had no way to end a match
        // that was not played out — an injury or a no-show left the fixture
        // permanently open.
        return retireResult(state, action);

      case 'reopen':
        return reopenResult(state);

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  Map<String, dynamic> _settleGame(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final target = _gameTo(ctx);
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final high = a > b ? a : b;

    // No cap: 15-13 is a legal table tennis game.
    if (high < target || (a - b).abs() < _winBy(ctx)) return state;

    final aWon = a > b;
    final completed = copyList(state['completedGames'])..add({'a': a, 'b': b});
    final gamesA = ((state['gamesA'] as num?) ?? 0).toInt() + (aWon ? 1 : 0);
    final gamesB = ((state['gamesB'] as num?) ?? 0).toInt() + (aWon ? 0 : 1);
    final matchOver = gamesA >= _gamesToWin(ctx) ||
        gamesB >= _gamesToWin(ctx) ||
        completed.length >= _gamesToWinMax(ctx);

    return mutate(state, (s) {
      s['completedGames'] = completed;
      s['gamesA'] = gamesA;
      s['gamesB'] = gamesB;
      s['currentA'] = 0;
      s['currentB'] = 0;
      // The first service alternates each game, and so do the ends.
      s['firstServer'] =
          Side.fromWire(s['firstServer'] as String? ?? 'a').opposite.wire;
      resetEndsForNewGame(s);
      if (matchOver) {
        s['complete'] = true;
        s['winner'] = gamesA > gamesB ? 'a' : 'b';
      }
    });
  }

  static List<StatColumn> get columns => [
        const StatColumn(key: _pointsWon, label: 'Points won', shortLabel: 'PTS'),
        const StatColumn(
          key: _serviceWinners,
          label: 'Service winners',
          shortLabel: 'SW',
        ),
        const StatColumn(key: _errors, label: 'Errors', shortLabel: 'E'),
      ];

  @override
  BoxScore boxScore(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side side,
  ) =>
      PlayerTally.boxScore(
        state: state, ctx: ctx, side: side, columns: columns);

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return '${state['gamesA'] ?? 0} - ${state['gamesB'] ?? 0}';
    }
    return '${state['currentA'] ?? 0} - ${state['currentB'] ?? 0}';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final games = copyList(state['completedGames'])
        .map((g) => '${g['a']}-${g['b']}')
        .toList();
    final live = state['complete'] == true
        ? null
        : '${state['currentA'] ?? 0}-${state['currentB'] ?? 0}*';
    final parts = [...games, if (live != null) live];
    return parts.isEmpty ? '0-0' : parts.join(', ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return retirementLine(state, ctx) ??
          'Final · games ${state['gamesA']}-${state['gamesB']}';
    }
    final gameNo = copyList(state['completedGames']).length + 1;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final deuceAt = _gameTo(ctx) - 1;
    final atDeuce = a >= deuceAt && b >= deuceAt;

    final serving =
        serverName(state, ctx) ?? ctx.nameFor(serverFor(state, ctx));
    final receiving = _isDoubles(ctx) ? receiverName(state, ctx) : null;

    final parts = <String>[
      'Game $gameNo · to ${_gameTo(ctx)}',
      // In doubles the pair is not enough: it is a fault if the wrong partner
      // plays the ball, so the pad names both ends of the exchange.
      receiving == null ? '$serving serving' : '$serving serves to $receiving',
      if (atDeuce) 'deuce, one serve each',
      if (endsChangeDue(state, ctx) != null && !endsAcknowledged(state, ctx))
        'CHANGE ENDS',
    ];
    return parts.join(' · ');
  }

  @override
  PadLayout get padLayout => PadLayout.duel;

  @override
  DuelBoard? duelBoard(Map<String, dynamic> state, ScoringContext ctx) {
    final done = state['complete'] == true;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final gamesA = ((state['gamesA'] as num?) ?? 0).toInt();
    final gamesB = ((state['gamesB'] as num?) ?? 0).toInt();
    final server = done ? null : serverFor(state, ctx);
    final target = _gameTo(ctx);
    final toWin = _gamesToWin(ctx);

    String? tagFor(int mine, int theirs, int gamesMine) {
      if (done) return null;
      if (mine < target - 1 || mine - theirs < 1) return null;
      return gamesMine == toWin - 1 ? 'Match point' : 'Game point';
    }

    final periods = <DuelPeriod>[
      for (final (i, g) in copyList(state['completedGames']).indexed)
        DuelPeriod(
          label: 'G${i + 1}',
          a: ((g['a'] as num?) ?? 0).toInt(),
          b: ((g['b'] as num?) ?? 0).toInt(),
        ),
      if (!done)
        DuelPeriod(
          label: 'G${copyList(state['completedGames']).length + 1}',
          a: a,
          b: b,
          current: true,
        ),
    ];

    // Games, not points, once it is over: the point counters are zeroed as
    // each game closes, so a finished match drawn from them reads 0 - 0.
    final winner = state['winner'];
    final serverLabel = server == null ? null : serverName(state, ctx);
    return DuelBoard(
      matchScore: DuelMatchScore(
        a: ((state['gamesA'] as num?) ?? 0).toInt(),
        b: ((state['gamesB'] as num?) ?? 0).toInt(),
        label: 'GAMES WON',
      ),
      a: DuelSide(
        name: ctx.entrantAName,
        score: done ? '$gamesA' : '$a',
        sub: done ? 'Games won' : 'Games $gamesA',
        serving: server == Side.a,
        serverName: server == Side.a ? serverLabel : null,
        tag: done ? (winner == 'a' ? 'Won' : null) : tagFor(a, b, gamesA),
        pips: done ? null : a,
      ),
      b: DuelSide(
        name: ctx.entrantBName,
        score: done ? '$gamesB' : '$b',
        sub: done ? 'Games won' : 'Games $gamesB',
        serving: server == Side.b,
        serverName: server == Side.b ? serverLabel : null,
        tag: done ? (winner == 'b' ? 'Won' : null) : tagFor(b, a, gamesB),
        pips: done ? null : b,
      ),
      periods: periods,
      status: statusLine(state, ctx),
      pipTarget: done ? null : target,
      pointsNote: '$target points per game · best of ${toWin * 2 - 1}',
      endsNote: _endsNote(state, ctx),
    );
  }

  /// Where the players are standing, and what will move them. Table tennis
  /// changes ends after every game and again at 5 in the decider.
  String? _endsNote(Map<String, dynamic> state, ScoringContext ctx) {
    final due = endsChangeDue(state, ctx);
    if (due != null) return due.label;
    final swapped = endsSwapped(state);
    final left = swapped ? ctx.entrantBName : ctx.entrantAName;
    final right = swapped ? ctx.entrantAName : ctx.entrantBName;
    return '$left left · $right right';
  }

  @override
  Side? rallyServingSide(Map<String, dynamic> state, ScoringContext ctx) =>
      serverFor(state, ctx);

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
      winnerSide: state['winner'] == null
          ? null
          : Side.fromWire(state['winner'] as String),
      scoreForA: ((state['gamesA'] as num?) ?? 0).toInt(),
      scoreForB: ((state['gamesB'] as num?) ?? 0).toInt(),
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
    // Asked in singles only, where the pad answers it itself without opening
    // anything — one side, one candidate. In doubles the question has no
    // answer the sport keeps, so it is not put to the scorer on every point.
    // See [_creditFor].
    final pointPrompts = _isDoubles(ctx)
        ? const <PlayerPrompt>[]
        : const [PlayerPrompt(key: 'playerId', label: 'Who won the point?')];

    return [
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: [
          ScoreControl(
            action: 'point',
            label: '+1',
            side: Side.a,
            style: ControlStyle.primary,
            shortcut: 'a',
            prompts: pointPrompts,
          ),
          const ScoreControl(
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
        controls: [
          ScoreControl(
            action: 'point',
            label: '+1',
            side: Side.b,
            style: ControlStyle.primary,
            shortcut: 'l',
            prompts: pointPrompts,
          ),
          const ScoreControl(
            action: 'correct',
            label: '−1',
            side: Side.b,
            style: ControlStyle.subtle,
            shortcut: 'm',
          ),
        ],
      ),
      ...endsControls(state, ctx),
      ...retireControls(ctx),
    ];
  }

  // --- Rally timeline ----------------------------------------------------

  @override
  List<Map<String, dynamic>> rallyCompletedPeriods(
    Map<String, dynamic> state,
  ) =>
      copyList(state['completedGames']);

  @override
  String get rallyPeriodNoun => 'Game';
}
