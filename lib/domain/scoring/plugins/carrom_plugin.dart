import '../player_stats.dart';
import '../rule_config.dart';
import '../scoring_plugin.dart';

/// Carrom, scored by the board.
///
/// The generic points engine had carrom as "first to 25", which is wrong in
/// both directions: a match runs to 29 points, and 25 is the *cap on a single
/// board*, not the match target. Getting this right matters because carrom is
/// one of the few sports in the catalogue that state associations across
/// Telangana actually run ladders for.
///
/// The laws encoded here, all configurable:
///
///  * A board is won by the player who pockets all nine of their coins first.
///  * The winner scores one point per opponent coin still on the board,
///    capped at 25.
///  * The queen is worth three, but only to a player who covered it, and only
///    while their running total is below 22 — a player on 22 or more gains
///    nothing from it, which is the rule most scorers forget.
///  * A match runs to 29 points or a fixed number of boards, whichever the
///    organizer chose.
/// What happened to the queen on a board: the three states that can actually
/// occur, so a scorer cannot record a fourth.
enum _Queen { none, covered, uncovered }

class CarromPlugin extends ScoringPlugin {
  const CarromPlugin();

  static const pluginKey = 'carrom';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Carrom';

  @override
  List<String> get headlineStats => const [_boardsWon];

  static const _boardsWon = 'boardsWon';
  static const _pointsScored = 'pointsScored';
  static const _coinsPocketed = 'coinsPocketed';
  static const _queens = 'queens';
  static const _queensCovered = 'queensCovered';
  static const _fouls = 'fouls';

  int _matchTarget(ScoringContext ctx) => ctx.intConfig('matchTarget', 29);
  int _maxBoards(ScoringContext ctx) => ctx.intConfig('maxBoards', 8);
  int _queenPoints(ScoringContext ctx) => ctx.intConfig('queenPoints', 3);
  int _coinPoints(ScoringContext ctx) => ctx.intConfig('coinPoints', 1);
  int _coinsPerSide(ScoringContext ctx) => ctx.intConfig('coinsPerSide', 9);
  int _maxBoardPoints(ScoringContext ctx) =>
      ctx.intConfig('maxBoardPoints', 25);
  int _foulPenalty(ScoringContext ctx) => ctx.intConfig('foulPenalty', 1);

  bool _queenMustBeCovered(ScoringContext ctx) =>
      ctx.boolConfig('queenMustBeCovered', true);

  /// Above this running total the queen stops being worth anything.
  int _queenCutoff(ScoringContext ctx) =>
      ctx.intConfig('queenCountsOnlyBelowPoints', 22);

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'a': 0,
        'b': 0,
        'boardsPlayed': 0,
        'boards': <Map<String, dynamic>>[],
        'complete': false,
        'winner': null,
        'draw': false,
        PlayerTally.stateKey: <String, dynamic>{},
      };

  int _score(Map<String, dynamic> state, String side) =>
      ((state[side] as num?) ?? 0).toInt();

  /// What a completed board is worth to its winner.
  ///
  /// Exposed so the pad can show the scorer the number before it is committed,
  /// and so it can be tested directly rather than only through a board.
  int boardValue({
    required int opponentCoinsLeft,
    required bool queenTaken,
    required bool queenCovered,
    required int winnerRunningTotal,
    required ScoringContext ctx,
  }) {
    final coins = opponentCoinsLeft.clamp(0, _coinsPerSide(ctx));
    var points = coins * _coinPoints(ctx);

    final queenCounts = queenTaken &&
        (!_queenMustBeCovered(ctx) || queenCovered) &&
        winnerRunningTotal < _queenCutoff(ctx);
    if (queenCounts) points += _queenPoints(ctx);

    return points.clamp(0, _maxBoardPoints(ctx));
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
      case 'board':
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Who won the board?');
        }
        final coinsLeft =
            (action.payload['opponentCoinsLeft'] as num?)?.toInt() ?? 0;
        // Read as a number, but only ever SENT by a pad that asked for one.
        // Before the board control declared its prompts this key was never
        // present, every board scored `0 * coinPoints` plus nothing for a
        // queen nobody was asked about, and a club match ran its three boards
        // out to a 0-0 draw. The default stays 0 for the same reason the
        // prompt is required: a board worth nothing is a plausible board, so
        // there is no sentinel that could have caught it.
        if (coinsLeft < 0 || coinsLeft > _coinsPerSide(ctx)) {
          return ScoringResult.rejected(
            'A side has ${_coinsPerSide(ctx)} coins, so between 0 and '
            '${_coinsPerSide(ctx)} can be left on the board.',
          );
        }
        return ScoringResult.ok(_recordBoard(state, action, ctx, coinsLeft));

      case 'foul':
        // A foul returns a coin and costs a point. Scored immediately rather
        // than at board end because the penalty applies to the running total.
        if (action.side == Side.neutral) {
          return const ScoringResult.rejected('Which side fouled?');
        }
        final key = action.side == Side.a ? 'a' : 'b';
        final penalty = _foulPenalty(ctx);
        var next = mutate(state, (s) {
          s[key] = (_score(state, key) - penalty).clamp(0, 1 << 30);
        });
        final by = action.payload['playerId'] as String?;
        if (by != null) {
          next = PlayerTally.add(next, by, _fouls, 1);
        }
        return ScoringResult.ok(next);

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
    int coinsLeft,
  ) {
    final winner = action.side;
    final key = winner == Side.a ? 'a' : 'b';
    final queen = _queenFrom(action.payload);
    final queenTaken = queen != _Queen.none;
    final queenCovered = queen == _Queen.covered;
    final running = _score(state, key);

    final value = boardValue(
      opponentCoinsLeft: coinsLeft,
      queenTaken: queenTaken,
      queenCovered: queenCovered,
      winnerRunningTotal: running,
      ctx: ctx,
    );

    var next = Map<String, dynamic>.from(state);
    next[key] = running + value;

    final boardsPlayed = ((state['boardsPlayed'] as num?) ?? 0).toInt() + 1;
    next['boardsPlayed'] = boardsPlayed;
    next['boards'] = copyList(state['boards'])
      ..add({
        'board': boardsPlayed,
        'winner': winner.wire,
        'points': value,
        'opponentCoinsLeft': coinsLeft,
        'queen': queenTaken,
        'queenCovered': queenCovered,
      });

    final playerId = action.payload['playerId'] as String?;
    if (playerId != null) {
      next = PlayerTally.addAll(next, playerId, {
        _boardsWon: 1,
        _pointsScored: value,
        _coinsPocketed: _coinsPerSide(ctx) - coinsLeft,
        if (queenTaken) _queens: 1,
        if (queenTaken && queenCovered) _queensCovered: 1,
      });
    }

    return _settle(next, ctx);
  }

  /// What the scorer said about the queen, from either shape the payload can
  /// take.
  ///
  /// Two booleans is the shape the engine has always stored and every existing
  /// board carries, but it is a bad question to PUT: `queen` and
  /// `queenCovered` can disagree — covered but not pocketed is not a state of
  /// the world — and a pad that offered two switches would let a scorer record
  /// it. One question with three answers cannot be answered incoherently, so
  /// that is what the control asks; the booleans stay as the stored form so no
  /// board recorded before this reads differently now.
  static _Queen _queenFrom(Map<String, dynamic> payload) {
    final v = payload['queen'];
    if (v is String) {
      return switch (v) {
        'covered' => _Queen.covered,
        'uncovered' => _Queen.uncovered,
        _ => _Queen.none,
      };
    }
    if (v != true) return _Queen.none;
    return payload['queenCovered'] == true ? _Queen.covered : _Queen.uncovered;
  }

  Map<String, dynamic> _settle(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    final target = _matchTarget(ctx);
    final maxBoards = _maxBoards(ctx);
    final a = _score(state, 'a');
    final b = _score(state, 'b');
    final played = ((state['boardsPlayed'] as num?) ?? 0).toInt();

    final byPoints = target > 0 && (a >= target || b >= target);
    final byBoards = maxBoards > 0 && played >= maxBoards;
    if (!byPoints && !byBoards) return state;

    return mutate(state, (s) {
      s['complete'] = true;
      s['draw'] = a == b;
      s['winner'] = a == b ? null : (a > b ? 'a' : 'b');
    });
  }

  // --- Presentation ---------------------------------------------------------

  @override
  String headline(Map<String, dynamic> state, ScoringContext ctx) =>
      '${_score(state, 'a')} - ${_score(state, 'b')}';

  @override
  String summary(Map<String, dynamic> state, ScoringContext ctx) =>
      headline(state, ctx);

  @override
  String? statusLine(Map<String, dynamic> state, ScoringContext ctx) {
    if (state['complete'] == true) return null;
    final played = ((state['boardsPlayed'] as num?) ?? 0).toInt();
    final parts = <String>['Board ${played + 1}'];
    final target = _matchTarget(ctx);
    if (target > 0) {
      final a = _score(state, 'a');
      final b = _score(state, 'b');
      final lead = a > b ? a : b;
      parts.add('${target - lead} to win');
    }
    return parts.join(' • ');
  }

  @override
  MatchOutcome outcome(Map<String, dynamic> state, ScoringContext ctx) {
    final a = _score(state, 'a');
    final b = _score(state, 'b');
    if (state['complete'] != true) {
      return MatchOutcome(isComplete: false, scoreForA: a, scoreForB: b);
    }
    final winner = state['winner'];
    return MatchOutcome(
      isComplete: true,
      winnerSide: winner is String ? Side.fromWire(winner) : null,
      isDraw: state['draw'] == true,
      scoreForA: a,
      scoreForB: b,
    );
  }

  @override
  List<ScoreControlGroup> controls(
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    // Carrom's engine already tallied boards, points, coins and queens to
    // `payload['playerId']` and nothing ever supplied one, so a doubles board
    // credited nobody. In singles the pad fills it without asking — see the
    // badminton rally control.
    const winner = [PlayerPrompt(key: 'playerId', label: 'Who won the board?')];
    const offender = [PlayerPrompt(key: 'playerId', label: 'Who fouled?')];

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

    // The board sheet needs the coin count and the queen, so the pad opens a
    // form rather than committing on a single tap. These controls declare the
    // intent; the widget layer collects the detail.
    //
    // ## Why the coin count is asked for and not assumed
    //
    // It IS the board's value. The winner scores one point per coin the loser
    // still has on the board, so "who won" answers almost nothing on its own —
    // the same tap is worth one point or nine. Until this prompt existed the
    // pad sent no count at all, the engine defaulted it to zero, and every
    // board in a club match was recorded as worth nothing: three boards
    // played, 0-0, match over, no winner. The button worked and the sport did
    // not.
    final coins = [
      ValuePrompt(
        key: 'opponentCoinsLeft',
        label: 'Coins left for the loser',
        decimals: 0,
        min: 0,
        max: _coinsPerSide(ctx).toDouble(),
      ),
    ];

    // Asked as one question rather than two switches — see [_queenFrom]. The
    // wording carries the rule that decides it, because "covered" is the one
    // carrom term a scorer at a village club may know by a different name and
    // it is worth three points either way.
    const queen = [
      ChoicePrompt(
        key: 'queen',
        label: 'Queen',
        options: [
          ChoiceOption('none', 'Not pocketed'),
          ChoiceOption('covered', 'Pocketed and covered'),
          ChoiceOption('uncovered', 'Pocketed but not covered'),
        ],
      ),
    ];

    return [
      ScoreControlGroup(
        title: 'Board won by',
        controls: [
          ScoreControl(
            action: 'board',
            label: ctx.entrantAName,
            side: Side.a,
            prompts: winner,
            values: coins,
            choices: queen,
            style: ControlStyle.primary,
            shortcut: 'a',
            tooltip: 'Record the board to ${ctx.entrantAName}',
          ),
          ScoreControl(
            action: 'board',
            label: ctx.entrantBName,
            side: Side.b,
            prompts: winner,
            values: coins,
            choices: queen,
            style: ControlStyle.primary,
            shortcut: 'l',
            tooltip: 'Record the board to ${ctx.entrantBName}',
          ),
        ],
      ),
      ScoreControlGroup(
        title: 'Foul',
        controls: [
          ScoreControl(
            action: 'foul',
            label: 'Foul ${ctx.entrantAName}',
            side: Side.a,
            prompts: offender,
            style: ControlStyle.danger,
          ),
          ScoreControl(
            action: 'foul',
            label: 'Foul ${ctx.entrantBName}',
            side: Side.b,
            prompts: offender,
            style: ControlStyle.danger,
          ),
        ],
      ),
    ];
  }

  static List<StatColumn> get columns => columnsFor();

  static List<StatColumn> columnsFor([RuleConfig? rules]) => [
        const StatColumn(
          key: _boardsWon,
          label: 'Boards won',
          shortLabel: 'BD',
        ),
        const StatColumn(
          key: _pointsScored,
          label: 'Points',
          shortLabel: 'PTS',
        ),
        const StatColumn(
          key: _coinsPocketed,
          label: 'Coins pocketed',
          shortLabel: 'C',
        ),
        const StatColumn(key: _queens, label: 'Queens', shortLabel: 'Q'),
        const StatColumn(
          key: _queensCovered,
          label: 'Queens covered',
          shortLabel: 'QC',
        ),
        const StatColumn(key: _fouls, label: 'Fouls', shortLabel: 'F'),
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
