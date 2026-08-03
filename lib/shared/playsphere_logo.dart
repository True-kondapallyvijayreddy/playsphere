import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The PlaySphere mark, drawn rather than shipped as an asset.
///
/// An asset would mean a raster at three densities in the APK for something
/// that is a circle and a glyph, and it would not follow the theme into dark
/// mode. Drawing it keeps the download smaller — which matters on the ₹8k
/// devices CLAUDE.md §2.8 targets — and keeps one definition of the brand.
class PlaySphereMark extends StatelessWidget {
  const PlaySphereMark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
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
