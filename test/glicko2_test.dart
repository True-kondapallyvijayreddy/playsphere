import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/rating/glicko2.dart';

/// Glicko-2, checked against Glickman's own worked example and against the
/// properties that make it worth using over Elo at grassroots level.
void main() {
  const engine = Glicko2(systemConstant: 0.5);

  group("Glickman's published worked example", () {
    // From the Glicko-2 paper: a player rated 1500 (RD 200) plays three games
    // against 1400/30, 1550/100 and 1700/300, winning the first and losing the
    // other two. The expected outcome is ~1464.06 with RD ~151.52.
    test('reproduces the paper to two decimal places', () {
      const player = Rating(rating: 1500, deviation: 200, volatility: 0.06);
      final result = engine.rate(player, const [
        RatingGame(
          opponent: Rating(rating: 1400, deviation: 30),
          score: 1,
        ),
        RatingGame(
          opponent: Rating(rating: 1550, deviation: 100),
          score: 0,
        ),
        RatingGame(
          opponent: Rating(rating: 1700, deviation: 300),
          score: 0,
        ),
      ]);

      expect(result.rating, closeTo(1464.06, 0.05));
      expect(result.deviation, closeTo(151.52, 0.05));
      expect(result.volatility, closeTo(0.05999, 0.0001));
    });
  });

  group('uncertainty is the point', () {
    test('an unrated player starts wide open and provisional', () {
      const fresh = Rating();
      expect(fresh.rating, 1500);
      expect(fresh.deviation, 350);
      expect(fresh.isProvisional, isTrue);
    });

    test('playing narrows the deviation', () {
      const fresh = Rating();
      final after = engine.rate(fresh, const [
        RatingGame(opponent: Rating(rating: 1500, deviation: 50), score: 1),
      ]);
      expect(after.deviation, lessThan(fresh.deviation));
    });

    test('not playing widens it again', () {
      // A rating nobody has tested for months is genuinely less reliable, and
      // a system that pretends otherwise leaves a stale name at the top of the
      // leaderboard forever.
      const settled = Rating(rating: 1700, deviation: 60, gamesPlayed: 40);
      final idle = engine.rate(settled, const []);
      expect(idle.rating, settled.rating); // unchanged
      expect(idle.deviation, greaterThan(settled.deviation));
    });

    test('deviation never grows past the unrated default', () {
      const stale = Rating(rating: 1700, deviation: 349);
      var r = stale;
      for (var period = 0; period < 50; period++) {
        r = engine.rate(r, const []);
      }
      expect(r.deviation, lessThanOrEqualTo(Rating.defaultDeviation));
    });
  });

  group('results move ratings the right way', () {
    test('beating a stronger opponent gains more than beating a weaker one', () {
      const player = Rating(rating: 1500, deviation: 80);
      final vsStrong = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1800, deviation: 80), score: 1),
      ]);
      final vsWeak = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1200, deviation: 80), score: 1),
      ]);
      expect(vsStrong.rating, greaterThan(vsWeak.rating));
      expect(vsWeak.rating, greaterThan(player.rating)); // still a gain
    });

    test('losing to a weaker opponent costs more than losing to a stronger', () {
      const player = Rating(rating: 1500, deviation: 80);
      final toWeak = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1200, deviation: 80), score: 0),
      ]);
      final toStrong = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1800, deviation: 80), score: 0),
      ]);
      expect(toWeak.rating, lessThan(toStrong.rating));
    });

    test('a draw between equals barely moves anything', () {
      const player = Rating(rating: 1500, deviation: 60);
      final drawn = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1500, deviation: 60), score: 0.5),
      ]);
      expect(drawn.rating, closeTo(1500, 1.0));
    });

    test('an uncertain opponent moves you less than a well-known one', () {
      // Beating someone whose rating nobody trusts is weak evidence.
      const player = Rating(rating: 1500, deviation: 80);
      final vsKnown = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1600, deviation: 30), score: 1),
      ]);
      final vsUnknown = engine.rate(player, const [
        RatingGame(opponent: Rating(rating: 1600, deviation: 300), score: 1),
      ]);
      expect(vsKnown.rating, greaterThan(vsUnknown.rating));
    });
  });

  group('team sports weight a player by contribution', () {
    test('a lower weight moves the rating less', () {
      const player = Rating(rating: 1500, deviation: 80);
      final full = engine.rate(player, const [
        RatingGame(
          opponent: Rating(rating: 1600, deviation: 60),
          score: 1,
          weight: 1.0,
        ),
      ]);
      final partial = engine.rate(player, const [
        RatingGame(
          opponent: Rating(rating: 1600, deviation: 60),
          score: 1,
          weight: 0.2,
        ),
      ]);
      // A substitute who played five minutes must not be credited with the
      // win as heavily as the player who decided it.
      expect(partial.rating, lessThan(full.rating));
      expect(partial.rating, greaterThan(player.rating));
    });
  });

  group('presentation', () {
    test('a confidence band is reported, not a bare number', () {
      const r = Rating(rating: 1500, deviation: 100);
      final (low, high) = r.confidenceInterval;
      expect(low, 1300);
      expect(high, 1700);
    });

    test('tiers are what a first-time player sees', () {
      expect(const Rating(rating: 1100).tier, 'Beginner');
      expect(const Rating(rating: 1500).tier, 'Club');
      expect(const Rating(rating: 2100).tier, 'State');
      expect(const Rating(rating: 2400).tier, 'Elite');
    });
  });

  group('anti-gaming', () {
    test('an implausible single-period swing is detectable', () {
      const before = Rating(rating: 1500, deviation: 60);
      const after = Rating(rating: 1650, deviation: 60);
      expect(Glicko2.isImplausibleSwing(before, after), isTrue);
      expect(
        Glicko2.isImplausibleSwing(before, const Rating(rating: 1540)),
        isFalse,
      );
    });
  });

  group('round trip', () {
    test('survives storage', () {
      const r = Rating(
        rating: 1612.5,
        deviation: 74.2,
        volatility: 0.0587,
        gamesPlayed: 19,
      );
      final back = Rating.fromMap(
        Map<String, dynamic>.from(r.toMap()),
      );
      expect(back.rating, r.rating);
      expect(back.deviation, r.deviation);
      expect(back.volatility, r.volatility);
      expect(back.gamesPlayed, r.gamesPlayed);
    });

    test('a missing document reads as an unrated player', () {
      final fresh = Rating.fromMap(null);
      expect(fresh.rating, Rating.defaultRating);
      expect(fresh.isProvisional, isTrue);
    });
  });
}
