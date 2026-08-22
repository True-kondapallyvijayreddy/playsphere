import 'package:flutter/material.dart';

import 'identity.dart';
import 'ui_kit.dart';

/// The artwork across the top of an event, a season, a club or a ground.
///
/// ## Why there is no empty state
///
/// The obvious way to build this is "show the banner if there is one", and it
/// is the wrong way. A grassroots club in Warangal will not have artwork ready
/// on the day it signs up, and a season put together the night before a
/// tournament will never have any at all. If no banner means no header, the
/// app looks unfinished for its entire first year in every district it enters
/// — which is precisely the period it has to look credible in.
///
/// So the absent state is not absence. When [imageUrl] is null this paints
/// generated art from the sport: a two-stop gradient in the sport's own colour
/// with its glyph oversized and bled off the right edge. It costs no bundle
/// size, it is different for every sport in the catalogue, and it means an
/// upload *replaces a good default* rather than filling an empty box. An
/// organizer who skips the picture is not punished for skipping it, which is
/// the only way an optional field stays genuinely optional.
///
/// [seed] shifts the gradient so two cricket events do not come out identical.
/// Derived from the entity's id rather than its name, so renaming a season
/// keeps its look.
class PsBanner extends StatelessWidget {
  const PsBanner({
    super.key,
    this.imageUrl,
    this.sportId,
    this.seed,
    this.fallbackIcon,
    this.fallbackColor,
    this.height = 150,
    this.child,
    this.trailing,
    this.borderRadius,
  });

  /// Uploaded artwork. Null is normal — see the class comment.
  final String? imageUrl;

  /// Which sport's colour and glyph the generated art uses. Null falls back to
  /// the neutral slate [SportVisual] already defines for unknown sports.
  final String? sportId;

  /// The entity's id, used only to vary the generated art.
  final String? seed;

  /// Overrides the glyph the generated art uses when [sportId] is null.
  ///
  /// Exists for the one subject in the product that is genuinely not a single
  /// sport: a season holding five events across five sports has no sport of
  /// its own, and falling back to the generic "unknown sport" mark would say
  /// something untrue about it. A trophy says the right thing.
  final IconData? fallbackIcon;

  /// Overrides the colour the generated art uses when [sportId] is null.
  final Color? fallbackColor;

  final double height;

  /// Laid over the scrim at the bottom left — a name, a meta row, a chip.
  final Widget? child;

  /// Top right, over the art. Where an edit affordance goes.
  final Widget? trailing;

  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(Ps.radius);
    final url = imageUrl;
    final hasUpload = url != null && url.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // One widget for all three states. `PsNetworkImage` draws the
            // fallback while loading, on failure and when there is no url at
            // all — so a banner never flashes empty on a slow connection and
            // a dead image host still leaves a header behind it rather than a
            // grey rectangle with a broken-image glyph in the middle.
            PsNetworkImage(
              url: hasUpload ? url : null,
              fit: BoxFit.cover,
              fallback: _GeneratedArt(
                sportId: sportId,
                seed: seed,
                fallbackIcon: fallbackIcon,
                fallbackColor: fallbackColor,
              ),
            ),

            // The scrim. Only ever painted where there is something to read,
            // so a banner with no child keeps its full colour.
            if (child != null)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.35, 1.0],
                    colors: [Color(0x00000000), Color(0xB0000000)],
                  ),
                ),
              ),

            if (child != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: child!,
              ),

            if (trailing != null)
              Positioned(top: 8, right: 8, child: trailing!),
          ],
        ),
      ),
    );
  }
}

/// The generated half: a sport-coloured gradient with the sport's glyph bled
/// off the right edge.
class _GeneratedArt extends StatelessWidget {
  const _GeneratedArt({
    this.sportId,
    this.seed,
    this.fallbackIcon,
    this.fallbackColor,
  });

  final String? sportId;
  final String? seed;
  final IconData? fallbackIcon;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final visual = SportVisual.of(sportId ?? '');
    final icon = sportId == null ? (fallbackIcon ?? visual.icon) : visual.icon;
    final colour =
        sportId == null ? (fallbackColor ?? visual.color) : visual.color;
    final base = HSLColor.fromColor(colour);

    // A small, bounded rotation — enough that two events in the same sport
    // read as different pages, not so much that cricket stops looking red.
    final drift = seed == null ? 0.0 : (PsIdentity.hash(seed!) % 17) - 8.0;
    final tinted = base
        .withHue((base.hue + drift) % 360)
        .withSaturation((base.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
    final deep = base
        .withHue((base.hue + drift) % 360)
        .withLightness((base.lightness * 0.62).clamp(0.0, 1.0))
        .toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tinted, deep],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final glyph = constraints.maxHeight * 1.45;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                right: -glyph * 0.22,
                bottom: -glyph * 0.28,
                child: Icon(
                  icon,
                  size: glyph,
                  color: Colors.white.withValues(alpha: 0.13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}
