import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/arena/arena_game.dart';
import 'package:playsphere/domain/arena/arena_registry.dart';
import 'package:playsphere/domain/arena/games/checkers_game.dart';
import 'package:playsphere/domain/arena/games/chess_game.dart';
import 'package:playsphere/domain/arena/games/connect_four_game.dart';
import 'package:playsphere/domain/arena/games/go_game.dart';
import 'package:playsphere/domain/arena/games/gomoku_game.dart';
import 'package:playsphere/domain/arena/games/reversi_game.dart';

import 'chess_engine_test.dart' show fen, squareIndex;

/// The game record is for somebody reading a game back to work out where it
/// went wrong, so the wording has to say what actually happened — which piece,
/// from where, to where, and what it did when it got there.
void main() {
  const config = GameConfig.empty;

  group('chess', () {
    const game = ChessGame();

    String describe(ArenaPosition p, bool Function(ArenaMove) pick) {
      final move = game.legalMoves(p, config).firstWhere(pick);
      return game.describe(p, move, config);
    }

    test('a quiet move names the piece and both squares', () {
      // Black king in the far corner: on e8 it would stand next to d7 and
      // make the move being described illegal.
      final p = fen('k7/8/3K4/8/8/8/8/8 w - -');
      expect(
        describe(p, (m) => m.to == squareIndex('d7')),
        'White king d6 → d7',
      );
    });

    test('a capture names what was taken and where', () {
      final p = fen('4k3/8/8/8/8/5b2/8/4K1N1 w - -');
      expect(
        describe(p, (m) => m.to == squareIndex('f3')),
        'White knight g1 takes the bishop on f3',
      );
    });

    test('check and checkmate are spelled out, not left as a symbol', () {
      final check = fen('4k3/8/8/8/8/8/8/4K2R w - -');
      expect(
        describe(check, (m) => m.to == squareIndex('h8')),
        'White rook h1 → h8 — check',
      );

      final mate = fen('6k1/5ppp/8/8/8/8/8/R3K2R w KQ -');
      expect(
        describe(mate, (m) => m.to == squareIndex('a8')),
        'White rook a1 → a8 — checkmate',
      );
    });

    test('castling says which side, and where the king went', () {
      final p = fen('4k3/8/8/8/8/8/8/R3K2R w KQ -');
      expect(
        describe(p, (m) => m.kind == MoveKind.castle && m.to == 62),
        'White castles kingside (king e1 → g1)',
      );
      expect(
        describe(p, (m) => m.kind == MoveKind.castle && m.to == 58),
        'White castles queenside (king e1 → c1)',
      );
    });

    test('promotion says what the pawn became', () {
      final p = fen('4k3/P7/8/8/8/8/8/4K3 w - -');
      expect(
        describe(p, (m) => m.kind == MoveKind.promote && m.extra['promo'] == 5),
        'White pawn a7 → a8, promoted to a queen — check',
      );
    });

    test('en passant explains itself', () {
      var p = fen('4k3/4p3/8/3P4/8/8/8/4K3 b - -');
      final double = game
          .legalMoves(p, config)
          .firstWhere((m) => m.to == squareIndex('e5'));
      p = game.apply(p, double, config);
      expect(
        describe(p, (m) => m.kind == MoveKind.enPassant),
        'White pawn d5 → e6, taking the pawn in passing',
      );
    });
  });

  group('the other games say what happened in their own terms', () {
    test('connect four names the column and where the disc landed', () {
      const game = ConnectFourGame();
      final p = game.initial(config);
      final drop =
          game.legalMoves(p, config).firstWhere((m) => m.extra['col'] == 3);
      expect(game.describe(p, drop, config),
          'Red drops into column D (the bottom)');

      final after = game.apply(p, drop, config);
      final second = game
          .legalMoves(after, config)
          .firstWhere((m) => m.extra['col'] == 3);
      expect(game.describe(after, second, config),
          'Yellow drops into column D (row 2)');
    });

    test('reversi counts the discs that turned over', () {
      const game = ReversiGame();
      final p = game.initial(config);
      final move = game.legalMoves(p, config).first;
      expect(
        game.describe(p, move, config),
        contains('turning over 1 disc'),
      );
    });

    test('go counts what a move captured', () {
      const game = GoGame();
      const small = GameConfig({'size': 5, 'komi': 0.5});
      final board = game.board(small);
      final cells = List<int>.filled(board.cells, 0);
      cells[board.index(1, 0)] = ArenaPosition.coded(1, 0);
      cells[board.index(0, 1)] = ArenaPosition.coded(1, 0);
      cells[board.index(1, 2)] = ArenaPosition.coded(1, 0);
      cells[board.index(1, 1)] = ArenaPosition.coded(1, 1);
      final p = ArenaPosition(
        cells: cells,
        turn: 0,
        meta: const {'passes': 0, 'caps': [0, 0]},
      );
      final capture = game
          .legalMoves(p, small)
          .firstWhere((m) => m.to == board.index(2, 1));
      expect(
        game.describe(p, capture, small),
        'Black plays C4, capturing 1 stone',
      );
      expect(
        game.describe(p, const ArenaMove.pass(), small),
        'Black passes',
      );
    });

    test('checkers says whether the jump continues, and when a man is crowned',
        () {
      const game = CheckersGame();
      final board = game.board(config);
      final cells = List<int>.filled(64, 0);
      cells[board.index(2, 5)] = ArenaPosition.coded(1, 0);
      cells[board.index(3, 4)] = ArenaPosition.coded(1, 1);
      cells[board.index(5, 2)] = ArenaPosition.coded(1, 1);
      final p = ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0});

      final first = game.legalMoves(p, config).single;
      expect(
        game.describe(p, first, config),
        contains('and can jump again'),
      );

      final mid = game.apply(p, first, config);
      final second = game.legalMoves(mid, config).single;
      expect(game.describe(mid, second, config), contains('taking a man'));
    });

    test('gomoku calls out a live four', () {
      const game = GomokuGame();
      final board = game.board(config);
      final cells = List<int>.filled(board.cells, 0);
      for (var i = 0; i < 3; i++) {
        cells[board.index(3 + i, 7)] = ArenaPosition.coded(1, 0);
      }
      final p = ArenaPosition(cells: cells, turn: 0);
      final move = game
          .legalMoves(p, config)
          .firstWhere((m) => m.to == board.index(6, 7));
      expect(game.describe(p, move, config), 'Black plays G8 — 4 in a row');
    });
  });

  test('every game can describe its own opening move', () {
    // A game that forgot to override `describe` still has to produce a
    // sentence rather than a blank row in the record.
    for (final game in ArenaGames.all) {
      final variant = game.variants.first;
      final gameConfig = GameConfig(variant.config);
      final start = game.initial(gameConfig);
      final move = game.legalMoves(start, gameConfig).first;
      final text = game.describe(start, move, gameConfig);
      expect(text, isNotEmpty, reason: '${game.name} described nothing');
      expect(text.length, greaterThan(6), reason: '${game.name}: "$text"');
    }
  });
}
