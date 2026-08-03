import '../../core/models/match_player.dart';
import 'player_stats.dart';

/// Who was the best player in a match, and by how much.
///
/// The flow declares a winner AND a best performer at the final ball, and a
/// grassroots match without one is missing the part people actually talk about
/// afterwards. A club match has no jury, so this is computed from what the
/// scorer already recorded rather than voted on: the same contribution points
/// that decide how a team result is distributed across a squad's ratings.
///
/// One definition, deliberately. If the MVP were computed from a second table
/// of weights it would eventually disagree with the ratings — the app would
/// name one player the best and hand a different one the biggest rating gain,
/// in the same match, and both numbers would be indefensible.
class ContributionScoring {
  const ContributionScoring._();

  /// What one unit of each statistic is worth when judging a contribution.
  ///
  /// **These keys must match what the engines actually write.** They are the
  /// same camelCase names the plugins use for [PlayerTally]; an entry that
  /// does not correspond to a real tally key contributes nothing and silently
  /// reduces that sport to pure win/loss distribution — which the spec (§8.1)
  /// forbids explicitly, and which is exactly what happened while this table
  /// was written in snake_case.
  ///
  /// `test/rating_service_test.dart` asserts every key here is emitted by at
  /// least one registered engine, so the two cannot drift apart again.
  static const weights = <String, double>{
    // Cricket.
    'runsScored': 1.0,
    'wickets': 20.0,
    'catches': 10.0,
    'stumpings': 12.0,
    'runOuts': 10.0,
    'ballsFaced': 0.1,
    'fours': 1.0,
    'sixes': 2.0,
    'maidens': 5.0,

    // Goal and point sports.
    'goals': 25.0,
    'assists': 15.0,
    'saves': 8.0,
    'points': 1.0,
    'rebounds': 2.0,
    'steals': 5.0,
    'blocks': 5.0,
    'aces': 5.0,
    'kills': 3.0,
    'digs': 2.0,

    // Kabaddi and kho-kho.
    'raidPoints': 5.0,
    'tacklePoints': 6.0,
    'superRaids': 10.0,
    'superTackles': 10.0,
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
  static const milestones = <String, ({num threshold, double bonus})>{
    'runsScored': (threshold: 50, bonus: 15.0),
    'wickets': (threshold: 5, bonus: 20.0),
    'raidPoints': (threshold: 10, bonus: 15.0),
    'tacklePoints': (threshold: 5, bonus: 15.0),
    'points': (threshold: 30, bonus: 15.0),
  };

  /// Raw contribution points from one player's tally.
  static double pointsFrom(Map<String, num> tally) {
    if (tally.isEmpty) return 0.0;

    var pts = 0.0;
    for (final entry in tally.entries) {
      final weight = weights[entry.key];
      if (weight != null) pts += entry.value * weight;
    }
    for (final m in milestones.entries) {
      final value = tally[m.key];
      if (value != null && value >= m.value.threshold) {
        pts += m.value.bonus;
      }
    }
    return pts;
  }
}

/// The best performer in a completed match.
class MatchAward {
  const MatchAward({
    required this.playerId,
    required this.name,
    required this.points,
    required this.onWinningSide,
    this.uid,
  });

  /// The lineup id, which is the uid for a registered player and a generated
  /// id for a guest.
  final String playerId;

  /// Null for a guest — someone who turned up, played, and has never installed
  /// the app. They can still be named the best player of a match they were
  /// the best player of; nothing accrues to a profile that does not exist.
  final String? uid;

  final String name;
  final double points;
  final bool onWinningSide;

  Map<String, Object?> toMap() => {
        'playerId': playerId,
        'uid': uid,
        'name': name,
        'points': points,
        'onWinningSide': onWinningSide,
      };

  static MatchAward? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final playerId = d['playerId'];
    final name = d['name'];
    if (playerId is! String || name is! String) return null;
    return MatchAward(
      playerId: playerId,
      uid: d['uid'] as String?,
      name: name,
      points: (d['points'] as num?)?.toDouble() ?? 0.0,
      onWinningSide: d['onWinningSide'] == true,
    );
  }
}

/// Picks the best performer of a finished match.
///
/// Returns null rather than inventing one when there is nothing to judge on:
/// a sport whose engine records no per-player statistics, or a match where
/// every tally is empty. An MVP awarded on no evidence is worse than no MVP —
/// it would always be the same player, the first one in the list, and every
/// club would notice within a week.
///
/// ## Ties
///
/// Broken toward the winning side first. This is a convention rather than a
/// mathematical truth, and it is the convention every sport uses: a player on
/// the losing side has to be *better*, not merely equal, to take the award.
/// Remaining ties fall to lineup order, which is stable, so a rebuild from the
/// event log names the same player every time — a match that renamed its MVP
/// on replay would be worse than one that never named one.
MatchAward? selectMvp({
  required Map<String, dynamic> scoreState,
  required List<MatchPlayer> lineupA,
  required List<MatchPlayer> lineupB,
  required String entrantAId,
  required String entrantBId,
  String? winnerEntrantId,
}) {
  MatchAward? best;

  void consider(MatchPlayer player, bool onWinningSide) {
    final points = ContributionScoring.pointsFrom(
      PlayerTally.of(scoreState, player.id),
    );
    // Zero contribution is not a candidate. Somebody has to have actually
    // done something.
    if (points <= 0) return;

    final candidate = MatchAward(
      playerId: player.id,
      uid: player.uid,
      name: player.name,
      points: points,
      onWinningSide: onWinningSide,
    );

    final current = best;
    if (current == null) {
      best = candidate;
      return;
    }
    if (points > current.points) {
      best = candidate;
      return;
    }
    if (points == current.points &&
        onWinningSide &&
        !current.onWinningSide) {
      best = candidate;
    }
  }

  // A draw has no winning side, so every tie falls through to lineup order.
  final aWon = winnerEntrantId != null && winnerEntrantId == entrantAId;
  final bWon = winnerEntrantId != null && winnerEntrantId == entrantBId;

  for (final p in lineupA) {
    consider(p, aWon);
  }
  for (final p in lineupB) {
    consider(p, bWon);
  }

  return best;
}
