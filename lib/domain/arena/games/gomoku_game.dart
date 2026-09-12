import '../arena_game.dart';
import 'line_rules.dart';

/// Gomoku — five in a row on the crossings of a go board.
///
/// Played free-style: an overline (six or more) wins like a five does, and
/// there are no opening restrictions. Tournament gomoku uses Renju or Swap2
/// precisely because free-style hands Black a known advantage — but those
/// rules cost a beginner more than the fairness is worth, and the Arena is
/// not rated, so the imbalance buys nothing back. If it ever matters, it is a
/// variant, not a rewrite.
class GomokuGame extends ArenaGame {
  const GomokuGame();

  static const gameId = 'gomoku';
  static const _stone = 1;

  @override
  String get id => gameId;

  @override
  String get name => 'Gomoku';

  @override
  String get tagline => 'Five stones in a row, anywhere';

  @override
  String get duration => '10 min';

  @override
  MoveInput get input => MoveInput.place;

  @override
  bool get allowsDrawOffer => false;

  @override
  List<String> get sideNames => const ['Black', 'White'];

  @override
  List<int> get sideColors => const [0xFF111827, 0xFFFAFAFA];

  @override
  List<GameVariant> get variants => const [
        GameVariant(
          id: 'standard',
          label: '15 × 15',
          note: 'The usual board',
          config: {'size': 15, 'need': 5},
        ),
        GameVariant(
          id: 'small',
          label: '9 × 9',
          note: 'Quick game, easier on a phone',
          config: {'size': 9, 'need': 5},
        ),
      ];

  @override
  BoardSpec board(GameConfig config) {
    final size = config.integer('size', 15);
    return BoardSpec(
      cols: size,
      rows: size,
      style: BoardStyle.lines,
      surface: 0xFFE8C88A,
    );
  }

  int _need(GameConfig config) => config.integer('need', 5);

  @override
  ArenaPosition initial(GameConfig config) => ArenaPosition(
        cells: List<int>.filled(board(config).cells, 0),
        turn: 0,
      );

  @override
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config) {
    if (outcome(p, const [], config) != null) return const [];
    final moves = <ArenaMove>[];
    for (var i = 0; i < p.cells.length; i++) {
      if (p.cells[i] == 0) moves.add(ArenaMove(to: i));
    }
    return moves;
  }

  @override
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config) {
    final cells = List<int>.from(p.cells);
    cells[m.to] = ArenaPosition.coded(_stone, p.turn);
    return ArenaPosition(cells: cells, turn: p.opponent, meta: {'last': m.to});
  }

  @override
  GameOutcome? outcome(
    ArenaPosition p,
    List<ArenaPosition> history,
    GameConfig config,
  ) {
    final line = anyRun(p, board(config), _need(config));
    if (line != null) {
      return GameOutcome(
        winner: ArenaPosition.sideOf(p.cells[line.first]),
        reason: '${line.length} in a row',
      );
    }
    if (!p.cells.contains(0)) return const GameOutcome.draw('Board full');
    return null;
  }

  @override
  List<int> highlights(ArenaPosition p, GameConfig config) =>
      anyRun(p, board(config), _need(config)) ?? const [];

  @override
  String notation(ArenaPosition before, ArenaMove m, GameConfig config) {
    final b = board(config);
    // Rows counted from the bottom, as board-game notation always is.
    return '${fileLabel(b.colOf(m.to))}${b.rows - b.rowOf(m.to)}';
  }

  @override
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final side = sideNames[before.turn];
    final point = notation(before, m, config);
    final after = apply(before, m, config);
    final line = runThrough(after, board(config), m.to, _need(config) - 1);
    // Calling out a live four is the single most useful note in a gomoku
    // record: it is the move the loser should have answered.
    if (line != null && outcome(after, const [], config) == null) {
      return '$side plays $point — ${line.length} in a row';
    }
    return '$side plays $point';
  }

  @override
  PieceArt? art(int code) {
    final side = ArenaPosition.sideOf(code);
    return side < 0 ? null : PieceArt(side: side, scale: 0.92);
  }
}
