import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The PlaySphere mark — the real artwork, the same one on the launcher icon
/// and the splash.
///
/// This used to be drawn: a brand-gradient square with Material's generic
/// `sports_score` flag in it, on the reasoning that a raster at three
/// densities was not worth it for a circle and a glyph. That reasoning held
/// only while there was no logo. Now there is one, and a placeholder flag in
/// the app bar above an icon showing the actual mark is a worse cost than the
/// bytes — a brand people do not recognise between the home screen and the
/// app is not a brand.
///
/// The size objection is answered rather than ignored: [_asset] is a 192px
/// file, roughly 25KB, which covers 3× density at every size this is drawn
/// and is a rounding error against the 3.5MB of full-resolution sources that
/// stay OUT of the bundle (see the assets block in pubspec.yaml).
///
/// The artwork carries its own near-black card, which is the brand, so it
/// does not follow the theme into dark mode and is not meant to — it reads
/// the same on both, the way an app icon does.
class PlaySphereMark extends StatelessWidget {
  const PlaySphereMark({super.key, this.size = 30});

  static const _asset = 'assets/branding/mark.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        _asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        // A missing asset must not take the whole app bar down with it. The
        // old drawn mark survives as the fallback, which is exactly what it
        // was built to be.
        errorBuilder: (context, _, __) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.sports_score,
            size: size * 0.62,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Mark plus wordmark — what sits at the top left of every signed-in screen.
///
/// The wordmark is two coloured spans rather than one, because "Play" and
/// "Sphere" read as a single word at a glance and the split is the only thing
/// that makes it a logo instead of a heading.
class PlaySphereLogo extends StatelessWidget {
  const PlaySphereLogo({
    super.key,
    this.markSize = 28,
    this.fontSize = 18,
    this.showMark = true,
  });

  final double markSize;
  final double fontSize;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'PlaySphere',
      excludeSemantics: true,
      // Scales the whole mark-plus-wordmark down when the slot is too narrow
      // for it, rather than clipping the tail off "Sphere". The drawer header
      // asks for the largest size anywhere in the app and shares a 304px
      // drawer with a close button, so at the default text scale it was 28px
      // over and the brand rendered visibly cut — and it got worse, not
      // better, for anyone who had raised their font size for legibility.
      //
      // FittedBox rather than Flexible: this widget also sits in an AppBar
      // title and in a popup menu, and a flex child would assert the moment
      // one of those handed it unbounded width. FittedBox measures the child
      // unconstrained and only scales if it has to, so it is correct under
      // both.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMark) ...[
              PlaySphereMark(size: markSize),
              SizedBox(width: markSize * 0.3),
            ],
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Play',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(
                    text: 'Sphere',
                    style: TextStyle(
                      color: AppTheme.primaryTurfGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: TextStyle(fontSize: fontSize, letterSpacing: -0.2),
            ),
          ],
        ),
      ),
    );
  }
}
