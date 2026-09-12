import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The coin every sport's toss is thrown with.
///
/// The toss used to resolve on `millisecondsSinceEpoch % 2` behind a snackbar:
/// no throw to watch, and a result that read the clock instead of chance. Two
/// matches started in the same millisecond got the same winner, and a scorer
/// who reopened the sheet a moment later could see the answer change under
/// them.
///
/// This is the throw. The coin is a real cylinder — two elliptical faces and
/// the milled band between them — spun about its diameter, carried through an
/// arc and set down on the face that won, so the edge shows itself as it
/// passes through the vertical and the landing is watched rather than read.
///
/// Driven by the screen that owns the toss rather than owning the toss itself:
/// [flip] throws it, [settleOn] turns it to a face without a throw for a toss
/// that was taken at the ground, and [onLanded] reports the face it stopped on.
/// Heads is side A and tails side B, and the caller states that before the
/// coin leaves the hand — a mapping revealed only after the result is one
/// nobody can check.
class TossCoin extends StatefulWidget {
  const TossCoin({
    super.key,
    required this.headsLabel,
    required this.tailsLabel,
    required this.onLanded,
    this.height = 300,
  });

  final String headsLabel;
  final String tailsLabel;

  /// True when it came down heads — side A.
  final ValueChanged<bool> onLanded;

  final double height;

  @override
  State<TossCoin> createState() => TossCoinState();
}

class TossCoinState extends State<TossCoin>
    with SingleTickerProviderStateMixin {
  /// Chance, not the clock. `Random.secure()` costs nothing at one throw per
  /// match and removes the last way a toss could be predicted or repeated.
  static final math.Random _rng = math.Random.secure();

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..addStatusListener(_onStatus);

  /// Where the coin is standing between throws: 0 shows heads, pi tails.
  double _restAngle = 0;

  /// Rotation of the throw in progress, from [_restAngle].
  double _sweep = 0;

  bool? _pending;

  bool get isFlipping => _c.isAnimating;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    HapticFeedback.mediumImpact();
    widget.onLanded(_pending!);
    // Fold the finished throw into the resting angle so the next one is
    // measured from where this one stopped. `_restAngle + _sweep` is the angle
    // already on screen, so rewinding the controller under it changes nothing
    // visually — and post-frame because a controller must not be driven from
    // inside its own status callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _restAngle += _sweep;
        _sweep = 0;
      });
      _c.reset();
    });
  }

  /// Throw it.
  void flip() {
    if (_c.isAnimating) return;
    final heads = _rng.nextBool();
    // It must come to rest showing the face that won, so the sweep is whole
    // turns from where it stands plus the half-turn that brings the other face
    // up. Six to nine turns keeps a fast spin legible without the result
    // feeling arbitrary in how long it takes to arrive.
    final turns = 6 + _rng.nextInt(4);
    final target = heads ? 0.0 : math.pi;
    var sweep = 2 * math.pi * turns + (target - _restAngle % (2 * math.pi));
    if (sweep < 0) sweep += 2 * math.pi;
    setState(() {
      _pending = heads;
      _sweep = sweep;
    });
    HapticFeedback.lightImpact();
    _c.forward(from: 0);
  }

  /// Turn it to a face without throwing it — the toss happened at the ground
  /// and is being entered by hand, so animating a throw would misrepresent
  /// where the result came from.
  void settleOn(bool heads) {
    if (_c.isAnimating) return;
    setState(() {
      _pending = heads;
      _restAngle = heads ? 0 : math.pi;
      _sweep = 0;
    });
    _c.reset();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Tall enough for the whole throw: the coin has to clear its own arc at
      // the top and set its shadow down at the bottom without either landing
      // on whatever sits below it.
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final d = math.min(box.maxWidth * 0.62, widget.height * 0.59);
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              // One eased clock drives rotation and arc together, so the coin
              // is back down at the instant it stops turning instead of
              // hanging over its own landing.
              final rotT = Curves.easeOutCubic.transform(t);
              // A struck coin rocks on its rim before it settles; this dies to
              // exactly zero at the end of the throw.
              final settle = _c.isAnimating
                  ? 0.07 * math.exp(-14 * (1 - t)) * math.sin(30 * (1 - t))
                  : 0.0;
              return CustomPaint(
                size: Size(box.maxWidth, widget.height),
                painter: _CoinPainter(
                  angle: _restAngle + _sweep * rotT + settle,
                  lift: math.sin(math.pi * rotT),
                  diameter: d,
                  headsName: widget.headsLabel,
                  tailsName: widget.tailsLabel,
                  shadow: Theme.of(context).colorScheme.shadow,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The coin itself, as a solid rather than a picture of a circle.
///
/// Rotating a cylinder about its horizontal diameter projects each face to an
/// ellipse of unchanged width and height `r * |cos angle|`, with the two face
/// centres separated vertically by `2 * halfThickness * sin angle`. The
/// silhouette between them is exactly a rectangle of the coin's full width, so
/// drawing far face, band, near face in that order gives a true cylinder with
/// no clipping — and the edge shows itself honestly as the coin passes through
/// the vertical, which is the frame that sells a flip.
class _CoinPainter extends CustomPainter {
  _CoinPainter({
    required this.angle,
    required this.lift,
    required this.diameter,
    required this.headsName,
    required this.tailsName,
    required this.shadow,
  });

  final double angle;

  /// 0 on the ground, 1 at the top of the arc.
  final double lift;
  final double diameter;
  final String headsName;
  final String tailsName;
  final Color shadow;

  static const _gold = Color(0xFFE8B923);
  static const _goldLight = Color(0xFFFFF0A8);
  static const _goldMid = Color(0xFFD9A520);
  static const _goldDeep = Color(0xFF9A6E08);
  static const _goldShade = Color(0xFF6B4B04);
  static const _ink = Color(0xFF4A3505);

  @override
  void paint(Canvas canvas, Size size) {
    final r = diameter / 2;
    final halfThick = r * 0.085;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final restY = size.height * 0.62;
    final arc = size.height * 0.25;
    final cx = size.width / 2;
    final cy = restY - arc * lift;

    _paintGroundShadow(canvas, cx, restY, r);

    // Nearer to the eye at the top of the arc.
    final scale = 1 + 0.10 * lift;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);

    // The +normal face carries heads and sits at screen y = -h*sin; it is the
    // nearer of the two whenever its normal still points at the viewer.
    final headsNear = cosA >= 0;
    final headsY = -halfThick * sinA;
    final tailsY = halfThick * sinA;
    final nearY = headsNear ? headsY : tailsY;
    final farY = headsNear ? tailsY : headsY;

    final faceRy = r * cosA.abs();

    _paintFace(canvas, farY, r, faceRy, isNear: false, heads: !headsNear);
    _paintBand(canvas, r, nearY, farY);
    _paintFace(canvas, nearY, r, faceRy, isNear: true, heads: headsNear);

    canvas.restore();
  }

  void _paintGroundShadow(Canvas canvas, double cx, double restY, double r) {
    // Tightens and darkens as the coin comes down, which is what tells the eye
    // the arc is depth and not just vertical travel.
    final w = r * (1.05 - 0.42 * lift);
    final h = r * (0.20 - 0.07 * lift);
    final rect = Rect.fromCenter(
      center: Offset(cx, restY + r * 0.86),
      width: w * 2,
      height: h * 2,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = shadow.withValues(alpha: 0.28 * (1 - 0.62 * lift))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
  }

  /// The milled band joining the two faces.
  void _paintBand(Canvas canvas, double r, double nearY, double farY) {
    final top = math.min(nearY, farY);
    final bottom = math.max(nearY, farY);
    if (bottom - top < 0.25) return;
    final rect = Rect.fromLTRB(-r, top, r, bottom);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [_goldShade, _goldMid, _goldLight, _goldMid, _goldShade],
          stops: [0.0, 0.28, 0.5, 0.72, 1.0],
        ).createShader(rect),
    );

    // Reeding. Spacing the grooves by cos of an even angle sweep bunches them
    // towards the rim exactly as they foreshorten on a real coin.
    final groove = Paint()..strokeWidth = math.max(0.6, r * 0.012);
    for (var i = 1; i < 44; i++) {
      final th = i / 44 * math.pi;
      final x = r * math.cos(th);
      groove.color = _goldShade.withValues(alpha: 0.38 * math.sin(th));
      canvas.drawLine(Offset(x, top), Offset(x, bottom), groove);
    }
  }

  /// One face, squashed into its ellipse by the rotation.
  void _paintFace(
    Canvas canvas,
    double dy,
    double r,
    double faceRy, {
    required bool isNear,
    required bool heads,
  }) {
    if (faceRy < 0.4) return;

    canvas.save();
    canvas.translate(0, dy);
    // Everything below is drawn on a full circle of radius r; the vertical
    // squash applies the foreshortening once, to the artwork as well as the
    // disc, so the emblem turns with the coin instead of sliding across it.
    canvas.scale(1, faceRy / r);

    final bounds = Rect.fromCircle(center: Offset.zero, radius: r);

    // Body, lit from the upper left.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.42, -0.46),
          radius: 0.95,
          colors: [_goldLight, _gold, _goldMid, _goldDeep],
          stops: [0.0, 0.42, 0.74, 1.0],
        ).createShader(bounds),
    );

    // Raised rim.
    canvas.drawCircle(
      Offset.zero,
      r * 0.945,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.085
        ..shader = const SweepGradient(
          colors: [
            _goldDeep,
            _goldLight,
            _goldMid,
            _goldLight,
            _goldDeep,
            _goldShade,
            _goldDeep,
          ],
          stops: [0.0, 0.16, 0.34, 0.55, 0.72, 0.88, 1.0],
        ).createShader(bounds),
    );

    canvas.drawCircle(
      Offset.zero,
      r * 0.80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.016)
        ..color = _goldShade.withValues(alpha: 0.55),
    );

    // Beading just inside the rim.
    final bead = Paint()..color = _goldShade.withValues(alpha: 0.42);
    for (var i = 0; i < 36; i++) {
      final th = i / 36 * 2 * math.pi;
      canvas.drawCircle(
        Offset(r * 0.87 * math.cos(th), r * 0.87 * math.sin(th)),
        r * 0.016,
        bead,
      );
    }

    _text(canvas, heads ? 'HEADS' : 'TAILS', Offset(0, -r * 0.52),
        r * 0.145, FontWeight.w700, 2.4);
    _text(canvas, heads ? 'H' : 'T', Offset(0, -r * 0.08),
        r * 0.58, FontWeight.w900, 0);
    _text(canvas, heads ? headsName : tailsName, Offset(0, r * 0.46),
        r * 0.135, FontWeight.w600, 0.4, maxWidth: r * 1.34);

    // Specular sweep, and a wash of shade on the face that is turned away.
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.70),
      math.pi * 1.12,
      math.pi * 0.52,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.10
        ..color = Colors.white.withValues(alpha: 0.22),
    );

    if (!isNear) {
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()..color = _goldShade.withValues(alpha: 0.45),
      );
    }

    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at,
    double size,
    FontWeight weight,
    double spacing, {
    double? maxWidth,
  }) {
    if (size < 1) return;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: _ink,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);

    final origin = Offset(at.dx - tp.width / 2, at.dy - tp.height / 2);
    // Struck, not printed: a light ghost below the letter reads as relief.
    final ghost = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: _goldLight.withValues(alpha: 0.55),
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    ghost.paint(canvas, origin + Offset(0, math.max(0.7, size * 0.045)));
    tp.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.angle != angle ||
      old.lift != lift ||
      old.diameter != diameter ||
      old.headsName != headsName ||
      old.tailsName != tailsName;
}
