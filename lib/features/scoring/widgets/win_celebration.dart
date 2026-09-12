import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui_kit.dart';

/// The five seconds after the last point.
///
/// ## Why this exists
///
/// The pad already knew the match was over — the engine flips `complete`, the
/// service writes `status: completed`, the controls swap for a "Reopen". What
/// none of that did was ANNOUNCE it. A scorer looking at the court, two
/// players standing at the umpire's chair and a parent holding a phone all
/// got the same thing: a screen that quietly stopped offering buttons. The
/// moment a match is won is the moment the whole app exists for, and it was
/// the only moment with no design on it at all.
///
/// So: the winner's name, big, for five seconds, over confetti, and then it
/// takes itself away. Deliberately time-boxed rather than waiting to be
/// dismissed — the scorer's hands are busy and the next thing they need is
/// the scorecard, not a modal to close. Tapping ends it early.
///
/// ## Why it is not a package
///
/// Every confetti package on pub is a dependency, a licence, a platform
/// surface and a rebuild for eighty lines of arithmetic. [_ConfettiPainter]
/// below is those eighty lines: deterministic from a seed, so the same match
/// celebrates the same way if the widget rebuilds mid-flight, and it paints
/// nothing once the animation has run out.
///
/// ## Why it takes strings, not a Fixture
///
/// Every sport ends differently and none of that difference belongs here.
/// A cricket innings, a badminton rubber, a kabaddi raid and an awarded
/// walkover all reduce to the same three facts — who won, what the score was,
/// what kind of result it was — and the caller is the only thing that knows
/// how its sport says them. Keeping this widget ignorant of the sport is what
/// makes "for all sports" true by construction rather than by a switch
/// statement somebody has to remember to extend.
class WinCelebration extends StatefulWidget {
  const WinCelebration({
    super.key,
    required this.title,
    this.subtitle,
    this.kicker,
    this.duration = const Duration(seconds: 5),
  });

  /// The headline. "Vijay won", "Hyderabad Strikers won", "Match drawn".
  final String title;

  /// The score, in the sport's own words. Optional: a walkover has none.
  final String? subtitle;

  /// What kind of ending this was, when it was not a normal one —
  /// "Walkover", "Retired", "Disqualified". Null for a match played out.
  final String? kicker;

  /// How long it stays. Five seconds by design: long enough to be read out
  /// loud to two players, short enough that nobody waits for it.
  final Duration duration;

  @override
  State<WinCelebration> createState() => _WinCelebrationState();
}

class _WinCelebrationState extends State<WinCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  /// Fixed per instance, so a rebuild — a keyboard opening, a rotation, the
  /// fixture listener delivering the same result again — does not re-scatter
  /// the confetti into a different pattern halfway through the fall.
  final int _seed = DateTime.now().microsecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    // The physical half of the announcement. A scorer whose eyes are on the
    // court finds out the match is over through their hand.
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Entry is fast and the exit is a fade over the last half second, both as
    // a fraction of the total so a caller that shortens `duration` gets a
    // proportionally quicker animation rather than a clipped one.
    final enter = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.12, curve: Curves.easeOutBack),
    );
    final leave = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.88, 1, curve: Curves.easeIn),
    );

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Opacity(
          opacity: 1 - leave.value,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _ConfettiPainter(progress: _c.value, seed: _seed),
              ),
              Center(
                child: Transform.scale(
                  scale: 0.6 + 0.4 * enter.value,
                  child: Opacity(
                    opacity: enter.value.clamp(0.0, 1.0),
                    child: _Card(
                      title: widget.title,
                      subtitle: widget.subtitle,
                      kicker: widget.kicker,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, this.kicker});

  final String title;
  final String? subtitle;
  final String? kicker;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius + 6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.emoji_events_rounded,
                size: 42, color: Colors.white),
          ),
          const SizedBox(height: 18),
          if (kicker != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ps.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                kicker!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: Ps.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            // Two lines, then ellipsis. A club name can be long and this is
            // read at a glance from a metre away; shrinking it to fit is the
            // wrong trade.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Congratulations!',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Ps.primary,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
              decoration: BoxDecoration(
                color: Ps.canvas,
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(color: Ps.border),
              ),
              child: Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Result recorded — standings, ratings and both records are '
            'updated.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.35, color: Ps.muted),
          ),
        ],
      ),
    );
  }
}

/// Falling paper, from a seed.
///
/// Each piece gets a fixed column, a fall speed, a spin rate and a colour from
/// [math.Random] seeded once, so the whole animation is a pure function of
/// `progress` — no per-frame allocation, no particle list to keep in state,
/// and identical output for identical input.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.seed});

  /// 0 → 1 across the celebration.
  final double progress;
  final int seed;

  static const _count = 90;

  /// The brand green and the trophy gold, plus two carnival colours to stop
  /// it reading as a corporate loading screen.
  static const _colours = [
    Ps.primary,
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFFFBBF24),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _count; i++) {
      final x = rnd.nextDouble() * size.width;
      // A head start per piece, so the burst is not a single flat curtain.
      final delay = rnd.nextDouble() * 0.35;
      // Slower pieces are still on screen when the fast ones have landed,
      // which is what makes it read as confetti rather than as a wipe.
      final speed = 0.8 + rnd.nextDouble() * 0.9;
      final w = 5.0 + rnd.nextDouble() * 6;
      final h = w * (0.5 + rnd.nextDouble());
      final spin = (rnd.nextDouble() - 0.5) * 14;
      final sway = 14 + rnd.nextDouble() * 26;
      final colour = _colours[rnd.nextInt(_colours.length)];

      final t = (progress - delay) * speed;
      if (t <= 0) continue;
      // Starts above the top edge and falls past the bottom; anything that
      // has fallen out of frame is simply not drawn.
      final y = -40 + t * (size.height + 80);
      if (y > size.height + 40) continue;

      canvas.save();
      canvas.translate(x + math.sin(t * 6 + i) * sway, y);
      canvas.rotate(t * spin);
      paint.color = colour.withValues(
        // Fades out over the last fifth, so the paper does not vanish
        // mid-air when the card fades.
        alpha:
            progress > 0.8 ? (1 - (progress - 0.8) / 0.2).clamp(0.0, 1.0) : 1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.seed != seed;
}

/// Shows [WinCelebration] over whatever is on screen and returns when it has
/// finished.
///
/// A route rather than an overlay entry, so the system back button and a stray
/// `Navigator.pop` cannot leave it stranded on top of the app, and a
/// transparent one so the pad stays visible behind it — the scorer sees the
/// final score under the confetti, which is the thing they are about to be
/// asked about.
///
/// It closes ITSELF after [WinCelebration.duration]. The timer is cancelled if
/// the route is gone (tapped away, or the screen was popped), and the pop is
/// guarded on the route still being current, so an announcement cannot eat a
/// screen the user navigated to during those five seconds.
Future<void> showWinCelebration(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? kicker,
  Duration duration = const Duration(seconds: 5),
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  Timer? timer;

  final route = PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => GestureDetector(
      // Tap anywhere to skip. The scorer who already knows who won should
      // not have to wait five seconds for the scorecard.
      onTap: () => navigator.canPop() ? navigator.pop() : null,
      behavior: HitTestBehavior.opaque,
      child: WinCelebration(
        title: title,
        subtitle: subtitle,
        kicker: kicker,
        duration: duration,
      ),
    ),
  );

  final done = navigator.push(route);
  timer = Timer(duration, () {
    if (route.isActive && route.isCurrent) navigator.removeRoute(route);
  });
  return done.whenComplete(() => timer?.cancel());
}
