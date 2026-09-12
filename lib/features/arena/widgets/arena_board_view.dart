import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/arena/arena_game.dart';
import 'chess_figures.dart';

/// The board. One widget for all six games.
///
/// It knows how to draw a checkered grid, a ruled grid and a cell grid; how to
/// put a disc or a glyph in a square; and how to turn a tap into a square
/// index. It does not know what any of those squares MEAN. Every rule —
/// which squares can be tapped, what a tap leads to, which squares are worth
/// highlighting — arrives as data from the engine, which is why chess and go
/// can share it without either being a special case.
class ArenaBoardView extends StatelessWidget {
  const ArenaBoardView({
    super.key,
    required this.game,
    required this.config,
    required this.position,
    required this.legalMoves,
    required this.flipped,
    required this.interactive,
    required this.selected,
    required this.onTapSquare,
    this.lastMove = const [],
  });

  final ArenaGame game;
  final GameConfig config;
  final ArenaPosition position;

  /// What the side to move may do. Empty when the board is being reviewed or
  /// the game is over, which is also what makes it read-only.
  final List<ArenaMove> legalMoves;

  /// Whether the viewer is the second player and should see the board from
  /// their own end.
  final bool flipped;

  final bool interactive;

  /// The square a from–to game has picked up, if any.
  final int? selected;

  final ValueChanged<int> onTapSquare;

  final List<int> lastMove;

  @override
  Widget build(BuildContext context) {
    final board = game.board(config);

    // Destinations reachable from the current selection, or — for placement
    // and column games, which have no selection — every playable point.
    final targets = <int>{};
    for (final m in legalMoves) {
      if (game.input == MoveInput.fromTo) {
        if (selected != null && m.from == selected) targets.add(m.to);
      } else if (m.to >= 0) {
        targets.add(m.to);
      }
    }
    final origins = <int>{
      for (final m in legalMoves)
        if (game.input == MoveInput.fromTo && m.from >= 0) m.from,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: side,
          height: side,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: interactive
                ? (details) {
                    final index = _hitTest(
                      details.localPosition,
                      board,
                      side,
                    );
                    if (index != null) onTapSquare(index);
                  }
                : null,
            child: CustomPaint(
              painter: _BoardPainter(
                game: game,
                config: config,
                board: board,
                position: position,
                flipped: flipped,
                selected: selected,
                targets: targets,
                origins: origins,
                highlights: game.highlights(position, config).toSet(),
                lastMove: lastMove.toSet(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Which square a tap landed on, accounting for the board being flipped and
  /// for stones sitting on crossings rather than in cells.
  int? _hitTest(Offset local, BoardSpec board, double size) {
    final geometry = _Geometry(board, size, flipped);
    return geometry.indexAt(local);
  }
}

/// Where everything sits, given a board and a widget size.
///
/// Pulled out of the painter because the tap handler needs exactly the same
/// arithmetic, and two copies of it drifting apart is how a board ends up
/// registering taps one square off near the edges.
class _Geometry {
  _Geometry(this.board, this.size, this.flipped) {
    // A lined board needs half a cell of margin so the outermost crossings —
    // which are playable points — are not drawn on the very edge of the
    // widget, with their stones cut in half.
    final onLines = board.style == BoardStyle.lines;
    padding = onLines ? size / (board.cols + 1) / 2 + 6 : 0;
    cell = (size - padding * 2) / board.cols;
  }

  final BoardSpec board;
  final double size;
  final bool flipped;
  late final double padding;
  late final double cell;

  bool get onLines => board.style == BoardStyle.lines;

  /// The screen position of a square's centre.
  Offset centreOf(int index) {
    var col = board.colOf(index);
    var row = board.rowOf(index);
    if (flipped) {
      col = board.cols - 1 - col;
      row = board.rows - 1 - row;
    }
    if (onLines) {
      // Crossings: the first point sits ON the first line, not half a cell in.
      final step = (size - padding * 2) / (board.cols - 1);
      return Offset(padding + col * step, padding + row * step);
    }
    return Offset(
      padding + (col + 0.5) * cell,
      padding + (row + 0.5) * cell,
    );
  }

  double get pieceSpan => onLines
      ? (size - padding * 2) / (board.cols - 1)
      : cell;

  int? indexAt(Offset local) {
    // Nearest point wins, rather than a strict rectangle test: on a phone a
    // 19×19 go board gives each crossing about 18 logical pixels, and demanding
    // a hit inside that box makes the board feel broken.
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < board.cells; i++) {
      final d = (centreOf(i) - local).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    if (best < 0) return null;
    final reach = pieceSpan * 0.75;
    return bestDistance <= reach * reach ? best : null;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.game,
    required this.config,
    required this.board,
    required this.position,
    required this.flipped,
    required this.selected,
    required this.targets,
    required this.origins,
    required this.highlights,
    required this.lastMove,
  });

  final ArenaGame game;
  final GameConfig config;
  final BoardSpec board;
  final ArenaPosition position;
  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final Set<int> origins;
  final Set<int> highlights;
  final Set<int> lastMove;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(board, size.width, flipped);
    _paintSurface(canvas, size, g);
    _paintMarkers(canvas, g);
    _paintPieces(canvas, g);
    if (board.showFileRank) _paintCoordinates(canvas, g);
  }

  void _paintSurface(Canvas canvas, Size size, _Geometry g) {
    final rect = Offset.zero & size;
    final radius = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    switch (board.style) {
      case BoardStyle.checkered:
        canvas.drawRRect(
          radius,
          Paint()..color = Color(board.lightSquare),
        );
        final dark = Paint()..color = Color(board.darkSquare);
        canvas.save();
        canvas.clipRRect(radius);
        for (var i = 0; i < board.cells; i++) {
          if ((board.colOf(i) + board.rowOf(i)) % 2 == 0) continue;
          final centre = g.centreOf(i);
          canvas.drawRect(
            Rect.fromCenter(center: centre, width: g.cell, height: g.cell),
            dark,
          );
        }
        canvas.restore();

      case BoardStyle.lines:
        canvas.drawRRect(radius, Paint()..color = Color(board.surface));
        final line = Paint()
          ..color = const Color(0x99000000)
          ..strokeWidth = 1;
        final first = g.centreOf(_unflipped(0));
        final last = g.centreOf(_unflipped(board.cells - 1));
        for (var i = 0; i < board.cols; i++) {
          final x = first.dx + (last.dx - first.dx) * i / (board.cols - 1);
          canvas.drawLine(Offset(x, first.dy), Offset(x, last.dy), line);
          final y = first.dy + (last.dy - first.dy) * i / (board.rows - 1);
          canvas.drawLine(Offset(first.dx, y), Offset(last.dx, y), line);
        }
        _paintStarPoints(canvas, g, line);

      case BoardStyle.cells:
        canvas.drawRRect(radius, Paint()..color = Color(board.surface));
        final line = Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
        for (var i = 0; i < board.cells; i++) {
          canvas.drawRect(
            Rect.fromCenter(
              center: g.centreOf(i),
              width: g.cell,
              height: g.cell,
            ),
            line,
          );
        }
    }
  }

  /// Go's handicap dots. Cosmetic, but their absence is the first thing a go
  /// player notices, and they double as a coordinate aid on a big board.
  ///
  /// The full three-by-three grid of nine belongs to a 19×19 board only. The
  /// smaller boards carry five — the four corner points and the centre — and
  /// the four extra side points a naive `[a, b, c] × [a, b, c]` produces are
  /// wrong in the same way as a chessboard with the wrong square colour in
  /// the corner: harmless to play on, and immediately noticed.
  void _paintStarPoints(Canvas canvas, _Geometry g, Paint line) {
    final size = board.cols;
    final edge = switch (size) {
      19 => 3,
      13 => 3,
      9 => 2,
      _ => -1,
    };
    if (edge < 0) return;
    final mid = size ~/ 2;

    final points = <(int, int)>[
      (edge, edge),
      (edge, size - 1 - edge),
      (size - 1 - edge, edge),
      (size - 1 - edge, size - 1 - edge),
      (mid, mid),
      if (size == 19) ...[
        (edge, mid),
        (mid, edge),
        (mid, size - 1 - edge),
        (size - 1 - edge, mid),
      ],
    ];

    final dot = Paint()..color = const Color(0xCC000000);
    // Scaled to the board: a fixed 3px dot is a blob on a 9×9 and invisible
    // on a 19×19.
    final radius = (g.pieceSpan * 0.10).clamp(1.5, 4.0);
    for (final (col, row) in points) {
      canvas.drawCircle(g.centreOf(board.index(col, row)), radius, dot);
    }
  }

  int _unflipped(int index) => index;

  void _paintMarkers(Canvas canvas, _Geometry g) {
    void mark(int index, Color color, {bool ring = false}) {
      final centre = g.centreOf(index);
      if (ring) {
        canvas.drawCircle(
          centre,
          g.pieceSpan * 0.42,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      } else {
        canvas.drawCircle(centre, g.pieceSpan * 0.16, Paint()..color = color);
      }
    }

    for (final index in lastMove) {
      final centre = g.centreOf(index);
      canvas.drawRect(
        Rect.fromCenter(
          center: centre,
          width: g.pieceSpan,
          height: g.pieceSpan,
        ),
        Paint()..color = const Color(0x40FFD54F),
      );
    }
    for (final index in highlights) {
      mark(index, const Color(0x66DC2626), ring: true);
    }
    // Whose turn it is, said on the board rather than only in the status line.
    //
    // A player looking at a chessboard is looking at the pieces, not at a
    // caption above them, and "is it me?" was costing a glance away every
    // time. Every piece with a legal move gets a soft disc behind it, so the
    // side to move is legible from the board alone — and, usefully for a
    // beginner, so is the fact that a pinned piece has nothing it may do.
    for (final index in origins) {
      if (index == selected) continue;
      final centre = g.centreOf(index);
      canvas
        ..drawCircle(
          centre,
          g.pieceSpan * 0.46,
          Paint()..color = const Color(0x3316A34A),
        )
        ..drawCircle(
          centre,
          g.pieceSpan * 0.46,
          Paint()
            ..color = const Color(0x5516A34A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
    }
    if (selected != null) {
      mark(selected!, const Color(0xCC16A34A), ring: true);
    }
    for (final index in targets) {
      final occupied = position.at(index) != 0;
      if (occupied) {
        mark(index, const Color(0xAA16A34A), ring: true);
      } else {
        mark(index, const Color(0x8816A34A));
      }
    }
  }

  void _paintPieces(Canvas canvas, _Geometry g) {
    for (var i = 0; i < board.cells; i++) {
      final art = game.art(position.at(i));
      if (art == null) continue;
      final centre = g.centreOf(i);
      final colour = Color(game.sideColors[art.side]);
      final radius = g.pieceSpan * art.scale / 2;

      if (art.figure == null) {
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..color = const Color(0x33000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        canvas.drawCircle(centre, radius, Paint()..color = colour);
        // Rimmed against the board rather than in a neutral grey: a black go
        // stone on dark wood, or a black checker on a dark square, needs an
        // edge that is not the colour it is sitting on.
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..color = art.side == 0
                ? const Color(0x59000000)
                : const Color(0x8AFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, radius * 0.09),
        );
        if (art.crowned) _paintCrown(canvas, centre, radius, art.side);
      } else {
        _paintFigure(canvas, centre, radius, art, colour);
      }
    }
  }

  /// A checkers king. Two stacked rings read better at 30 logical pixels than
  /// any crown glyph, which turns to mud at that size.
  void _paintCrown(Canvas canvas, Offset centre, double radius, int side) {
    final ink = side == 0 ? const Color(0xFF7F1D1D) : const Color(0xFFF9FAFB);
    canvas.drawCircle(
      centre,
      radius * 0.55,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      centre,
      radius * 0.28,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// A chess piece, drawn from a vector outline and tinted.
  ///
  /// Both sides share the silhouette: White is the shape filled light with a
  /// dark rim, Black the same shape filled dark with a light rim. That is why
  /// the two armies always match in weight, which the Unicode figurines this
  /// replaced never did.
  void _paintFigure(
    Canvas canvas,
    Offset centre,
    double radius,
    PieceArt art,
    Color colour,
  ) {
    // The rim is the opposing army's colour, which is what keeps an ivory
    // piece readable on a light square and a black one readable on a dark
    // square. Without it each side vanishes into half the board.
    final rim =
        art.side == 0 ? const Color(0xFF16161A) : const Color(0xFFF4EBDC);
    final box = Rect.fromCenter(
      center: centre,
      width: radius * 2,
      height: radius * 2,
    );
    final path = chessFigurePath(art.figure!, box);

    // Lifts the piece off the square. Small, but it is what stops a dark
    // piece on a dark square reading as a hole in the board.
    canvas
      ..save()
      ..translate(0, radius * 0.06)
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0x38000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      )
      ..restore()
      ..drawPath(path, Paint()..color = colour)
      ..drawPath(
        path,
        Paint()
          ..color = rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.1, radius * 0.085)
          ..strokeJoin = StrokeJoin.round,
      );
  }

  void _paintCoordinates(Canvas canvas, _Geometry g) {
    for (var col = 0; col < board.cols; col++) {
      final index = board.index(col, board.rows - 1);
      final centre = g.centreOf(index);
      _label(
        canvas,
        String.fromCharCode(97 + col),
        Offset(centre.dx - g.cell / 2 + 3, centre.dy + g.cell / 2 - 12),
      );
    }
    for (var row = 0; row < board.rows; row++) {
      final index = board.index(0, row);
      final centre = g.centreOf(index);
      _label(
        canvas,
        '${board.rows - row}',
        Offset(centre.dx - g.cell / 2 + 3, centre.dy - g.cell / 2 + 2),
      );
    }
  }

  void _label(Canvas canvas, String text, Offset at) {
    TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Color(0x99000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.position != position ||
      old.selected != selected ||
      old.flipped != flipped ||
      !setEquals(old.targets, targets) ||
      !setEquals(old.lastMove, lastMove) ||
      !setEquals(old.highlights, highlights);
}

bool setEquals(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);
