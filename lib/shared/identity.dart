import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'ui_kit.dart';

/// How PlaySphere draws a person, a club or a team when it has no picture of
/// them — and how it draws them when it does.
///
/// ## Why this file exists
///
/// Before it, the same club rendered three different ways: a 56pt rounded
/// square on its own home screen, a 26pt six-radius tile on the rankings
/// ladder, and a plain grey Material circle with one letter in it in the club
/// switcher, the drawer and the join screen — three places that ignored
/// `logoUrl` altogether even after a club had uploaded one. Fifteen files
/// hand-rolled their own initials fallback and disagreed about shape, colour,
/// how many letters to show and what to do with an empty name. That
/// disagreement is what makes an otherwise complete app read as unfinished:
/// not the absence of pictures, but the absence of one way of drawing them.
///
/// ## Why the fallback is generated rather than blank
///
/// A grassroots club in Warangal will not have a crest ready on the day it
/// signs up, and a fourteen-year-old signing up will not have a headshot. If
/// "no image" means a grey disc, the app looks empty for its entire first year
/// in every district it enters — exactly the period in which it has to look
/// credible. So the default is not absence: it is a coloured monogram derived
/// from the entity's id, stable forever, different for every club.
///
/// This is also what keeps every upload in the product genuinely **optional**.
/// Nothing in PlaySphere requires a picture: a crest, a team logo, a season
/// banner, a ground photo and a member's own face are all skippable, and
/// skipping one costs the person nothing, because the generated identity is
/// already a finished-looking answer. An upload replaces a good default rather
/// than filling an empty box.
abstract final class PsIdentity {
  /// The letters to show when there is no picture.
  ///
  /// One for a person, two for a club or a team — and the difference is
  /// deliberate, not cosmetic: it is what lets a mixed list be scanned. A
  /// single letter reads as somebody's name; a pair reads as an institution.
  static String initials(String name, {int max = 1}) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (max <= 1 || words.length == 1) {
      // `characters` and not `[0]`: a Telugu or Hindi name's first glyph is
      // several code units, and `name[0]` slices it in half and renders a
      // replacement box. Half the call sites this replaced had that bug.
      return words.first.characters.first.toUpperCase();
    }
    return (words.first.characters.first + words[1].characters.first)
        .toUpperCase();
  }

  /// The colour for an entity, chosen from a fixed set and never changing.
  ///
  /// Keyed on the id rather than the name, so a club that renames itself keeps
  /// its colour and two clubs both called "Sports Club" do not collide.
  static Color color(String? seed) {
    if (seed == null || seed.isEmpty) return _palette.first;
    return _palette[hash(seed) % _palette.length];
  }

  /// A stable hash.
  ///
  /// Deliberately not `String.hashCode`: Dart does not guarantee that is the
  /// same between runs, and a crest that changes colour when the app restarts
  /// is worse than one that never had a colour.
  static int hash(String s) {
    var h = 0;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0x7FFFFFFF;
    }
    return h;
  }

  /// Ten hues, every one of which carries white text at 4.5:1 or better.
  ///
  /// Checked rather than eyeballed — a monogram whose letter is unreadable is
  /// worse than a grey disc, and the mid-tone version of most of these
  /// (orange-600, yellow-600, green-600) fails that test even though it looks
  /// livelier in a swatch.
  static const List<Color> _palette = [
    Color(0xFFDC2626), // red 600
    Color(0xFFC2410C), // orange 700
    Color(0xFFA16207), // yellow 700
    Color(0xFF15803D), // green 700
    Color(0xFF0F766E), // teal 700
    Color(0xFF0E7490), // cyan 700
    Color(0xFF2563EB), // blue 600
    Color(0xFF4F46E5), // indigo 600
    Color(0xFF7C3AED), // violet 600
    Color(0xFFDB2777), // pink 600
  ];
}

/// Every remote image in the app, cached on disk and never able to leave a
/// hole in a layout.
///
/// Flutter's own `ImageCache` is memory-only and dies with the process, so a
/// raw `Image.network` re-downloads a face every time a list is scrolled back
/// up. [fallback] is used for all three of the states a network image has —
/// loading, failed, and no-url — so the space it occupies always contains
/// something deliberate and the layout never reflows.
class PsNetworkImage extends StatelessWidget {
  const PsNetworkImage({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String? url;

  /// Drawn while loading, on failure, and when [url] is null or blank.
  final Widget fallback;

  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.trim().isEmpty) return fallback;

    return CachedNetworkImage(
      imageUrl: u,
      width: width,
      height: height,
      fit: fit,
      // No spinner. A 32pt spinner inside a 32pt avatar is noise, and the
      // monogram underneath is already the right shape and the right colour —
      // so the load reads as the photo arriving rather than as a gap filling.
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
      fadeInDuration: const Duration(milliseconds: 140),
    );
  }
}

/// A person: circular, one initial, one colour that is theirs forever.
class PsAvatar extends StatelessWidget {
  const PsAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.seed,
    this.size = 40,
  });

  final String name;
  final String? photoUrl;

  /// The uid, so the colour survives a name change. Falls back to the name
  /// where a caller genuinely has no id — a squad sheet entry typed by hand.
  final String? seed;

  /// Diameter, not radius. `CircleAvatar` takes a radius and half the call
  /// sites this replaced had picked one that did not match the row beside it.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: PsNetworkImage(
          url: photoUrl,
          width: size,
          height: size,
          fallback: _Monogram(
            text: PsIdentity.initials(name),
            color: PsIdentity.color(seed ?? name),
            size: size,
            borderRadius: BorderRadius.circular(size),
          ),
        ),
      ),
    );
  }
}

/// A club or a team: a squircle, two initials.
///
/// Not a circle, and the difference carries information. A round mark reads as
/// a person and a rounded square reads as an institution, so a list holding
/// both — a match between a club and a player, a search across everything —
/// can be understood without reading a word of it.
class PsCrest extends StatelessWidget {
  const PsCrest({
    super.key,
    required this.name,
    this.logoUrl,
    this.seed,
    this.size = 44,
  });

  final String name;
  final String? logoUrl;
  final String? seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: PsNetworkImage(
          url: logoUrl,
          width: size,
          height: size,
          // `contain`, not `cover`. A crest is usually a logo on a flat
          // background and cropping it to a square cuts the club's name off
          // the bottom of its own badge.
          fit: BoxFit.contain,
          fallback: _Monogram(
            text: PsIdentity.initials(name, max: 2),
            color: PsIdentity.color(seed ?? name),
            size: size,
            borderRadius: radius,
          ),
        ),
      ),
    );
  }
}

/// The generated mark itself.
class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.text,
    required this.color,
    required this.size,
    required this.borderRadius,
  });

  final String text;
  final Color color;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    // A shallow vertical gradient rather than a flat fill. It is the whole
    // difference between something that reads as designed and something that
    // reads as "no image".
    final lighter =
        hsl.withLightness((hsl.lightness * 1.18).clamp(0.0, 1.0)).toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lighter, color],
        ),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            // Holds a fixed ratio to the tile, so a 24pt mark and a 96pt mark
            // read as one component at two sizes rather than as two
            // components. Two letters get slightly less room than one.
            fontSize: size * (text.characters.length > 1 ? 0.36 : 0.44),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            height: 1,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// A grey block standing in for content that has not arrived, with a slow
/// shimmer across it.
///
/// `AsyncView` showed a centred spinner on all 65 screens that use it. A
/// spinner says "wait"; a skeleton in the shape of the list says "this is what
/// is coming", which is both a shorter-feeling wait and a truer one.
class PsSkeleton extends StatefulWidget {
  const PsSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<PsSkeleton> createState() => _PsSkeletonState();
}

class _PsSkeletonState extends State<PsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    // Honours the system setting: a shimmer is decoration, and somebody who
    // has asked for less motion should get a plain block.
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
        .disableAnimations) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.isAnimating ? _controller.value : 0.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: const [
                Color(0xFFEDF1F5),
                Color(0xFFE2E8F0),
                Color(0xFFEDF1F5),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The shape most of the app's loading states actually have: a run of rows,
/// each an avatar-sized block and two lines of text.
class PsListSkeleton extends StatelessWidget {
  const PsListSkeleton({super.key, this.rows = 5, this.leadingSize = 44});

  final int rows;
  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  PsSkeleton(
                    width: leadingSize,
                    height: leadingSize,
                    radius: leadingSize * 0.28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Rows of slightly different widths, because five
                        // identical bars read as a broken table rather than as
                        // content arriving.
                        const PsSkeleton(
                          width: double.infinity,
                          height: 12,
                          radius: 4,
                        ),
                        const SizedBox(height: 8),
                        PsSkeleton(
                          width: 120 + (i.isEven ? 40 : 0),
                          height: 10,
                          radius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The tinted disc an [EmptyState] glyph sits in.
///
/// Exported so a screen that wants an empty state of its own shape can use the
/// same mark rather than inventing one.
class PsEmptyArt extends StatelessWidget {
  const PsEmptyArt({super.key, required this.icon, this.size = 92});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Two discs rather than one: a wide, very faint ring and a smaller
          // solid one. It is a small thing and it is most of the difference
          // between "designed empty state" and "grey icon in the middle of a
          // blank screen".
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Ps.primary.withValues(alpha: 0.06),
            ),
          ),
          Container(
            width: size * 0.66,
            height: size * 0.66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Ps.primary.withValues(alpha: 0.11),
            ),
          ),
          Icon(icon, size: size * 0.34, color: Ps.primary),
        ],
      ),
    );
  }
}
