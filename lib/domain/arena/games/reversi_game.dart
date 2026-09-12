import '../arena_game.dart';
import 'line_rules.dart';

/// Reversi (Othello) — outflank a line of discs and they all turn over.
///
/// The rule that shapes the code is that a move is only legal if it flips
/// something. That makes "where may I play" and "what happens if I play
/// there" the same computation, so [_flips] is written once and both
/// [legalMoves] and [apply] read it. Working them out separately is how an
/// implementation ends up letting a player place a disc that flips nothing,
/// which quietly breaks the whole game.
///
/// Passing is not optional here and never a choice: a player with no
/// outflanking move MUST pass, so [legalMoves] hands back a single pass
/// rather than an empty list, and the board screen shows it as the only
/// thing available.
class ReversiGame extends ArenaGame {
  const ReversiGame();

  static const gameId = 'reversi';
  static const _disc = 1;

  @override
  String get id => gameId;

  @override
  String get name => 'Reversi';

  @override
  String get tagline => 'Flip the board, hold the corners';

  @override
  String get duration => '10 min';

  @override
  MoveInput get input => MoveInput.place;

  @override
  bool get allowsPass => false; // Forced, never chosen — see the class note.

  @override
  bool get allowsDrawOffer => false;

  @override
  List<String> get sideNames => const ['Black', 'White'];

  @override
  List<int> get sideColors => const [0xFF111827, 0xFFF9FAFB];

  @override
  List<GameVariant> get variants => const [
        GameVariant(
          id: 'standard',
          label: '8 × 8',
          note: 'Standard Othello',
          config: {'size': 8},
        ),
        GameVariant(
          id: 'small',
          label: '6 × 6',
          note: 'Half the length, same ideas',
          config: {'size': 6},
        ),
      ];

  @override
  BoardSpec board(GameConfig config) {
    final size = config.integer('size', 8);
    return BoardSpec(
      cols: size,
      rows: size,
      style: BoardStyle.cells,
      surface: 0xFF15803D,
    );
  }

  @override
  ArenaPosition initial(GameConfig config) {
    final b = board(config);
    final cells = List<int>.filled(b.cells, 0);
    // The four centre discs, set crosswise. Which diagonal holds which colour
    // is fixed by the rules, not arbitrary: black starts on the a1–h8 diagonal.
    final lo = b.cols ~/ 2 - 1;
    final hi = b.cols ~/ 2;
    cells[b.index(lo, lo)] = ArenaPosition.coded(_disc, 1);
    cells[b.index(hi, hi)] = ArenaPosition.coded(_disc, 1);
    cells[b.index(hi, lo)] = ArenaPosition.coded(_disc, 0);
    cells[b.index(lo, hi)] = ArenaPosition.coded(_disc, 0);
    return ArenaPosition(cells: cells, turn: 0);
  }

  /// Every disc that placing at [index] for [side] would turn over.
  ///
  /// A direction only counts once it is CLOSED by one of the mover's own
  /// discs — an unbroken run that walks off the edge of the board, or into an
  /// empty square, flips nothing.
  List<int> _flips(ArenaPosition p, BoardSpec b, int index, int side) {
    if (p.cells[index] != 0) return const [];
    final mine = ArenaPosition.coded(_disc, side);
    final theirs = ArenaPosition.coded(_disc, 1 - side);
    final col = b.colOf(index);
    final row = b.rowOf(index);
    final out = <int>[];

    for (final dir in const [
      [1, 0], [-1, 0], [0, 1], [0, -1],
      [1, 1], [1, -1], [-1, 1], [-1, -1],
    ]) {
      final run = <int>[];
      var c = col + dir[0];
      var r = row + dir[1];
      while (b.inBounds(c, r) && p.cells[b.index(c, r)] == theirs) {
        run.add(b.index(c, r));
        c += dir[0];
        r += dir[1];
      }
      if (run.isNotEmpty && b.inBounds(c, r) && p.cells[b.index(c, r)] == mine) {
        out.addAll(run);
      }
    }
    return out;
  }

  List<ArenaMove> _placements(ArenaPosition p, GameConfig config, int side) {
    final b = board(config);
    final moves = <ArenaMove>[];
    for (var i = 0; i < p.cells.length; i++) {
      final flips = _flips(p, b, i, side);
      if (flips.isNotEmpty) {
        moves.add(ArenaMove(
          to: i,
          kind: MoveKind.capture,
          extra: {'flips': flips},
        ));
      }
    }
    return moves;
  }

  @override
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config) {
    if (outcome(p, const [], config) != null) return const [];
    final mine = _placements(p, config, p.turn);
    if (mine.isNotEmpty) return mine;
    // No outflanking move: the turn passes, and that is the only legal act.
    return const [ArenaMove.pass()];
  }

  @override
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config) {
    if (m.kind == MoveKind.pass) {
      return ArenaPosition(
        cells: p.cells,
        turn: p.opponent,
        meta: const {'passed': true},
      );
    }
    final cells = List<int>.from(p.cells);
    cells[m.to] = ArenaPosition.coded(_disc, p.turn);
    final flips = (m.extra['flips'] as List?)?.whereType<num>() ?? const [];
    for (final f in flips) {
      cells[f.toInt()] = ArenaPosition.coded(_disc, p.turn);
    }
    return ArenaPosition(
      cells: cells,
      turn: p.opponent,
      meta: {'last': m.to, 'flipped': flips.map((f) => f.toInt()).toList()},
    );
  }

  int _count(ArenaPosition p, int side) =>
      p.cells.where((c) => ArenaPosition.sideOf(c) == side).length;

  @override
  GameOutcome? outcome(
    ArenaPosition p,
    List<ArenaPosition> history,
    GameConfig config,
  ) {
    final boardFull = !p.cells.contains(0);
    // The other ending: neither side can outflank anything, which happens
    // well before a full board once one colour has been wiped out.
    final stuck = _placements(p, config, 0).isEmpty &&
        _placements(p, config, 1).isEmpty;
    if (!boardFull && !stuck) return null;

    final a = _count(p, 0).toDouble();
    final b = _count(p, 1).toDouble();
    final scores = [a, b];
    if (a == b) return GameOutcome.draw('$a–$b, level');
    final winner = a > b ? 0 : 1;
    return GameOutcome(
      winner: winner,
      reason: '${sideNames[winner]} ${a > b ? a.toInt() : b.toInt()}'
          '–${a > b ? b.toInt() : a.toInt()}',
      scores: scores,
    );
  }

  @override
  List<int> highlights(ArenaPosition p, GameConfig config) {
    final last = p.meta['last'];
    return last is int ? [last] : const [];
  }

  @override
  String? sideSummary(ArenaPosition p, int side, GameConfig config) =>
      '${_count(p, side)} discs';

  @override
  String notation(ArenaPosition before, ArenaMove m, GameConfig config) {
    if (m.kind == MoveKind.pass) return '—';
    final b = board(config);
    return '${fileLabel(b.colOf(m.to)).toLowerCase()}${b.rowOf(m.to) + 1}';
  }

  @override
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final side = sideNames[before.turn];
    if (m.kind == MoveKind.pass) {
      return '$side has no move and must pass';
    }
    final flips = (m.extra['flips'] as List?)?.length ?? 0;
    return '$side plays ${notation(before, m, config)}, '
        'turning over $flips ${flips == 1 ? 'disc' : 'discs'}';
  }

  @override
  PieceArt? art(int code) {
    final side = ArenaPosition.sideOf(code);
    return side < 0 ? null : PieceArt(side: side, scale: 0.84);
  }
}
