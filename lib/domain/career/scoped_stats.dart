import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../scoring/player_stats.dart';

/// Which slice of a career is being looked at.
///
/// `docs/Heart_of_the_playsphere.md` §18: "All are different views of the
/// same underlying match data." That is the whole idea — there is one set of
/// matches, and a scope is a filter over it, never a separate stored total.
/// Storing per-scope aggregates would mean five numbers that can disagree
/// with each other, which is exactly the "statistical inconsistency" §9
/// warns against.
enum StatScope {
  all('All', null),
  tournament('Tournament', MatchSource.tournament),
  season('Season', MatchSource.season),
  challenge('Challenge', MatchSource.challenge),
  singleMatch('Single Match', MatchSource.singleMatch);

  const StatScope(this.label, this.source);

  final String label;

  /// Null for [all], which matches everything.
  final MatchSource? source;

  bool matches(Fixture fixture) =>
      source == null || fixture.resolvedSource == source;
}

/// One player's totals over some set of matches.
///
/// Deliberately not tied to a sport's vocabulary: [tally] is whatever
/// counters that sport's engine writes, summed. A cricket scope carries runs
/// and wickets, a football one goals and assists, and this class knows about
/// neither — the same reason `CareerStats.tally` is an open map.
class ScopedStats {
  const ScopedStats({
    required this.scope,
    required this.matches,
    required this.won,
    required this.lost,
    required this.drawn,
    required this.tally,
  });

  final StatScope scope;

  /// Matches counted — finished ones only. A scheduled fixture is not a
  /// performance, and counting it would inflate every average by dividing
  /// real runs by imagined innings.
  final int matches;

  final int won;
  final int lost;
  final int drawn;

  /// Summed per-counter totals, keyed exactly as the sport's engine keys them.
  final Map<String, num> tally;

  bool get isEmpty => matches == 0;

  /// Wins as a percentage of matches with a decided outcome.
  ///
  /// Draws are excluded from the denominator rather than counted as half a
  /// loss: a 60% win rate over ten matches means something different if four
  /// were draws, and folding them in hides that.
  double? get winRate {
    final decided = won + lost;
    if (decided == 0) return null;
    return won / decided;
  }

  /// Builds every scope in one pass over a player's matches.
  ///
  /// One pass rather than one per scope: a career is a few hundred fixtures
  /// and five separate filters over it would be five times the work for the
  /// same answer, on the phones this product targets.
  static Map<StatScope, ScopedStats> forPlayer({
    required List<Fixture> fixtures,
    required String uid,
    String? sportId,
  }) {
    final counters = <StatScope, Map<String, num>>{
      for (final scope in StatScope.values) scope: <String, num>{},
    };
    final matches = <StatScope, int>{for (final s in StatScope.values) s: 0};
    final won = <StatScope, int>{for (final s in StatScope.values) s: 0};
    final lost = <StatScope, int>{for (final s in StatScope.values) s: 0};
    final drawn = <StatScope, int>{for (final s in StatScope.values) s: 0};

    for (final fixture in fixtures) {
      // Finished matches only, and only ones whose result is safe to count —
      // a match still awaiting an official's verification is not yet a fact.
      // Same gate the statistics engine applies.
      if (!fixture.countsTowardsRecords) continue;
      if (sportId != null && fixture.sport.split(':').first != sportId) {
        continue;
      }

      // The lineup id, which is the uid for a registered player. A guest has
      // a generated id and no uid, so they never match here — correct, since
      // this is somebody's own profile.
      final side = fixture.sideForUid(uid);
      if (side == null) continue;
      final mine = PlayerTally.of(fixture.scoreState, uid);
      final outcome = fixture.outcomeForUid(uid);

      for (final scope in StatScope.values) {
        if (!scope.matches(fixture)) continue;
        matches[scope] = matches[scope]! + 1;
        switch (outcome) {
          case PlayerResult.won:
            won[scope] = won[scope]! + 1;
          case PlayerResult.lost:
            lost[scope] = lost[scope]! + 1;
          case PlayerResult.drawn:
            drawn[scope] = drawn[scope]! + 1;
          case null:
            break;
        }
        final bucket = counters[scope]!;
        for (final entry in mine.entries) {
          bucket[entry.key] = (bucket[entry.key] ?? 0) + entry.value;
        }
      }
    }

    return {
      for (final scope in StatScope.values)
        scope: ScopedStats(
          scope: scope,
          matches: matches[scope]!,
          won: won[scope]!,
          lost: lost[scope]!,
          drawn: drawn[scope]!,
          tally: counters[scope]!,
        ),
    };
  }
}
