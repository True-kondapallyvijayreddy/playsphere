import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../domain/rating/overall_glicko.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/ui_kit.dart';

/// The one-glance answer to "how am I doing" — a person's level, how far
/// through it they are, and the three numbers behind it.
///
/// ## Why a level and not just the rating
///
/// The account panel already had the rating available and never showed it,
/// because a bare `1642` is not an answer for the person who opens their own
/// profile — it is an answer for a selector reading somebody else's. What a
/// player wants from their own panel is *where they stand and what moves it*,
/// and a ladder with a visible next rung says that in one line where a number
/// says it in none.
///
/// ## Why the levels are the tiers that already exist
///
/// [Rating.tier] has shipped a seven-band ladder — Beginner, Developing,
/// Club, Strong, District, State, Elite — since ratings did, and the profile,
/// the roster chip and the tournament entry list all speak it. Inventing a
/// second ladder here would have given the same player two different levels
/// on two screens of the same app. So the level IS the tier: Level 1 is
/// Beginner, Level 7 is Elite, and the bar fills with the person's position
/// inside their current band.
///
/// Nothing here is stored or computed anew — every figure is read from
/// [overallGlickoProvider], [careerProvider] and [playerMemoriesProvider],
/// which the panel was already watching.
class PersonalLevelBoard extends ConsumerWidget {
  const PersonalLevelBoard({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overall = ref.watch(overallGlickoProvider(uid)).valueOrNull;
    final career = ref.watch(careerProvider(uid)).valueOrNull ?? const [];
    final memories = ref.watch(playerMemoriesProvider(uid)).valueOrNull ?? const [];

    final matches = career.fold<int>(0, (s, l) => s + l.matchesPlayed);
    final sports = career.where((l) => l.matchesPlayed > 0).length;
    final level = PlayerLevel.of(overall);

    return PsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LevelMedal(level: level),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${level.number} · ${level.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.caption(overall),
                      style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                    ),
                  ],
                ),
              ),
              if (overall != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${overall.overall.round()}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      'XP',
                      style: TextStyle(fontSize: 11, color: Ps.faint),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),

          // The bar. `value` is position inside the current band, so a person
          // one point into "Strong" reads as an empty bar rather than as a
          // full one belonging to the band they just left.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: level.progress,
              minHeight: 8,
              backgroundColor: Ps.border,
              valueColor: const AlwaysStoppedAnimation(Ps.primary),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  level.nextLabel,
                  style: const TextStyle(fontSize: 12, color: Ps.muted),
                ),
              ),
              Text(
                '${(level.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: Ps.muted,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Ps.border),
          const SizedBox(height: 12),

          Row(
            children: [
              _BoardStat(value: '$matches', label: 'Matches'),
              _BoardStat(value: '$sports', label: 'Sports'),
              _BoardStat(value: '${memories.length}', label: 'Memories'),
              _BoardStat(
                value: overall == null
                    ? '—'
                    : SportCatalog.byId(overall.primary.sportId).name,
                label: 'Best sport',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A person's rung on the ladder, and how far up it they are.
///
/// Split out from the widget so it can be reasoned about — and tested —
/// without a `WidgetTester`, and so any other surface that wants to say
/// "Level 4" says the same Level 4.
class PlayerLevel {
  const PlayerLevel({
    required this.number,
    required this.name,
    required this.progress,
    required this.pointsToNext,
    required this.provisional,
  });

  /// 1–7, matching the position of [name] in the tier ladder.
  final int number;

  /// The tier's own word for this band — the vocabulary the rest of the app
  /// already uses beside a rating.
  final String name;

  /// 0–1 through the current band. 1 for the top band, which has no next rung.
  final double progress;

  /// Rating points to the next band, or null at the top.
  final int? pointsToNext;

  /// The rating behind this is still being pulled toward the 1500 prior.
  final bool provisional;

  /// The band edges [Rating.tier] switches on, as (upper bound, name). The
  /// bottom edge of the ladder is 1000 and the top is 2400 — outside the range
  /// any real rating reaches, so the first and last bands still have a width
  /// to measure progress against.
  static const List<(double, String)> _bands = [
    (1200, 'Beginner'),
    (1400, 'Developing'),
    (1600, 'Club'),
    (1800, 'Strong'),
    (2000, 'District'),
    (2200, 'State'),
    (2400, 'Elite'),
  ];
  static const double _floor = 1000;

  /// Level 1 with an empty bar, for a person who has not been rated yet.
  /// Deliberately not "no level": everybody starts on the ladder, and a blank
  /// where the level goes reads as something broken rather than as a start.
  static const PlayerLevel unrated = PlayerLevel(
    number: 1,
    name: 'Beginner',
    progress: 0,
    pointsToNext: null,
    provisional: true,
  );

  static PlayerLevel of(OverallGlicko? overall) {
    if (overall == null) return unrated;
    final rating = overall.overall;

    var index = _bands.indexWhere((b) => rating < b.$1);
    if (index < 0) index = _bands.length - 1;

    final lower = index == 0 ? _floor : _bands[index - 1].$1;
    final upper = _bands[index].$1;
    final within = ((rating - lower) / (upper - lower)).clamp(0.0, 1.0);
    final isTop = index == _bands.length - 1;

    return PlayerLevel(
      number: index + 1,
      name: _bands[index].$2,
      progress: isTop ? 1 : within,
      pointsToNext: isTop ? null : (upper - rating).ceil(),
      provisional: overall.isProvisional,
    );
  }

  /// What sits under the level name.
  String caption(OverallGlicko? overall) {
    if (overall == null) {
      return 'Play a rated match and your level starts climbing.';
    }
    if (provisional) {
      final m = overall.effectiveMatches.round();
      return 'Still settling — ${m == 1 ? '1 rated match' : '$m rated matches'} '
          'so far.';
    }
    return 'Across ${overall.components.length} '
        '${overall.components.length == 1 ? 'sport' : 'sports'}.';
  }

  /// What sits under the bar.
  String get nextLabel {
    if (pointsToNext == null) {
      return provisional ? 'Rating still settling' : 'Top level reached';
    }
    final next = _bands[number].$2;
    return '$pointsToNext to $next';
  }
}

/// The badge on the left: the level number, in the brand green.
class _LevelMedal extends StatelessWidget {
  const _LevelMedal({required this.level});

  final PlayerLevel level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Ps.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: Ps.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'LVL',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: Ps.primary,
            ),
          ),
          Text(
            '${level.number}',
            style: const TextStyle(
              fontSize: 20,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: Ps.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardStat extends StatelessWidget {
  const _BoardStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: '$label $value',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Ps.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Ps.muted)),
          ],
        ),
      ),
    );
  }
}
