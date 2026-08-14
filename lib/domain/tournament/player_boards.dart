import '../../core/models/fixture.dart';
import '../scoring/player_stats.dart';

/// One player's total for one counter, across a set of matches.
class BoardEntry {
  const BoardEntry({
    required this.playerId,
    required this.displayName,
    required this.value,
    required this.matches,
    this.uid,
  });

  /// The lineup id — the uid for a registered player, a generated id for a
  /// guest who turned up and played.
  final String playerId;

  /// Null for a guest. A guest can top a tournament's run chart without ever
  /// having installed the app, and refusing to rank them would misreport the
  /// tournament to protect a profile that does not exist.
  final String? uid;

  final String displayName;
  final num value;

  /// How many matches contributed. Shown beside the total because "61 wickets
  /// in 8 matches" and "61 in 30" are not the same achievement.
  final int matches;
}

/// One ranked board — "Runs", "Wickets" — over a set of matches.
class StatBoard {
  const StatBoard({required this.key, required this.entries});

  /// The tally counter this board ranks by, exactly as the sport's engine
  /// writes it.
  final String key;

  /// Highest first.
  final List<BoardEntry> entries;

  bool get isEmpty => entries.isEmpty;
}

/// Per-player boards built from every match in a tournament or a season.
///
/// `docs/Heart_of_the_playsphere.md` §16/§17: a tournament wants batting and
/// bowling charts alongside its points table, and a season wants the same per
/// sport. Both are the same computation over a different set of fixtures,
/// which is why this takes fixtures rather than a tournament.
///
/// ## Why the counters are discovered rather than declared
///
/// It would be simpler to hard-code Batting / Bowling / Fielding tabs. That
/// is a cricket answer, and this runs for fifteen sports whose engines share
/// no vocabulary — football writes goals and assists, kabaddi raid points,
/// chess nothing at all. So the boards are whatever counters the matches
/// actually recorded, which is correct for every sport including ones added
/// later.
class PlayerBoards {
  const PlayerBoards._(this.boards);

  /// Keyed by counter, in descending order of how many players have a figure
  /// for it — so the counter that describes the sport best leads.
  final List<StatBoard> boards;

  StatBoard? boardFor(String key) {
    for (final board in boards) {
      if (board.key == key) return board;
    }
    return null;
  }

  bool get isEmpty => boards.isEmpty;

  /// One set of boards per sport, for a season that spans several.
  ///
  /// `docs/Heart_of_the_playsphere.md` §17: a season wants the same charts a
  /// tournament does, *per sport*. Merging them into one set is nearly right
  /// on its own — the counters are already sport-specific vocabulary, so runs
  /// and goals never land on the same board — but it leaves a hockey parent
  /// scrolling past six cricket charts to reach theirs, and it silently merges
  /// the two sports that DO share a counter name (assists, in football and
  /// basketball) into one meaningless chart.
  ///
  /// Keyed by [Fixture.sport]. Insertion order follows the order the sports
  /// first appear in [fixtures], which the caller has already sorted.
  static Map<String, PlayerBoards> bySport(List<Fixture> fixtures) {
    final byId = <String, List<Fixture>>{};
    for (final fixture in fixtures) {
      byId.putIfAbsent(fixture.sport, () => []).add(fixture);
    }
    final out = <String, PlayerBoards>{};
    for (final entry in byId.entries) {
      final boards = PlayerBoards.from(entry.value);
      // A sport whose engine records no per-player counters — chess, most
      // obviously — contributes no boards and must not contribute an empty
      // tab either.
      if (!boards.isEmpty) out[entry.key] = boards;
    }
    return out;
  }

  /// Builds every board in one pass.
  ///
  /// [minValue] drops zero and negative totals: a bowler who never bowled has
  /// a 0 in the wickets column and putting them on the wickets chart is
  /// noise, not information.
  static PlayerBoards from(List<Fixture> fixtures) {
    // playerId -> counter -> total
    final totals = <String, Map<String, num>>{};
    final names = <String, String>{};
    final uids = <String, String>{};
    final appearances = <String, Set<String>>{};

    for (final fixture in fixtures) {
      // The same gate the profile and the statistics engine use: an
      // unfinished or unverified match is not a performance yet. Without this
      // a tournament's charts would move while a match was still being
      // played, then move again when it was corrected.
      if (!fixture.countsTowardsRecords) continue;

      // `scoredPlayers`, not the two line-ups: an individual draw records real
      // per-player figures and names nobody in a line-up, so walking the
      // sheets alone drew an empty chart for a tournament played to a final.
      for (final player in fixture.scoredPlayers) {
        final tally = PlayerTally.of(fixture.scoreState, player.id);
        if (tally.isEmpty) continue;

        names[player.id] = player.name;
        final uid = player.uid;
        if (uid != null && uid.isNotEmpty) uids[player.id] = uid;
        appearances.putIfAbsent(player.id, () => <String>{}).add(fixture.id);

        final bucket = totals.putIfAbsent(player.id, () => <String, num>{});
        for (final entry in tally.entries) {
          bucket[entry.key] = (bucket[entry.key] ?? 0) + entry.value;
        }
      }
    }

    // Invert into one board per counter.
    final byCounter = <String, List<BoardEntry>>{};
    for (final playerEntry in totals.entries) {
      final playerId = playerEntry.key;
      for (final counter in playerEntry.value.entries) {
        if (counter.value <= 0) continue;
        byCounter.putIfAbsent(counter.key, () => []).add(
              BoardEntry(
                playerId: playerId,
                uid: uids[playerId],
                displayName: names[playerId] ?? 'Player',
                value: counter.value,
                matches: appearances[playerId]?.length ?? 0,
              ),
            );
      }
    }

    final boards = <StatBoard>[];
    for (final entry in byCounter.entries) {
      final ranked = entry.value
        ..sort((a, b) {
          final byValue = b.value.compareTo(a.value);
          // Fewer matches breaks a tie: the same total in less cricket is the
          // better performance, and a stable order stops the chart shuffling
          // between reads.
          if (byValue != 0) return byValue;
          final byMatches = a.matches.compareTo(b.matches);
          if (byMatches != 0) return byMatches;
          return a.displayName.compareTo(b.displayName);
        });
      boards.add(StatBoard(key: entry.key, entries: ranked));
    }

    boards.sort((a, b) {
      final byDepth = b.entries.length.compareTo(a.entries.length);
      if (byDepth != 0) return byDepth;
      return a.key.compareTo(b.key);
    });

    return PlayerBoards._(boards);
  }
}
