import 'dart:math';

import '../../core/models/competition.dart';
import '../rating/glicko2.dart';

/// One entrant's seeding verdict, with the reason attached.
///
/// The reason is not decoration. A player who expected to be seeded and was
/// not will ask why, and "you have played two matches, which is not enough for
/// us to know how good you are" is an answer an organizer can give. A bare
/// null seed is not.
class SeedVerdict {
  const SeedVerdict({
    required this.entrantId,
    required this.seed,
    required this.rating,
    required this.reason,
  });

  final String entrantId;

  /// 1 = top seed. Null means unseeded — drawn at random with everyone else.
  final int? seed;

  /// The rating this decision was made on, for the published seeding list.
  final double? rating;

  final String reason;

  bool get isSeeded => seed != null;
}

class SeedingResult {
  const SeedingResult({required this.verdicts, required this.seededCount});

  final List<SeedVerdict> verdicts;
  final int seededCount;

  Map<String, int> get seedsByEntrant => {
        for (final v in verdicts)
          if (v.seed != null) v.entrantId: v.seed!,
      };
}

/// Decides who is seeded, from the ratings the product already computes.
///
/// ## Why this had to be written
///
/// `Entrant.seed` was a hand-typed integer, and `FixtureGenerator._seedOrShuffle`
/// fell back to `Random(42)` when nobody had one — so an unseeded 38-player
/// draw was a raffle. Meanwhile `glicko2.dart` and `cross_sport_index.dart`
/// were built and tested. The product computed a ranking and then ignored it
/// at the one moment a ranking is for.
///
/// ## Why an unrated player is unseeded, never seed 1
///
/// Glicko-2 carries a rating deviation precisely because a rating alone is not
/// a claim about strength — it is a claim plus a confidence. A newcomer starts
/// at 1500 with RD 350, which is the algorithm saying "we have no idea". Sorting
/// on rating alone would place that newcomer above every established player
/// rated 1400, and hand them a protected bracket position on the strength of
/// having never played.
///
/// So a player is seedable only when the rating means something: enough games,
/// and a deviation small enough to be a statement rather than a placeholder.
/// Everyone else is drawn at random, which is both fairer and what every
/// federation does with an unranked entry.
/// One rating for a side made of several people.
///
/// ## Why a team needed its own answer
///
/// [SeedingPolicy] reads `ratings[entrant.id]`, and the only thing that ever
/// filled that map was `RatingService.getRating(entrant.uid)` — which is null
/// for every team, however strong. So a league of clubs, a school kabaddi
/// tournament and a corporate cricket season all drew their brackets from
/// `Random(42)` while Glicko-2 sat computed for every individual in them. The
/// ratings existed; nothing added them up.
///
/// ## How the three numbers are combined, and why each is the conservative one
///
///  - **Rating: the mean.** A team is its players, and at seeding time there
///    is nothing to weight them by — minutes, roles and contribution are facts
///    about matches already played, not about a squad list.
///
///  - **Deviation: the mean, NOT the standard error of the mean.** The
///    tempting formula is `sqrt(Σrd²)/n`, which shrinks with squad size: it
///    would hand a team of eleven complete unknowns an RD of 105 — the
///    algorithm's way of saying "we are confident" — out of eleven separate
///    admissions that we know nothing. That is manufacturing certainty from
///    ignorance. The mean says what is true instead: a team of unknowns is
///    unknown, a team of established players is known, and squad size does not
///    change either. It also leaves room for the uncertainty no per-player
///    number captures at all — which eleven of the twenty on the sheet
///    actually turn up.
///
///  - **Games played: the median.** [SeedingPolicy.minGames] asks whether
///    there is enough evidence to seed on. The mean lets one veteran of sixty
///    matches carry ten debutants over the line; the minimum lets one debutant
///    sink a settled side. The median asks the question that matters — is this
///    side, in the main, made of players we have seen — and neither outlier
///    moves it.
///
/// Returns null for a side with nobody rated at all, which the policy already
/// reads correctly as "no rating yet — drawn at random".
Rating? combineTeamRating(List<Rating> members) {
  final rated = [
    for (final r in members)
      // A member with no rating document at all arrives as the Glicko default
      // (1500 / 350 / 0 games). Averaging those in would drag a strong side
      // toward 1500 and pretend the absent player was merely average, so they
      // are excluded from the rating and counted in the median as the zero
      // games they have.
      if (r.gamesPlayed > 0) r,
  ];
  if (rated.isEmpty) return null;

  final rating =
      rated.map((r) => r.rating).reduce((a, b) => a + b) / rated.length;
  final deviation =
      rated.map((r) => r.deviation).reduce((a, b) => a + b) / rated.length;
  final volatility =
      rated.map((r) => r.volatility).reduce((a, b) => a + b) / rated.length;

  // Over EVERY member, not only the rated ones: a squad that is half
  // debutants is half unproven, and dropping them from the count would let
  // the two players who have records speak for the eleven who have not.
  final games = [for (final r in members) r.gamesPlayed]..sort();
  final median = games.isEmpty
      ? 0
      : games.length.isOdd
          ? games[games.length ~/ 2]
          : ((games[games.length ~/ 2 - 1] + games[games.length ~/ 2]) / 2)
              .floor();

  return Rating(
    rating: rating,
    deviation: deviation,
    volatility: volatility,
    gamesPlayed: median,
  );
}

class SeedingPolicy {
  const SeedingPolicy({
    this.minGames = 5,
    this.maxDeviation = 150,
  });

  /// Matches needed before a rating is treated as evidence.
  final int minGames;

  /// Above this RD, Glicko itself is saying it does not know. 350 is the
  /// starting value; 150 is roughly where a rating becomes a statement.
  final double maxDeviation;

  /// How many seeds a draw of [fieldSize] should carry.
  ///
  /// A quarter of the bracket, which is the federation convention — 8 seeds in
  /// a 32 draw, 16 in a 64 — and it is not arbitrary: it is exactly the number
  /// that can be kept apart until the quarter-finals. Seeding more than that
  /// makes promises the bracket shape cannot keep.
  static int seedCountFor(int fieldSize) {
    if (fieldSize < 4) return 0;
    var bracket = 1;
    while (bracket < fieldSize) {
      bracket *= 2;
    }
    return max(2, bracket ~/ 4);
  }

  /// Ranks [entrants] by rating and returns who is seeded, and why.
  ///
  /// [ratings] is keyed by entrant id. A missing entry is treated as unrated,
  /// which is the correct reading — a player with no rating document has
  /// played nothing we have recorded.
  SeedingResult assign({
    required List<Entrant> entrants,
    required Map<String, Rating> ratings,
    int? maxSeeds,
  }) {
    final active = [
      for (final e in entrants)
        if (!e.withdrawn) e,
    ];

    final seedable = <({Entrant entrant, Rating rating})>[];
    final unseedable = <SeedVerdict>[];

    for (final e in active) {
      final r = ratings[e.id];
      if (r == null) {
        unseedable.add(SeedVerdict(
          entrantId: e.id,
          seed: null,
          rating: null,
          reason: 'No rating yet — drawn at random.',
        ));
        continue;
      }
      if (r.gamesPlayed < minGames) {
        unseedable.add(SeedVerdict(
          entrantId: e.id,
          seed: null,
          rating: r.rating,
          reason: '${r.gamesPlayed} of $minGames rated matches played — '
              'not enough to seed on. Drawn at random.',
        ));
        continue;
      }
      if (r.deviation > maxDeviation) {
        unseedable.add(SeedVerdict(
          entrantId: e.id,
          seed: null,
          rating: r.rating,
          reason: 'Rating not settled enough to seed on '
              '(±${(2 * r.deviation).round()}). Drawn at random.',
        ));
        continue;
      }
      seedable.add((entrant: e, rating: r));
    }

    // Strongest first. Ties break on the tighter deviation — between two
    // players of equal rating, the one we are more certain about is the safer
    // one to protect — and then on id, so the order is total and a redrawn
    // seeding list is identical.
    seedable.sort((a, b) {
      final byRating = b.rating.rating.compareTo(a.rating.rating);
      if (byRating != 0) return byRating;
      final byRd = a.rating.deviation.compareTo(b.rating.deviation);
      if (byRd != 0) return byRd;
      return a.entrant.id.compareTo(b.entrant.id);
    });

    final wanted = maxSeeds ?? seedCountFor(active.length);
    final count = min(wanted, seedable.length);

    final verdicts = <SeedVerdict>[
      for (var i = 0; i < seedable.length; i++)
        if (i < count)
          SeedVerdict(
            entrantId: seedable[i].entrant.id,
            seed: i + 1,
            rating: seedable[i].rating.rating,
            reason: 'Seed ${i + 1} on a rating of '
                '${seedable[i].rating.rating.round()}.',
          )
        else
          SeedVerdict(
            entrantId: seedable[i].entrant.id,
            seed: null,
            rating: seedable[i].rating.rating,
            reason: 'Rated, but outside the top $count. Drawn at random.',
          ),
      ...unseedable,
    ];

    return SeedingResult(verdicts: verdicts, seededCount: count);
  }
}
