import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/glicko_badge.dart';
import 'package:playsphere/domain/rating/glicko2.dart';
import 'package:playsphere/domain/rating/overall_glicko.dart';

/// These numbers are the contract between `lib/domain/rating/overall_glicko.dart`
/// and `functions/overall_glicko.js`. The two implement the same formula for
/// two different reasons — the app has to be able to explain the number it is
/// showing, the server has to denormalise it onto the user document — and
/// nothing but this table stops them drifting apart.
void main() {
  const engine = OverallGlickoEngine();
  final now = DateTime.utc(2026, 8, 27);

  /// An established rating: RD 60 (confidence 0.829), played yesterday.
  ///
  /// [deviation] is a parameter because RD and match count move together in
  /// real Glicko-2 — four games leaves an RD around 180, forty leaves around
  /// 60 — and a test that pairs a forty-game deviation with a four-game record
  /// would be asserting against a state the engine can never actually be
  /// handed.
  SportRatingEvidence established(String sport, double rating,
          {int matches = 40, double deviation = 60}) =>
      SportRatingEvidence(
        sportId: sport,
        rating: Rating(
          rating: rating,
          deviation: deviation,
          gamesPlayed: matches,
        ),
        lastPlayedAt: now.subtract(const Duration(days: 1)),
      );

  group('the worked example on the class doc', () {
    test('four established sports blend to 1717', () {
      final result = engine.compute(
        entries: [
          established('cricket', 1842),
          established('badminton', 1618),
          established('football', 1497),
          established('volleyball', 1325),
        ],
        asOf: now,
      );

      expect(result, isNotNull);
      // Between the mean (1570) and the best sport (1842), leaning to the
      // best — which is the whole point of the rank decay.
      expect(result!.overall.round(), 1717);
      expect(result.isProvisional, isFalse);
      expect(result.primary.sportId, 'cricket');
      expect(
        result.components.map((c) => c.sportId),
        ['cricket', 'badminton', 'football', 'volleyball'],
      );
    });

    test('the breakdown reproduces the headline', () {
      final result = engine.compute(
        entries: [
          established('cricket', 1842),
          established('badminton', 1618),
          established('football', 1497),
          established('volleyball', 1325),
        ],
        asOf: now,
      )!;

      var weighted = 0.0;
      var total = 0.0;
      for (final c in result.components) {
        weighted += c.rating * c.weight;
        total += c.weight;
      }
      final blend = weighted / total;
      final rebuilt = 1500 + (blend - 1500) * result.evidenceWeight;

      // The profile explains the number by re-deriving it from the same
      // components it renders. If that ever stops working, the explanation on
      // screen is fiction.
      expect(rebuilt, closeTo(result.overall, 0.0001));
    });
  });

  group('a single sport is not diluted', () {
    test('an established one-sport player keeps their own rating', () {
      final result = engine.compute(
        entries: [established('cricket', 1842)],
        asOf: now,
      )!;

      // Not exactly 1842 — forty matches leave a sliver of shrinkage — but
      // close enough that the profile does not look like it is arguing with
      // the cricket card two rows below it.
      expect(result.overall, closeTo(1842, 3));
      expect(result.isProvisional, isFalse);
    });

    test('dabbling in a second sport costs far less than a mean would', () {
      final one = engine.compute(
        entries: [established('cricket', 1842)],
        asOf: now,
      )!;
      final two = engine.compute(
        entries: [
          established('cricket', 1842),
          // Four games of volleyball for fun. The RD that goes with four
          // games is what keeps this cheap: an uncertain rating gets little
          // say in the blend, so a casual sport cannot rewrite an identity
          // built on forty cricket matches.
          established('volleyball', 1325, matches: 4, deviation: 180),
        ],
        asOf: now,
      )!;

      const mean = (1842 + 1325) / 2; // 1583.5 — what a naive average gives
      expect(two.overall, greaterThan(mean + 100));
      expect(one.overall - two.overall, lessThan(120));
      expect(two.primary.sportId, 'cricket');
    });
  });

  group('thin evidence cannot mint a headline number', () {
    test('two matches are shrunk hard toward 1500 and flagged', () {
      final result = engine.compute(
        entries: [
          SportRatingEvidence(
            sportId: 'cricket',
            // What Glicko-2 leaves after two wins: high rating, high RD.
            rating: const Rating(rating: 1750, deviation: 290, gamesPlayed: 2),
            lastPlayedAt: now,
          ),
        ],
        asOf: now,
      )!;

      expect(result.isProvisional, isTrue);
      expect(result.overall, lessThan(1600));
      expect(result.overall, greaterThan(1500));
    });

    test('an unplayed sport does not vote', () {
      final result = engine.compute(
        entries: [
          established('cricket', 1842),
          const SportRatingEvidence(
            sportId: 'football',
            rating: Rating(), // signed up, never played
          ),
        ],
        asOf: now,
      )!;

      expect(result.components, hasLength(1));
      expect(result.components.single.sportId, 'cricket');
    });

    test('no rated match at all is null, never 1500', () {
      expect(
        engine.compute(entries: const [], asOf: now),
        isNull,
      );
      expect(
        engine.compute(
          entries: const [SportRatingEvidence(sportId: 'cricket', rating: Rating())],
          asOf: now,
        ),
        isNull,
      );
    });
  });

  group('recency', () {
    test('a sport not played for a year counts for a quarter', () {
      final result = engine.compute(
        entries: [
          SportRatingEvidence(
            sportId: 'cricket',
            rating: const Rating(rating: 1842, deviation: 60, gamesPlayed: 40),
            lastPlayedAt: now.subtract(const Duration(days: 365)),
          ),
        ],
        asOf: now,
      )!;

      expect(result.components.single.recency, closeTo(0.25, 0.01));
      // Both the blend weight and the effective match count decay, so a rating
      // that has sat untouched for a year no longer carries a full headline.
      expect(result.overall, lessThan(1842));
      expect(result.overall, greaterThan(1500));
    });

    test('a missing timestamp is a data gap, not an absence', () {
      final result = engine.compute(
        entries: [
          const SportRatingEvidence(
            sportId: 'cricket',
            rating: Rating(rating: 1842, deviation: 60, gamesPlayed: 40),
          ),
        ],
        asOf: now,
      )!;

      expect(result.components.single.recency, 1.0);
    });
  });

  group('chess time controls collapse to one sport', () {
    test('blitz and classical do not count as two sports', () {
      final result = engine.compute(
        entries: [
          established('chess:blitz', 1900),
          established('chess:classical', 1700, matches: 10),
          established('cricket', 1600),
        ],
        asOf: now,
      )!;

      expect(result.components.map((c) => c.sportId), ['chess', 'cricket']);
      // The better-evidenced reading stands for the sport: classical has the
      // same RD here, so blitz wins the tie on nothing but being first — what
      // matters is that only one chess row survives.
      expect(result.components.first.matches, anyOf(40, 10));
    });

    test('an underscore in a real sport id is NOT a separator', () {
      // The bug this pins. `table_tennis`, `kho_kho`, `athletics_sprint` and
      // `athletics_field` are whole sport ids. Splitting on `_` as well as `:`
      // would truncate table tennis to `table` — which matches nothing in
      // `SportCatalog`, so the profile would render it as a grey "Other" tile
      // — and would merge sprint and field athletics into a single pool whose
      // ratings measure two unrelated abilities.
      final result = engine.compute(
        entries: [
          established('table_tennis', 1800),
          established('athletics_sprint', 1700),
          established('athletics_field', 1600),
          established('kho_kho', 1550),
        ],
        asOf: now,
      )!;

      expect(
        result.components.map((c) => c.sportId),
        ['table_tennis', 'athletics_sprint', 'athletics_field', 'kho_kho'],
      );
    });
  });

  _badgeTests();

  test('order is stable for identical inputs', () {
    List<SportRatingEvidence> entries() => [
          established('badminton', 1600),
          established('cricket', 1600),
          established('football', 1600),
        ];

    final a = engine.compute(entries: entries(), asOf: now)!;
    final b = engine.compute(entries: entries().reversed.toList(), asOf: now)!;

    expect(
      a.components.map((c) => c.sportId),
      b.components.map((c) => c.sportId),
    );
    expect(a.overall, closeTo(b.overall, 0.0001));
  });
}

/// The travelling copy — what a roster, an entry list or a player card reads.
///
/// Decoding it is not the formality it looks like. The one piece of real logic
/// is the re-sort, and the reason it exists is the reason this group does.
void _badgeTests() {
  group('GlickoBadge', () {
    test('comes back strongest-first however Firestore ordered the map', () {
      // A Firestore map is unordered and arrives keyed alphabetically, so the
      // server's rank order does not survive the wire. Without the re-sort in
      // `fromMap`, every card in the app would silently list sports in
      // alphabetical order and look like the rating was wrong.
      final badge = GlickoBadge.fromMap({
        'overall': 1717,
        'provisional': false,
        'sports': {'badminton': 1618, 'cricket': 1842, 'football': 1497},
        'sportCount': 4,
      })!;

      expect(badge.sports.keys.toList(), ['cricket', 'badminton', 'football']);
      expect(badge.overall, 1717);
      expect(badge.hiddenSportCount, 1);
    });

    test('a missing provisional flag reads as provisional', () {
      // Absent means absent. A document written before the flag existed must
      // not claim a confidence nothing measured.
      final badge = GlickoBadge.fromMap({'overall': 1600, 'sports': {}})!;
      expect(badge.provisional, isTrue);
    });

    test('an absent or malformed map is null, not a number', () {
      expect(GlickoBadge.fromMap(null), isNull);
      expect(GlickoBadge.fromMap('1700'), isNull);
      expect(GlickoBadge.fromMap({'sports': {}}), isNull);
    });

    test('ratingFor answers for a base sport and its time controls', () {
      final badge = GlickoBadge.fromMap({
        'overall': 1700,
        'provisional': false,
        'sports': {'chess': 1900, 'cricket': 1600},
        'sportCount': 2,
      })!;

      expect(badge.ratingFor('chess'), 1900);
      expect(badge.ratingFor('chess:blitz'), 1900);
      expect(badge.ratingFor('chess:classical'), 1900);
      // The colon is the ONLY separator. `Fixture.ratingKey` never writes an
      // underscore, and real sport ids contain them, so an underscore has to
      // be part of the id rather than a delimiter.
      expect(badge.ratingFor('table_tennis'), isNull);
      // Not carried is not the same as unrated — the caller falls back to the
      // overall rather than showing a blank. See `GlickoChip.forSport`.
      expect(badge.ratingFor('kabaddi'), isNull);
    });
  });
}
