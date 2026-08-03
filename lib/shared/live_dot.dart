import 'package:flutter/material.dart';

/// The pulsing red dot that marks a match as being played right now.
///
/// Shared rather than redeclared per screen: it existed as a byte-identical
/// private widget on both the home dashboard and the club home, and the
/// reduce-motion handling below is exactly the kind of thing that gets fixed
/// in one copy and not the other.
///
/// The pulse stops for anyone who has asked their phone to reduce motion.
/// That setting is not decoration — it is what people with vestibular
/// disorders use to keep an interface usable — and a dashboard listing
/// several live matches would otherwise put several independent tickers on
/// screen, each holding the raster pipeline awake indefinitely on exactly the
/// 2GB devices CLAUDE.md §2.8 targets. With motion off the dot stays solid,
/// so it still reads as live; only the animation goes.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 10});

  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than initState because it reads MediaQuery, and it must run
    // again when the setting changes — the user can turn reduce-motion on
    // while the app is open and expect it to take effect.
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.35, end: 1.0)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          color: Color(0xFFDC2626),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
