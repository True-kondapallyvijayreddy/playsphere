import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/arena/arena_game.dart';
import 'package:playsphere/domain/arena/arena_registry.dart';
import 'package:playsphere/domain/arena/games/chess_game.dart';
import 'package:playsphere/features/arena/widgets/arena_board_view.dart';
import 'package:playsphere/features/arena/widgets/chess_figures.dart';
import 'package:playsphere/features/arena/widgets/arena_game_emblem.dart';

/// Pictures of the artwork, so it can be looked at rather than imagined.
///
/// Goldens here are for the DRAWING, not the layout — the pieces and the tile
/// emblems are vector paths, which render identically under `flutter test` and
/// on a phone, so a golden is an honest picture of what ships. (Anything
/// involving text would not be: the test environment has no real fonts.)
///
/// Run `flutter test --update-goldens test/arena/arena_artwork_golden_test.dart`
/// after changing a silhouette, then actually open the PNG. A Flutter upgrade
/// that changes rasterisation will also need that refresh — check the diff
/// image it writes before accepting one, because "the toolchain moved" and
/// "the knight lost its ear" arrive looking identical.
void main() {
  testWidgets('the six chess pieces, both colours', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          child: _PieceSheet(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_PieceSheet),
      matchesGoldenFile('goldens/chess_pieces.png'),
    );
  });

  testWidgets('the opening chessboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: SizedBox(
            width: 360,
            height: 360,
            child: ArenaBoardView(
              game: ArenaGames.chess,
              config: GameConfig.empty,
              position: ArenaGames.chess.initial(GameConfig.empty),
              legalMoves:
                  ArenaGames.chess.legalMoves(
                ArenaGames.chess.initial(GameConfig.empty),
                GameConfig.empty,
              ),
              flipped: false,
              interactive: true,
              selected: 52,
              onTapSquare: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ArenaBoardView),
      matchesGoldenFile('goldens/chess_board.png'),
    );
  });

  testWidgets('every game tile emblem', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _EmblemSheet(),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_EmblemSheet),
      matchesGoldenFile('goldens/game_emblems.png'),
    );
  });

  testWidgets('a checkers board with kings', (tester) async {
    const game = ArenaGames.checkers;
    var position = game.initial(GameConfig.empty);
    // Crown one of each so the crown mark is in the picture.
    final cells = List<int>.from(position.cells);
    cells[game.board(GameConfig.empty).index(2, 5)] =
        ArenaPosition.coded(2, 0);
    cells[game.board(GameConfig.empty).index(3, 2)] =
        ArenaPosition.coded(2, 1);
    position = position.copyWith(cells: cells);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: ArenaBoardView(
              game: game,
              config: GameConfig.empty,
              position: position,
              legalMoves: game.legalMoves(position, GameConfig.empty),
              flipped: false,
              interactive: true,
              selected: null,
              onTapSquare: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ArenaBoardView),
      matchesGoldenFile('goldens/checkers_board.png'),
    );
  });

  testWidgets('a go board mid-game', (tester) async {
    const game = ArenaGames.go;
    const config = GameConfig({'size': 9, 'komi': 5.5});
    var position = game.initial(config);
    for (final point in const [30, 40, 39, 31, 21, 49, 41, 50, 22, 32]) {
      final move = game
          .legalMoves(position, config)
          .firstWhere((m) => m.to == point);
      position = game.apply(position, move, config);
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: ArenaBoardView(
              game: game,
              config: config,
              position: position,
              legalMoves: const [],
              flipped: false,
              interactive: false,
              selected: null,
              onTapSquare: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ArenaBoardView),
      matchesGoldenFile('goldens/go_board.png'),
    );
  });
}

/// Both armies on a plain ground, big enough to judge the silhouettes.
class _PieceSheet extends StatelessWidget {
  const _PieceSheet();

  @override
  Widget build(BuildContext context) {
    const kinds = [
      ChessGame.king,
      ChessGame.queen,
      ChessGame.rook,
      ChessGame.bishop,
      ChessGame.knight,
      ChessGame.pawn,
    ];
    return Container(
      color: const Color(0xFF94A3B8),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final side in const [0, 1])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final kind in kinds)
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CustomPaint(
                      painter: _OnePiece(
                        kind: kind,
                        side: side,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OnePiece extends CustomPainter {
  const _OnePiece({required this.kind, required this.side});

  final int kind;
  final int side;

  @override
  void paint(Canvas canvas, Size size) {
    // Painted through the real board view's own code path by reusing the
    // game's art declaration, so this cannot drift from what the board draws.
    final art = ArenaGames.chess.art(ArenaPosition.coded(kind, side))!;
    final colour = Color(ArenaGames.chess.sideColors[art.side]);
    final rim =
        side == 0 ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);
    drawChessFigure(
      canvas,
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width * 0.82,
        height: size.height * 0.82,
      ),
      art.figure!,
      Paint()..color = colour,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_OnePiece old) =>
      old.kind != kind || old.side != side;
}

class _EmblemSheet extends StatelessWidget {
  const _EmblemSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final row in const [
            [0, 1, 2],
            [3, 4, 5],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final i in row)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: ArenaGameEmblem(
                      game: ArenaGames.all[i],
                      size: 88,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          // The same six at the size they actually ship at on a tile. Drawn
          // here because artwork that only works blown up is artwork that
          // does not work: a chess figurine inside a 54dp emblem is about
          // 16dp tall, which is where a silhouette either still reads or
          // turns to mush.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final game in ArenaGames.all)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: ArenaGameEmblem(game: game),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
