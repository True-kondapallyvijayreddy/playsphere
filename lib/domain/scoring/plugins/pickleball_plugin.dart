import '../player_stats.dart';
import '../racket_rules.dart';
import '../rally_timeline.dart';
import '../scoring_plugin.dart';

/// Pickleball.
///
/// ## Why this is not "badminton with different numbers"
///
/// Every other racket sport in the catalogue awards a point to whoever wins
/// the rally. Pickleball's traditional scoring does not: **only the serving
/// side can score**. Lose a rally while receiving and nothing happens to the
/// score at all — the serve moves, and that is the entire consequence. An
/// engine that adds a point to the rally winner does not produce a slightly
/// wrong pickleball score, it produces a number that has no relationship to
/// the game being played, and it produces it silently.
///
/// That single rule is why this is a plugin and not a preset.
///
/// ## The rules encoded here
///
///  * **Side-out scoring.** The server's side scores; the receiver's side
///    only wins the serve. Configurable, because MLP-style **rally scoring**
///    (every rally scores, to 21) is now common enough that a league will ask
///    for it — see `rallyScoring`.
///  * **Two servers per team, and the opening exception.** Each side gets two
///    service turns before a side-out, except the side serving first in a
///    game, which gets one. That is why a pickleball game opens on the call
///    "0 – 0 – 2": the second server is already up.
///  * **The service court is derived, never entered.** The server serves from
///    the right when their own side's score is even. Storing it would let it
///    drift out of step with the score that defines it.
///  * **The score is three numbers, not two.** "8 – 5 – 2" — serving side,
///    receiving side, server number — is how the score is called before every
///    serve, and a pad that shows only two of them is missing the one a player
///    will query.
///  * **Ends change at 6** in a game to 11, and after every game. The trigger
///    scales with the target, so a game to 15 changes at 8 and a game to 21 at
///    11, all from configuration.
class PickleballPlugin extends ScoringPlugin with RallyTimeline, RacketMatch {
  const PickleballPlugin();

  static const pluginKey = 'pickleball';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Pickleball';

  @override
  List<String> get headlineStats => const [_pointsWon];

  static const _pointsWon = 'pointsWon';
  static const _rallies = 'rallies';
  static const _serviceAces = 'serviceAces';
  static const _winners = 'winners';
  static const _errors = 'errors';

  int _gameTo(ScoringContext ctx) => ctx.intConfig('pointsPerSet', 11);
  int _gamesToWin(ScoringContext ctx) => ctx.intConfig('setsToWin', 2);
  int _winBy(ScoringContext ctx) => ctx.intConfig('winBy', 2);
  int _maxGames(ScoringContext ctx) =>
      ctx.intConfig('maxSets', _gamesToWin(ctx) * 2 - 1);

  /// A hard cap ends a game that will not otherwise finish. Zero — the
  /// pickleball default — means win-by-two runs as long as it needs to.
  int _hardCap(ScoringContext ctx) => ctx.intConfig('hardCap', 0);

  /// Rally scoring awards every rally to its winner, the way badminton does.
  /// Off by default: traditional side-out scoring is still the tournament
  /// standard.
  bool _rallyScoring(ScoringContext ctx) =>
      ctx.boolConfig('rallyScoring', false);

  /// Service turns a side gets before the serve goes over. Two in doubles by
  /// law; singles has exactly one and the setting is ignored there.
  int _serversPerSide(ScoringContext ctx) => ctx.intConfig('serversPerSide', 2);

  /// Whether the side serving first in a game gets only one service turn.
  /// This is the rule behind the "0 – 0 – 2" opening call.
  bool _firstServerException(ScoringContext ctx) =>
      ctx.boolConfig('firstServerException', true);

  /// The score at which ends change mid-game. Defaults to half the target
  /// rounded up — 6 in a game to 11 — which is the law for every standard
  /// target rather than a coincidence of the number 11.
  int _changeEndsAt(ScoringContext ctx) =>
      ctx.intConfig('changeEndsAt', (_gameTo(ctx) + 1) ~/ 2);

  bool _isDoubles(Map<String, dynamic> state, ScoringContext ctx) {
    if (ctx.config.containsKey('doubles')) return ctx.boolConfig('doubles', false);
    // No format recorded: infer from the line-up, which is what a pad that
    // skipped setup will have.
    return ctx.lineupA.length > 1 || ctx.lineupB.length > 1;
  }

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'currentA': 0,
        'currentB': 0,
        'gamesA': 0,
        'gamesB': 0,
        'completedGames': <Map<String, dynamic>>[],
        // The toss winner serves first unless they chose otherwise.
        'server': ctx.startingSide.wire,
        // 1 or 2. Opens at 2 in doubles under the first-server exception, so
        // the opening call really is "0 – 0 – 2".
        'serverNumber':
            _firstServerException(ctx) && _isDoubles({}, ctx) ? 2 : 1,
        // Which member of each pair is currently in the right-hand court.
        // Pickleball partners swap courts only when their own side scores, so
        // this cannot be derived from the score alone.
        'rightCourtA': 0,
        'rightCourtB': 0,
        'complete': false,
        'winner': null,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  // --- Derived service state ----------------------------------------------

  Side serverFor(Map<String, dynamic> state) =>
      Side.fromWire(state['server'] as String? ?? 'a');

  int serverNumber(Map<String, dynamic> state) =>
      ((state['serverNumber'] as num?) ?? 1).toInt();

  /// Which court the server delivers from — right on an even score.
  String serviceCourt(Map<String, dynamic> state) {
    final server = serverFor(state);
    final score =
        ((state[server == Side.a ? 'currentA' : 'currentB'] as num?) ?? 0)
            .toInt();
    return score.isEven ? 'right' : 'left';
  }

  /// The score as it is called before the serve: serving side, receiving
  /// side, and — in doubles — which server is up.
  ///
  /// This is the canonical pickleball score. It is deliberately built from
  /// the SERVER's point of view rather than always reading A-then-B, because
  /// that is what is called on court and a scorer checking the pad against
  /// what they just heard has to see the same three numbers in the same
  /// order.
  String calledScore(Map<String, dynamic> state, ScoringContext ctx) {
    final server = serverFor(state);
    final mine =
        ((state[server == Side.a ? 'currentA' : 'currentB'] as num?) ?? 0)
            .toInt();
    final theirs =
        ((state[server == Side.a ? 'currentB' : 'currentA'] as num?) ?? 0)
            .toInt();
    if (_rallyScoring(ctx) || !_isDoubles(state, ctx)) return '$mine – $theirs';
    return '$mine – $theirs – ${serverNumber(state)}';
  }

  /// Names the player who should be serving.
  ///
  /// In doubles this is the partner in the correct court: server 1 is
  /// whoever is on the right when the score is even. Returns null when no
  /// line-up was entered.
  String? serverName(Map<String, dynamic> state, ScoringContext ctx) {
    final server = serverFor(state);
    final squad = ctx.lineupFor(server);
    if (squad.isEmpty) return null;
    if (squad.length == 1) return squad.first.name;
    return squad[serverIndexFor(state, server) % squad.length].name;
  }

  int _rightCourt(Map<String, dynamic> state, Side side) =>
      ((state[side == Side.a ? 'rightCourtA' : 'rightCourtB'] as num?) ?? 0)
          .toInt();

  /// Which member of [side] is serving.
  ///
  /// Server 1 serves from the right at an even score; server 2 is the
  /// partner. Working from who is standing where keeps the name right after
  /// the pair has swapped courts.
  int serverIndexFor(Map<String, dynamic> state, Side side) {
    final right = _rightCourt(state, side);
    return serverNumber(state) == 1 ? right : (right + 1) % 2;
  }

  /// Which member of [side] is receiving.
  ///
  /// The serve is diagonal, so the receiver is the partner standing in the
  /// service court of the same hand as the server's.
  int receiverIndexFor(Map<String, dynamic> state, Side side) {
    final right = _rightCourt(state, side);
    return serviceCourt(state) == 'right' ? right : (right + 1) % 2;
  }

  /// Who a rally is credited to when nobody was asked.
  ///
  /// A convention in doubles rather than a measurement — pickleball, like
  /// badminton, records no such thing, and either partner can end a rally
  /// from anywhere. What the laws DO fix is who served and who received, so
  /// the rally goes against the two players who exchanged it. That is worth
  /// far more than the dialog it replaces, which asked "who won the rally?"
  /// on every point of every doubles game.
  String? _creditFor(
    Map<String, dynamic> state,
    ScoringContext ctx,
    Side winner,
  ) {
    final squad = ctx.lineupFor(winner);
    if (squad.isEmpty) return null;
    if (squad.length == 1) return squad.first.id;
    final index = serverFor(state) == winner
        ? serverIndexFor(state, winner)
        : receiverIndexFor(state, winner);
    return squad[index % squad.length].id;
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
      case 'rally':
      case 'point':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Who won the rally?');
        }
        return ScoringResult.ok(_awardRally(state, action, ctx));

      case RacketMatch.changeEndsAction:
        return acknowledgeEndsResult(state, ctx);

      case 'set_first_server':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Which side serves first?');
        }
        final played = ((state['currentA'] as num?) ?? 0).toInt() +
            ((state['currentB'] as num?) ?? 0).toInt();
        if (played > 0) {
          return const ScoringResult.rejected(
            'The first server can only be set before the first rally.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['server'] = action.side.wire;
        }));

      case 'correct':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correct which side?');
        }
        final key = action.side == Side.a ? 'currentA' : 'currentB';
        final current = ((state[key] as num?) ?? 0).toInt();
        if (current <= 0) {
          return const ScoringResult.rejected(
            'That side has no points in this game to take back.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) => s[key] = current - 1));

      case RacketMatch.retireAction:
        return retireResult(state, action);

      case 'reopen':
        return reopenResult(state);

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  /// The heart of the sport: who won the rally, and what that is worth.
  Map<String, dynamic> _awardRally(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    final side = action.side;
    final server = serverFor(state);
    final servingSideWon = side == server;
    final doubles = _isDoubles(state, ctx);
    final rally = _rallyScoring(ctx);

    var next = Map<String, dynamic>.from(state);
    int v(String k) => ((next[k] as num?) ?? 0).toInt();

    // A point is scored by the rally winner under rally scoring, and only by
    // the serving side under traditional scoring. This one branch is the
    // whole difference between the two systems.
    final scores = rally || servingSideWon;
    if (scores) {
      final key = side == Side.a ? 'currentA' : 'currentB';
      next[key] = v(key) + 1;
    }

    if (servingSideWon) {
      // The serving pair swaps courts on every point they win. Nothing else
      // in the sport moves players, which is why this is tracked rather than
      // derived.
      if (doubles) {
        final ck = side == Side.a ? 'rightCourtA' : 'rightCourtB';
        next[ck] = (v(ck) + 1) % 2;
      }
    } else {
      next = _passServe(next, ctx, doubles: doubles);
    }

    // Player-level credit.
    final winnerId =
        action.payload['playerId'] as String? ?? _creditFor(state, ctx, side);
    if (winnerId != null) {
      final how = action.payload['how'] as String?;
      next = PlayerTally.addAll(next, winnerId, {
        _rallies: 1,
        if (scores) _pointsWon: 1,
        if (how == 'ace' && servingSideWon) _serviceAces: 1,
        if (how == 'winner') _winners: 1,
      });
    }
    final errorById = action.payload['errorByPlayerId'] as String? ??
        action.payload['errorById'] as String?;
    if (errorById != null) {
      next = PlayerTally.addAll(next, errorById, {_errors: 1});
    }

    return _settleGame(next, ctx);
  }

  /// Moves the serve on after the serving side lost the rally.
  ///
  /// In doubles the serve goes to the partner first and only then over the
  /// net — that is what "two servers" means, and it is the rule most often
  /// lost by a scorer keeping the game in their head.
  Map<String, dynamic> _passServe(
    Map<String, dynamic> state,
    ScoringContext ctx, {
    required bool doubles,
  }) {
    final next = Map<String, dynamic>.from(state);
    final number = serverNumber(next);
    final perSide = doubles ? _serversPerSide(ctx) : 1;

    if (number < perSide) {
      next['serverNumber'] = number + 1;
      return next;
    }

    // Side out.
    final incoming = serverFor(next).opposite;
    next['server'] = incoming.wire;
    next['serverNumber'] = 1;
    return next;
  }

  Map<String, dynamic> _settleGame(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final target = _gameTo(ctx);
    final cap = _hardCap(ctx);
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final high = a > b ? a : b;

    final marginReached = (a - b).abs() >= _winBy(ctx);
    final cappedOut = cap > 0 && high >= cap;
    if (high < target) return state;
    if (!marginReached && !cappedOut) return state;

    final aWon = a > b;
    final completed = copyList(state['completedGames'])..add({'a': a, 'b': b});
    final gamesA = ((state['gamesA'] as num?) ?? 0).toInt() + (aWon ? 1 : 0);
    final gamesB = ((state['gamesB'] as num?) ?? 0).toInt() + (aWon ? 0 : 1);
    final toWin = _gamesToWin(ctx);
    final matchOver = gamesA >= toWin ||
        gamesB >= toWin ||
        completed.length >= _maxGames(ctx);

    final doubles = _isDoubles(state, ctx);

    return mutate(state, (s) {
      s['completedGames'] = completed;
      s['gamesA'] = gamesA;
      s['gamesB'] = gamesB;
      s['currentA'] = 0;
      s['currentB'] = 0;
      // The side that won the game serves first in the next one, and the
      // opening one-server exception applies again.
      s['server'] = aWon ? 'a' : 'b';
      s['serverNumber'] =
          _firstServerException(ctx) && doubles ? _serversPerSide(ctx) : 1;
      s['rightCourtA'] = 0;
      s['rightCourtB'] = 0;
      resetEndsForNewGame(s);
      if (matchOver) {
        s['complete'] = true;
        s['draw'] = false;
        s['winner'] = gamesA > gamesB ? 'a' : 'b';
      }
    });
  }

  // --- Change of ends ------------------------------------------------------

  @override
  EndsChange? endsChangeDue(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return null;
    final at = _changeEndsAt(ctx);
    if (at <= 0) return null;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    // The law is "when the first side reaches" the trigger, so it fires once
    // per game — the moment either score crosses it.
    if (a < at && b < at) return null;
    final gameNo = copyList(state['completedGames']).length + 1;
    return EndsChange(
      id: 'g$gameNo@$at',
      label: 'Change ends',
      detail: 'Game $gameNo — first side has reached $at.',
    );
  }

  // --- Presentation --------------------------------------------------------

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
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    if (state['complete'] != true && (a > 0 || b > 0)) games.add('$a-$b');
    return games.isEmpty ? '0-0' : games.join(', ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return retirementLine(state, ctx) ??
          'Final · games ${state['gamesA']}-${state['gamesB']}';
    }

    final parts = <String>[];
    final gameNo = copyList(state['completedGames']).length + 1;
    parts.add('Game $gameNo · to ${_gameTo(ctx)}');
    parts.add(calledScore(state, ctx));

    final name = serverName(state, ctx) ?? ctx.nameFor(serverFor(state));
    parts.add('$name serving from the ${serviceCourt(state)}');

    final ends = endsChangeDue(state, ctx);
    if (ends != null && !endsAcknowledged(state, ctx)) {
      parts.add('CHANGE ENDS');
    }

    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final target = _gameTo(ctx);
    if (a >= target - 1 && b >= target - 1) parts.add('Deuce');

    return parts.join(' • ');
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
    final server = done ? null : serverFor(state);
    final target = _gameTo(ctx);
    final toWin = _gamesToWin(ctx);
    final rally = _rallyScoring(ctx);

    /// Only the serving side can be at game point under side-out scoring —
    /// the receiver cannot win the game on the next rally however far ahead
    /// they are, because the next rally cannot give them a point. Showing
    /// them "game point" would be the pad asserting something the rules
    /// forbid.
    String? tagFor(Side side, int mine, int theirs, int gamesMine) {
      if (done) return null;
      if (!rally && side != server) return null;
      if (mine < target - 1 || mine - theirs < _winBy(ctx) - 1) return null;
      return gamesMine == toWin - 1 ? 'Match point' : 'Game point';
    }

    final completed = copyList(state['completedGames']);
    final periods = <DuelPeriod>[
      for (final (i, g) in completed.indexed)
        DuelPeriod(
          label: 'G${i + 1}',
          a: ((g['a'] as num?) ?? 0).toInt(),
          b: ((g['b'] as num?) ?? 0).toInt(),
        ),
      if (!done)
        DuelPeriod(
          label: 'G${completed.length + 1}',
          a: a,
          b: b,
          current: true,
        ),
    ];

    // The server label carries the court and the server number, because all
    // three are one fact to a scorer: "Meera, right, server 2".
    final serverLabel = server == null
        ? null
        : [
            serverName(state, ctx),
            '${serviceCourt(state)} court',
            if (!rally && _isDoubles(state, ctx)) 'server ${serverNumber(state)}',
          ].whereType<String>().join(' · ');

    final winner = state['winner'];
    return DuelBoard(
      matchScore: DuelMatchScore(a: gamesA, b: gamesB, label: 'GAMES WON'),
      a: DuelSide(
        name: ctx.entrantAName,
        score: done ? '$gamesA' : '$a',
        sub: done ? 'Games won' : (toWin > 1 ? 'Games $gamesA' : null),
        serving: server == Side.a,
        serverName: server == Side.a ? serverLabel : null,
        tag: done
            ? (winner == 'a' ? 'Won' : null)
            : tagFor(Side.a, a, b, gamesA),
        pips: done ? null : a,
      ),
      b: DuelSide(
        name: ctx.entrantBName,
        score: done ? '$gamesB' : '$b',
        sub: done ? 'Games won' : (toWin > 1 ? 'Games $gamesB' : null),
        serving: server == Side.b,
        serverName: server == Side.b ? serverLabel : null,
        tag: done
            ? (winner == 'b' ? 'Won' : null)
            : tagFor(Side.b, b, a, gamesB),
        pips: done ? null : b,
      ),
      periods: periods,
      status: statusLine(state, ctx),
      pipTarget: done ? null : target,
      pointsNote: '$target points per game · best of ${toWin * 2 - 1}',
      endsNote: _endsNote(state, ctx),
    );
  }

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
      serverFor(state);

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final gamesA = ((state['gamesA'] as num?) ?? 0).toInt();
    final gamesB = ((state['gamesB'] as num?) ?? 0).toInt();
    if (state['complete'] != true) {
      return MatchOutcome(
        isComplete: false,
        scoreForA: gamesA,
        scoreForB: gamesB,
      );
    }
    final winner = state['winner'];
    return MatchOutcome(
      isComplete: true,
      winnerSide: winner is String ? Side.fromWire(winner) : null,
      isDraw: winner == null,
      scoreForA: gamesA,
      scoreForB: gamesB,
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

    // Asked in singles only, where the pad answers it itself without a
    // dialog — one side, one candidate. In doubles the question has no
    // answer the sport records, so it is not put to the scorer forty times a
    // game; the point is credited to the server or the receiver, both of
    // which the laws already fix. See [_creditFor].
    final winner = _isDoubles(state, ctx)
        ? const <PlayerPrompt>[]
        : const [PlayerPrompt(key: 'playerId', label: 'Who won the rally?')];

    final groups = <ScoreControlGroup>[
      ScoreControlGroup(
        title: 'Rally won by',
        controls: [
          ScoreControl(
            action: 'rally',
            label: ctx.entrantAName,
            side: Side.a,
            style: ControlStyle.primary,
            shortcut: 'a',
            prompts: winner,
          ),
          ScoreControl(
            action: 'rally',
            label: ctx.entrantBName,
            side: Side.b,
            style: ControlStyle.primary,
            shortcut: 'l',
            prompts: winner,
          ),
        ],
      ),
      ...endsControls(state, ctx),
      ScoreControlGroup(
        title: 'Corrections',
        controls: [
          ScoreControl(
            action: 'correct',
            label: '−1 ${ctx.entrantAName}',
            side: Side.a,
            style: ControlStyle.subtle,
          ),
          ScoreControl(
            action: 'correct',
            label: '−1 ${ctx.entrantBName}',
            side: Side.b,
            style: ControlStyle.subtle,
          ),
        ],
      ),
      ...retireControls(ctx),
    ];

    return groups;
  }

  static List<StatColumn> get columns => [
        const StatColumn(key: _pointsWon, label: 'Points won', shortLabel: 'PTS'),
        const StatColumn(key: _rallies, label: 'Rallies won', shortLabel: 'R'),
        const StatColumn(
          key: _serviceAces,
          label: 'Service aces',
          shortLabel: 'ACE',
        ),
        const StatColumn(key: _winners, label: 'Winners', shortLabel: 'W'),
        const StatColumn(key: _errors, label: 'Errors', shortLabel: 'E'),
        StatColumn(
          key: 'rallyPct',
          label: 'Rally win %',
          shortLabel: 'R%',
          isPercentage: true,
          decimals: 1,
          derive: (t) {
            final won = (t[_rallies] ?? 0).toDouble();
            final errs = (t[_errors] ?? 0).toDouble();
            final total = won + errs;
            return total == 0 ? 0 : won / total;
          },
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

  // --- Rally timeline ------------------------------------------------------

  @override
  List<Map<String, dynamic>> rallyCompletedPeriods(
    Map<String, dynamic> state,
  ) =>
      copyList(state['completedGames']);

  @override
  String get rallyPeriodNoun => 'Game';

  @override
  String get rallyPointAction => 'rally';
}
