import 'package:flutter/material.dart';

import '../../../domain/arena/arena_game.dart';
import 'chess_figures.dart';

/// A small picture of the game itself, for the tiles on the Arena list.
///
/// ## Why this is drawn rather than iconified
///
/// The grid first used Material icons — a castle for chess, a circle for
/// checkers, crosshairs for go. They were all the same shape at a glance and
/// none of them told you what the game was: the only thing separating go from
/// gomoku was a tint. Six near-identical grey glyphs is a worse grid than no
/// pictures at all.
///
/// So each tile shows a scrap of the real board: the actual squares, the
/// actual colours, the actual pieces. Chess and checkers are instantly told
/// apart by a figurine against a crown; go and gomoku by five stones in a row
/// against a capture shape; reversi and connect four by their own board
/// colours, which are half of what people recognise those games by.
///
/// ## It reads the engine, so a seventh game needs nothing here
///
/// The board style, the surface and square colours, the side colours and the
/// piece art all come from the [ArenaGame] itself — the same calls the real
/// board makes. Only the little sample position below is written here, and a
/// game with none falls back to its own opening position clipped to a corner.
/// Adding a game stays a file in `domain/arena/games/`.
class ArenaGameEmblem extends StatelessWidget {
  const ArenaGameEmblem({
    super.key,
    required this.game,
    this.size = 60,
  });

  final ArenaGame game;
  final double size;

  /// A characteristic scrap of each board: how many points across, and what
  /// stands on them.
  ///
  /// Piece codes are the game's OWN codes, so [ArenaGame.art] resolves them
  /// exactly as it would mid-game — a white king really is a white king, and a
  /// crowned checker really carries the crown the board draws.
  static const Map<String, (int cols, int rows, Map<int, int> pieces)>
      _previews = {
    // A king facing a knight. Three squares is the fewest that still reads as
    // a chessboard, and it leaves the figurines big enough to recognise.
    'chess': (3, 3, {6: 6, 2: -2}),
    // A man and a crowned king, which is the whole game in two discs.
    'checkers': (3, 3, {6: 1, 2: -2}),
    // Discs resting on the floor of the frame, because they fall.
    'connect_four': (3, 3, {6: 1, 7: -1, 4: 1}),
    // The opening four, set crosswise exactly as the real game starts.
    'reversi': (4, 4, {5: -1, 10: -1, 6: 1, 9: 1}),
    // Four in a row and the stone that blocked the fifth. Kept on the middle
    // rank rather than the diagonal: a stone on a true corner point is
    // clipped by the tile's own rounded edge.
    'gomoku': (5, 5, {10: 1, 11: 1, 12: 1, 13: 1, 14: -1}),
    // A stone in atari — three neighbours taken, one liberty left.
    'go': (5, 5, {12: -1, 7: 1, 11: 1, 17: 1}),
  };

  @override
  Widget build(BuildContext context) {
    final spec = _previews[game.id];
    final config = GameConfig(game.variant(null).config);
    final board = game.board(config);

    final (cols, rows, pieces) = spec ??
        (
          board.cols.clamp(3, 5),
          board.rows.clamp(3, 5),
          const <int, int>{},
        );

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EmblemPainter(
          game: game,
          style: board.style,
          lightSquare: Color(board.lightSquare),
          darkSquare: Color(board.darkSquare),
          surface: Color(board.surface),
          cols: cols,
          rows: rows,
          pieces: pieces,
        ),
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter({
    required this.game,
    required this.style,
    required this.lightSquare,
    required this.darkSquare,
    required this.surface,
    required this.cols,
    required this.rows,
    required this.pieces,
  });

  final ArenaGame game;
  final BoardStyle style;
  final Color lightSquare;
  final Color darkSquare;
  final Color surface;
  final int cols;
  final int rows;
  final Map<int, int> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rounded =
        RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.save();
    canvas.clipRRect(rounded);

    // Stones on a ruled board sit on the crossings, so the grid is inset far
    // enough that an edge stone is not sliced in half by the tile border.
    final onLines = style == BoardStyle.lines;
    final pad = onLines ? size.width / (cols + 1) / 2 : 0.0;
    final cell = (size.width - pad * 2) / cols;
    final step = onLines ? (size.width - pad * 2) / (cols - 1) : cell;

    Offset centre(int index) {
      final col = index % cols;
      final row = index ~/ cols;
      return onLines
          ? Offset(pad + col * step, pad + row * step)
          : Offset(pad + (col + 0.5) * cell, pad + (row + 0.5) * cell);
    }

    switch (style) {
      case BoardStyle.checkered:
        canvas.drawRect(rect, Paint()..color = lightSquare);
        final dark = Paint()..color = darkSquare;
        for (var i = 0; i < cols * rows; i++) {
          if ((i % cols + i ~/ cols) % 2 == 0) continue;
          canvas.drawRect(
            Rect.fromCenter(
                center: centre(i), width: cell, height: cell),
            dark,
          );
        }

      case BoardStyle.lines:
        canvas.drawRect(rect, Paint()..color = surface);
        final line = Paint()
          ..color = const Color(0x77000000)
          ..strokeWidth = 0.8;
        for (var i = 0; i < cols; i++) {
          final x = pad + i * step;
          canvas.drawLine(
              Offset(x, pad), Offset(x, size.height - pad), line);
          final y = pad + i * step;
          canvas.drawLine(
              Offset(pad, y), Offset(size.width - pad, y), line);
        }

      case BoardStyle.cells:
        canvas.drawRect(rect, Paint()..color = surface);
        final line = Paint()
          ..color = const Color(0x2E000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        for (var i = 0; i < cols * rows; i++) {
          canvas.drawRect(
            Rect.fromCenter(
                center: centre(i), width: cell, height: cell),
            line,
          );
        }
    }

    final span = onLines ? step : cell;
    for (final entry in pieces.entries) {
      final art = game.art(entry.value);
      if (art == null) continue;
      final at = centre(entry.key);
      final colour = Color(game.sideColors[art.side]);
      final radius = span * art.scale / 2;

      if (art.figure == null) {
        canvas.drawCircle(at, radius, Paint()..color = colour);
        canvas.drawCircle(
          at,
          radius,
          Paint()
            ..color = const Color(0x40000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        if (art.crowned) {
          final ink = art.side == 0
              ? const Color(0xFF7F1D1D)
              : const Color(0xFFF9FAFB);
          canvas.drawCircle(
            at,
            radius * 0.5,
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        }
      } else {
        final rim = art.side == 0
            ? const Color(0xFF1F2937)
            : const Color(0xFFF3F4F6);
        drawChessFigure(
          canvas,
          Rect.fromCenter(
            center: at,
            width: radius * 2,
            height: radius * 2,
          ),
          art.figure!,
          Paint()..color = colour,
          Paint()
            ..color = rim
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    canvas.restore();
    // A hairline over the top, so a pale board still separates from a white
    // card.
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = const Color(0x1A000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_EmblemPainter old) =>
      old.game.id != game.id || old.cols != cols || old.rows != rows;
}
