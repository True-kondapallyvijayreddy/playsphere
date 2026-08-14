import '../../core/models/fixture.dart';
import '../scoring/player_stats.dart';

/// A club's record in one sport — matches played and the summed tally of
/// everyone who represented it — the club-scoped counterpart to
/// [CareerLine]/`ScopedStats`.
///
/// ## Why there is no won/lost/drawn here
///
/// A fixture lives under exactly one club's `orgId`, but that does not mean
/// the match was that club against an outside opponent — plenty of matches
/// are two of a club's own teams playing each other (a school's house
/// matches are the common case). "The club won" is meaningless when both
/// sides are the same club. A genuine club-vs-club result exists only for
/// the separate Challenge feature and for open tournaments an outside club
/// entered, and detecting those correctly is real, separate work — left for
/// later rather than folded in here and done wrong. So a club's record is
/// **played** and the **stat tally**, not a win/loss record.
///
/// ## Why this is computed on the client, like a player's own splits
///
/// Same reasoning `PlayerStatsScreen` documents for `ScopedStats`: a stored
/// per-club aggregate is one more number that can drift from the fixtures
/// it was supposed to summarize, and a club's match history is no bigger
/// than a player's — cheap to filter fresh every time rather than trust a
/// cached total.
class ClubSportStats {
  const ClubSportStats({
    required this.sportId,
    required this.matches,
    required this.tally,
  });

  final String sportId;

  /// Finished matches only — see [Fixture.countsTowardsRecords].
  final int matches;

  /// Every counter from every player on either side, summed. Keyed exactly
  /// as the sport's engine keys it, the same open-map shape
  /// `CareerStats.tally` uses.
  final Map<String, num> tally;

  bool get isEmpty => matches == 0;

  /// One row per sport the club has played, most-played first — the same
  /// "what is this club best known for" ordering `CareerLine.prominence`
  /// uses for a player.
  ///
  /// [fixtures] must already be scoped to one club — see
  /// `Refs.allFixturesQuery.where('orgId', isEqualTo: orgId)` — this does no
  /// org filtering of its own.
  static List<ClubSportStats> forFixtures(List<Fixture> fixtures) {
    final matches = <String, int>{};
    final tally = <String, Map<String, num>>{};

    for (final fixture in fixtures) {
      if (!fixture.countsTowardsRecords) continue;
      // Chess is rated per time control (`chess:blitz`); a club's record is
      // kept per sport, not per time control, same split every other career
      // reader applies to `Fixture.sport`.
      final sportId = fixture.sport.split(':').first;
      matches[sportId] = (matches[sportId] ?? 0) + 1;
      final bucket = tally.putIfAbsent(sportId, () => <String, num>{});
      for (final entry in PlayerTally.everyone(fixture.scoreState).entries) {
        bucket[entry.key] = (bucket[entry.key] ?? 0) + entry.value;
      }
    }

    final sportIds = {...matches.keys, ...tally.keys}.toList()
      ..sort((a, b) => (matches[b] ?? 0).compareTo(matches[a] ?? 0));

    return [
      for (final id in sportIds)
        ClubSportStats(
          sportId: id,
          matches: matches[id] ?? 0,
          tally: tally[id] ?? const <String, num>{},
        ),
    ];
  }
}
