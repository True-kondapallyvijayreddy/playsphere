import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/arena_match.dart';
import 'package:playsphere/domain/arena/arena_game.dart';
import 'package:playsphere/domain/arena/games/checkers_game.dart';
import 'package:playsphere/domain/arena/games/chess_game.dart';

/// Replay is the contract between the two phones.
///
/// Neither player's device receives a board — each derives one from the same
/// move list. These tests are about that derivation: that it reproduces the
/// game exactly, that whose-turn-it-is falls out of it rather than being
/// stored and trusted, and that a move list which does NOT replay is reported
/// instead of being papered over.
void main() {
  const alice = 'uid-alice';
  const bob = 'uid-bob';

  ArenaMatch matchOf({
    required String gameId,
    required List<ArenaMoveRecord> moves,
    ArenaStatus status = ArenaStatus.active,
    Map<String, dynamic> config = const {},
  }) =>
      ArenaMatch(
        id: 'm1',
        gameId: gameId,
        variantId: 'standard',
        config: config,
        players: const [alice, bob],
        names: const {alice: 'Alice', bob: 'Bob'},
        status: status,
        challengerUid: bob,
        moves: moves,
      );

  /// Plays a sequence through the engine the way the repository does, so the
  /// records under test are built the same way real ones are.
  List<ArenaMoveRecord> record(
    ArenaGame game,
    List<ArenaMove Function(List<ArenaMove> legal)> picks, {
    Map<String, dynamic> config = const {},
  }) {
    final gameConfig = GameConfig(config);
    var position = game.initial(gameConfig);
    final out = <ArenaMoveRecord>[];
    for (var i = 0; i < picks.length; i++) {
      final legal = game.legalMoves(position, gameConfig);
      final move = picks[i](legal);
      out.add(ArenaMoveRecord(
        ply: i,
        uid: position.turn == 0 ? alice : bob,
        side: position.turn,
        notation: game.notation(position, move, gameConfig),
        move: move,
      ));
      position = game.apply(position, move, gameConfig);
    }
    return out;
  }

  group('replay', () {
    const chess = ChessGame();

    ArenaMove named(List<ArenaMove> legal, String san) => legal.firstWhere(
          (m) => chess
                  .notation(
                    // Notation needs the position, which the caller no longer
                    // has — so this helper is only used where the move is
                    // unambiguous by its squares instead.
                    chess.initial(GameConfig.empty),
                    m,
                    GameConfig.empty,
                  )
                  .replaceAll(RegExp(r'[+#]'), '') ==
              san,
        );

    test('a move list rebuilds every position it passed through', () {
      final moves = record(chess, [
        (legal) => named(legal, 'e4'),
        (legal) => legal.firstWhere((m) => m.from == 12 && m.to == 28),
        (legal) => legal.firstWhere((m) => m.from == 62 && m.to == 45),
      ]);
      final match = matchOf(gameId: 'chess', moves: moves);

      final replay = match.replay();
      expect(replay.truncatedAt, isNull);
      expect(replay.ply, 3);
      expect(replay.positions.length, 4,
          reason: 'the opening position plus one per move');
      expect(replay.current.turn, 1, reason: 'Black to move after three plies');
      // The knight really is on f3.
      expect(replay.current.cells[45],
          ArenaPosition.coded(ChessGame.knight, 0));
    });

    test('a prefix can be replayed for review', () {
      final moves = record(chess, [
        (legal) => named(legal, 'e4'),
        (legal) => legal.firstWhere((m) => m.from == 12 && m.to == 28),
      ]);
      final match = matchOf(gameId: 'chess', moves: moves);

      final opening = match.replay(upToPly: 0);
      expect(opening.ply, 0);
      expect(opening.current.cells, chess.initial(GameConfig.empty).cells);

      final afterOne = match.replay(upToPly: 1);
      expect(afterOne.ply, 1);
      expect(afterOne.current.turn, 1);
    });

    test('whose turn it is comes from the moves, never from a stored field',
        () {
      final match = matchOf(gameId: 'chess', moves: const []);
      expect(match.turnUid, alice, reason: 'players[0] moves first');
      expect(match.isTurn(bob), isFalse);

      final afterOne = matchOf(
        gameId: 'chess',
        moves: record(chess, [(legal) => named(legal, 'e4')]),
      );
      expect(afterOne.turnUid, bob);
    });

    test('a game that is not active has no turn', () {
      final match = matchOf(
        gameId: 'chess',
        moves: const [],
        status: ArenaStatus.pending,
      );
      expect(match.turnUid, isNull);
    });

    test('a move that does not fit the rules stops the replay and is reported',
        () {
      // A rook teleporting across a full board — nothing the engine would
      // ever generate, standing in for a tampered or corrupted document.
      const bogus = ArenaMoveRecord(
        ply: 0,
        uid: alice,
        side: 0,
        notation: 'Ra5',
        move: ArenaMove(from: 56, to: 32),
      );
      final match = matchOf(gameId: 'chess', moves: [bogus]);

      final replay = match.replay();
      expect(replay.truncatedAt, 0);
      expect(replay.ply, 0, reason: 'the board stays at the last good position');
      expect(replay.current.cells, chess.initial(GameConfig.empty).cells);
    });

    test('an unknown game degrades instead of drawing the wrong board', () {
      final match = matchOf(gameId: 'shogi', moves: const []);
      expect(match.game, isNull);
      expect(match.replay().truncatedAt, 0);
      expect(match.turnUid, isNull);
    });
  });

  group('a checkers chain is one player, two records', () {
    const checkers = CheckersGame();
    final board = checkers.board(GameConfig.empty);

    test('the turn does not pass until the chain ends', () {
      // Built by hand rather than from the opening, because a double jump
      // cannot arise in two plies.
      final cells = List<int>.filled(64, 0);
      cells[board.index(2, 5)] = ArenaPosition.coded(1, 0);
      cells[board.index(3, 4)] = ArenaPosition.coded(1, 1);
      cells[board.index(5, 2)] = ArenaPosition.coded(1, 1);
      var position = ArenaPosition(
        cells: cells,
        turn: 0,
        meta: const {'quiet': 0},
      );

      final first = checkers.legalMoves(position, GameConfig.empty).single;
      position = checkers.apply(position, first, GameConfig.empty);
      expect(position.turn, 0, reason: 'same player, mid-chain');

      final second = checkers.legalMoves(position, GameConfig.empty).single;
      position = checkers.apply(position, second, GameConfig.empty);
      expect(position.turn, 1, reason: 'chain over');

      // Both hops are separate records, which is what makes the move list
      // show what actually happened rather than one composite entry.
      expect(
        checkers.notation(
          ArenaPosition(cells: cells, turn: 0, meta: const {'quiet': 0}),
          first,
          GameConfig.empty,
        ),
        contains('x'),
      );
    });
  });

  group('the document', () {
    test('names the two sides and their opponent', () {
      final match = matchOf(gameId: 'chess', moves: const []);
      expect(match.sideOf(alice), 0);
      expect(match.sideOf(bob), 1);
      expect(match.opponentOf(alice), bob);
      expect(match.nameOf(bob), 'Bob');
      expect(match.nameOf('someone-else'), 'Player');
    });

    test('a move round-trips through its stored map', () {
      const move = ArenaMove(
        from: 12,
        to: 28,
        kind: MoveKind.promote,
        extra: {'promo': 5},
      );
      final restored = ArenaMove.fromMap(move.toMap());
      expect(restored, move);
      expect(restored.key, move.key);
    });

    test('carries no rating field of any kind', () {
      // The Arena's whole premise. If a rating ever needs to be written, it
      // must be a deliberate change here, not something that slips in.
      final match = matchOf(gameId: 'chess', moves: const []);
      final stored = match.toCreate();
      expect(stored.keys, isNot(contains('rating')));
      expect(stored.keys, isNot(contains('glicko')));
      expect(stored.keys, isNot(contains('ratingKey')));
    });
  });
}
