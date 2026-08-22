import '../player_stats.dart';
import '../racket_rules.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';
import '../rally_timeline.dart';

/// Badminton, scored properly.
///
/// The spec makes badminton a Phase 1 MVP sport alongside cricket, and a
/// generic "first to 21" counter does not satisfy it. Three things separate
/// real badminton scoring from a points tally:
///
///  * **The service court is derived, never entered.** The server stands right
///    when their own score is even and left when it is odd. A scorer should
///    never be asked which court to serve from, because the score already
///    determines it — and a pad that asks will eventually be told wrong.
///  * **Doubles service rotation.** In doubles the pair keeps serving while it
///    wins rallies, alternating who serves; losing the rally hands service to
///    the opponents. Tracking this is what allows the pad to name the server.
///  * **Intervals and change of ends** are part of the laws, not decoration:
///    the interval at 11 (or 8 under the BWF 3x15 system) and the change of
///    ends in the deciding game both have to fire at the right score.
///
/// Every number is configuration. Badminton is mid-transition between the
/// 21-point system and the BWF-approved 3x15 system expected in 2026, and
/// this engine plays either from a preset — see `rule_config.dart`.
class BadmintonPlugin extends ScoringPlugin with RallyTimeline, RacketMatch {
  const BadmintonPlugin();

  static const pluginKey = 'badminton';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Badminton';

  @override
  List<String> get headlineStats => const [_pointsWon];

  static const _pointsWon = 'pointsWon';
  static const _pointsOnServe = 'pointsOnServe';
  static const _pointsOnReceive = 'pointsOnReceive';
  static const _serviceAces = 'serviceAces';
  static const _errors = 'errors';
  static const _rallies = 'rallies';

  int _gameTo(ScoringContext ctx) => ctx.intConfig('pointsPerSet', 21);
  int _gamesToWin(ScoringContext ctx) => ctx.intConfig('setsToWin', 2);
  int _winBy(ScoringContext ctx) => ctx.intConfig('winBy', 2);

  /// The hard cap: at 29-all the next point takes the game whatever the
  /// margin. Zero disables the cap entirely.
  int _hardCap(ScoringContext ctx) => ctx.intConfig('hardCap', 30);

  /// Score at which play pauses for the interval — 11 under the 21-point
  /// system, 8 under BWF 3x15.
  int _intervalAt(ScoringContext ctx) => ctx.intConfig('intervalAt', 11);

  /// Score at which ends change in the deciding game.
  int _changeEndsAt(ScoringContext ctx) =>
      ctx.intConfig('changeEndsInDecidingAt', _intervalAt(ctx));

  int _maxGames(ScoringContext ctx) =>
      ctx.intConfig('maxSets', _gamesToWin(ctx) * 2 - 1);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'currentA': 0,
        'currentB': 0,
        'gamesA': 0,
        'gamesB': 0,
        'completedGames': <Map<String, dynamic>>[],
        // Who serves the first rally of the current game — the side the
        // toss handed the serve to, not always A. See
        // `ScoringContext.startingSide`.
        'server': ctx.startingSide.wire,
        // Where each pair is STANDING, as the index of the player who is
        // currently in the right service court. Not a rotation counter — see
        // [rightCourt].
        'rightCourtA': 0,
        'rightCourtB': 0,
        // Whether the scorer has said who is serving for that side yet. The
        // arrangement above is a guess until they do, and the pad asks once
        // per side rather than guessing for a whole match.
        'courtsSetA': false,
        'courtsSetB': false,
        'endsSwapped': false,
        'intervalTaken': false,
        'complete': false,
        'winner': null,
        'draw': false,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  // --- Derived service state ------------------------------------------------

  Side serverFor(Map<String, dynamic> state) =>
      Side.fromWire(state['server'] as String? ?? 'a');

  /// Which court the server delivers from.
  ///
  /// Derived from the serving side's own score: even means the right court,
  /// odd means the left. This is a law of the game, so it is computed rather
  /// than stored — stored, it could drift out of step with the score.
  String serviceCourt(Map<String, dynamic> state) {
    final server = serverFor(state);
    final score = ((state[server == Side.a ? 'currentA' : 'currentB'] as num?) ??
            0)
        .toInt();
    return score.isEven ? 'right' : 'left';
  }

  /// Which player of [side] stands in the RIGHT service court right now.
  ///
  /// A position, not a rotation counter, and that distinction is the whole
  /// reason this file used to have to ask the scorer who won every rally.
  /// Badminton doubles has no rotation: the serving pair swaps courts each
  /// time it wins a rally, the receiving pair stands still, and nobody ever
  /// changes places for any other reason. Store where the four players are
  /// and every other question — who serves, who receives, from which court —
  /// is arithmetic on the score. Store a counter instead, as this did, and
  /// the answer drifts the first time the serve changes hands.
  int rightCourt(Map<String, dynamic> state, Side side) =>
      ((state[side == Side.a ? 'rightCourtA' : 'rightCourtB'] as num?) ?? 0)
          .toInt();

  /// True once the scorer has said who is serving for [side].
  ///
  /// Until they have, the arrangement above is line-up order — a guess that
  /// is right half the time. The pad asks once, on that side's first serve,
  /// and never again for the rest of the match.
  bool courtsSet(Map<String, dynamic> state, Side side) =>
      state[side == Side.a ? 'courtsSetA' : 'courtsSetB'] == true;

  int _scoreOf(Map<String, dynamic> state, Side side) =>
      ((state[side == Side.a ? 'currentA' : 'currentB'] as num?) ?? 0).toInt();

  /// Which member of [side] serves, were [side] serving now.
  ///
  /// The server delivers from the right court on an even score and the left
  /// on an odd one, so who it is falls out of the stored position and the
  /// score together. Note what this produces while a pair holds the serve:
  /// they win, they swap courts AND their score gains one, the two changes
  /// cancel, and the SAME player serves again. That is the law — the serving
  /// pair alternates courts, not servers — and it is what the old counter,
  /// which handed the serve to the partner on every point won, got backwards.
  int serverIndexFor(Map<String, dynamic> state, Side side) {
    final right = rightCourt(state, side);
    return _scoreOf(state, side).isEven ? right : 1 - right;
  }

  /// Which member of [side] receives, were [side] receiving now.
  ///
  /// The serve is diagonal, so the receiver is the player standing in the
  /// service court of the same hand as the server's — right serves to right,
  /// left to left, across the net. Receiving out of turn is a fault and the
  /// umpire's most common call, so the pad names both ends of the exchange.
  int receiverIndexFor(Map<String, dynamic> state, Side side) {
    final right = rightCourt(state, side);
    return serviceCourt(state) == 'right' ? right : 1 - right;
  }

  /// Records who is serving for [side], as a court arrangement.
  ///
  /// Takes the answer at the moment it is given and works backwards through
  /// the parity law: a player serving on an even score is in the right court,
  /// on an odd score in the left. One answer fixes both partners for the rest
  /// of the match.
  Map<String, dynamic> _placeServer(
    Map<String, dynamic> state,
    Side side,
    int index,
  ) =>
      mutate(state, (s) {
        s[side == Side.a ? 'rightCourtA' : 'rightCourtB'] =
            _scoreOf(state, side).isEven ? index : 1 - index;
        s[side == Side.a ? 'courtsSetA' : 'courtsSetB'] = true;
      });

  /// The index of [id] in [side]'s line-up, or null if they are not in it.
  int? _indexOf(ScoringContext ctx, Side side, String? id) {
    if (id == null) return null;
    final squad = ctx.lineupFor(side);
    for (final (i, p) in squad.indexed) {
      if (p.id == id) return i;
    }
    return null;
  }

  /// Names the player who should be serving, in singles or doubles.
  ///
  /// Returns null when no line-up was entered, in which case the pad shows the
  /// side name only.
  String? serverName(Map<String, dynamic> state, ScoringContext ctx) {
    final server = serverFor(state);
    final squad = ctx.lineupFor(server);
    if (squad.isEmpty) return null;
    if (squad.length == 1) return squad.first.name;
    return squad[serverIndexFor(state, server) % squad.length].name;
  }

  bool _isDoubles(ScoringContext ctx) {
    if (ctx.config.containsKey('doubles')) {
      return ctx.boolConfig('doubles', false);
    }
    return ctx.lineupA.length > 1 || ctx.lineupB.length > 1;
  }

  /// Names the player who should be receiving.
  ///
  /// Null in singles, or when no line-up was entered.
  String? receiverName(Map<String, dynamic> state, ScoringContext ctx) {
    final receiving = serverFor(state).opposite;
    final squad = ctx.lineupFor(receiving);
    if (squad.length < 2 || !_isDoubles(ctx)) return null;
    return squad[receiverIndexFor(state, receiving) % squad.length].name;
  }

  /// True when the score has just reached the interval in the current game.
  bool atInterval(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['intervalTaken'] == true) return false;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final at = _intervalAt(ctx);
    return at > 0 && (a == at || b == at) && a != b;
  }

  bool _isDecidingGame(Map<String, dynamic> state, ScoringContext ctx) {
    final toWin = _gamesToWin(ctx);
    final a = ((state['gamesA'] as num?) ?? 0).toInt();
    final b = ((state['gamesB'] as num?) ?? 0).toInt();
    return a == toWin - 1 && b == toWin - 1;
  }

  /// The mid-game change of ends: in the deciding game only, once a side
  /// reaches the trigger score. Ends also change after every game, which is
  /// handled at the game boundary rather than asked of the scorer.
  @override
  EndsChange? endsChangeDue(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return null;
    if (!_isDecidingGame(state, ctx)) return null;
    final at = _changeEndsAt(ctx);
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

  /// True when the players should have changed ends and have not yet.
  bool shouldChangeEnds(Map<String, dynamic> state, ScoringContext ctx) =>
      endsChangeDue(state, ctx) != null && !endsAcknowledged(state, ctx);

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
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Who won the rally?');
        }
        // The one question doubles asks, answered on the way past. It names
        // the SERVER of the rally just played, not its winner, and it arrives
        // only on the first rally each pair serves — after that the pad knows
        // where everybody is standing and stops asking. See [controls].
        var from = state;
        final serverId = action.payload['serverId'] as String?;
        final serving = serverFor(state);
        final placed = _indexOf(ctx, serving, serverId);
        if (placed != null) from = _placeServer(from, serving, placed);
        return ScoringResult.ok(_awardRally(from, action, ctx));

      case 'interval':
        return ScoringResult.ok(mutate(state, (s) {
          s['intervalTaken'] = true;
        }));

      case RacketMatch.changeEndsAction:
        return acknowledgeEndsResult(state, ctx);

      case 'set_first_server':
        final side = action.side;
        if (side == Side.neutral) {
          return const ScoringResult.rejected('Which side serves first?');
        }
        // Only meaningful before a rally has been played in the game.
        final played = ((state['currentA'] as num?) ?? 0).toInt() +
            ((state['currentB'] as num?) ?? 0).toInt();
        if (played > 0) {
          return const ScoringResult.rejected(
            'The first server can only be set before the first rally.',
          );
        }
        final named = _indexOf(ctx, side, action.payload['playerId'] as String?);
        var next = mutate(state, (s) {
          s['server'] = side.wire;
        });
        if (named != null) next = _placeServer(next, side, named);
        return ScoringResult.ok(next);

      case 'correct':
        // Removes the most recent point from a side. Appended as its own
        // event so the log stays append-only.
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
        return ScoringResult.ok(mutate(state, (s) {
          s[key] = current - 1;
        }));

      case 'finish':
        final ga = ((state['gamesA'] as num?) ?? 0).toInt();
        final gb = ((state['gamesB'] as num?) ?? 0).toInt();
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = false;
          s['winner'] = ga == gb ? null : (ga > gb ? 'a' : 'b');
        }));

      case RacketMatch.retireAction:
        // A retirement hands the match to the opponent regardless of score,
        // which is why it cannot be expressed as points. It now carries the
        // REASON as well: injury, walkover and disqualification are three
        // different facts and the record used to flatten them into one.
        return retireResult(state, action);

      case 'reopen':
        return reopenResult(state);

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  Map<String, dynamic> _awardRally(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
  ) {
    final side = action.side;
    final key = side == Side.a ? 'currentA' : 'currentB';
    final wasServing = serverFor(state) == side;

    var next = Map<String, dynamic>.from(state);
    int v(String k) => ((next[k] as num?) ?? 0).toInt();

    next[key] = v(key) + 1;

    // Service passes to the rally winner. When the serving side wins, in
    // doubles the serve moves to the other member of the pair; in singles the
    // index is meaningless and simply toggles harmlessly.
    if (wasServing) {
      // The pair swaps courts and the same player serves again — the score
      // gaining one flips the parity right back. Nothing else moves.
      final courtKey = side == Side.a ? 'rightCourtA' : 'rightCourtB';
      next[courtKey] = 1 - v(courtKey);
    } else {
      // A side-out. The receiving pair does NOT change places; they simply
      // gain the serve, and who serves it falls out of their own score.
      next['server'] = side.wire;
    }

    // Player-level credit. Badminton's meaningful split is points won while
    // serving versus while receiving — it is what separates a player who
    // holds serve from one who only breaks.
    final winnerId =
        action.payload['playerId'] as String? ?? _creditFor(state, ctx, side);
    if (winnerId != null) {
      final isAce = action.payload['ace'] == true;
      next = PlayerTally.addAll(next, winnerId, {
        _pointsWon: 1,
        _rallies: 1,
        if (wasServing) _pointsOnServe: 1 else _pointsOnReceive: 1,
        if (isAce && wasServing) _serviceAces: 1,
      });
    }
    // An unforced error is credited against the player who made it, on the
    // losing side, so the pad can offer "point to A — B's error".
    final errorById = action.payload['errorByPlayerId'] as String?;
    if (errorById != null) {
      next = PlayerTally.addAll(next, errorById, {
        _errors: 1,
        _rallies: 1,
      });
    }

    return _settleGame(next, ctx);
  }

  /// Who a rally is credited to when nobody was asked.
  ///
  /// In SINGLES the side is the player and this is simply a fact. In DOUBLES
  /// it is a convention, and worth being honest about: badminton has no way
  /// to know which partner hit the winning shot — both are on court, either
  /// can end the rally, and no scoresheet in the sport records it. What the
  /// laws DO fix is who served and who received, so the point goes to the two
  /// players who actually exchanged it: the server when the serving pair
  /// wins, the receiver when the receiving pair breaks.
  ///
  /// The alternative was the dialog this replaces — "who won the rally?", on
  /// every point, eighty times in a game to 21, in front of a court the
  /// scorer is meant to be watching. It bought an attribution that is a guess
  /// either way, at the cost of the one thing a scoring pad must never spend:
  /// the scorer's attention on the next rally.
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

    return mutate(state, (s) {
      s['completedGames'] = completed;
      s['gamesA'] = gamesA;
      s['gamesB'] = gamesB;
      s['currentA'] = 0;
      s['currentB'] = 0;
      s['intervalTaken'] = false;
      resetEndsForNewGame(s);
      // The side that won the game serves first in the next one.
      //
      // The court arrangement carries over rather than resetting. Pairs do
      // change ends between games, but they do not re-draw who stands where,
      // and re-asking at every game start would put the one question this pad
      // asks back in front of the scorer three times a match. `set_first_server`
      // is there for the pair that does swap.
      if (matchOver) {
        s['complete'] = true;
        s['draw'] = false;
        s['winner'] = gamesA > gamesB ? 'a' : (gamesB > gamesA ? 'b' : null);
      }
    });
  }

  // --- Presentation ---------------------------------------------------------

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    return '$a - $b';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final games = copyList(state['completedGames'])
        .map((g) => '${g['a']}-${g['b']}')
        .toList();
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    if (state['complete'] != true && (a > 0 || b > 0)) {
      games.add('$a-$b');
    }
    return games.isEmpty ? '0-0' : games.join(', ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return retirementLine(state, ctx);

    final parts = <String>[];
    final gameNo = copyList(state['completedGames']).length + 1;
    parts.add('Game $gameNo');

    final name = serverName(state, ctx) ?? ctx.nameFor(serverFor(state));
    final court = serviceCourt(state) == 'right' ? 'right' : 'left';
    final receiver = receiverName(state, ctx);
    parts.add(receiver == null
        ? '$name to serve from the $court court'
        : '$name to serve from the $court court to $receiver');

    if (atInterval(state, ctx)) parts.add('INTERVAL');
    if (shouldChangeEnds(state, ctx)) parts.add('CHANGE ENDS');

    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final target = _gameTo(ctx);
    if (a >= target - 1 && b >= target - 1) {
      final cap = _hardCap(ctx);
      if (cap > 0 && (a == cap - 1 || b == cap - 1)) {
        parts.add('Match point — next rally decides');
      } else {
        parts.add('Deuce');
      }
    }
    return parts.join(' • ');
  }

  @override
  PadLayout get padLayout => PadLayout.duel;

  @override
  DuelBoard? duelBoard(Map<String, dynamic> state, ScoringContext ctx) {
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final gamesA = ((state['gamesA'] as num?) ?? 0).toInt();
    final gamesB = ((state['gamesB'] as num?) ?? 0).toInt();
    final done = state['complete'] == true;
    final server = done ? null : serverFor(state);
    final target = _gameTo(ctx);
    final cap = _hardCap(ctx);
    final toWin = _gamesToWin(ctx);

    /// What the next rally would settle for [mine], if anything.
    ///
    /// A scoreboard that does not say "match point" is withholding the one
    /// thing everybody in the hall already knows, and it is also the moment a
    /// scorer is most likely to mis-tap — the cue is worth the six lines.
    String? tagFor(int mine, int theirs, int gamesMine) {
      if (done) return null;
      final atCap = cap > 0 && mine == cap - 1;
      final wouldWinGame = atCap || (mine >= target - 1 && mine - theirs >= 1);
      if (!wouldWinGame) return null;
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

    // The server's name carries the service court with it. They are one fact
    // to a scorer — "Anand, right court" is what they are checking — and
    // splitting them across two lines of a small panel reads as two.
    final serverLabel = server == null
        ? null
        : [
            serverName(state, ctx),
            '${serviceCourt(state)} court',
          ].whereType<String>().join(' · ');

    // A finished match shows GAMES, not the points of the last rally.
    //
    // The current-point counters are reset to zero the moment a game closes,
    // so a completed match rendered from them reads "0 – 0" — the one score
    // it certainly was not. Every other surface in the product shows a
    // finished badminton match as 2-1, and the pad has to agree with them.
    final winner = state['winner'];
    return DuelBoard(
      matchScore: DuelMatchScore(
        a: ((state['gamesA'] as num?) ?? 0).toInt(),
        b: ((state['gamesB'] as num?) ?? 0).toInt(),
        label: 'GAMES WON',
      ),
      a: DuelSide(
        name: ctx.entrantAName,
        score: done ? '$gamesA' : '$a',
        sub: done
            ? 'Games won'
            : (toWin > 1 ? 'Games $gamesA' : null),
        serving: server == Side.a,
        serverName: server == Side.a ? serverLabel : null,
        tag: done ? (winner == 'a' ? 'Won' : null) : tagFor(a, b, gamesA),
        pips: done ? null : a,
      ),
      b: DuelSide(
        name: ctx.entrantBName,
        score: done ? '$gamesB' : '$b',
        sub: done
            ? 'Games won'
            : (toWin > 1 ? 'Games $gamesB' : null),
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

  /// The ends line under the pad: where each side is standing and what moves
  /// them. Badminton changes ends between games and again mid-decider, and a
  /// scorer who misses the mid-game swap enters the rest of the match on the
  /// wrong halves of their own screen.
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

    // Doubles asks ONE question, once per side, and then never again.
    //
    // What used to be here was a required "who won the rally?" on both of the
    // pad's primary buttons. In singles the pad filled it in silently (one
    // candidate, one answer), but in doubles it opened a dialog on every
    // point — eighty of them in a game to 21 — to collect an attribution the
    // sport does not actually record. See [_creditFor].
    //
    // What the engine genuinely could not derive was where the four players
    // were standing, and that needs asking exactly twice: once when each pair
    // first serves. From those two answers the laws carry the arrangement
    // through every side-out and into the next game, and the scorer is back
    // to one tap a rally.
    final serving = serverFor(state);
    final askServer = _isDoubles(ctx) && !courtsSet(state, serving);
    final prompts = askServer
        ? [
            PlayerPrompt(
              key: 'serverId',
              label: 'Who is serving for ${ctx.nameFor(serving)}?',
              // Drawn from the SERVING side, which is not the side whose
              // button was pressed when the receivers break — so the pool is
              // named outright rather than taken from the acting side.
              from: PromptSource.eitherSide,
              only: [for (final p in ctx.lineupFor(serving)) p.id],
            ),
          ]
        : const <PlayerPrompt>[];

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
            prompts: prompts,
          ),
          ScoreControl(
            action: 'rally',
            label: ctx.entrantBName,
            side: Side.b,
            style: ControlStyle.primary,
            shortcut: 'l',
            prompts: prompts,
          ),
        ],
      ),
    ];

    if (atInterval(state, ctx)) {
      groups.add(const ScoreControlGroup(title: 'Interval', controls: [
        ScoreControl(
          action: 'interval',
          label: 'Interval taken',
          style: ControlStyle.secondary,
          shortcut: 'i',
        ),
      ]));
    }

    groups.addAll(endsControls(state, ctx));

    groups.add(ScoreControlGroup(
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
    ));

    groups.addAll(retireControls(ctx));

    return groups;
  }

  static List<StatColumn> get columns => columnsFor();

  static List<StatColumn> columnsFor([RuleConfig? rules]) => [
        const StatColumn(
          key: _pointsWon,
          label: 'Points won',
          shortLabel: 'PTS',
        ),
        const StatColumn(
          key: _pointsOnServe,
          label: 'Points on serve',
          shortLabel: 'SRV',
        ),
        const StatColumn(
          key: _pointsOnReceive,
          label: 'Points on receive',
          shortLabel: 'RCV',
        ),
        const StatColumn(
          key: _serviceAces,
          label: 'Service aces',
          shortLabel: 'ACE',
        ),
        const StatColumn(key: _errors, label: 'Errors', shortLabel: 'E'),
        StatColumn(
          key: 'servePct',
          label: 'Serve win %',
          shortLabel: 'S%',
          isPercentage: true,
          decimals: 1,
          derive: (t) {
            final serve = (t[_pointsOnServe] ?? 0).toDouble();
            final total = (t[_pointsWon] ?? 0).toDouble();
            return total == 0 ? 0 : serve / total;
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
        columns: columnsFor(ctx.rules),
      );

  // --- Rally timeline ----------------------------------------------------

  @override
  List<Map<String, dynamic>> rallyCompletedPeriods(
    Map<String, dynamic> state,
  ) =>
      copyList(state['completedGames']);

  @override
  String get rallyPeriodNoun => 'Game';

  /// Badminton's engine logs a won rally as `rally`, not `point`.
  @override
  String get rallyPointAction => 'rally';
}
