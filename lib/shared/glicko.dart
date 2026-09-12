/// How PlaySphere draws a competitive standing, wherever one appears.
///
/// ## Why this is one file and not a chip per screen
///
/// The same argument `identity.dart` makes about faces and crests, applied to
/// the number instead of the picture. A standing that is a green pill on the
/// profile, bare grey text on a roster and a differently-rounded badge on a
/// tournament entry list reads as three unrelated numbers that happen to sit
/// near three names — and the one thing this feature has to do is read as ONE
/// thing about a person, everywhere that person appears.
///
/// ## Why the provisional state is not optional
///
/// Every widget here that can show a number can show that the number is not
/// settled yet, and none of them lets a caller suppress it. A composite off
/// two matches and a composite off two hundred are the same digits at the same
/// size, and the difference between them is the entire reason Glicko-2 was
/// chosen over Elo. A scout reading a team sheet has no way to tell which one
/// they are looking at unless the badge says so itself.
library;

import 'package:flutter/material.dart';

import '../core/models/glicko_badge.dart';
import '../domain/rating/overall_glicko.dart';
import '../domain/scoring/scoring_registry.dart';
import 'ui_kit.dart';

/// The pill: `Glicko 1716`.
///
/// [GlickoChipSize.compact] is for lists — a roster row, an entry list, a
/// squad picker — where the number rides beside a name at caption size.
/// [GlickoChipSize.prominent] is for the one place a person's standing is the
/// headline rather than an annotation: their own profile.
enum GlickoChipSize { compact, prominent }

class GlickoChip extends StatelessWidget {
  const GlickoChip({
    super.key,
    required this.rating,
    this.provisional = false,
    this.size = GlickoChipSize.compact,
    this.label = 'Glicko',
  });

  /// Convenience for the common case: the denormalised badge off a user
  /// document, which is what every surface other than the profile holds.
  /// Returns null when there is nothing to draw, so a caller can write
  /// `GlickoChip.forBadge(user.glicko) ?? const SizedBox.shrink()` and never
  /// invent a number for somebody who has not played.
  static GlickoChip? forBadge(
    GlickoBadge? badge, {
    GlickoChipSize size = GlickoChipSize.compact,
  }) {
    if (badge == null) return null;
    return GlickoChip(
      rating: badge.overall,
      provisional: badge.provisional,
      size: size,
    );
  }

  /// The chip for a person in the context of ONE sport — a team roster, a
  /// squad sheet, an entry list for a badminton tournament.
  ///
  /// Shows that sport's own rating where the travelling badge carries it, and
  /// falls back to the overall standing where it does not, labelled so the
  /// two can never be mistaken for each other. Showing nothing would be the
  /// wrong fallback: a person on a volleyball roster who is rated in
  /// volleyball but ranks it fourth among their sports has a standing, and a
  /// blank beside their name says they do not.
  static GlickoChip? forSport(GlickoBadge? badge, String sportId) {
    if (badge == null) return null;
    final inSport = badge.ratingFor(sportId);
    if (inSport == null) {
      return GlickoChip(rating: badge.overall, provisional: badge.provisional);
    }
    return GlickoChip(
      rating: inSport,
      // The per-sport figure in the travelling badge is the authoritative
      // rating for that sport, not the composite — so the composite's
      // "still settling" flag does not apply to it.
      label: SportCatalog.byId(sportId.split(':').first).name,
    );
  }

  final int rating;
  final bool provisional;
  final GlickoChipSize size;

  /// `Glicko` on a profile; a sport name on a per-sport chip.
  final String label;

  @override
  Widget build(BuildContext context) {
    final compact = size == GlickoChipSize.compact;
    final theme = Theme.of(context);

    // Provisional is drawn as a *quieter* chip rather than a louder one. A
    // warning colour would make an ordinary early-career state look like an
    // error on the profile of someone who has done nothing wrong; muting it
    // says the same thing — this is not settled — without the alarm.
    final foreground = provisional ? Ps.muted : Ps.ink;
    final background = provisional
        ? Ps.border.withValues(alpha: 0.55)
        : Ps.primary.withValues(alpha: 0.12);

    return Semantics(
      label: provisional
          ? '$label $rating, provisional'
          : '$label $rating',
      excludeSemantics: true,
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(compact ? 8 : Ps.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provisional) ...[
              Icon(Icons.hourglass_empty, size: compact ? 11 : 14,
                  color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: (compact
                      ? theme.textTheme.labelSmall
                      : theme.textTheme.labelMedium)
                  ?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(width: compact ? 4 : 6),
            Text(
              '$rating',
              style: (compact
                      ? theme.textTheme.labelMedium
                      : theme.textTheme.titleMedium)
                  ?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
                // Tabular figures so a column of these in a roster lines up
                // digit-for-digit instead of shimmering as it scrolls.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `🏏 1842 · 🏸 1618 · ⚽ 1497` — the per-sport standings under a name.
///
/// Drawn with the sport glyphs from [SportVisual] rather than emoji, for the
/// reason that class already documents: emoji render from the system font, so
/// the same strip is flat grey on one Android build and glossy 3D on another.
class SportGlickoStrip extends StatelessWidget {
  const SportGlickoStrip({
    super.key,
    required this.sports,
    this.hiddenCount = 0,
    this.iconSize = 15,
  });

  /// Sport id to rating, strongest first.
  final Map<String, int> sports;

  /// Sports the person has that this strip is not showing, so it can say so
  /// rather than implying these are all of them.
  final int hiddenCount;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (sports.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final entries = sports.entries.toList();

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final e in entries)
          Semantics(
            label: '${SportCatalog.byId(e.key).name} ${e.value}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  SportVisual.of(e.key).icon,
                  size: iconSize,
                  color: SportVisual.of(e.key).color,
                ),
                const SizedBox(width: 4),
                Text(
                  '${e.value}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Ps.ink,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        if (hiddenCount > 0)
          Text(
            '+$hiddenCount more',
            style: theme.textTheme.labelSmall?.copyWith(color: Ps.muted),
          ),
      ],
    );
  }
}

/// The profile's answer to "why is my number what it is".
///
/// A bare composite invites exactly one question, and a product that cannot
/// answer it has published a score rather than a rating. This shows the
/// headline, then every sport that fed it and how much each one counted — the
/// same three factors the engine multiplies, in the order it multiplies them.
class GlickoBreakdown extends StatelessWidget {
  const GlickoBreakdown({super.key, required this.result, required this.isMe});

  final OverallGlicko result;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overall = result.overall.round();
    final leading = result.components.first;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall Glicko',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Ps.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$overall',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Ps.ink,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            result.tier,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Ps.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (result.isProvisional)
                GlickoChip(
                  rating: overall,
                  provisional: true,
                  label: 'Settling',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.isProvisional
                ? (isMe
                    ? 'Still settling — ${_matches(result)} rated so far. '
                        'Play more and this number sharpens.'
                    : 'Still settling — ${_matches(result)} rated so far.')
                : 'Across ${result.components.length} '
                    '${result.components.length == 1 ? 'sport' : 'sports'}, '
                    'led by ${SportCatalog.byId(leading.sportId).name}.',
            style: theme.textTheme.bodySmall?.copyWith(color: Ps.muted),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Ps.border),
          const SizedBox(height: 12),

          for (final c in result.components) ...[
            _ComponentRow(component: c),
            if (c != result.components.last) const SizedBox(height: 10),
          ],

          const SizedBox(height: 14),
          // The composite is not a Glicko rating and the profile says so in
          // its own words rather than in a footnote nobody reads. §3 of the
          // brief is explicit about this: the sport numbers are authoritative,
          // this one is PlaySphere's index across them.
          Text(
            'Each sport above carries its own Glicko rating — those are the '
            'authoritative numbers. The overall is PlaySphere\'s cross-sport '
            'index, led by your strongest sport and weighted by how recent and '
            'how settled each rating is.',
            style: theme.textTheme.bodySmall?.copyWith(color: Ps.faint),
          ),
        ],
      ),
    );
  }

  String _matches(OverallGlicko r) {
    final m = r.effectiveMatches.round();
    return m == 1 ? '1 match' : '$m matches';
  }
}

/// One sport's line in the breakdown: what it rates, and how much it counted.
class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component});

  final OverallGlickoComponent component;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = SportCatalog.byId(component.sportId).name;

    return Row(
      children: [
        SportBadge(sportId: component.sportId, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Text(
                _why(),
                style: theme.textTheme.bodySmall?.copyWith(color: Ps.muted),
              ),
            ],
          ),
        ),
        Text(
          '${component.rating.round()}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// The plain-language version of `confidence × recency × rankFactor`.
  ///
  /// Percentages rather than the raw factors: "counts 37%" is a sentence a
  /// player can argue with, and `0.829 × 1.0 × 0.45` is not.
  String _why() {
    final share = (component.weight * 100).round();
    final matches = component.matches;
    final parts = <String>[
      '$matches rated ${matches == 1 ? 'match' : 'matches'}',
      'counts $share%',
    ];
    // Only mentioned when it is actually doing something, so the line stays
    // short for the ordinary case of a sport played this season.
    if (component.recency < 0.7) {
      parts.add('not played recently');
    }
    return parts.join(' · ');
  }
}
