import '../arena_game.dart';

/// Checkers, English draughts rules — 8×8, men move one square diagonally
/// forward, kings move both ways, and capturing is compulsory.
///
/// ## Multi-jumps are several moves, not one
///
/// A double jump could be modelled as a single move carrying a path. It is
/// modelled here as two moves that happen to share a turn: after a jump, if
/// the same piece can jump again, [apply] leaves `turn` alone and records the
/// square it must continue from in `meta['chain']`, and [legalMoves] then
/// offers only jumps from there.
///
/// That choice is worth the small amount of state it costs. The player taps
/// each hop, which is how the game is played on a real board and removes any
/// need for the screen to disambiguate between two paths with the same start
/// and end. And every hop lands in the move list separately, so a game
/// reviewed afterwards shows what actually happened rather than one composite
/// entry.
///
/// Crowning ends a move even mid-chain, which is the English rule and not a
/// simplification: a man that reaches the back row by a jump stops there and
/// jumps on as a king only on its next turn.
class CheckersGame extends ArenaGame {
  const CheckersGame();

  static const gameId = 'checkers';
  static const _man = 1;
  static const _king = 2;

  /// Plies without a capture or a man moving, after which the game is drawn.
  /// Kings shuffling at each other cannot make progress and somebody has to
  /// call it.
  static const _quietLimit = 80;

  @override
  String get id => gameId;

  @override
  String get name => 'Checkers';

  @override
  String get tagline => 'Jump, crown, and take everything';

  @override
  String get duration => '15 min';

  @override
  MoveInput get input => MoveInput.fromTo;

  @override
  List<String> get sideNames => const ['Red', 'Black'];

  @override
  List<int> get sideColors => const [0xFFE03131, 0xFF16161A];

  @override
  List<GameVariant> get variants => const [
        GameVariant(
          id: 'standard',
          label: '8 × 8',
          note: 'English draughts, 12 pieces each',
          config: {'size': 8, 'ranks': 3},
        ),
      ];

  @override
  BoardSpec board(GameConfig config) {
    final size = config.integer('size', 8);
    return BoardSpec(
      cols: size,
      rows: size,
      style: BoardStyle.checkered,
      lightSquare: 0xFFF1E4C3,
      darkSquare: 0xFF9C6B45,
      showFileRank: false,
    );
  }

  /// Only the dark squares are in play, which halves the board and is why
  /// draughts notation numbers 32 squares rather than 64.
  bool _playable(BoardSpec b, int index) =>
      (b.colOf(index) + b.rowOf(index)) % 2 == 1;

  /// Side 0 sits at the bottom and advances up the board; side 1 the reverse.
  int _forward(int side) => side == 0 ? -1 : 1;

  int _crownRow(BoardSpec b, int side) => side == 0 ? 0 : b.rows - 1;

  @override
  ArenaPosition initial(GameConfig config) {
    final b = board(config);
    final ranks = config.integer('ranks', 3);
    final cells = List<int>.filled(b.cells, 0);
    for (var i = 0; i < b.cells; i++) {
      if (!_playable(b, i)) continue;
      final row = b.rowOf(i);
      if (row < ranks) cells[i] = ArenaPosition.coded(_man, 1);
      if (row >= b.rows - ranks) cells[i] = ArenaPosition.coded(_man, 0);
    }
    return ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0});
  }

  /// The diagonals a piece may travel along: forward only for a man, both
  /// ways for a king.
  List<List<int>> _steps(int code) {
    final side = ArenaPosition.sideOf(code);
    final fwd = _forward(side);
    if (ArenaPosition.kindOf(code) == _king) {
      return const [
        [1, 1], [1, -1], [-1, 1], [-1, -1],
      ];
    }
    return [
      [1, fwd],
      [-1, fwd],
    ];
  }

  List<ArenaMove> _jumpsFrom(ArenaPosition p, BoardSpec b, int from) {
    final code = p.cells[from];
    if (code == 0) return const [];
    final side = ArenaPosition.sideOf(code);
    final col = b.colOf(from);
    final row = b.rowOf(from);
    final out = <ArenaMove>[];

    for (final step in _steps(code)) {
      final overC = col + step[0];
      final overR = row + step[1];
      final landC = col + step[0] * 2;
      final landR = row + step[1] * 2;
      if (!b.inBounds(landC, landR)) continue;
      final over = b.index(overC, overR);
      final land = b.index(landC, landR);
      final victim = p.cells[over];
      if (victim == 0 || ArenaPosition.sideOf(victim) == side) continue;
      if (p.cells[land] != 0) continue;
      out.add(ArenaMove(
        from: from,
        to: land,
        kind: MoveKind.capture,
        extra: {'over': over},
      ));
    }
    return out;
  }

  List<ArenaMove> _stepsFrom(ArenaPosition p, BoardSpec b, int from) {
    final code = p.cells[from];
    if (code == 0) return const [];
    final col = b.colOf(from);
    final row = b.rowOf(from);
    final out = <ArenaMove>[];
    for (final step in _steps(code)) {
      final c = col + step[0];
      final r = row + step[1];
      if (!b.inBounds(c, r)) continue;
      final to = b.index(c, r);
      if (p.cells[to] == 0) out.add(ArenaMove(from: from, to: to));
    }
    return out;
  }

  @override
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config) {
    final b = board(config);

    // Mid-chain: the jumping piece is the only one that may move, and only by
    // jumping again.
    final chain = p.meta['chain'];
    if (chain is int) return _jumpsFrom(p, b, chain);

    final jumps = <ArenaMove>[];
    final quiet = <ArenaMove>[];
    for (var i = 0; i < b.cells; i++) {
      if (ArenaPosition.sideOf(p.cells[i]) != p.turn) continue;
      jumps.addAll(_jumpsFrom(p, b, i));
      quiet.addAll(_stepsFrom(p, b, i));
    }
    // Compulsory capture: with a jump on the board, nothing else is legal.
    return jumps.isNotEmpty ? jumps : quiet;
  }

  @override
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config) {
    final b = board(config);
    final cells = List<int>.from(p.cells);
    var code = cells[m.from];
    cells[m.from] = 0;

    final captured = m.extra['over'];
    if (captured is int) cells[captured] = 0;

    // Crowning, which in English draughts also ENDS the move.
    var crowned = false;
    if (ArenaPosition.kindOf(code) == _man &&
        b.rowOf(m.to) == _crownRow(b, p.turn)) {
      code = ArenaPosition.coded(_king, p.turn);
      crowned = true;
    }
    cells[m.to] = code;

    final after = ArenaPosition(cells: cells, turn: p.turn);
    final canContinue = captured is int &&
        !crowned &&
        _jumpsFrom(after, b, m.to).isNotEmpty;

    // Progress: a capture or a man moving resets the shuffle counter. Two
    // kings walking up and down a diagonal do not.
    final wasMan = ArenaPosition.kindOf(p.cells[m.from]) == _man;
    final quiet = (captured is int || wasMan)
        ? 0
        : ((p.meta['quiet'] as num?)?.toInt() ?? 0) + 1;

    return ArenaPosition(
      cells: cells,
      turn: canContinue ? p.turn : p.opponent,
      meta: {
        'quiet': quiet,
        'last': m.to,
        'from': m.from,
        if (canContinue) 'chain': m.to,
      },
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
    if (_count(p, p.turn) == 0) {
      return GameOutcome(
        winner: p.opponent,
        reason: 'All pieces captured',
      );
    }
    if (legalMoves(p, config).isEmpty) {
      // Blocked in with pieces still on the board loses just the same.
      return GameOutcome(winner: p.opponent, reason: 'No moves left');
    }
    final quiet = (p.meta['quiet'] as num?)?.toInt() ?? 0;
    if (quiet >= _quietLimit) {
      return const GameOutcome.draw('40 moves without progress');
    }
    return null;
  }

  @override
  List<int> highlights(ArenaPosition p, GameConfig config) {
    final last = p.meta['last'];
    final from = p.meta['from'];
    return [if (from is int) from, if (last is int) last];
  }

  @override
  String? sideSummary(ArenaPosition p, int side, GameConfig config) {
    final kings = p.cells
        .where((c) =>
            ArenaPosition.sideOf(c) == side &&
            ArenaPosition.kindOf(c) == _king)
        .length;
    final total = _count(p, side);
    return kings == 0 ? '$total left' : '$total left · $kings K';
  }

  /// Draughts numbers only the dark squares, 1–32 in reading order, and every
  /// published game score uses those numbers. "11-15" is a move, "11x18" a
  /// jump.
  int _square(BoardSpec b, int index) {
    var n = 0;
    for (var i = 0; i <= index; i++) {
      if (_playable(b, i)) n++;
    }
    return n;
  }

  @override
  String notation(ArenaPosition before, ArenaMove m, GameConfig config) {
    final b = board(config);
    final sep = m.kind == MoveKind.capture ? 'x' : '-';
    return '${_square(b, m.from)}$sep${_square(b, m.to)}';
  }

  @override
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final b = board(config);
    final side = sideNames[before.turn];
    final king = ArenaPosition.kindOf(before.cells[m.from]) == _king;
    final piece = king ? 'king' : 'man';
    final from = _square(b, m.from);
    final to = _square(b, m.to);

    if (m.kind != MoveKind.capture) {
      return '$side $piece moves $from → $to';
    }
    final over = m.extra['over'];
    final jumped = over is int
        ? (ArenaPosition.kindOf(before.cells[over]) == _king ? 'king' : 'man')
        : 'piece';
    final after = apply(before, m, config);
    final chained = after.meta.containsKey('chain');
    final crowned = !king &&
        ArenaPosition.kindOf(after.cells[m.to]) == _king;
    return '$side $piece jumps $from → $to, taking a $jumped'
        '${chained ? ' — and can jump again' : ''}'
        '${crowned ? ' — crowned' : ''}';
  }

  @override
  PieceArt? art(int code) {
    final side = ArenaPosition.sideOf(code);
    if (side < 0) return null;
    return PieceArt(
      side: side,
      crowned: ArenaPosition.kindOf(code) == _king,
      scale: 0.78,
    );
  }
}
