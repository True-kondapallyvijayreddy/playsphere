import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/arena/games/chess_game.dart';

/// The six chess pieces, drawn as vector silhouettes.
///
/// ## Why not the Unicode figurines
///
/// '♞' is one character and no code, which is why the board used it first. It
/// is also a code point in a symbol block that a device is free not to have a
/// font for — and the failure is not a slightly plainer knight, it is a tofu
/// box where a piece should be, on every square, with the game unplayable.
/// Android's symbol coverage varies by version and vendor; a web build depends
/// on whatever the browser falls back to. That is a lot of ways for a
/// chessboard to break for reasons nothing in this app controls.
///
/// Paths render identically everywhere, scale to any square size without
/// hinting artefacts, and let both sides share one silhouette so a black
/// bishop is exactly a white bishop filled dark — which the two Unicode
/// families are not: they come from different parts of the font and land at
/// visibly different weights.
///
/// Each piece is composed from primitives — circles, trapezoids, a stepped
/// polygon — in a normalised 0–1 box, then scaled. Composition rather than one
/// continuous outline because a silhouette assembled from named parts can be
/// adjusted a part at a time.
void drawChessFigure(
  Canvas canvas,
  Rect box,
  int kind,
  Paint fill,
  Paint outline,
) {
  final path = chessFigurePath(kind, box);
  canvas.drawPath(path, fill);
  canvas.drawPath(path, outline);
}

/// The silhouette, in [box].
///
/// The parts are UNIONED into a single outline rather than added to one path
/// as overlapping subpaths. That distinction is the difference between a piece
/// and a smudge: stroking a path made of overlapping subpaths outlines every
/// internal seam too, so a queen's five crown beads and her collar and her
/// stem all get rimmed where they meet, and at the ~45dp a square actually
/// gets on a phone the accumulated dark seams swallow the fill — a white
/// queen came out reading as a black one. One merged outline strokes only the
/// true edge.
Path chessFigurePath(int kind, Rect box) {
  final w = box.width;
  final h = box.height;
  double x(double t) => box.left + w * t;
  double y(double t) => box.top + h * t;

  // Every piece stands on the same foot, which is what makes a row of them
  // look like a set rather than six unrelated drawings.
  Path base() => Path()
    ..addRRect(
      RRect.fromLTRBR(
        x(0.13),
        y(0.80),
        x(0.87),
        y(0.94),
        Radius.circular(h * 0.035),
      ),
    )
    ..addRRect(
      RRect.fromLTRBR(
        x(0.22),
        y(0.72),
        x(0.78),
        y(0.82),
        Radius.circular(h * 0.025),
      ),
    );

  /// The tapered stem from the foot up to [top], [halfWidth] wide there.
  Path stem(double top, double halfWidth) => Path()
    ..moveTo(x(0.5 - halfWidth), y(top))
    ..lineTo(x(0.5 + halfWidth), y(top))
    ..lineTo(x(0.72), y(0.74))
    ..lineTo(x(0.28), y(0.74))
    ..close();

  /// The ring most pieces wear where the stem meets the head.
  Path collar(double top, double bottom, double halfWidth) => Path()
    ..addRRect(
      RRect.fromLTRBR(
        x(0.5 - halfWidth),
        y(top),
        x(0.5 + halfWidth),
        y(bottom),
        Radius.circular(h * 0.02),
      ),
    );

  final parts = <Path>[];

  switch (kind) {
    case ChessGame.pawn:
      parts
        ..add(base())
        ..add(stem(0.46, 0.11))
        ..add(collar(0.42, 0.50, 0.20))
        ..add(Path()
          ..addOval(Rect.fromCircle(
            center: Offset(x(0.5), y(0.30)),
            radius: w * 0.155,
          )));

    case ChessGame.rook:
      parts
        ..add(base())
        ..add(stem(0.44, 0.16))
        ..add(collar(0.40, 0.48, 0.26));
      // The battlement: a block with two notches cut out of the top.
      final crown = Path()
        ..moveTo(x(0.22), y(0.42))
        ..lineTo(x(0.22), y(0.20))
        ..lineTo(x(0.34), y(0.20))
        ..lineTo(x(0.34), y(0.28))
        ..lineTo(x(0.43), y(0.28))
        ..lineTo(x(0.43), y(0.20))
        ..lineTo(x(0.57), y(0.20))
        ..lineTo(x(0.57), y(0.28))
        ..lineTo(x(0.66), y(0.28))
        ..lineTo(x(0.66), y(0.20))
        ..lineTo(x(0.78), y(0.20))
        ..lineTo(x(0.78), y(0.42))
        ..close();
      parts.add(crown);

    case ChessGame.bishop:
      parts
        ..add(base())
        ..add(stem(0.52, 0.12))
        ..add(collar(0.48, 0.56, 0.22));
      // The mitre: a teardrop, wide at the shoulders and drawn to a point.
      final mitre = Path()
        ..moveTo(x(0.5), y(0.14))
        ..cubicTo(x(0.76), y(0.26), x(0.74), y(0.42), x(0.62), y(0.50))
        ..lineTo(x(0.38), y(0.50))
        ..cubicTo(x(0.26), y(0.42), x(0.24), y(0.26), x(0.5), y(0.14))
        ..close();
      parts
        ..add(mitre)
        ..add(Path()
          ..addOval(Rect.fromCircle(
            center: Offset(x(0.5), y(0.11)),
            radius: w * 0.055,
          )));

    case ChessGame.knight:
      // A horse's head in profile, facing left — the one piece that is a
      // drawing rather than an assembly, so it is a single traced outline.
      parts
        ..add(base())
        ..add(
          Path()
            ..moveTo(x(0.30), y(0.74))
            ..lineTo(x(0.74), y(0.74))
            // Down the back of the neck.
            ..cubicTo(x(0.76), y(0.54), x(0.74), y(0.36), x(0.62), y(0.24))
            // Ear.
            ..lineTo(x(0.66), y(0.11))
            ..lineTo(x(0.53), y(0.19))
            // Over the brow and down the face to the muzzle.
            ..cubicTo(x(0.44), y(0.15), x(0.32), y(0.20), x(0.25), y(0.31))
            ..lineTo(x(0.15), y(0.44))
            ..cubicTo(x(0.12), y(0.49), x(0.15), y(0.53), x(0.21), y(0.52))
            // The jaw, then down into the chest.
            ..lineTo(x(0.33), y(0.48))
            ..cubicTo(x(0.30), y(0.58), x(0.30), y(0.66), x(0.30), y(0.74))
            ..close(),
        );

    case ChessGame.queen:
      parts
        ..add(base())
        ..add(stem(0.50, 0.14))
        ..add(collar(0.46, 0.54, 0.26));
      // A coronet: five points, each finished with a bead.
      final crown = Path()..moveTo(x(0.24), y(0.48));
      const peaks = [0.24, 0.37, 0.50, 0.63, 0.76];
      for (var i = 0; i < peaks.length; i++) {
        crown
          ..lineTo(x(peaks[i]), y(i.isEven ? 0.20 : 0.28))
          ..lineTo(x(peaks[i] + 0.065), y(0.40));
      }
      crown
        ..lineTo(x(0.76), y(0.48))
        ..close();
      parts.add(crown);
      for (var i = 0; i < peaks.length; i++) {
        parts.add(Path()
          ..addOval(Rect.fromCircle(
            center: Offset(x(peaks[i]), y(i.isEven ? 0.19 : 0.27)),
            radius: w * 0.058,
          )));
      }

    case ChessGame.king:
      parts
        ..add(base())
        ..add(stem(0.52, 0.14))
        ..add(collar(0.48, 0.56, 0.26))
        // The crown, cinched at the waist.
        ..add(
          Path()
            ..moveTo(x(0.26), y(0.50))
            ..lineTo(x(0.30), y(0.32))
            ..lineTo(x(0.42), y(0.40))
            ..lineTo(x(0.5), y(0.30))
            ..lineTo(x(0.58), y(0.40))
            ..lineTo(x(0.70), y(0.32))
            ..lineTo(x(0.74), y(0.50))
            ..close(),
        )
        // The cross on top, drawn chunky enough to survive being scaled down
        // to a phone square.
        ..add(Path()
          ..addRect(Rect.fromLTRB(x(0.44), y(0.05), x(0.56), y(0.34))))
        ..add(Path()
          ..addRect(Rect.fromLTRB(x(0.35), y(0.125), x(0.65), y(0.235))));

    default:
      parts.add(Path()
        ..addOval(
          Rect.fromCircle(center: box.center, radius: math.min(w, h) * 0.4),
        ));
  }

  // Fold the parts into one outline. `union` also drops the seams where two
  // parts meet, which is the whole point — see this function's own note.
  var merged = parts.first;
  for (final part in parts.skip(1)) {
    merged = Path.combine(PathOperation.union, merged, part);
  }
  return merged;
}
