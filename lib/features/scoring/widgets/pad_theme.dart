import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui_kit.dart';

/// The visual language every scoring pad is drawn in.
///
/// ## Why the pads get their own tokens
///
/// [Ps] is the app's palette and it is deliberately flat: hairline borders,
/// no shadows, a cool slate ramp. That is right for a screen you read —
/// a club page, a fixture list, a profile — where flatness keeps a dense page
/// calm.
///
/// A scoring pad is not a screen you read. It is an instrument, held at
/// arm's length, in daylight, by somebody who is watching the game rather
/// than the phone and who has to hit the right key without looking straight
/// at it. Flat tiles of equal weight are the worst possible surface for that:
/// nothing separates from anything, a press gives no acknowledgement, and the
/// key that ends an innings looks like the key that scores a single.
///
/// So the pads add depth, and only the pads. Everything here derives from
/// [Ps] rather than restating it — the brand green, the live red and the
/// slate ramp are still the app's — so a pad reads as the same product, one
/// surface further forward.
class PadInk {
  const PadInk._();

  // --- The board --------------------------------------------------------

  /// The scoreboard gradient. Near-black at the top so white numerals sit at
  /// maximum contrast, lifting to a blue-slate at the bottom so the panel has
  /// a direction and does not read as a flat black rectangle.
  static const Color boardTop = Color(0xFF080D18);
  static const Color boardMid = Color(0xFF0E1729);
  static const Color boardBottom = Color(0xFF16233C);

  /// The hairline INSIDE the board, one step lighter than the board itself.
  /// A border drawn in [Ps.border] around a near-black panel reads as a halo.
  static const Color boardEdge = Color(0xFF243350);

  /// Secondary text on the board. [Ps.faint] is tuned for white paper and
  /// disappears at 9pt on near-black.
  static const Color boardMuted = Color(0xFF94A3B8);

  // --- Tiles ------------------------------------------------------------

  /// The neutral key: everything that is neither the primary action nor
  /// destructive. Slate rather than grey so it sits in the same family as the
  /// board above it.
  static const Color slate = Color(0xFF334155);

  /// The attention colour for a state that changes what the next press may
  /// be — a free hit, a new batter due. Amber is the only warm hue on the
  /// pad, which is what makes it impossible to miss.
  static const Color amber = Color(0xFFF59E0B);

  // --- Depth ------------------------------------------------------------

  /// A panel sitting on the page: the crease table, the ball strip.
  ///
  /// Two shadows rather than one. The tight, nearly-opaque first shadow is
  /// the contact edge that stops the panel floating; the wide, faint second
  /// is the ambient light. One shadow can be either crisp or soft and gets
  /// the other wrong.
  static const List<BoxShadow> panel = [
    BoxShadow(
      color: Color(0x0F0F172A),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x14172554),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  /// The scoreboard, which sits above everything else and casts accordingly.
  static const List<BoxShadow> board = [
    BoxShadow(
      color: Color(0x1A0F172A),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x2E0B1220),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  /// A key at rest. Tinted with the key's own accent rather than grey, so a
  /// red key casts a red shadow — the cheapest way to make a destructive
  /// control feel destructive before it is read.
  static List<BoxShadow> key(Color accent, {required bool filled}) => [
        BoxShadow(
          color: accent.withValues(alpha: filled ? 0.30 : 0.10),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: accent.withValues(alpha: filled ? 0.16 : 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// A key under the thumb. Not "no shadow": a key that loses its shadow
  /// entirely on press appears to fall through the screen. It sinks.
  static List<BoxShadow> keyPressed(Color accent) => [
        BoxShadow(
          color: accent.withValues(alpha: 0.22),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  /// The fill of a solid key.
  ///
  /// A vertical gradient from a lightened accent to the accent itself, which
  /// is what gives a flat rectangle the read of a moulded key. The lift is
  /// small — a flashy gradient on twenty keys at once is a toy, and this pad
  /// is used by officials.
  static LinearGradient keyFill(Color accent) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(accent, Colors.white, 0.18)!,
          accent,
          Color.lerp(accent, Colors.black, 0.06)!,
        ],
        stops: const [0, 0.55, 1],
      );

  /// The fill of a hollow key: a barely-there wash of its accent over the
  /// card surface, so the key still belongs to its group by colour.
  static LinearGradient keyGhost(Color accent) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(Ps.surface, accent, 0.05)!,
          Color.lerp(Ps.surface, accent, 0.11)!,
        ],
      );

  /// Numerals that do not shift as they change.
  ///
  /// Every number on a pad is live: a total that reflows from 99 to 100, or a
  /// strike rate whose digits jog sideways on each ball, is read as movement
  /// on a screen the scorer is only glancing at. Tabular figures hold column.
  static const List<FontFeature> figures = [FontFeature.tabularFigures()];
}

/// A key that acknowledges the thumb.
///
/// ## Why this is not just an `InkWell`
///
/// A Material ripple is a poor fit for a scoring pad and the reason is
/// timing, not taste. The ripple expands over ~300ms and reads as feedback
/// AFTER the press; a scorer tapping four balls in an over is already moving
/// to the next key while the last ripple is still growing, so the pad appears
/// to lag the hand. Worse, on the one surface where a mis-tap is a wrong
/// scoreline, a ripple never says WHICH key took the press — it says only
/// that somewhere was touched.
///
/// A key that sinks under the finger says both, immediately: the thing that
/// moved is the thing that was pressed, and it moved at the moment of
/// contact. The haptic tick is the same message through a second sense, which
/// is what makes the pad usable without looking at it.
class PadPressable extends StatefulWidget {
  const PadPressable({
    super.key,
    required this.builder,
    required this.onTap,
    this.borderRadius,
  });

  /// Built with whether the key is currently held, so the caller can swap its
  /// own shadow and fill rather than having them imposed here.
  final Widget Function(BuildContext context, bool pressed) builder;

  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  State<PadPressable> createState() => _PadPressableState();
}

class _PadPressableState extends State<PadPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v || !mounted) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTap: enabled
          ? () {
              // Fired here rather than on tap-down so a press the scorer
              // slides off — the standard way to abandon a mis-aimed tap —
              // neither buzzes nor scores.
              HapticFeedback.selectionClick();
              widget.onTap!.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down && enabled ? 0.955 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.builder(context, _down && enabled),
      ),
    );
  }
}
