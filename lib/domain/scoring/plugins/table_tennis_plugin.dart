import '../player_stats.dart';
import '../scoring_plugin.dart';

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
class TableTennisPlugin extends ScoringPlugin {
  const TableTennisPlugin();

  static const pluginKey = 'table_tennis';

  @override
  String get key => pluginKey;

  @override
  String get displayName => 'Table tennis';

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

  @override
  Map<String, dynamic> initialState(ScoringContext ctx) => {
        'currentA': 0,
        'currentB': 0,
        'gamesA': 0,
        'gamesB': 0,
        'completedGames': <Map<String, dynamic>>[],
        'firstServer': 'a',
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
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final first = Side.fromWire(state['firstServer'] as String? ?? 'a');
    final deuceAt = _gameTo(ctx) - 1;
    final played = a + b;

    int blocks;
    if (a >= deuceAt && b >= deuceAt) {
      // Everything before deuce in whole blocks, then the deuce rate after.
      final beforeDeuce = deuceAt * 2;
      final atDeuce = _serveEveryAtDeuce(ctx).clamp(1, 1 << 30);
      blocks = beforeDeuce ~/ _serveEvery(ctx) +
          (played - beforeDeuce) ~/ atDeuce;
    } else {
      blocks = played ~/ _serveEvery(ctx);
    }
    return blocks.isEven ? first : first.opposite;
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
        final player = action.payload['playerId'] as String?;
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

      case 'reopen':
        return ScoringResult.ok(mutate(state, (s) {
          s['complete'] = false;
          s['winner'] = null;
        }));

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
    final matchOver =
        gamesA >= _gamesToWin(ctx) || gamesB >= _gamesToWin(ctx);

    return mutate(state, (s) {
      s['completedGames'] = completed;
      s['gamesA'] = gamesA;
      s['gamesB'] = gamesB;
      s['currentA'] = 0;
      s['currentB'] = 0;
      // The first service alternates each game.
      s['firstServer'] =
          Side.fromWire(s['firstServer'] as String? ?? 'a').opposite.wire;
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
      return 'Final · games ${state['gamesA']}-${state['gamesB']}';
    }
    final gameNo = copyList(state['completedGames']).length + 1;
    final a = ((state['currentA'] as num?) ?? 0).toInt();
    final b = ((state['currentB'] as num?) ?? 0).toInt();
    final deuceAt = _gameTo(ctx) - 1;
    final atDeuce = a >= deuceAt && b >= deuceAt;
    return 'Game $gameNo · to ${_gameTo(ctx)} · '
        '${ctx.nameFor(serverFor(state, ctx))} serving'
        '${atDeuce ? " · deuce, one serve each" : ""}';
  }

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
    return [
      ScoreControlGroup(
        title: ctx.entrantAName,
        controls: const [
          ScoreControl(
            action: 'point',
            label: '+1',
            side: Side.a,
            style: ControlStyle.primary,
            shortcut: 'a',
            prompts: [
              PlayerPrompt(key: 'playerId', label: 'Who won the point?'),
            ],
          ),
          ScoreControl(
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
        controls: const [
          ScoreControl(
            action: 'point',
            label: '+1',
            side: Side.b,
            style: ControlStyle.primary,
            shortcut: 'l',
            prompts: [
              PlayerPrompt(key: 'playerId', label: 'Who won the point?'),
            ],
          ),
          ScoreControl(
            action: 'correct',
            label: '−1',
            side: Side.b,
            style: ControlStyle.subtle,
            shortcut: 'm',
          ),
        ],
      ),
    ];
  }
}
