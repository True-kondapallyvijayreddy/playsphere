import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/fixture.dart';
import '../core/models/match_player.dart';
import '../domain/career/career_stats.dart';
import '../domain/rating/glicko2.dart';
import '../domain/scoring/player_stats.dart';

/// Service responsible for calculating sport-specific contribution weights,
/// running Glicko-2 rating updates, and persisting ratings & career statistics
/// to Firestore when a match completes.
class RatingService {
  const RatingService({
    FirebaseFirestore? firestore,
    Glicko2? glicko2,
  })  : _db = firestore,
        _glicko2 = glicko2 ?? const Glicko2();

  final FirebaseFirestore? _db;
  final Glicko2 _glicko2;

  FirebaseFirestore get _firestore => _db ?? Refs.db;

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
  /// **These keys must match what the engines actually write.** They are the
  /// same camelCase names the plugins use for [PlayerTally]; an entry that
  /// does not correspond to a real tally key contributes nothing and silently
  /// reduces that sport to pure win/loss distribution — which §8.1 forbids
  /// explicitly, and which is exactly what happened while this table was
  /// written in snake_case.
  ///
  /// `test/rating_service_test.dart` asserts every key here is emitted by at
  /// least one registered engine, so the two cannot drift apart again.
  static const contributionWeights = <String, double>{
    // Goal sports — football, hockey.
    //
    // A clean sheet is deliberately absent: it is a property of the side at
    // full time, not a counter on a player, so there is nothing in the tally
    // to weight. It belongs in an award, not here.
    'goals': 30.0,
    'assists': 20.0,
    'saves': 5.0,
    'shotsOnTarget': 2.0,
    'pcGoals': 25.0,

    // Cricket.
    'runsScored': 1.0,
    'wickets': 20.0,
    'catches': 10.0,
    'stumpings': 10.0,
    'runOuts': 10.0,
    'runOutAssists': 5.0,
    'maidens': 5.0,

    // Basketball.
    'points': 1.0,
    'offRebounds': 1.5,
    'defRebounds': 1.5,
    'steals': 2.5,
    'blocks': 2.5,

    // Kabaddi.
    'raidPoints': 5.0,
    'tacklePoints': 5.0,
    'superRaids': 10.0,
    'superTackles': 10.0,

    // Volleyball and racket sports.
    'kills': 3.0,
    'aces': 5.0,
    'digs': 2.0,
    'pointsWon': 1.0,
    'serviceAces': 5.0,

    // Kho-kho. Dives are counted by type rather than as one "dive points"
    // bucket, because the two are worth different amounts in different
    // rulesets — see the UKK and KKFI presets.
    'touchPoints': 5.0,
    'poleDives': 5.0,
    'skyDives': 5.0,
    'dreamRunPoints': 5.0,

    // Mind and board sports.
    'boardsWon': 20.0,
    'queensCovered': 10.0,
  };

  /// A milestone worth a bonus on top of the per-unit weights, because a
  /// fifty is worth more than fifty singles spread over a season.
  static const _milestones = <String, ({num threshold, double bonus})>{
    'runsScored': (threshold: 50, bonus: 15.0),
    'wickets': (threshold: 5, bonus: 20.0),
    'raidPoints': (threshold: 10, bonus: 15.0),
    'tacklePoints': (threshold: 5, bonus: 15.0),
    'points': (threshold: 30, bonus: 15.0),
  };

  /// Computes raw MVP contribution points from a player's tally.
  double _computeContributionPoints(Map<String, num> tally) {
    if (tally.isEmpty) return 0.0;

    var pts = 0.0;
    for (final entry in tally.entries) {
      final weight = contributionWeights[entry.key];
      if (weight != null) pts += entry.value * weight;
    }
    for (final m in _milestones.entries) {
      final value = tally[m.key];
      if (value != null && value >= m.value.threshold) {
        pts += m.value.bonus;
      }
    }
    return pts;
  }

  /// Reads a player's Glicko-2 rating for a sport from Firestore, returning
  /// default rating (1500, 350, 0.06) if unrated.
  Future<Rating> getRating(String uid, String sportId) async {
    final snapshot = await Refs.userRating(uid, sportId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return const Rating();
    }
    return Rating.fromMap(snapshot.data()!);
  }

  /// Processes Glicko-2 rating updates and career statistics for all registered
  /// players in a completed fixture.
  Future<void> processMatchRatings({
    required Fixture fixture,
    required Map<String, dynamic> scoreState,
  }) async {
    // Career statistics are kept per sport; ratings additionally split by
    // time control for chess. Keying either on the plugin would merge chess,
    // carrom, athletics and swimming into one pool, because they share
    // engines — see Fixture.sport and Fixture.ratingKey.
    final sportId = fixture.sport;
    final ratingKey = fixture.ratingKey;
    final orgId = fixture.orgId;
    final playedAt = fixture.completedAt ?? DateTime.now();

    // 1. Identify registered players for both sides
    final sideAPlayers =
        fixture.lineupA.where((p) => p.uid != null).toList(growable: false);
    final sideBPlayers =
        fixture.lineupB.where((p) => p.uid != null).toList(growable: false);

    if (sideAPlayers.isEmpty && sideBPlayers.isEmpty) return;

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

    // 6. Accumulate career statistics
    final contributions = const CareerAggregator().contributionsFrom(
      scoreState: scoreState,
      ctx: fixture.scoringContext(),
      sportId: sportId,
      orgId: orgId,
      playedAt: playedAt,
    );

    final batch = _firestore.batch();

    // 7. Rate Side A players
    for (final player in sideAPlayers) {
      final uid = player.uid!;
      final current = currentRatings[uid] ?? const Rating();
      final weight = weightsA[player.id] ?? 1.0;
      final updated = _glicko2.rate(
        current,
        [RatingGame(opponent: opponentRatingForA, score: scoreA, weight: weight)],
      );
      batch.set(
        Refs.userRating(uid, ratingKey),
        updated.toMap(),
        SetOptions(merge: true),
      );
    }

    // 8. Rate Side B players
    for (final player in sideBPlayers) {
      final uid = player.uid!;
      final current = currentRatings[uid] ?? const Rating();
      final weight = weightsB[player.id] ?? 1.0;
      final updated = _glicko2.rate(
        current,
        [RatingGame(opponent: opponentRatingForB, score: scoreB, weight: weight)],
      );
      batch.set(
        Refs.userRating(uid, ratingKey),
        updated.toMap(),
        SetOptions(merge: true),
      );
    }

    // 9. Update Career Stats documents in Firestore
    for (final c in contributions) {
      final statRef = Refs.userCareerStat(c.uid, sportId);
      final fields = <String, Object?>{
        'uid': c.uid,
        'sportId': sportId,
        'matchesPlayed': FieldValue.increment(1),
        'lastPlayedAt': Timestamp.fromDate(c.playedAt),
      };
      for (final entry in c.tally.entries) {
        fields['tally.${entry.key}'] = FieldValue.increment(entry.value);
      }
      batch.set(statRef, fields, SetOptions(merge: true));
    }

    await batch.commit();
  }
}
