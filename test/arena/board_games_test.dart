import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/arena/arena_game.dart';
import 'package:playsphere/domain/arena/games/checkers_game.dart';
import 'package:playsphere/domain/arena/games/connect_four_game.dart';
import 'package:playsphere/domain/arena/games/go_game.dart';
import 'package:playsphere/domain/arena/games/gomoku_game.dart';
import 'package:playsphere/domain/arena/games/reversi_game.dart';

/// The rules that are easy to get wrong, one test each.
///
/// These are not exhaustive move-generation tests the way the chess perft
/// suite is — they are the specific rules an implementation silently omits:
/// compulsory capture, the suicide ban, ko, forced passing, crowning ending a
/// move. A game missing any one of them still *runs*, which is exactly why
/// each one needs a test naming it.
void main() {
  group('checkers', () {
    const game = CheckersGame();
    const config = GameConfig.empty;
    final board = game.board(config);

    test('opens with the seven moves the rules allow', () {
      expect(game.legalMoves(game.initial(config), config).length, 7);
    });

    test('capturing is compulsory — nothing else is offered', () {
      final cells = List<int>.filled(64, 0);
      cells[board.index(2, 5)] = ArenaPosition.coded(1, 0); // red man
      cells[board.index(3, 4)] = ArenaPosition.coded(1, 1); // black, jumpable
      cells[board.index(6, 5)] = ArenaPosition.coded(1, 0); // free to shuffle
      final p = ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0});

      final moves = game.legalMoves(p, config);
      expect(moves.every((m) => m.kind == MoveKind.capture), isTrue,
          reason: 'the quiet move by the far man must be suppressed');
      expect(moves.single.to, board.index(4, 3));
    });

    test('a double jump keeps the turn and lands both hops in the record', () {
      final cells = List<int>.filled(64, 0);
      cells[board.index(2, 5)] = ArenaPosition.coded(1, 0);
      cells[board.index(3, 4)] = ArenaPosition.coded(1, 1);
      cells[board.index(5, 2)] = ArenaPosition.coded(1, 1);
      final p = ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0});

      final first = game.legalMoves(p, config).single;
      final mid = game.apply(p, first, config);
      expect(mid.turn, 0, reason: 'still the same player mid-chain');
      expect(mid.meta['chain'], board.index(4, 3));

      final second = game.legalMoves(mid, config);
      expect(second.every((m) => m.from == board.index(4, 3)), isTrue,
          reason: 'only the jumping piece may move');
      final end = game.apply(mid, second.single, config);
      expect(end.turn, 1, reason: 'chain over, turn passes');
      expect(end.cells.where((c) => ArenaPosition.sideOf(c) == 1).length, 0);
    });

    test('crowning ends the move even with another jump available', () {
      // A red man one jump from the back row, with a second victim beyond it.
      final cells = List<int>.filled(64, 0);
      cells[board.index(2, 2)] = ArenaPosition.coded(1, 0);
      cells[board.index(3, 1)] = ArenaPosition.coded(1, 1);
      cells[board.index(5, 1)] = ArenaPosition.coded(1, 1);
      final p = ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0});

      final jump = game.legalMoves(p, config).single;
      final after = game.apply(p, jump, config);
      expect(ArenaPosition.kindOf(after.cells[board.index(4, 0)]), 2,
          reason: 'crowned');
      expect(after.meta.containsKey('chain'), isFalse);
      expect(after.turn, 1, reason: 'the move is over');
    });

    test('a player with no move loses', () {
      final cells = List<int>.filled(64, 0);
      cells[board.index(0, 7)] = ArenaPosition.coded(1, 0);
      cells[board.index(1, 6)] = ArenaPosition.coded(1, 1);
      cells[board.index(2, 5)] = ArenaPosition.coded(1, 1);
      final p = ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0});
      expect(game.outcome(p, const [], config)!.winner, 1);
    });
  });

  group('reversi', () {
    const game = ReversiGame();
    const config = GameConfig.empty;
    final board = game.board(config);

    test('opens with four legal moves', () {
      expect(game.legalMoves(game.initial(config), config).length, 4);
    });

    test('a placement flips the outflanked line', () {
      final p = game.initial(config);
      final d3 = game
          .legalMoves(p, config)
          .firstWhere((m) => m.to == board.index(3, 2));
      final after = game.apply(p, d3, config);
      expect(ArenaPosition.sideOf(after.cells[board.index(3, 3)]), 0,
          reason: 'the white disc between turned over');
      expect(after.cells.where((c) => c != 0).length, 5);
    });

    test('a player with nothing to flip is handed a pass, not an empty list',
        () {
      // Black in the corner with White beside it: Black can outflank at c1,
      // White can outflank nothing. Both sides being stuck would END the
      // game rather than pass it, so the opponent must still have a move.
      final cells = List<int>.filled(64, 0);
      cells[board.index(0, 0)] = ArenaPosition.coded(1, 0);
      cells[board.index(1, 0)] = ArenaPosition.coded(1, 1);
      final p = ArenaPosition(cells: cells, turn: 1);
      final moves = game.legalMoves(p, config);
      expect(moves.single.kind, MoveKind.pass);
    });

    test('the game ends when neither side can move, and counts discs', () {
      final cells = List<int>.filled(64, 0);
      for (var i = 0; i < 40; i++) {
        cells[i] = ArenaPosition.coded(1, 0);
      }
      for (var i = 40; i < 64; i++) {
        cells[i] = ArenaPosition.coded(1, 1);
      }
      final p = ArenaPosition(cells: cells, turn: 0);
      final result = game.outcome(p, const [], config)!;
      expect(result.winner, 0);
      expect(result.scores, [40.0, 24.0]);
    });
  });

  group('connect four', () {
    const game = ConnectFourGame();
    const config = GameConfig.empty;
    final board = game.board(config);

    test('a disc falls to the bottom of its column', () {
      final p = game.initial(config);
      final drop = game
          .legalMoves(p, config)
          .firstWhere((m) => m.extra['col'] == 3);
      expect(drop.to, board.index(3, board.rows - 1));
      final after = game.apply(p, drop, config);
      // The next disc in the same column rests on top of it.
      final next = game
          .legalMoves(after, config)
          .firstWhere((m) => m.extra['col'] == 3);
      expect(next.to, board.index(3, board.rows - 2));
    });

    test('four in a row wins and the winning line is reported', () {
      var p = game.initial(config);
      // Red builds a row along the bottom while Yellow stacks elsewhere.
      for (final cols in const [[0, 6], [1, 6], [2, 6], [3, 6]]) {
        p = game.apply(
          p,
          game.legalMoves(p, config).firstWhere((m) => m.extra['col'] == cols[0]),
          config,
        );
        if (game.outcome(p, const [], config) != null) break;
        p = game.apply(
          p,
          game.legalMoves(p, config).firstWhere((m) => m.extra['col'] == cols[1]),
          config,
        );
      }
      final result = game.outcome(p, const [], config)!;
      expect(result.winner, 0);
      expect(game.highlights(p, config).length, 4);
    });

    test('a full board with no line is a draw', () {
      final cells = List<int>.filled(board.cells, 0);
      // Stripes by column pair: no four ever line up.
      for (var i = 0; i < board.cells; i++) {
        final col = board.colOf(i);
        cells[i] = ArenaPosition.coded(1, (col ~/ 2) % 2);
      }
      final p = ArenaPosition(cells: cells, turn: 0);
      expect(game.legalMoves(p, config), isEmpty);
    });
  });

  group('gomoku', () {
    const game = GomokuGame();
    const config = GameConfig.empty;
    final board = game.board(config);

    test('five in a row wins', () {
      final cells = List<int>.filled(board.cells, 0);
      for (var i = 0; i < 5; i++) {
        cells[board.index(3 + i, 7)] = ArenaPosition.coded(1, 0);
      }
      final p = ArenaPosition(cells: cells, turn: 1);
      final result = game.outcome(p, const [], config)!;
      expect(result.winner, 0);
      expect(game.highlights(p, config).length, 5);
    });

    test('four in a row does not', () {
      final cells = List<int>.filled(board.cells, 0);
      for (var i = 0; i < 4; i++) {
        cells[board.index(3 + i, 7)] = ArenaPosition.coded(1, 0);
      }
      final p = ArenaPosition(cells: cells, turn: 1);
      expect(game.outcome(p, const [], config), isNull);
    });

    test('a diagonal counts too', () {
      final cells = List<int>.filled(board.cells, 0);
      for (var i = 0; i < 5; i++) {
        cells[board.index(2 + i, 2 + i)] = ArenaPosition.coded(1, 1);
      }
      final p = ArenaPosition(cells: cells, turn: 0);
      expect(game.outcome(p, const [], config)!.winner, 1);
    });
  });

  group('go', () {
    const game = GoGame();
    // A 5×5 board keeps the shapes readable; the engine takes its size from
    // the config, not from the variant list, so a test may use any board.
    const config = GameConfig({'size': 5, 'komi': 0.5});
    final board = game.board(config);
    int at(int col, int row) => board.index(col, row);

    ArenaPosition position(Map<int, int> stones, int turn) {
      final cells = List<int>.filled(board.cells, 0);
      stones.forEach((index, side) {
        cells[index] = ArenaPosition.coded(1, side);
      });
      return ArenaPosition(
        cells: cells,
        turn: turn,
        meta: const {'passes': 0, 'caps': [0, 0]},
      );
    }

    test('a surrounded stone is lifted', () {
      final p = position({
        at(1, 0): 0,
        at(0, 1): 0,
        at(1, 2): 0,
        at(1, 1): 1,
      }, 0);
      final capture =
          game.legalMoves(p, config).firstWhere((m) => m.to == at(2, 1));
      final after = game.apply(p, capture, config);
      expect(after.cells[at(1, 1)], 0, reason: 'the white stone is gone');
      expect((after.meta['caps'] as List)[0], 1);
    });

    test('suicide is not offered', () {
      final p = position({at(1, 0): 0, at(0, 1): 0}, 1);
      final moves = game.legalMoves(p, config).map((m) => m.to);
      expect(moves, isNot(contains(at(0, 0))),
          reason: 'white would have no liberty there');
    });

    test('but the same point is legal when playing it captures', () {
      // The corner has no liberty of its own — both neighbours are black —
      // so this is suicide UNLESS the two black stones die first. They do:
      // white already holds every one of their other liberties. Capture is
      // resolved before self-capture, and this is the test that says so.
      final p = position({
        at(1, 0): 0,
        at(0, 1): 0,
        at(2, 0): 1,
        at(1, 1): 1,
        at(0, 2): 1,
      }, 1);
      final moves = game.legalMoves(p, config).map((m) => m.to);
      expect(moves, contains(at(0, 0)));

      final capture =
          game.legalMoves(p, config).firstWhere((m) => m.to == at(0, 0));
      final after = game.apply(p, capture, config);
      expect(after.cells[at(1, 0)], 0);
      expect(after.cells[at(0, 1)], 0);
      expect((after.meta['caps'] as List)[1], 2);
    });

    test('ko forbids the immediate recapture', () {
      final p = position({
        at(1, 0): 0,
        at(0, 1): 0,
        at(1, 2): 0,
        at(2, 0): 1,
        at(3, 1): 1,
        at(2, 2): 1,
        at(1, 1): 1,
      }, 0);
      final take =
          game.legalMoves(p, config).firstWhere((m) => m.to == at(2, 1));
      final after = game.apply(p, take, config);
      final replies = game.legalMoves(after, config).map((m) => m.to);
      expect(replies, isNot(contains(at(1, 1))),
          reason: 'taking straight back would repeat the position');
    });

    test('two passes end the game and komi decides an empty board', () {
      var p = game.initial(config);
      p = game.apply(p, const ArenaMove.pass(), config);
      expect(game.outcome(p, const [], config), isNull,
          reason: 'one pass is not an ending');
      p = game.apply(p, const ArenaMove.pass(), config);
      final result = game.outcome(p, const [], config)!;
      expect(result.winner, 1, reason: 'White holds the komi');
      expect(result.scores, [0.0, 0.5]);
    });

    test('area scoring counts stones plus the territory they enclose', () {
      var p = position({at(2, 2): 0}, 0);
      p = game.apply(p, const ArenaMove.pass(), config);
      p = game.apply(p, const ArenaMove.pass(), config);
      final result = game.outcome(p, const [], config)!;
      // One stone plus all 24 empty points, which only Black reaches.
      expect(result.scores, [25.0, 0.5]);
      expect(result.winner, 0);
    });
  });
}
