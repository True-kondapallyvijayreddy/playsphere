import '../player_stats.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';

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
class BadmintonPlugin extends ScoringPlugin {
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
        // Who serves the first rally of the current game.
        'server': 'a',
        // In doubles, which member of the serving pair is on: 0 or 1.
        'serverIndexA': 0,
        'serverIndexB': 0,
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

  /// Names the player who should be serving, in singles or doubles.
  ///
  /// Returns null when no line-up was entered, in which case the pad shows the
  /// side name only.
  String? serverName(Map<String, dynamic> state, ScoringContext ctx) {
    final server = serverFor(state);
    final squad = ctx.lineupFor(server);
    if (squad.isEmpty) return null;
    if (squad.length == 1) return squad.first.name;
    final idx =
        ((state[server == Side.a ? 'serverIndexA' : 'serverIndexB'] as num?) ??
                0)
            .toInt();
    return squad[idx % squad.length].name;
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

  /// True when the players should have changed ends in the deciding game.
  bool shouldChangeEnds(Map<String, dynamic> state, ScoringContext ctx) {
    if (!_isDecidingGame(state, ctx)) return false;
    if (state['endsSwapped'] == true) return false;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final at = _changeEndsAt(ctx);
    return at > 0 && (a >= at || b >= at);
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
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Who won the rally?');
        }
        return ScoringResult.ok(_awardRally(state, action, ctx));

      case 'interval':
        return ScoringResult.ok(mutate(state, (s) {
          s['intervalTaken'] = true;
        }));

      case 'change_ends':
        return ScoringResult.ok(mutate(state, (s) {
          s['endsSwapped'] = !(s['endsSwapped'] == true);
        }));

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
        return ScoringResult.ok(mutate(state, (s) {
          s['server'] = side.wire;
        }));

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

      case 'retire':
        // A retirement hands the match to the opponent regardless of score,
        // which is why it cannot be expressed as points.
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Which side retired?');
        }
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = false;
          s['winner'] = action.side.opposite.wire;
          s['retired'] = action.side.wire;
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
          s['draw'] = false;
          s.remove('retired');
        }));

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
      final idxKey = side == Side.a ? 'serverIndexA' : 'serverIndexB';
      next[idxKey] = (v(idxKey) + 1) % 2;
    } else {
      next['server'] = side.wire;
    }

    // Player-level credit. Badminton's meaningful split is points won while
    // serving versus while receiving — it is what separates a player who
    // holds serve from one who only breaks.
    final winnerId = action.payload['playerId'] as String?;
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
      s['endsSwapped'] = false;
      // The side that won the game serves first in the next one.
      s['server'] = aWon ? 'a' : 'b';
      s['serverIndexA'] = 0;
      s['serverIndexB'] = 0;
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
    if (state['complete'] == true) {
      final retired = state['retired'];
      if (retired is String) {
        return '${ctx.nameFor(Side.fromWire(retired))} retired';
      }
      return null;
    }

    final parts = <String>[];
    final gameNo = copyList(state['completedGames']).length + 1;
    parts.add('Game $gameNo');

    final name = serverName(state, ctx) ?? ctx.nameFor(serverFor(state));
    final court = serviceCourt(state) == 'right' ? 'right' : 'left';
    parts.add('$name to serve from the $court court');

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

    final groups = <ScoreControlGroup>[
      ScoreControlGroup(
        title: 'Rally won by',
        controls: [
          // `_awardRally` has always tallied the point to
          // `payload['playerId']`, and nothing ever supplied one — so every
          // rally was credited to nobody and a badminton career profile was
          // permanently empty however many games were scored. This is a
          // softer failure than the sports that rejected outright, and a
          // worse one: it looked like it worked.
          //
          // In singles the pad fills this in without asking (see
          // `ScoringScreen._askPlayers`) — the side IS the player, and one
          // extra tap per rally across a 21-point game is not a trade worth
          // making. In doubles it asks, because there the answer is real.
          ScoreControl(
            action: 'rally',
            label: ctx.entrantAName,
            side: Side.a,
            style: ControlStyle.primary,
            shortcut: 'a',
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who won the rally?'),
            ],
          ),
          ScoreControl(
            action: 'rally',
            label: ctx.entrantBName,
            side: Side.b,
            style: ControlStyle.primary,
            shortcut: 'l',
            prompts: const [
              PlayerPrompt(key: 'playerId', label: 'Who won the rally?'),
            ],
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

    if (shouldChangeEnds(state, ctx)) {
      groups.add(const ScoreControlGroup(title: 'Ends', controls: [
        ScoreControl(
          action: 'change_ends',
          label: 'Ends changed',
          style: ControlStyle.secondary,
          shortcut: 'e',
        ),
      ]));
    }

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
        const ScoreControl(
          action: 'retire',
          label: 'Retire',
          side: Side.a,
          style: ControlStyle.danger,
        ),
        const ScoreControl(
          action: 'retire',
          label: 'Retire',
          side: Side.b,
          style: ControlStyle.danger,
        ),
      ],
    ));

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
}
