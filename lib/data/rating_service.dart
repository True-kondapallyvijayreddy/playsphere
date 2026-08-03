import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/fixture.dart';
import '../core/models/match_player.dart';
import '../domain/rating/glicko2.dart';
import '../domain/scoring/match_award.dart';
import '../domain/scoring/player_stats.dart';

/// Contribution weights and Glicko-2 projections.
///
/// No longer persists anything: `onMatchSettled` settles ratings and career
/// statistics server-side, and `firestore.rules` denies every client write to
/// both collections. See [processMatchRatings] for why that move was
/// necessary even though the old client path was already tightly guarded.
class RatingService {
  const RatingService({
    FirebaseFirestore? firestore,
    Glicko2? glicko2,
  })  : _db = firestore,
        _glicko2 = glicko2 ?? const Glicko2();

  /// Retained so existing call sites keep compiling, and unused: nothing in
  /// this class writes any more.
  // ignore: unused_field
  final FirebaseFirestore? _db;
  final Glicko2 _glicko2;

  /// Calculates individual performance weights (w_i in [0.2, 1.8]) for a squad
  /// based on their sport-specific player tallies.
  ///
  /// Higher contribution relative to team average yields higher weight.
  /// If tallies are empty or zero, returns 1.0 for all players.
  Map<String, double> calculatePerformanceWeights(
    Map<String, dynamic> scoreState,
    List<MatchPlayer> lineup,
  ) {
    if (lineup.isEmpty) return const {};

    final pointsMap = <String, double>{};
    var totalTeamPoints = 0.0;

    for (final player in lineup) {
      final tally = PlayerTally.of(scoreState, player.id);
      final rawPts = _computeContributionPoints(tally);
      pointsMap[player.id] = rawPts;
      totalTeamPoints += rawPts;
    }

    final avgPoints = totalTeamPoints / lineup.length;
    final weights = <String, double>{};

    for (final player in lineup) {
      final pts = pointsMap[player.id] ?? 0.0;
      if (avgPoints <= 0) {
        weights[player.id] = 1.0;
      } else {
        final rawWeight = pts / avgPoints;
        // Clamp weight to [0.2, 1.8] to guarantee baseline rating adjustment
        // while heavily rewarding high MVP contribution.
        weights[player.id] = rawWeight.clamp(0.2, 1.8);
      }
    }

    return weights;
  }

  /// What one unit of each statistic is worth when judging a contribution.
  ///
  /// Now a single definition shared with the MVP award — see
  /// [ContributionScoring.weights]. It used to live here, which meant the
  /// best player of a match and the biggest rating gain in that same match
  /// were computed from two tables that could drift apart. Re-exported rather
  /// than moved outright because `test/rating_service_test.dart` asserts
  /// against this name that every key is emitted by a real engine.
  static const contributionWeights = ContributionScoring.weights;

  /// Computes raw MVP contribution points from a player's tally.
  double _computeContributionPoints(Map<String, num> tally) =>
      ContributionScoring.pointsFrom(tally);

  /// Reads a player's Glicko-2 rating for a sport from Firestore, returning
  /// default rating (1500, 350, 0.06) if unrated.
  Future<Rating> getRating(String uid, String sportId) async {
    final snapshot = await Refs.userRating(uid, sportId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return const Rating();
    }
    return Rating.fromMap(snapshot.data()!);
  }

  /// Projects what a finished match *would* do to everyone's rating.
  ///
  /// ## This no longer writes anything
  ///
  /// Settlement moved to the `onMatchSettled` Cloud Function, and
  /// `firestore.rules` now denies every client write to `ratings/` and
  /// `career_stats/`. The reason is in the rules file: the old client path was
  /// the narrowest write in the product — assigned scorer only, on a fixture
  /// the target actually played in, every field typed and bounded, one game at
  /// a time — and narrow still is not verifiable. Nothing in a rule can tell a
  /// real single-game delta from a small self-serving nudge repeated over a
  /// season by somebody who scores genuine matches.
  ///
  /// The method is kept because the projection is still worth having on the
  /// client: a scoring pad can show "this result moves you +18" before the
  /// server confirms it. It returns the computed ratings instead of
  /// persisting them.
  Future<Map<String, Rating>> processMatchRatings({
    required Fixture fixture,
    required Map<String, dynamic> scoreState,
  }) async {
    // A result nobody played is not evidence about anybody's skill.
    //
    // This guard is the point of `MatchResultType`. A walkover, a no-show, a
    // disqualification and a concession all produce a winner, and rating that
    // winner as though they had beaten someone is how a rating system stops
    // meaning anything — a player could climb by drawing opponents who never
    // turn up. Until this check existed nothing anywhere asked the question:
    // forced results happened to skip the rating path by construction rather
    // than by decision, so the protection was accidental and one refactor
    // away from vanishing.
    //
    // A retirement passes deliberately. Somebody did play, the winner earned
    // it, and every federation counts it.
    if (!fixture.resultType.countsForRating) return const {};
    // Career statistics are kept per sport; ratings additionally split by
    // time control for chess. Keying either on the plugin would merge chess,
    // carrom, athletics and swimming into one pool, because they share
    // engines — see Fixture.sport and Fixture.ratingKey.
    final ratingKey = fixture.ratingKey;

    // 1. Identify registered players for both sides
    final sideAPlayers =
        fixture.lineupA.where((p) => p.uid != null).toList(growable: false);
    final sideBPlayers =
        fixture.lineupB.where((p) => p.uid != null).toList(growable: false);

    if (sideAPlayers.isEmpty && sideBPlayers.isEmpty) return const {};

    // 2. Fetch existing ratings for all registered players
    final allPlayers = [...sideAPlayers, ...sideBPlayers];
    final currentRatings = <String, Rating>{};

    for (final player in allPlayers) {
      currentRatings[player.uid!] = await getRating(player.uid!, ratingKey);
    }

    // 3. Compute side average ratings for opponent benchmark
    double averageRating(List<MatchPlayer> squad) {
      if (squad.isEmpty) return Rating.defaultRating;
      final sum = squad.fold<double>(
        0.0,
        (acc, p) =>
            acc + (currentRatings[p.uid!]?.rating ?? Rating.defaultRating),
      );
      return sum / squad.length;
    }

    final avgRatingA = averageRating(sideAPlayers);
    final avgRatingB = averageRating(sideBPlayers);

    final opponentRatingForA =
        Rating(rating: avgRatingB, deviation: Rating.defaultDeviation);
    final opponentRatingForB =
        Rating(rating: avgRatingA, deviation: Rating.defaultDeviation);

    // 4. Calculate team outcomes S in {1.0, 0.5, 0.0}
    double scoreA = 0.5;
    double scoreB = 0.5;
    if (!fixture.isDraw) {
      if (fixture.winnerEntrantId == fixture.entrantAId) {
        scoreA = 1.0;
        scoreB = 0.0;
      } else if (fixture.winnerEntrantId == fixture.entrantBId) {
        scoreA = 0.0;
        scoreB = 1.0;
      }
    }

    // 5. Calculate performance contribution weights for both teams
    final weightsA = calculatePerformanceWeights(scoreState, fixture.lineupA);
    final weightsB = calculatePerformanceWeights(scoreState, fixture.lineupB);


    // Nothing is written here any more. `onMatchSettled` reads this same
    // fixture server-side and derives both the ratings and the career tallies
    // from it, so there is no client write path to secure — which was the
    // whole point of moving it.
    //
    // The projection is still computed and returned: a scoring pad showing
    // "this result moves you +18" before the server confirms is worth having,
    // and it is now honestly a *preview* rather than the authority.
    final projected = <String, Rating>{};

    for (final player in sideAPlayers) {
      final uid = player.uid!;
      projected[uid] = _glicko2.rate(
        currentRatings[uid] ?? const Rating(),
        [
          RatingGame(
            opponent: opponentRatingForA,
            score: scoreA,
            weight: weightsA[player.id] ?? 1.0,
          ),
        ],
      );
    }

    for (final player in sideBPlayers) {
      final uid = player.uid!;
      projected[uid] = _glicko2.rate(
        currentRatings[uid] ?? const Rating(),
        [
          RatingGame(
            opponent: opponentRatingForB,
            score: scoreB,
            weight: weightsB[player.id] ?? 1.0,
          ),
        ],
      );
    }

    return projected;
  }
}
