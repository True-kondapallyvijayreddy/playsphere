import 'dart:math' as math;

import 'glicko2.dart';

/// A summary of everyone's rating in one sport, just enough to place one more
/// rating inside it.
///
/// A percentile needs a population to be a percentile against. Storing the
/// full distribution as a mean/stddev would assume ratings are normally
/// distributed, which a grassroots leaderboard with a handful of very strong
/// club players and a long tail of first-timers usually is not. A raw sample
/// of current ratings makes no such assumption and costs nothing to compute
/// against — it is exactly what the materialized ratings view already holds.
class SportPopulation {
  const SportPopulation({required this.sportId, required this.ratings});

  final String sportId;

  /// Every rated player's current rating in this sport. Ordering does not
  /// matter — [percentileOf] sorts internally.
  ///
  /// Callers should normally exclude the player's own rating from this
  /// sample. Including it is harmless (it just makes 100th percentile
  /// unreachable in a population of one) but is rarely what's intended.
  final List<double> ratings;

  /// Where [rating] sits in this population, 0–100, 100 being the top.
  ///
  /// With nobody to compare against, the honest answer is "unknown" — but a
  /// cross-sport index cannot render "unknown" as one of its terms, so this
  /// returns the middle (50) rather than either extreme. A brand-new sport
  /// with one player in it should not silently crown them the best OR worst
  /// player PlaySphere has ever seen.
  double percentileOf(double rating) {
    if (ratings.isEmpty) return 50;
    var below = 0;
    var equal = 0;
    for (final r in ratings) {
      if (r < rating) {
        below++;
      } else if (r == rating) {
        equal++;
      }
    }
    // Ties split credit instead of all counting as "beaten" or "beaten by" —
    // otherwise two players tied at the top of a small pool would show
    // different percentiles depending on iteration order alone.
    return ((below + equal / 2) / ratings.length) * 100;
  }
}

/// One sport's rating, ready to be folded into a [CrossSportIndex].
class SportRatingEntry {
  const SportRatingEntry({
    required this.sportId,
    required this.rating,
    required this.population,
    this.lastPlayedAt,
  });

  final String sportId;
  final Rating rating;
  final SportPopulation population;

  /// When this player last played this sport. Null is treated as "decayed
  /// entirely" rather than "just played" — a missing timestamp is a data gap,
  /// and a data gap must never look like evidence of current form.
  final DateTime? lastPlayedAt;
}

/// What one sport contributed to the index, kept around specifically so the
/// UI can answer "why is my number X" rather than presenting a bare score.
/// This is the "document formula in-app for transparency" requirement made
/// concrete: every factor the formula multiplies is on this object.
class SportContribution {
  const SportContribution({
    required this.sportId,
    required this.percentile,
    required this.recencyWeight,
    required this.confidence,
  });

  final String sportId;

  /// 0–100, this player's standing within the sport's population.
  final double percentile;

  /// 0–1, how much a live/recent player this still counts as.
  final double recencyWeight;

  /// 0–1, how much the rating itself is trusted (derived from RD).
  final double confidence;

  /// This sport's own percentile after both discounts are applied. Always
  /// ≤ [percentile], since recency and confidence only ever pull it down —
  /// neither factor can make a player look better than their raw standing.
  double get discountedPercentile => percentile * recencyWeight * confidence;
}

/// The Sports OS Index for one player: a single 0–100 number summarising
/// standing across every sport they play, plus the breakdown that produced
/// it.
class CrossSportIndexResult {
  const CrossSportIndexResult({required this.index, required this.components});

  /// 0–100.
  final double index;

  /// One entry per sport that had evidence to contribute, in input order.
  final List<SportContribution> components;
}

/// Computes the Cross-Sport Index per CLAUDE.md §8.2:
/// `index = Σ [percentile_within_sport × recency_weight × confidence(1/RD)]`,
/// normalised 0–100.
///
/// The spec's Σ is a sum, but a sum of per-sport percentiles (each already
/// 0–100) has no natural ceiling — a player active in four sports would sum
/// past 100 even at middling percentiles in all of them, which makes "0–100"
/// a lie for anyone but a single-sport player. This computes the discounted
/// percentile per sport exactly as specified, then normalises by AVERAGING
/// across the sports that had evidence rather than dividing by an arbitrary
/// constant. That keeps two properties the spec implies but doesn't spell
/// out: a single-sport player's index is precisely their own discounted
/// percentile (nothing is diluted just because they play one sport), and a
/// multi-sport player's index is bounded by the same 0–100 scale as every
/// term inside it, so playing more sports can never be a shortcut to a
/// higher number than actually being good at them.
class CrossSportIndex {
  const CrossSportIndex({this.recencyHalfLifeDays = defaultHalfLifeDays});

  /// Days for the recency weight to fall to half. The spec calls out ~180
  /// days as the sane default for grassroots play, where a season gap is
  /// normal and should not read as "quit."
  static const double defaultHalfLifeDays = 180;

  final double recencyHalfLifeDays;

  /// Exponential decay: 1.0 the day a player last played, halving every
  /// [recencyHalfLifeDays]. Exponential rather than linear because the
  /// difference between "played yesterday" and "played last week" should
  /// matter far less than the difference between "played a year ago" and
  /// "played two years ago" — a cliff-edge cutoff would make the index jump
  /// the instant a player crosses an arbitrary day count.
  double recencyWeightFor(DateTime lastPlayedAt, DateTime asOf) {
    final daysSince =
        asOf.difference(lastPlayedAt).inMilliseconds / Duration.millisecondsPerDay;
    if (daysSince <= 0) return 1.0; // "last played" in the future — no penalty
    if (recencyHalfLifeDays <= 0) return 0.0;
    return math.pow(0.5, daysSince / recencyHalfLifeDays).toDouble();
  }

  /// 0 at a brand-new, unrated deviation (350 — nothing is known yet), rising
  /// to 1 as RD shrinks toward 0 (the rating is well established). Anchored
  /// to [Rating.defaultDeviation] rather than an independently chosen
  /// constant so this always agrees with what glicko2.dart considers "know
  /// nothing about this player."
  double confidenceFor(Rating rating) {
    final c = 1 - rating.deviation / Rating.defaultDeviation;
    return c.clamp(0.0, 1.0);
  }

  /// Computes the index, or null when there is nothing to compute it from.
  ///
  /// Null rather than 0 is deliberate: 0 on a 0–100 index reads as "the
  /// worst player on the platform," which is false and defamatory for
  /// someone who simply hasn't played a rated match yet. The UI's job is to
  /// render null as "not enough data" — never as a number.
  CrossSportIndexResult? compute({
    required List<SportRatingEntry> entries,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final components = <SportContribution>[];

    for (final entry in entries) {
      // No games played means no evidence beyond the prior — this sport has
      // nothing to say about the player yet, so it must not vote.
      if (entry.rating.gamesPlayed == 0) continue;

      final percentile = entry.population.percentileOf(entry.rating.rating);
      final recency = entry.lastPlayedAt == null
          ? 0.0
          : recencyWeightFor(entry.lastPlayedAt!, now);
      final confidence = confidenceFor(entry.rating);

      components.add(SportContribution(
        sportId: entry.sportId,
        percentile: percentile,
        recencyWeight: recency,
        confidence: confidence,
      ));
    }

    if (components.isEmpty) return null;

    final total =
        components.fold<double>(0, (sum, c) => sum + c.discountedPercentile);
    final index = (total / components.length).clamp(0.0, 100.0);

    return CrossSportIndexResult(index: index, components: components);
  }
}
