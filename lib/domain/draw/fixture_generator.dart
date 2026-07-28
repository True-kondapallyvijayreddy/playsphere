import 'dart:math';

import '../../core/models/competition.dart';
import '../../core/models/enums.dart';

/// A fixture the generator produced, before it has been written to Firestore.
class PlannedFixture {
  const PlannedFixture({
    required this.round,
    required this.matchIndex,
    required this.roundLabel,
    this.entrantA,
    this.entrantB,
    this.feedsWinnerToIndex,
    this.feedsWinnerToSlot,
  });

  final int round;
  final int matchIndex;
  final String roundLabel;

  /// Null on a knockout placeholder whose entrant is decided by an earlier
  /// match, or on the empty side of a bye.
  final Entrant? entrantA;
  final Entrant? entrantB;

  /// Index into the generated list where this match's winner advances.
  final int? feedsWinnerToIndex;

  /// Which side of that match the winner occupies — 'a' or 'b'.
  ///
  /// Recorded explicitly rather than derived from [matchIndex] parity, because
  /// matchIndex counts across the whole bracket while pairing is within a
  /// round: with an odd number of first-round matches the two would disagree
  /// and winners would overwrite each other.
  final String? feedsWinnerToSlot;

  bool get isBye => entrantA == null || entrantB == null;
}

/// Builds the draw for a competition.
///
/// Pure and deterministic given a seed, so the same entrant list always
/// produces the same bracket — which matters when an organizer regenerates a
/// draw after a withdrawal and needs to explain why it changed.
class FixtureGenerator {
  const FixtureGenerator();

  List<PlannedFixture> generate({
    required CompetitionFormat format,
    required List<Entrant> entrants,
    int? shuffleSeed,
  }) {
    final active = entrants.where((e) => !e.withdrawn).toList();
    if (active.length < 2) return const [];

    return switch (format) {
      CompetitionFormat.roundRobin ||
      CompetitionFormat.leagueTable =>
        _roundRobin(active),
      CompetitionFormat.knockout ||
      CompetitionFormat.doubleElimination ||
      CompetitionFormat.groupThenKnockout =>
        _knockout(active, shuffleSeed),
      CompetitionFormat.swiss => _swissFirstRound(active, shuffleSeed),
      CompetitionFormat.finalOnly ||
      CompetitionFormat.heatsThenFinal =>
        const [],
    };
  }

  /// Circle method: every entrant plays every other exactly once.
  ///
  /// With an odd number of entrants a phantom "bye" entrant is added so each
  /// round is complete; matches against it are dropped. Without that, one
  /// entrant silently plays fewer matches than the rest and the league table
  /// is wrong.
  List<PlannedFixture> _roundRobin(List<Entrant> entrants) {
    final list = List<Entrant?>.from(entrants);
    if (list.length.isOdd) list.add(null);

    final n = list.length;
    final rounds = n - 1;
    final half = n ~/ 2;
    final fixtures = <PlannedFixture>[];
    var matchIndex = 0;

    // Position 0 stays fixed; the rest rotate one place each round.
    final rotation = List<Entrant?>.from(list);

    for (var round = 0; round < rounds; round++) {
      for (var i = 0; i < half; i++) {
        final a = rotation[i];
        final b = rotation[n - 1 - i];
        if (a == null || b == null) continue;

        // Alternate home/away by round so the same entrant is not always
        // listed first — on a scoreboard that reads as always batting or
        // serving first.
        final swap = round.isOdd && i == 0;
        fixtures.add(PlannedFixture(
          round: round + 1,
          matchIndex: matchIndex++,
          roundLabel: 'Round ${round + 1}',
          entrantA: swap ? b : a,
          entrantB: swap ? a : b,
        ));
      }

      final fixed = rotation[0];
      final rest = rotation.sublist(1)
        ..insert(0, rotation.removeLast());
      rotation
        ..clear()
        ..add(fixed)
        ..addAll(rest.take(n - 1));
    }

    return fixtures;
  }

  /// Single-elimination bracket sized to the next power of two.
  ///
  /// Byes are handed to the strongest seeds, and standard seed pairing is
  /// used (1 vs lowest, 2 vs second lowest, …) so the top two seeds can only
  /// meet in the final. Random pairing here is the difference between a real
  /// tournament and a raffle.
  List<PlannedFixture> _knockout(List<Entrant> entrants, int? shuffleSeed) {
    final seeded = List<Entrant>.from(entrants);
    final anySeeded = seeded.any((e) => e.seed != null);
    if (anySeeded) {
      seeded.sort((a, b) =>
          (a.seed ?? 1 << 20).compareTo(b.seed ?? 1 << 20));
    } else {
      seeded.shuffle(Random(shuffleSeed ?? 42));
    }

    var bracketSize = 1;
    while (bracketSize < seeded.length) {
      bracketSize *= 2;
    }

    // Slot order for a standard bracket, built by repeatedly mirroring.
    var slots = <int>[0, 1];
    while (slots.length < bracketSize) {
      final size = slots.length * 2;
      slots = [
        for (final s in slots) ...[s, size - 1 - s],
      ];
    }

    final placed = List<Entrant?>.generate(
      bracketSize,
      (i) => slots[i] < seeded.length ? seeded[slots[i]] : null,
    );

    final totalRounds = (log(bracketSize) / log(2)).round();
    final fixtures = <PlannedFixture>[];
    var matchIndex = 0;

    // Round 1.
    final firstRoundCount = bracketSize ~/ 2;
    for (var i = 0; i < firstRoundCount; i++) {
      fixtures.add(PlannedFixture(
        round: 1,
        matchIndex: matchIndex++,
        roundLabel: _roundLabel(1, totalRounds),
        entrantA: placed[i * 2],
        entrantB: placed[i * 2 + 1],
        feedsWinnerToIndex: firstRoundCount + (i ~/ 2),
        feedsWinnerToSlot: i.isEven ? 'a' : 'b',
      ));
    }

    // Later rounds are placeholders filled as winners emerge.
    var matchesInRound = firstRoundCount ~/ 2;
    var round = 2;
    var indexOfRoundStart = firstRoundCount;
    while (matchesInRound >= 1) {
      final nextRoundStart = indexOfRoundStart + matchesInRound;
      for (var i = 0; i < matchesInRound; i++) {
        fixtures.add(PlannedFixture(
          round: round,
          matchIndex: matchIndex++,
          roundLabel: _roundLabel(round, totalRounds),
          feedsWinnerToIndex:
              matchesInRound == 1 ? null : nextRoundStart + (i ~/ 2),
          feedsWinnerToSlot:
              matchesInRound == 1 ? null : (i.isEven ? 'a' : 'b'),
        ));
      }
      indexOfRoundStart = nextRoundStart;
      matchesInRound ~/= 2;
      round++;
    }

    return fixtures;
  }

  /// Swiss pairs by current standing each round, so only round one can be
  /// generated up front. Subsequent rounds are produced after results land.
  List<PlannedFixture> _swissFirstRound(List<Entrant> entrants, int? seed) {
    final list = List<Entrant>.from(entrants);
    final anySeeded = list.any((e) => e.seed != null);
    if (anySeeded) {
      list.sort((a, b) => (a.seed ?? 1 << 20).compareTo(b.seed ?? 1 << 20));
    } else {
      list.shuffle(Random(seed ?? 42));
    }

    // Top half plays bottom half.
    final half = list.length ~/ 2;
    final fixtures = <PlannedFixture>[];
    for (var i = 0; i < half; i++) {
      fixtures.add(PlannedFixture(
        round: 1,
        matchIndex: i,
        roundLabel: 'Round 1',
        entrantA: list[i],
        entrantB: list[i + half],
      ));
    }
    return fixtures;
  }

  static String _roundLabel(int round, int totalRounds) {
    final fromEnd = totalRounds - round;
    return switch (fromEnd) {
      0 => 'Final',
      1 => 'Semi-final',
      2 => 'Quarter-final',
      _ => 'Round $round',
    };
  }
}
