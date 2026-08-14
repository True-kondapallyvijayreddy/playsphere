import '../player_stats.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';

/// Chess, scored as a match rather than a point counter.
///
/// Chess is structurally unlike every other sport here: the result is one of
/// three values, a draw is a first-class outcome rather than an edge case, and
/// the interesting record is the *move list*, not a running total. Scoring it
/// with the generic points engine — which is what the catalogue did before —
/// produced a match that could reach 5-3 and never end.
///
/// A tie-match (board-by-board team chess, as school and college leagues play
/// it) is supported by scoring several boards into one fixture: each board
/// contributes its result to the side totals, which is why the score is held
/// as a double.
///
/// Move capture is optional and configurable. A village club scoring a blitz
/// round does not want to type SAN; a rated classical game does.
class ChessPlugin extends ScoringPlugin {
  const ChessPlugin();

  static const pluginKey = 'chess';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Chess';

  @override
  List<String> get headlineStats => const [_points];

  static const _wins = 'wins';
  static const _draws = 'draws';
  static const _losses = 'losses';
  static const _points = 'points';
  static const _gamesPlayed = 'gamesPlayed';
  static const _whiteGames = 'whiteGames';
  static const _blackGames = 'blackGames';

  double _winPoints(ScoringContext ctx) => ctx.doubleConfig('winPoints', 1.0);
  double _drawPoints(ScoringContext ctx) => ctx.doubleConfig('drawPoints', 0.5);
  double _lossPoints(ScoringContext ctx) => ctx.doubleConfig('lossPoints', 0.0);

  /// How many boards make up this fixture. One for an individual game, more
  /// for a team match.
  int _boards(ScoringContext ctx) => ctx.intConfig('boards', 1);

  bool _recordMoves(ScoringContext ctx) => ctx.boolConfig('recordMoves', false);

  /// Which time control this was played at. Ratings are kept per time
  /// control — a bullet rating and a classical rating measure different
  /// skills, and merging them is why §7.11 asks for the split.
  String timeControl(ScoringContext ctx) =>
      ctx.stringConfig('timeControl', 'classical');

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        // Held as doubles because a draw is worth half a point.
        'a': 0.0,
        'b': 0.0,
        'boardsPlayed': 0,
        'results': <Map<String, dynamic>>[],
        // SAN move list for the board in progress.
        'moves': <String>[],
        'complete': false,
        'winner': null,
        'draw': false,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  double _score(Map<String, dynamic> state, String side) =>
      ((state[side] as num?) ?? 0).toDouble();

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
      case 'move':
        if (!_recordMoves(ctx)) {
          return const ScoringResult.rejected(
            'This time control is not recording moves.',
          );
        }
        final san = (action.payload['san'] as String?)?.trim();
        if (san == null || san.isEmpty) {
          return const ScoringResult.rejected('What move was played?');
        }
        final moves = List<String>.from(
          (state['moves'] as List?)?.whereType<String>() ?? const <String>[],
        )..add(san);
        return ScoringResult.ok(mutate(state, (s) {
          s['moves'] = moves;
        }));

      case 'takeback':
        final moves = List<String>.from(
          (state['moves'] as List?)?.whereType<String>() ?? const <String>[],
        );
        if (moves.isEmpty) {
          return const ScoringResult.rejected('No moves to take back.');
        }
        moves.removeLast();
        return ScoringResult.ok(mutate(state, (s) {
          s['moves'] = moves;
        }));

      case 'result':
        // The board is decided. `outcome` is win-a / win-b / draw, and
        // `reason` records how — resignation, checkmate, flag, agreement.
        final result = action.payload['result'] as String?;
        if (result != 'a' && result != 'b' && result != 'draw') {
          return const ScoringResult.rejected(
            'A board ends as a win to one side or a draw.',
          );
        }
        return ScoringResult.ok(_recordBoard(state, action, ctx, result!));

      case 'finish':
        final a = _score(state, 'a');
        final b = _score(state, 'b');
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = true;
          s['draw'] = a == b;
          s['winner'] = a == b ? null : (a > b ? 'a' : 'b');
        }));

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
          s['draw'] = false;
        }));

      default:
        return ScoringResult.rejected('Unknown action "${action.type}".');
    }
  }

  Map<String, dynamic> _recordBoard(
    Map<String, dynamic> state,
    ScoreAction action,
    ScoringContext ctx,
    String result,
  ) {
    final isDraw = result == 'draw';
    final winPts = _winPoints(ctx);
    final drawPts = _drawPoints(ctx);
    final lossPts = _lossPoints(ctx);

    var next = Map<String, dynamic>.from(state);

    next['a'] = _score(state, 'a') +
        (isDraw ? drawPts : (result == 'a' ? winPts : lossPts));
    next['b'] = _score(state, 'b') +
        (isDraw ? drawPts : (result == 'b' ? winPts : lossPts));

    final boardsPlayed = ((state['boardsPlayed'] as num?) ?? 0).toInt() + 1;
    next['boardsPlayed'] = boardsPlayed;

    final moves = List<String>.from(
      (state['moves'] as List?)?.whereType<String>() ?? const <String>[],
    );

    final results = copyList(state['results'])
      ..add({
        'board': boardsPlayed,
        'result': result,
        'reason': action.payload['reason'] ?? 'unknown',
        'whitePlayerId': action.payload['whitePlayerId'],
        'blackPlayerId': action.payload['blackPlayerId'],
        if (moves.isNotEmpty) 'pgn': pgnOf(moves),
      });
    next['results'] = results;
    // The next board starts from an empty move list.
    next['moves'] = <String>[];

    // Player-level credit, so a board result reaches career stats and the
    // per-time-control rating.
    final white = action.payload['whitePlayerId'] as String?;
    final black = action.payload['blackPlayerId'] as String?;

    if (white != null) {
      next = PlayerTally.addAll(next, white, {
        _gamesPlayed: 1,
        _whiteGames: 1,
        if (result == 'a') _wins: 1,
        if (result == 'b') _losses: 1,
        if (isDraw) _draws: 1,
        _points: isDraw ? drawPts : (result == 'a' ? winPts : lossPts),
      });
    }
    if (black != null) {
      next = PlayerTally.addAll(next, black, {
        _gamesPlayed: 1,
        _blackGames: 1,
        if (result == 'b') _wins: 1,
        if (result == 'a') _losses: 1,
        if (isDraw) _draws: 1,
        _points: isDraw ? drawPts : (result == 'b' ? winPts : lossPts),
      });
    }

    // A fixture of N boards finishes when all N are in.
    if (boardsPlayed >= _boards(ctx)) {
      final a = _score(next, 'a');
      final b = _score(next, 'b');
      next['complete'] = true;
      next['draw'] = a == b;
      next['winner'] = a == b ? null : (a > b ? 'a' : 'b');
    }
    return next;
  }

  /// Renders a move list as PGN movetext.
  ///
  /// Only the movetext, not the seven-tag roster: the tags duplicate data the
  /// fixture already holds (event, site, date, players, result), and storing
  /// them twice invites the two copies to disagree. An exporter assembles the
  /// full PGN from the fixture plus this.
  static String pgnOf(List<String> moves) {
    final buf = StringBuffer();
    for (var i = 0; i < moves.length; i++) {
      if (i.isEven) {
        if (i > 0) buf.write(' ');
        buf.write('${(i ~/ 2) + 1}.');
      }
      buf.write(' ${moves[i]}');
    }
    return buf.toString();
  }

  /// The move list for the board in progress.
  List<String> movesOf(Map<String, dynamic> state) => List<String>.from(
        (state['moves'] as List?)?.whereType<String>() ?? const <String>[],
      );

  // --- Presentation ---------------------------------------------------------

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) =>
      '${_fmt(_score(state, 'a'))} - ${_fmt(_score(state, 'b'))}';

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) =>
      headline(state, ctx);

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return null;
    final parts = <String>[];
    final boards = _boards(ctx);
    if (boards > 1) {
      final played = ((state['boardsPlayed'] as num?) ?? 0).toInt();
      parts.add('Board ${played + 1} of $boards');
    }
    parts.add(timeControl(ctx));
    if (_recordMoves(ctx)) {
      final n = movesOf(state).length;
      if (n > 0) parts.add('${(n / 2).ceil()} moves');
    }
    return parts.join(' • ');
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    // Side totals are halves; the standings column is an int, so report the
    // board count each side has taken rather than rounding the half-points.
    final a = _score(state, 'a');
    final b = _score(state, 'b');
    if (state['complete'] != true) {
      return MatchOutcome(
        isComplete: false,
        scoreForA: (a * 2).round(),
        scoreForB: (b * 2).round(),
      );
    }
    final winner = state['winner'];
    return MatchOutcome(
      isComplete: true,
      winnerSide: winner is String ? Side.fromWire(winner) : null,
      isDraw: state['draw'] == true,
      scoreForA: (a * 2).round(),
      scoreForB: (b * 2).round(),
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
        title: 'Board result',
        controls: [
          ScoreControl(
            action: 'result',
            label: '1 - 0',
            side: Side.a,
            style: ControlStyle.primary,
            payload: const {'result': 'a'},
            shortcut: '1',
            tooltip: '${ctx.entrantAName} wins the board',
          ),
          const ScoreControl(
            action: 'result',
            label: '½ - ½',
            style: ControlStyle.secondary,
            payload: {'result': 'draw'},
            shortcut: '5',
            tooltip: 'Draw',
          ),
          ScoreControl(
            action: 'result',
            label: '0 - 1',
            side: Side.b,
            style: ControlStyle.primary,
            payload: const {'result': 'b'},
            shortcut: '0',
            tooltip: '${ctx.entrantBName} wins the board',
          ),
        ],
      ),
    ];

    if (_recordMoves(ctx)) {
      groups.add(const ScoreControlGroup(
        title: 'Moves',
        controls: [
          ScoreControl(
            action: 'takeback',
            label: 'Take back',
            style: ControlStyle.subtle,
            shortcut: 'z',
            tooltip: 'Remove the last recorded move',
          ),
        ],
      ));
    }

    return groups;
  }

  static List<StatColumn> get columns => columnsFor();

  static List<StatColumn> columnsFor([RuleConfig? rules]) => [
        const StatColumn(key: _gamesPlayed, label: 'Games', shortLabel: 'G'),
        const StatColumn(key: _wins, label: 'Wins', shortLabel: 'W'),
        const StatColumn(key: _draws, label: 'Draws', shortLabel: 'D'),
        const StatColumn(key: _losses, label: 'Losses', shortLabel: 'L'),
        const StatColumn(
          key: _points,
          label: 'Points',
          shortLabel: 'PTS',
          decimals: 1,
        ),
        StatColumn(
          key: 'scorePct',
          label: 'Score %',
          shortLabel: 'S%',
          isPercentage: true,
          decimals: 1,
          derive: (t) {
            final games = (t[_gamesPlayed] ?? 0).toDouble();
            return games == 0 ? 0 : (t[_points] ?? 0).toDouble() / games;
          },
        ),
        const StatColumn(key: _whiteGames, label: 'As white', shortLabel: 'WH'),
        const StatColumn(key: _blackGames, label: 'As black', shortLabel: 'BL'),
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
