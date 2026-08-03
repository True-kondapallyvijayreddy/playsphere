import '../player_stats.dart';
import '../scoring_plugin.dart';

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
class TennisPlugin extends ScoringPlugin {
  const TennisPlugin();

  static const pluginKey = 'tennis';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Tennis';

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
        'server': 'a',
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

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
        }));

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
    // Service alternates every game.
    next['server'] =
        Side.fromWire(next['server'] as String? ?? 'a').opposite.wire;

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
      final w = state['winner'];
      return w is String ? '${ctx.nameFor(Side.fromWire(w))} won' : 'Final';
    }
    final parts = <String>[
      if (state['inTiebreak'] == true)
        'Tiebreak'
      else
        'Games ${state['gamesA'] ?? 0}-${state['gamesB'] ?? 0}',
      '${ctx.nameFor(serverFor(state))} serving',
    ];
    if (isBreakPoint(state, ctx)) parts.add('BREAK POINT');
    return parts.join(' · ');
  }

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
    ];
  }
}
