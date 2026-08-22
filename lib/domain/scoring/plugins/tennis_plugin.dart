import '../player_stats.dart';
import '../racket_rules.dart';
import '../scoring_plugin.dart';
import '../rally_timeline.dart';

/// Tennis, with the real scoring ladder.
///
/// Tennis is the one sport where a naive point counter is not merely
/// incomplete but *wrong*: the score is not a number, it is a ladder — 15, 30,
/// 40, deuce, advantage — nested inside games, nested inside sets, with a
/// tiebreak that has its own serving rotation. An engine that counts points
/// cannot render "40-30" or decide when a game was won.
///
/// Encoded, all configurable:
///
///  * **A game needs four points and a two-point margin.** 40-40 is deuce, and
///    from there it is advantage and back until someone leads by two. With
///    `noAd` the next point after deuce simply wins.
///  * **A set is six games with a two-game margin.** At 6-6 a tiebreak.
///  * **The tiebreak serving order is unlike anything else**: the first server
///    serves one point, then service alternates every TWO points. Getting this
///    wrong misattributes every ace and double fault in the tiebreak.
///  * **The deciding set can be a 10-point match tiebreak** instead of a full
///    set, which is now standard in most formats.
class TennisPlugin extends ScoringPlugin with RallyTimeline, RacketMatch {
  const TennisPlugin();

  static const pluginKey = 'tennis';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Tennis';

  @override
  List<String> get headlineStats => const [_pointsWon];

  static const _aces = 'aces';
  static const _doubleFaults = 'doubleFaults';
  static const _winners = 'winners';
  static const _unforcedErrors = 'unforcedErrors';
  static const _pointsWon = 'pointsWon';
  static const _breakPointsWon = 'breakPointsWon';
  static const _breakPointsFaced = 'breakPointsFaced';

  int _setsToWin(ScoringContext ctx) => ctx.intConfig('setsToWin', 2);
  int _gamesPerSet(ScoringContext ctx) => ctx.intConfig('gamesPerSet', 6);
  int _tiebreakTo(ScoringContext ctx) => ctx.intConfig('tiebreakTo', 7);
  bool _noAd(ScoringContext ctx) => ctx.boolConfig('noAd', false);

  /// Many formats replace a deciding set with a 10-point match tiebreak.
  bool _decidingSetTiebreak(ScoringContext ctx) =>
      ctx.boolConfig('decidingSetTiebreak', false);
  int _decidingTiebreakTo(ScoringContext ctx) =>
      ctx.intConfig('decidingTiebreakTo', ctx.intConfig('matchTiebreakTo', 10));

  /// Points needed to take a game, and the margin required. Fast4 and other
  /// abbreviated formats vary both, so neither is a constant.
  int _pointsToWinGame(ScoringContext ctx) =>
      ctx.intConfig('pointsToWinGame', 4);
  int _gameWinBy(ScoringContext ctx) => ctx.intConfig('gameWinBy', 2);

  /// Games needed to take a set, and by what margin. Fast4 sets are to four
  /// and need only a one-game margin.
  int _gamesWinBy(ScoringContext ctx) => ctx.intConfig('gamesWinBy', 2);

  int _tiebreakWinBy(ScoringContext ctx) => ctx.intConfig('tiebreakWinBy', 2);

  /// How often ends change inside a tiebreak. Six by law — and a number the
  /// presets have carried since they were written without any engine ever
  /// reading it.
  int _tiebreakChangeEndsEvery(ScoringContext ctx) =>
      ctx.intConfig('tiebreakChangeEndsEvery', 6);

  /// Doubles needs to know which partner is serving. Singles ignores it.
  bool _isDoubles(ScoringContext ctx) {
    if (ctx.config.containsKey('doubles')) {
      return ctx.boolConfig('doubles', false);
    }
    return ctx.lineupA.length > 1 || ctx.lineupB.length > 1;
  }

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        // Points within the current game, as raw counts. The ladder is a
        // rendering of these, not a separate state.
        'pointsA': 0,
        'pointsB': 0,
        'gamesA': 0,
        'gamesB': 0,
        'setsA': 0,
        'setsB': 0,
        'completedSets': <Map<String, dynamic>>[],
        // Set by the toss: choosing to serve starts you serving, choosing
        // to receive or to pick ends hands the first game to the opponent.
        'server': ctx.startingSide.wire,
        // Which partner of each pair serves this side's next service game.
        // Tennis doubles fixes the order for the whole set, so it advances
        // once per service game rather than being derivable from the score.
        'serverIndexA': 0,
        'serverIndexB': 0,
        'inTiebreak': false,
        'tiebreakPointsPlayed': 0,
        'complete': false,
        'winner': null,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  /// Renders one side's game score the way tennis says it: 0, 15, 30, 40, AD.
  String pointLabel(Map<String, dynamic> state, Side side, ScoringContext ctx) {
    if (state['inTiebreak'] == true) {
      return ((state[side == Side.a ? 'pointsA' : 'pointsB'] as num?) ?? 0)
          .toInt()
          .toString();
    }
    final mine = ((state[side == Side.a ? 'pointsA' : 'pointsB'] as num?) ?? 0).toInt();
    final theirs = ((state[side == Side.a ? 'pointsB' : 'pointsA'] as num?) ?? 0).toInt();

    if (mine >= 3 && theirs >= 3) {
      if (mine == theirs) return '40';
      return mine > theirs ? 'AD' : '40';
    }
    return switch (mine) {
      0 => '0',
      1 => '15',
      2 => '30',
      _ => '40',
    };
  }

  /// Whose serve it is. In a tiebreak the rotation is unlike the rest of the
  /// match: one point, then every two.
  Side serverFor(Map<String, dynamic> state) {
    final base = Side.fromWire(state['server'] as String? ?? 'a');
    if (state['inTiebreak'] != true) return base;
    final played = ((state['tiebreakPointsPlayed'] as num?) ?? 0).toInt();
    // Point 0 → base. Points 1,2 → other. Points 3,4 → base. And so on.
    final blocks = ((played + 1) ~/ 2) % 2;
    return blocks == 0 ? base : base.opposite;
  }

  /// True when the receiver is one point from taking the server's game.
  bool isBreakPoint(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['inTiebreak'] == true) return false;
    final server = Side.fromWire(state['server'] as String? ?? 'a');
    final receiver = server.opposite;
    final rec = ((state[receiver == Side.a ? 'pointsA' : 'pointsB'] as num?) ?? 0).toInt();
    final srv = ((state[server == Side.a ? 'pointsA' : 'pointsB'] as num?) ?? 0).toInt();
    // With no-ad, the receiver only needs to be level or ahead at 40.
    if (_noAd(ctx)) return rec >= 3 && rec >= srv;
    // With advantage scoring, the receiver must be one point from four AND
    // two clear: that is, already at 40 or better and at least one ahead.
    return rec >= 3 && rec - srv >= 1;
  }

  /// Names the partner who should be serving this game.
  ///
  /// Null in singles with no line-up, or whenever nobody has been entered —
  /// the pad then shows the side name alone rather than inventing one.
  String? serverName(Map<String, dynamic> state, ScoringContext ctx) {
    final server = serverFor(state);
    final squad = ctx.lineupFor(server);
    if (squad.isEmpty) return null;
    if (squad.length == 1 || !_isDoubles(ctx)) return squad.first.name;
    final idx =
        ((state[server == Side.a ? 'serverIndexA' : 'serverIndexB'] as num?) ??
                0)
            .toInt();
    return squad[idx % squad.length].name;
  }

  /// Ends change after every odd game of a set, and every six points of a
  /// tiebreak.
  ///
  /// Both numbers come from the laws and both were previously unimplemented —
  /// `tiebreakChangeEndsEvery` sat in the presets unread. The odd-game rule is
  /// stated as "at the end of the first, third and every subsequent alternate
  /// game", which is the same thing as "whenever the games played in this set
  /// total an odd number".
  @override
  EndsChange? endsChangeDue(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return null;
    final setNo = copyList(state['completedSets']).length + 1;

    if (state['inTiebreak'] == true) {
      final every = _tiebreakChangeEndsEvery(ctx);
      if (every <= 0) return null;
      final played = ((state['tiebreakPointsPlayed'] as num?) ?? 0).toInt();
      if (played == 0 || played % every != 0) return null;
      return EndsChange(
        id: 'tb$setNo@$played',
        label: 'Change ends',
        detail: 'Tie-break — $played points played.',
      );
    }

    final games = ((state['gamesA'] as num?) ?? 0).toInt() +
        ((state['gamesB'] as num?) ?? 0).toInt();
    // Mid-game the players are already at their ends; the change belongs to
    // the game boundary, which is the only moment both point counters are
    // zero.
    final midGame = (((state['pointsA'] as num?) ?? 0).toInt() +
            ((state['pointsB'] as num?) ?? 0).toInt()) >
        0;
    if (games == 0 || games.isEven || midGame) return null;
    return EndsChange(
      id: 'set${setNo}g$games',
      label: 'Change ends',
      detail: 'Set $setNo — $games games played.',
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
        final how = action.payload['how'] as String?;
        final player = action.payload['playerId'] as String?;
        final wasBreakPoint = isBreakPoint(state, ctx);
        final server = Side.fromWire(state['server'] as String? ?? 'a');

        var next = Map<String, dynamic>.from(state);

        if (player != null) {
          next = PlayerTally.addAll(next, player, {
            _pointsWon: 1,
            if (how == 'ace') _aces: 1,
            if (how == 'winner') _winners: 1,
            if (wasBreakPoint && action.side != server) _breakPointsWon: 1,
          });
        }
        // A double fault or unforced error is charged to whoever made it —
        // which is the side that LOST the point.
        final culprit = action.payload['errorById'] as String?;
        if (culprit != null) {
          next = PlayerTally.addAll(next, culprit, {
            if (how == 'double_fault') _doubleFaults: 1,
            if (how == 'unforced_error') _unforcedErrors: 1,
          });
        }
        if (wasBreakPoint && action.side == server) {
          final srvPlayer = action.payload['serverPlayerId'] as String?;
          if (srvPlayer != null) {
            next = PlayerTally.add(next, srvPlayer, _breakPointsFaced, 1);
          }
        }

        return ScoringResult.ok(_awardPoint(next, action.side, ctx));

      case 'correct':
        // Takes back the last point of the current game. The event log is
        // never rewritten — see `ScoringPlugin.undoActionType` for the full
        // undo — but a scorer who has simply over-tapped wants one button,
        // not a trip through the history.
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Correct which side?');
        }
        final key = action.side == Side.a ? 'pointsA' : 'pointsB';
        final current = ((state[key] as num?) ?? 0).toInt();
        if (current <= 0) {
          return const ScoringResult.rejected(
            'That side has no points in this game to take back.',
          );
        }
        return ScoringResult.ok(mutate(state, (s) {
          s[key] = current - 1;
          if (s['inTiebreak'] == true) {
            final played = ((s['tiebreakPointsPlayed'] as num?) ?? 0).toInt();
            // The tiebreak service rotation is counted from points played,
            // so taking a point back has to take the count back with it or
            // the wrong player is shown serving for the rest of the breaker.
            s['tiebreakPointsPlayed'] = played > 0 ? played - 1 : 0;
          }
        }));

      case RacketMatch.changeEndsAction:
        return acknowledgeEndsResult(state, ctx);

      case RacketMatch.retireAction:
        // Tennis had no retirement at all until now: a player who rolled an
        // ankle at 4-3 left the scorer with a fixture that could not be
        // closed by any action the engine accepted.
        return retireResult(state, action);

      case 'reopen':
        return reopenResult(state);

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  Map<String, dynamic> _awardPoint(
    Map<String, dynamic> state,
    Side side,
    ScoringContext ctx,
  ) {
    final key = side == Side.a ? 'pointsA' : 'pointsB';
    final otherKey = side == Side.a ? 'pointsB' : 'pointsA';
    var next = Map<String, dynamic>.from(state);
    int v(String k) => ((next[k] as num?) ?? 0).toInt();

    next[key] = v(key) + 1;

    if (next['inTiebreak'] == true) {
      next['tiebreakPointsPlayed'] = v('tiebreakPointsPlayed') + 1;
      final target = _isDecidingSet(next, ctx) && _decidingSetTiebreak(ctx)
          ? _decidingTiebreakTo(ctx)
          : _tiebreakTo(ctx);
      if (v(key) >= target &&
          v(key) - v(otherKey) >= _tiebreakWinBy(ctx)) {
        return _awardSet(next, side, ctx, viaTiebreak: true);
      }
      return next;
    }

    // A game needs four points and a two-point margin — or, with no-ad, the
    // next point after deuce.
    final mine = v(key);
    final theirs = v(otherKey);
    final noAd = _noAd(ctx);
    final toWin = _pointsToWinGame(ctx);
    // With no-ad there is no advantage: four points takes the game whatever
    // the margin, so 4-3 wins where advantage scoring would call it AD.
    // Testing `mine >= 3 && theirs >= 3` instead would award the game AT
    // deuce, to whoever happened to arrive there second.
    final gameWon = noAd
        ? mine >= toWin
        : (mine >= toWin && mine - theirs >= _gameWinBy(ctx));

    if (gameWon) return _awardGame(next, side, ctx);
    return next;
  }

  bool _isDecidingSet(Map<String, dynamic> state, ScoringContext ctx) {
    final toWin = _setsToWin(ctx);
    final a = ((state['setsA'] as num?) ?? 0).toInt();
    final b = ((state['setsB'] as num?) ?? 0).toInt();
    return a == toWin - 1 && b == toWin - 1;
  }

  Map<String, dynamic> _awardGame(
    Map<String, dynamic> state,
    Side side,
    ScoringContext ctx,
  ) {
    var next = Map<String, dynamic>.from(state);
    int v(String k) => ((next[k] as num?) ?? 0).toInt();

    final gk = side == Side.a ? 'gamesA' : 'gamesB';
    final otherGk = side == Side.a ? 'gamesB' : 'gamesA';
    next[gk] = v(gk) + 1;
    next['pointsA'] = 0;
    next['pointsB'] = 0;
    // Service alternates every game — and within a doubles pair the two
    // partners take turns, so the side that has just served advances to its
    // other partner for its next service game.
    final outgoing = Side.fromWire(next['server'] as String? ?? 'a');
    final idxKey = outgoing == Side.a ? 'serverIndexA' : 'serverIndexB';
    next[idxKey] = (v(idxKey) + 1) % 2;
    next['server'] = outgoing.opposite.wire;

    final target = _gamesPerSet(ctx);
    final mine = v(gk);
    final theirs = v(otherGk);

    if (mine >= target && mine - theirs >= _gamesWinBy(ctx)) {
      return _awardSet(next, side, ctx);
    }
    // Six all: tiebreak, unless the format replaces a deciding set with a
    // match tiebreak, in which case that is what this already is.
    if (mine == target && theirs == target) {
      next['inTiebreak'] = true;
      next['tiebreakPointsPlayed'] = 0;
      next['pointsA'] = 0;
      next['pointsB'] = 0;
    }
    return next;
  }

  Map<String, dynamic> _awardSet(
    Map<String, dynamic> state,
    Side side,
    ScoringContext ctx, {
    bool viaTiebreak = false,
  }) {
    var next = Map<String, dynamic>.from(state);
    int v(String k) => ((next[k] as num?) ?? 0).toInt();

    final completed = copyList(next['completedSets'])
      ..add({
        'a': viaTiebreak && v('gamesA') == v('gamesB')
            ? v('gamesA') + (side == Side.a ? 1 : 0)
            : v('gamesA'),
        'b': viaTiebreak && v('gamesA') == v('gamesB')
            ? v('gamesB') + (side == Side.b ? 1 : 0)
            : v('gamesB'),
        'tiebreak': viaTiebreak,
      });

    final sk = side == Side.a ? 'setsA' : 'setsB';
    next[sk] = v(sk) + 1;
    next['completedSets'] = completed;
    next['gamesA'] = 0;
    next['gamesB'] = 0;
    next['pointsA'] = 0;
    next['pointsB'] = 0;
    next['inTiebreak'] = false;
    next['tiebreakPointsPlayed'] = 0;
    clearEndsAcknowledgement(next);

    if (v(sk) >= _setsToWin(ctx)) {
      next['complete'] = true;
      next['winner'] = side.wire;
    } else if (_isDecidingSet(next, ctx) && _decidingSetTiebreak(ctx)) {
      // The deciding "set" is a match tiebreak in this format.
      next['inTiebreak'] = true;
      next['tiebreakPointsPlayed'] = 0;
    }
    return next;
  }

  static List<StatColumn> get columns => [
        const StatColumn(key: _pointsWon, label: 'Points won', shortLabel: 'PTS'),
        const StatColumn(key: _aces, label: 'Aces', shortLabel: 'ACE'),
        const StatColumn(
          key: _doubleFaults,
          label: 'Double faults',
          shortLabel: 'DF',
        ),
        const StatColumn(key: _winners, label: 'Winners', shortLabel: 'W'),
        const StatColumn(
          key: _unforcedErrors,
          label: 'Unforced errors',
          shortLabel: 'UE',
        ),
        const StatColumn(
          key: _breakPointsWon,
          label: 'Break points won',
          shortLabel: 'BP',
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

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      return '${state['setsA'] ?? 0} - ${state['setsB'] ?? 0}';
    }
    return '${pointLabel(state, Side.a, ctx)} - '
        '${pointLabel(state, Side.b, ctx)}';
  }

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) {
    final sets = copyList(state['completedSets'])
        .map((s) => '${s['a']}-${s['b']}')
        .toList();
    final current = state['complete'] == true
        ? null
        : '${state['gamesA'] ?? 0}-${state['gamesB'] ?? 0}*';
    final parts = [...sets, if (current != null) current];
    return parts.isEmpty ? '0-0' : parts.join(', ');
  }

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) {
      final retired = retirementLine(state, ctx);
      if (retired != null) return retired;
      final w = state['winner'];
      return w is String ? '${ctx.nameFor(Side.fromWire(w))} won' : 'Final';
    }
    final serving = serverName(state, ctx) ?? ctx.nameFor(serverFor(state));
    final parts = <String>[
      if (state['inTiebreak'] == true)
        'Tiebreak'
      else
        'Games ${state['gamesA'] ?? 0}-${state['gamesB'] ?? 0}',
      '$serving serving',
    ];
    if (isBreakPoint(state, ctx)) parts.add('BREAK POINT');
    if (endsChangeDue(state, ctx) != null && !endsAcknowledged(state, ctx)) {
      parts.add('CHANGE ENDS');
    }
    return parts.join(' · ');
  }

  @override
  PadLayout get padLayout => PadLayout.duel;

  @override
  DuelBoard? duelBoard(Map<String, dynamic> state, ScoringContext ctx) {
    final done = state['complete'] == true;
    final server = done ? null : serverFor(state);
    final gamesA = ((state['gamesA'] as num?) ?? 0).toInt();
    final gamesB = ((state['gamesB'] as num?) ?? 0).toInt();
    final tiebreak = state['inTiebreak'] == true;
    final breakPoint = !done && isBreakPoint(state, ctx);

    final periods = <DuelPeriod>[
      for (final (i, st) in copyList(state['completedSets']).indexed)
        DuelPeriod(
          label: 'S${i + 1}',
          a: ((st['a'] as num?) ?? 0).toInt(),
          b: ((st['b'] as num?) ?? 0).toInt(),
        ),
      if (!done)
        DuelPeriod(
          label: 'S${copyList(state['completedSets']).length + 1}',
          a: gamesA,
          b: gamesB,
          current: true,
        ),
    ];

    // The break point belongs to the RECEIVER, which is the half of it that
    // is easy to get backwards: it is the server who is in trouble.
    final receiver = server?.opposite;

    // The serving partner's name, so a doubles pad says who is actually
    // about to serve rather than only which pair.
    final serverLabel = server == null ? null : serverName(state, ctx);

    DuelSide sideFor(Side side, int games) => DuelSide(
          name: ctx.nameFor(side),
          // The big number is the game score — '40', 'AD', or the tiebreak
          // count — because that is what the next tap changes. Games and sets
          // are the smaller lines, which is the way every tennis scoreboard
          // in the world is arranged.
          score: done
              ? '${(state[side == Side.a ? 'setsA' : 'setsB'] as num?) ?? 0}'
              : pointLabel(state, side, ctx),
          sub: done ? 'Sets won' : 'Games $games',
          serving: server == side,
          serverName: server == side ? serverLabel : null,
          tag: done
              ? (state['winner'] == side.wire ? 'Won' : null)
              : (breakPoint && receiver == side ? 'Break point' : null),
          // Boxes only in a tie-break, which is the one part of tennis that
          // IS a race to a number. Drawing them for 15/30/40 would diagram a
          // rule the sport does not have — see [DuelSide.pips].
          pips: !done && tiebreak
              ? ((state[side == Side.a ? 'pointsA' : 'pointsB'] as num?) ?? 0)
                  .toInt()
              : null,
        );

    return DuelBoard(
      matchScore: DuelMatchScore(
        a: ((state['setsA'] as num?) ?? 0).toInt(),
        b: ((state['setsB'] as num?) ?? 0).toInt(),
        label: 'SETS WON',
      ),
      a: sideFor(Side.a, gamesA),
      b: sideFor(Side.b, gamesB),
      periods: periods,
      status: tiebreak ? 'Tie-break' : statusLine(state, ctx),
      pipTarget: !done && tiebreak ? _tiebreakTo(ctx) : null,
      pointsNote: 'Best of ${_setsToWin(ctx) * 2 - 1} sets',
      endsNote: _endsNote(state, ctx),
    );
  }

  /// Which end each side is on, and what will move them. Tennis changes ends
  /// on odd games and every six points of a tie-break, and a pad that does not
  /// say so leaves the scorer to count games in their head.
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
    if (state['complete'] != true) return MatchOutcome.inProgress;
    return MatchOutcome(
      isComplete: true,
      winnerSide: state['winner'] == null
          ? null
          : Side.fromWire(state['winner'] as String),
      scoreForA: ((state['setsA'] as num?) ?? 0).toInt(),
      scoreForB: ((state['setsB'] as num?) ?? 0).toInt(),
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

    // Filled without asking in singles, asked in doubles — see the note on
    // the badminton rally control for why the two differ.
    const winner = [PlayerPrompt(key: 'playerId', label: 'Who won the point?')];

    List<ScoreControl> forSide(Side side, String key) => [
          ScoreControl(
            action: 'point',
            label: 'Point',
            side: side,
            style: ControlStyle.primary,
            shortcut: key,
            prompts: winner,
          ),
          ScoreControl(
            action: 'point',
            label: 'Ace',
            side: side,
            payload: const {'how': 'ace'},
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who served the ace?'),
            ],
          ),
          ScoreControl(
            action: 'point',
            label: 'Winner',
            side: side,
            payload: const {'how': 'winner'},
            prompts: winner,
          ),
        ];

    return [
      ScoreControlGroup(title: ctx.entrantAName, controls: forSide(Side.a, 'a')),
      ScoreControlGroup(title: ctx.entrantBName, controls: forSide(Side.b, 'l')),
      ...endsControls(state, ctx),
      ScoreControlGroup(
        title: 'Corrections',
        controls: [
          ScoreControl(
            action: 'correct',
            label: '−1 ${ctx.entrantAName}',
            side: Side.a,
            style: ControlStyle.subtle,
            shortcut: 'z',
          ),
          ScoreControl(
            action: 'correct',
            label: '−1 ${ctx.entrantBName}',
            side: Side.b,
            style: ControlStyle.subtle,
            shortcut: 'm',
          ),
        ],
      ),
      ...retireControls(ctx),
    ];
  }

  // --- Rally timeline ----------------------------------------------------

  @override
  List<Map<String, dynamic>> rallyCompletedPeriods(
    Map<String, dynamic> state,
  ) =>
      copyList(state['completedSets']);

  @override
  String get rallyPeriodNoun => 'Set';
}
