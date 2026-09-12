import 'dart:typed_data';

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
    this.imageBytes,
    this.logoUrl,
    this.logoBytes,
    this.logoName,
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

  /// Artwork chosen on a create form and not yet uploaded, drawn in place of
  /// [imageUrl]. See [PsNetworkImage.bytes] for why a create screen needs it.
  final Uint8List? imageBytes;

  /// The subject's own badge, laid on the artwork rather than behind it.
  ///
  /// Absent by default and drawn nowhere when null — deliberately not a
  /// placeholder square. A banner is already a complete header without a
  /// crest (that is the whole argument of this class), so an empty slot would
  /// turn every season that never had a badge into one that looks like it is
  /// missing something.
  ///
  /// When present it sits at the bottom left with [child] beside it, because
  /// a mark and the name it belongs to have to read as one unit — a crest
  /// floating in the opposite corner from the title reads as a sponsor.
  final String? logoUrl;

  /// The crest as staged bytes, for the same reason [imageBytes] exists.
  final Uint8List? logoBytes;

  /// Only used to letter the crest's monogram while an uploaded one loads.
  final String? logoName;

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

  /// Whether there is a badge to draw over the art.
  bool get _hasLogo =>
      (logoBytes != null && logoBytes!.isNotEmpty) ||
      (logoUrl != null && logoUrl!.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(Ps.radius);
    final url = imageUrl;
    final hasUpload = url != null && url.trim().isNotEmpty;

    // The crest scales with the header so one component covers the 156pt
    // season header and the 110pt card thumbnail without a second set of
    // numbers, and is bounded so it never eats a short banner.
    final crestSize = (height * 0.30).clamp(34.0, 56.0);

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
              bytes: imageBytes,
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
            if (child != null || _hasLogo)
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

            if (child != null || _hasLogo)
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: !_hasLogo
                    ? child!
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // A white plinth behind the badge, because a crest
                          // is usually dark art on a transparent or white
                          // ground and would otherwise disappear into a dark
                          // photograph or into the scrim.
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(crestSize * 0.30),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x40000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: PsCrest(
                              name: logoName ?? '',
                              logoUrl: logoUrl,
                              logoBytes: logoBytes,
                              seed: seed,
                              size: crestSize,
                            ),
                          ),
                          if (child != null) ...[
                            const SizedBox(width: 12),
                            Expanded(child: child!),
                          ],
                        ],
                      ),
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
