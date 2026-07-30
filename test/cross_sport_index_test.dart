import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/rating/cross_sport_index.dart';
import 'package:playsphere/domain/rating/glicko2.dart';

/// The Cross-Sport Index (CLAUDE.md §8.2): a single 0–100 headline number
/// blending a player's standing across every sport they play, discounted by
/// how recently they played and how much the rating itself can be trusted.
void main() {
  const index = CrossSportIndex();
  final now = DateTime(2026, 1, 1);

  group('SportPopulation.percentileOf', () {
    test('an empty population reads as the middle, not an extreme', () {
      const pop = SportPopulation(sportId: 'chess', ratings: []);
      expect(pop.percentileOf(2000), 50);
    });

    test('ties split credit instead of resolving one way', () {
      const pop = SportPopulation(sportId: 'chess', ratings: [1500, 1500]);
      // Both entries equal the query rating, so both are "half above, half
      // below" — the correct percentile for a value tied with everyone else
      // in a population of two is the middle.
      expect(pop.percentileOf(1500), 50);
    });

    test('top of a known population is close to 100', () {
      const pop = SportPopulation(
        sportId: 'football',
        ratings: [1000, 1200, 1400, 1600, 1800],
      );
      expect(pop.percentileOf(2000), 100);
      expect(pop.percentileOf(900), 0);
    });
  });

  group('single sport', () {
    test("a player's index is their own discounted percentile, undiluted", () {
      const population = SportPopulation(
        sportId: 'badminton',
        ratings: [1400, 1450, 1500, 1550, 1600, 1650, 1700, 1750, 1800, 1850],
      );
      const rating = Rating(rating: 1900, deviation: 50, gamesPlayed: 30);
      final result = index.compute(entries: [
        SportRatingEntry(
          sportId: 'badminton',
          rating: rating,
          population: population,
          lastPlayedAt: now,
        ),
      ], asOf: now);

      expect(result, isNotNull);
      expect(result!.components, hasLength(1));
      expect(result.components.single.percentile, 100);
      // confidence = 1 - 50/350 ≈ 0.857, recency = 1 (played today).
      const expectedConfidence = 1 - 50 / 350;
      expect(result.components.single.confidence, closeTo(expectedConfidence, 1e-9));
      expect(result.components.single.recencyWeight, 1.0);
      // Single sport ⇒ index == that sport's own discounted percentile.
      expect(result.index, closeTo(100 * expectedConfidence, 1e-6));
    });
  });

  group('multi sport', () {
    test('index is the average of each sport\'s discounted percentile', () {
      const populationA = SportPopulation(
        sportId: 'cricket',
        ratings: [1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900],
      );
      const populationB = SportPopulation(
        sportId: 'kabaddi',
        ratings: [1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900],
      );
      // Rated exactly at the 80th and 40th percentile marks of their pools,
      // both fully confident and freshly played, so the maths is exact.
      const ratingA = Rating(rating: 1750, deviation: 0, gamesPlayed: 50);
      const ratingB = Rating(rating: 1250, deviation: 0, gamesPlayed: 50);

      final result = index.compute(entries: [
        SportRatingEntry(
          sportId: 'cricket',
          rating: ratingA,
          population: populationA,
          lastPlayedAt: now,
        ),
        SportRatingEntry(
          sportId: 'kabaddi',
          rating: ratingB,
          population: populationB,
          lastPlayedAt: now,
        ),
      ], asOf: now);

      expect(result, isNotNull);
      expect(result!.components, hasLength(2));
      expect(result.components[0].percentile, 80);
      expect(result.components[1].percentile, 30);
      // Average of 80 and 30 is 55 — bounded by the same 0–100 scale as
      // either sport alone, never the sum (110).
      expect(result.index, closeTo(55, 1e-6));
    });

    test('playing more sports never inflates the index past any one of them',
        () {
      const perfectPop = SportPopulation(sportId: 's', ratings: [1000]);
      const perfectRating = Rating(rating: 2000, deviation: 0, gamesPlayed: 50);
      final entries = List.generate(
        5,
        (i) => SportRatingEntry(
          sportId: 'sport$i',
          rating: perfectRating,
          population: perfectPop,
          lastPlayedAt: now,
        ),
      );
      final result = index.compute(entries: entries, asOf: now);
      expect(result!.index, closeTo(100, 1e-6));
      expect(result.index, lessThanOrEqualTo(100));
    });
  });

  group('recency decay', () {
    test('a full half-life out halves the contribution', () {
      const population = SportPopulation(
        sportId: 'tennis',
        ratings: [1000, 1200, 1400, 1500, 1800],
      );
      const rating = Rating(rating: 1600, deviation: 0, gamesPlayed: 40);

      final fresh = index.compute(entries: [
        SportRatingEntry(
          sportId: 'tennis',
          rating: rating,
          population: population,
          lastPlayedAt: now,
        ),
      ], asOf: now)!;

      final staleByOneHalfLife = index.compute(entries: [
        SportRatingEntry(
          sportId: 'tennis',
          rating: rating,
          population: population,
          lastPlayedAt: now.subtract(const Duration(days: 180)),
        ),
      ], asOf: now)!;

      expect(fresh.index, closeTo(80, 1e-6)); // percentile 80, full weight
      expect(staleByOneHalfLife.index, closeTo(40, 1e-6)); // half of that
    });

    test('a custom half-life is honoured', () {
      const fastDecay = CrossSportIndex(recencyHalfLifeDays: 30);
      const population = SportPopulation(sportId: 'x', ratings: [1000]);
      const rating = Rating(rating: 2000, deviation: 0, gamesPlayed: 10);
      final result = fastDecay.compute(entries: [
        SportRatingEntry(
          sportId: 'x',
          rating: rating,
          population: population,
          lastPlayedAt: now.subtract(const Duration(days: 30)),
        ),
      ], asOf: now)!;
      expect(result.index, closeTo(50, 1e-6)); // 100 percentile * 0.5 weight
    });

    test('a missing last-played date decays to zero rather than crashing',
        () {
      const population = SportPopulation(sportId: 'x', ratings: [1000]);
      const rating = Rating(rating: 2000, deviation: 0, gamesPlayed: 10);
      final result = index.compute(entries: [
        const SportRatingEntry(
          sportId: 'x',
          rating: rating,
          population: population,
          lastPlayedAt: null,
        ),
      ], asOf: now)!;
      expect(result.components.single.recencyWeight, 0);
      expect(result.index, 0);
    });
  });

  group('confidence discounts uncertain ratings', () {
    test('a provisional player with huge RD is heavily discounted', () {
      const population = SportPopulation(
        sportId: 'hockey',
        ratings: [1400, 1500, 1600, 1700, 1800],
      );
      final confident = index.compute(entries: [
        SportRatingEntry(
          sportId: 'hockey',
          rating: const Rating(rating: 1650, deviation: 0, gamesPlayed: 30),
          population: population,
          lastPlayedAt: now,
        ),
      ], asOf: now)!;
      final uncertain = index.compute(entries: [
        SportRatingEntry(
          sportId: 'hockey',
          rating: const Rating(rating: 1650, deviation: 300, gamesPlayed: 5),
          population: population,
          lastPlayedAt: now,
        ),
      ], asOf: now)!;

      expect(uncertain.index, lessThan(confident.index));
      expect(confident.index, closeTo(60, 1e-6));
      const expectedUncertain = 60 * (1 - 300 / 350);
      expect(uncertain.index, closeTo(expectedUncertain, 1e-6));
    });

    test('a fresh, never-played rating (RD = default) zeroes that sport out',
        () {
      const population = SportPopulation(
        sportId: 'chess',
        ratings: [1400, 1500, 1600],
      );
      // gamesPlayed > 0 so this is NOT the "no rated sports" case — it's a
      // real, single played game whose rating still can't be trusted yet.
      final result = index.compute(entries: [
        SportRatingEntry(
          sportId: 'chess',
          rating: const Rating(gamesPlayed: 1), // default 1500/350
          population: population,
          lastPlayedAt: now,
        ),
      ], asOf: now)!;
      expect(result.index, 0);
      expect(result.components, hasLength(1)); // it still shows up, at zero
    });
  });

  group('no rated sports', () {
    test('an empty sport list returns null, never zero', () {
      expect(index.compute(entries: const []), isNull);
    });

    test('sports with zero games played contribute nothing and yield null',
        () {
      const population = SportPopulation(sportId: 'x', ratings: [1500]);
      final result = index.compute(entries: [
        const SportRatingEntry(
          sportId: 'x',
          rating: Rating(), // never actually played
          population: population,
          lastPlayedAt: null,
        ),
      ]);
      expect(result, isNull);
    });
  });

  group('bounded 0-100', () {
    test('never exceeds 100 even for a maxed-out multi-sport player', () {
      const pop = SportPopulation(sportId: 's', ratings: [1000, 1000]);
      const maxed = Rating(rating: 3000, deviation: 0, gamesPlayed: 100);
      final entries = List.generate(
        6,
        (i) => SportRatingEntry(
          sportId: 'sport$i',
          rating: maxed,
          population: pop,
          lastPlayedAt: now,
        ),
      );
      final result = index.compute(entries: entries, asOf: now)!;
      expect(result.index, lessThanOrEqualTo(100));
      expect(result.index, greaterThanOrEqualTo(0));
    });

    test('never goes below 0 for a stale, unconfident, bottom-ranked player',
        () {
      const pop = SportPopulation(sportId: 's', ratings: [3000, 3000]);
      const worst = Rating(rating: 1000, deviation: 349, gamesPlayed: 1);
      final result = index.compute(entries: [
        SportRatingEntry(
          sportId: 's',
          rating: worst,
          population: pop,
          lastPlayedAt: now.subtract(const Duration(days: 3650)),
        ),
      ], asOf: now)!;
      expect(result.index, greaterThanOrEqualTo(0));
      expect(result.index, lessThanOrEqualTo(100));
    });
  });
}
