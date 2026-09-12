import '../arena_game.dart';
import 'line_rules.dart';

/// Connect Four — drop a disc, make four in a row.
///
/// The one game in the Arena with a *direction*: discs fall. That has two
/// consequences the interface has to carry rather than the screen assuming
/// them. A move is a column, not a square ([MoveInput.column]), because the
/// row is decided by gravity and asking a player to aim at the right one
/// would be a worse game. And the board never flips for the second player
/// (`flipForSideOne: false`) — every other game here is symmetric across the
/// board, but an upside-down connect four grid would show discs falling
/// upwards.
class ConnectFourGame extends ArenaGame {
  const ConnectFourGame();

  static const gameId = 'connect_four';
  static const _stone = 1;

  @override
  String get id => gameId;

  @override
  String get name => 'Connect Four';

  @override
  String get tagline => 'Drop discs, make four in a row';

  @override
  String get duration => '5 min';

  @override
  MoveInput get input => MoveInput.column;

  // Nothing to agree to: a connect four game that is not won is a full board,
  // and both players can see it filling.
  @override
  bool get allowsDrawOffer => false;

  @override
  List<String> get sideNames => const ['Red', 'Yellow'];

  @override
  List<int> get sideColors => const [0xFFE11D48, 0xFFF59E0B];

  @override
  List<GameVariant> get variants => const [
        GameVariant(
          id: 'standard',
          label: '7 × 6',
          note: 'The classic grid',
          config: {'cols': 7, 'rows': 6, 'need': 4},
        ),
        GameVariant(
          id: 'wide',
          label: '9 × 7',
          note: 'Longer games, more room to build',
          config: {'cols': 9, 'rows': 7, 'need': 4},
        ),
      ];

  @override
  BoardSpec board(GameConfig config) => BoardSpec(
        cols: config.integer('cols', 7),
        rows: config.integer('rows', 6),
        style: BoardStyle.cells,
        surface: 0xFF1D4ED8,
        flipForSideOne: false,
      );

  int _need(GameConfig config) => config.integer('need', 4);

  @override
  ArenaPosition initial(GameConfig config) {
    final b = board(config);
    return ArenaPosition(
      cells: List<int>.filled(b.cells, 0),
      turn: 0,
      meta: const {},
    );
  }

  /// The square a disc dropped into [col] would come to rest on, or -1 when
  /// the column is full. Rows run downwards from 0, so the resting place is
  /// the LAST empty one.
  int _landing(ArenaPosition p, BoardSpec b, int col) {
    for (var row = b.rows - 1; row >= 0; row--) {
      if (p.cells[b.index(col, row)] == 0) return b.index(col, row);
    }
    return -1;
  }

  @override
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config) {
    if (outcome(p, const [], config) != null) return const [];
    final b = board(config);
    final moves = <ArenaMove>[];
    for (var col = 0; col < b.cols; col++) {
      final landing = _landing(p, b, col);
      if (landing >= 0) {
        // `to` is the resting square, not the column, so the board screen can
        // preview exactly where the disc will end up without knowing that
        // this game has gravity at all.
        moves.add(ArenaMove(to: landing, extra: {'col': col}));
      }
    }
    return moves;
  }

  @override
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config) {
    final cells = List<int>.from(p.cells);
    cells[m.to] = ArenaPosition.coded(_stone, p.turn);
    return ArenaPosition(
      cells: cells,
      turn: p.opponent,
      meta: {'last': m.to},
    );
  }

  @override
  GameOutcome? outcome(
    ArenaPosition p,
    List<ArenaPosition> history,
    GameConfig config,
  ) {
    final b = board(config);
    final line = anyRun(p, b, _need(config));
    if (line != null) {
      final winner = ArenaPosition.sideOf(p.cells[line.first]);
      return GameOutcome(
        winner: winner,
        reason: '${_need(config)} in a row',
      );
    }
    if (!p.cells.contains(0)) {
      return const GameOutcome.draw('Board full');
    }
    return null;
  }

  @override
  List<int> highlights(ArenaPosition p, GameConfig config) =>
      anyRun(p, board(config), _need(config)) ?? const [];

  @override
  String notation(ArenaPosition before, ArenaMove m, GameConfig config) {
    final b = board(config);
    return fileLabel(b.colOf(m.to));
  }

  @override
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final b = board(config);
    final side = sideNames[before.turn];
    final column = fileLabel(b.colOf(m.to));
    // Which row it came to rest on is the part a player replaying the game
    // cannot reconstruct from the column alone.
    final height = b.rows - b.rowOf(m.to);
    return '$side drops into column $column '
        '(${height == 1 ? 'the bottom' : 'row $height'})';
  }

  @override
  PieceArt? art(int code) {
    final side = ArenaPosition.sideOf(code);
    return side < 0 ? null : PieceArt(side: side, scale: 0.82);
  }
}
