import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/arena/arena_game.dart';
import 'package:playsphere/domain/arena/games/chess_game.dart';

/// Perft — walk the whole legal move tree to a fixed depth and count the
/// leaves.
///
/// This is the only chess test worth writing first. A hand-written "can a
/// knight reach f3" suite passes happily while en passant is broken, castling
/// through check is allowed, or a pinned piece can move; perft catches all of
/// them at once, because the published node counts for these positions are
/// exact and a single illegal move anywhere in the tree changes the total.
///
/// The positions are the standard ones from the Chess Programming Wiki, each
/// chosen to hammer a different corner of the rules.
void main() {
  const game = ChessGame();
  const config = GameConfig.empty;

  int perft(ArenaPosition p, int depth) {
    final moves = game.legalMoves(p, config);
    if (depth == 1) return moves.length;
    var total = 0;
    for (final m in moves) {
      total += perft(game.apply(p, m, config), depth - 1);
    }
    return total;
  }

  group('perft', () {
    test('initial position', () {
      final start = game.initial(config);
      expect(perft(start, 1), 20);
      expect(perft(start, 2), 400);
      expect(perft(start, 3), 8902);
      expect(perft(start, 4), 197281);
    });

    test('kiwipete — castling, pins and captures', () {
      final p = fen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -',
      );
      expect(perft(p, 1), 48);
      expect(perft(p, 2), 2039);
      expect(perft(p, 3), 97862);
    });

    test('endgame — en passant and rook checks', () {
      final p = fen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -');
      expect(perft(p, 1), 14);
      expect(perft(p, 2), 191);
      expect(perft(p, 3), 2812);
      expect(perft(p, 4), 43238);
    });

    test('promotion tangle', () {
      final p = fen(
        'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq -',
      );
      expect(perft(p, 1), 6);
      expect(perft(p, 2), 264);
      expect(perft(p, 3), 9467);
    });
  });

  group('outcomes', () {
    test('fool\'s mate is checkmate, and Black wins it', () {
      var p = game.initial(config);
      for (final san in ['f3', 'e5', 'g4', 'Qh4']) {
        p = playSan(game, p, san);
      }
      final result = game.outcome(p, [p], config);
      expect(result, isNotNull);
      expect(result!.reason, 'Checkmate');
      expect(result.winner, 1, reason: 'Black delivered it');
    });

    test('stalemate is a draw, not a loss', () {
      // Black to move, king on h8, boxed in but not attacked.
      final p = fen('7k/5Q2/6K1/8/8/8/8/8 b - -');
      final result = game.outcome(p, [p], config);
      expect(result!.isDraw, isTrue);
      expect(result.reason, 'Stalemate');
    });

    test('bare kings are insufficient material', () {
      final p = fen('7k/8/8/8/8/8/8/K7 w - -');
      expect(game.outcome(p, [p], config)!.reason, 'Insufficient material');
    });

    test('king and rook is still playable', () {
      final p = fen('7k/8/8/8/8/8/8/K6R w - -');
      expect(game.outcome(p, [p], config), isNull);
    });

    test('fifty moves without a pawn or a capture draws', () {
      final p = fen('7k/8/8/8/8/8/8/K6R w - -');
      final stalled = p.copyWith(meta: {...p.meta, 'half': 100});
      expect(game.outcome(stalled, [stalled], config)!.reason,
          'Fifty-move rule');
    });

    test('threefold repetition draws', () {
      final p = fen('7k/8/8/8/8/8/8/K6R w - -');
      expect(game.outcome(p, [p, p, p], config)!.reason,
          'Threefold repetition');
    });
  });

  group('special moves', () {
    test('castling moves the rook too', () {
      final p = fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq -');
      final short = game
          .legalMoves(p, config)
          .firstWhere((m) => m.kind == MoveKind.castle && m.to == 62);
      final after = game.apply(p, short, config);
      expect(after.cells[62], ArenaPosition.coded(ChessGame.king, 0));
      expect(after.cells[61], ArenaPosition.coded(ChessGame.rook, 0));
      expect(after.cells[63], 0, reason: 'rook left h1');
      expect(game.notation(p, short, config), 'O-O');
    });

    test('a king may not castle through an attacked square', () {
      // Black rook on f8 covers f1, so White's short castle is illegal while
      // the long one stays available.
      final p = fen('5r2/8/8/8/8/8/8/R3K2R w KQ -');
      final castles =
          game.legalMoves(p, config).where((m) => m.kind == MoveKind.castle);
      expect(castles.map((m) => m.to), [58], reason: 'queenside only');
    });

    test('en passant removes the pawn beside the mover', () {
      var p = fen('4k3/4p3/8/3P4/8/8/8/4K3 b - -');
      p = playSan(game, p, 'e5'); // double step past the white pawn
      final ep = game
          .legalMoves(p, config)
          .firstWhere((m) => m.kind == MoveKind.enPassant);
      final after = game.apply(p, ep, config);
      expect(after.cells[squareIndex('e5')], 0,
          reason: 'the captured pawn is lifted');
      expect(after.cells[squareIndex('e6')],
          ArenaPosition.coded(ChessGame.pawn, 0));
      expect(game.notation(p, ep, config), 'dxe6');
    });

    test('promotion offers all four pieces and names them', () {
      final p = fen('4k3/P7/8/8/8/8/8/4K3 w - -');
      final promos =
          game.legalMoves(p, config).where((m) => m.kind == MoveKind.promote);
      expect(promos.length, 4);
      expect(
        promos.map((m) => m.label).toSet(),
        {'Queen', 'Rook', 'Bishop', 'Knight'},
      );
      final toQueen = promos.firstWhere((m) => m.extra['promo'] == 5);
      expect(game.notation(p, toQueen, config), 'a8=Q+');
      final after = game.apply(p, toQueen, config);
      expect(after.cells[squareIndex('a8')],
          ArenaPosition.coded(ChessGame.queen, 0));
    });

    test('a pinned piece cannot move', () {
      // The knight on e2 is pinned to e1 by the rook on e8.
      final p = fen('4r3/8/8/8/8/8/4N3/4K3 w - -');
      final knightMoves =
          game.legalMoves(p, config).where((m) => m.from == squareIndex('e2'));
      expect(knightMoves, isEmpty);
    });
  });

  group('notation', () {
    test('disambiguates by file when two rooks share a rank', () {
      // King on e4, out of the way: without that, the king on e1 blocks the
      // h1 rook and only one rook reaches d1, so nothing needs disambiguating.
      final p = fen('4k3/8/8/8/4K3/8/8/R6R w - -');
      final toD1 = game
          .legalMoves(p, config)
          .firstWhere((m) =>
              m.to == squareIndex('d1') && m.from == squareIndex('a1'));
      expect(game.notation(p, toD1, config), 'Rad1');
    });

    test('falls back to the rank when the file cannot separate them', () {
      // Both rooks on the a-file, so 'Ra' says nothing and the rank must.
      final p = fen('4k3/8/8/R7/4K3/8/8/R7 w - -');
      final toA3 = game
          .legalMoves(p, config)
          .firstWhere((m) =>
              m.to == squareIndex('a3') && m.from == squareIndex('a1'));
      expect(game.notation(p, toA3, config), 'R1a3');
    });

    test('marks check', () {
      final p = fen('4k3/8/8/8/8/8/8/4K2R w - -');
      final check = game
          .legalMoves(p, config)
          .firstWhere((m) => m.to == squareIndex('h8'));
      expect(game.notation(p, check, config), 'Rh8+');
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers: a FEN reader and a SAN player, so tests can state a position the
// way chess literature does instead of building 64 integers by hand.
// ---------------------------------------------------------------------------

int squareIndex(String algebraic) {
  final file = algebraic.codeUnitAt(0) - 97;
  final rank = int.parse(algebraic[1]);
  return (8 - rank) * 8 + file;
}

ArenaPosition fen(String text) {
  final parts = text.split(' ');
  final cells = List<int>.filled(64, 0);
  var index = 0;
  const kinds = {
    'p': ChessGame.pawn,
    'n': ChessGame.knight,
    'b': ChessGame.bishop,
    'r': ChessGame.rook,
    'q': ChessGame.queen,
    'k': ChessGame.king,
  };
  for (final ch in parts[0].split('')) {
    if (ch == '/') continue;
    final skip = int.tryParse(ch);
    if (skip != null) {
      index += skip;
      continue;
    }
    final kind = kinds[ch.toLowerCase()]!;
    final side = ch == ch.toUpperCase() ? 0 : 1;
    cells[index++] = ArenaPosition.coded(kind, side);
  }
  final rights = parts.length > 2 && parts[2] != '-' ? parts[2] : '';
  final ep =
      parts.length > 3 && parts[3] != '-' ? squareIndex(parts[3]) : -1;
  return ArenaPosition(
    cells: cells,
    turn: parts.length > 1 && parts[1] == 'b' ? 1 : 0,
    meta: {
      'castle': rights,
      'ep': ep,
      'half': 0,
      'repeat': '$rights|$ep',
    },
  );
}

ArenaPosition playSan(ChessGame game, ArenaPosition p, String san) {
  const config = GameConfig.empty;
  final move = game
      .legalMoves(p, config)
      .firstWhere((m) => game.notation(p, m, config).replaceAll(RegExp(r'[+#]'), '') == san,
          orElse: () => throw StateError('no legal move "$san"'));
  return game.apply(p, move, config);
}
