import 'dart:math';

import '../../core/models/competition.dart';
import '../../core/models/enums.dart';

/// Which sub-bracket a fixture belongs to.
///
/// A plain knockout or a round robin only ever has one shape, so this used
/// to be implicit. Double elimination and groups+knockout both produce
/// several structurally different kinds of match in a single draw — a
/// group-stage match is not interchangeable with a losers-bracket match —
/// and downstream code (standings, brackets UI, the scheduler) needs to
/// know which is which without guessing from round numbers.
enum Bracket {
  /// Single-elimination ladder — either the whole draw (plain knockout), or
  /// the qualifier stage of groups+knockout.
  knockout,

  /// The undefeated side of a double-elimination draw.
  winners,

  /// The one-loss side of a double-elimination draw.
  losers,

  /// Winners-bracket champion vs. losers-bracket champion.
  grandFinal,

  /// Played only if the losers-bracket champion wins [grandFinal] — a
  /// double-elimination decider exists because a single loss must not be
  /// allowed to eliminate the side that came through undefeated. See
  /// [FixtureGenerator._doubleElimination] for why this is emitted as an
  /// unconditioned placeholder rather than pre-populated.
  grandFinalReset,

  /// Round robin within one group of a groups+knockout draw.
  group,
}

/// Identifies a not-yet-known knockout entrant by table position — "the
/// winner of Group B" — rather than by identity.
///
/// At draw time the group stage has not been played, so no real [Entrant]
/// exists yet for a qualifier slot. This is what lets the knockout phase of
/// [CompetitionFormat.groupThenKnockout] be generated up front, in one pass,
/// alongside the groups: the bracket's *shape* (who plays whom, seeded so
/// group-mates cannot meet again immediately) is pure structure and does
/// not depend on results. Only the entrant identity does. Application code
/// fills [PlannedFixture.entrantA] / [PlannedFixture.entrantB] for these
/// matches once each group's table (via `StandingsCalculator`) is final.
class QualifierSource {
  const QualifierSource({required this.groupId, required this.position});

  final String groupId;

  /// 1 = group winner, 2 = runner-up, and so on.
  final int position;

  @override
  String toString() => 'Group $groupId #$position';

  @override
  bool operator ==(Object other) =>
      other is QualifierSource &&
      other.groupId == groupId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(groupId, position);
}

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
    this.feedsLoserToIndex,
    this.feedsLoserToSlot,
    this.bracket = Bracket.knockout,
    this.groupId,
    this.qualifierA,
    this.qualifierB,
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

  /// Index into the generated list where this match's *loser* is sent —
  /// populated only inside a double-elimination draw, where losing a
  /// winners-bracket match drops a player into the losers bracket instead of
  /// eliminating them outright. Null everywhere else, including every
  /// losers-bracket match itself (a losers-bracket loss is a real
  /// elimination — it goes nowhere).
  final int? feedsLoserToIndex;
  final String? feedsLoserToSlot;

  /// Which sub-bracket this match belongs to. See [Bracket].
  final Bracket bracket;

  /// Set on [Bracket.group] matches — which group this fixture belongs to
  /// ("A", "B", …). Null everywhere else.
  final String? groupId;

  /// Set on knockout-phase matches of a groups+knockout draw whose entrant
  /// is not yet known — describes *which table position* will fill this
  /// side once groups finish, e.g. "winner of Group A". Null once the real
  /// [entrantA] is known (plain knockout, double elimination, or a
  /// groups+knockout match after resolution), and null for a side that is
  /// genuinely empty (a bye).
  final QualifierSource? qualifierA;
  final QualifierSource? qualifierB;

  /// True when one side is empty — either a genuine bracket bye (padding to
  /// the next power of two) or a placeholder still waiting on an earlier
  /// result. Callers that need to tell the two apart should check whether
  /// the *other* side is populated: a real bye has exactly one side filled
  /// at generation time and it never becomes a match that needs playing.
  bool get isBye => entrantA == null || entrantB == null;
}

/// Builds the draw for a competition.
///
/// Pure and deterministic given a seed, so the same entrant list always
/// produces the same bracket — which matters when an organizer regenerates a
/// draw after a withdrawal and needs to explain why it changed.
///
/// ## Structure vs. results
///
/// Every format here separates two concerns that are easy to conflate: the
/// *shape* of the draw (who could possibly meet whom, and where a winner or
/// loser goes next) is pure structure, fixed the moment entrants and seeds
/// are known. Who actually wins is not known until matches are played. This
/// generator only ever produces the former — a full graph of matches wired
/// together by list index — and leaves every entrant slot that depends on a
/// result as `null`, for application code to fill in as results land (the
/// existing `feedsWinnerToFixtureId` / `feedsWinnerToSlot` mechanism used by
/// the knockout bracket already does this for match winners; the same
/// pattern extends to double-elimination losers and to groups+knockout
/// qualifiers).
///
/// The one exception, and the one piece of "resolution" this generator does
/// perform itself, is a bracket bye: when a slot is empty by construction
/// (not because a match hasn't been played, but because there was never an
/// opponent there), the surviving entrant is auto-advanced one round forward
/// at generation time. See [_buildKnockoutFixtures] for exactly which cases
/// qualify and why only round one ever does.
class FixtureGenerator {
  const FixtureGenerator();

  List<PlannedFixture> generate({
    required CompetitionFormat format,
    required List<Entrant> entrants,
    int? shuffleSeed,

    /// When true, round robin / league table plays a second leg with each
    /// fixture's entrants swapped (away becomes home), doubling the fixture
    /// count to N×(N−1). Off by default because a double round-robin is
    /// twice the commitment for an organizer to schedule, and §9 warns
    /// against even a single round robin once N > 12 for a one-day event.
    bool doubleRoundRobin = false,

    /// Whether a double-elimination draw carries a bracket-reset slot for
    /// the case where the losers-bracket champion beats the undefeated
    /// winners-bracket champion in the first grand-final match. Ignored for
    /// every other format.
    bool bracketReset = true,

    /// Groups+knockout: entrants per group. If null, derived from
    /// [numGroups], or defaults to roughly 4 per group.
    int? groupSize,

    /// Groups+knockout: number of groups. Takes priority over [groupSize]
    /// when both are given.
    int? numGroups,

    /// Groups+knockout: how many entrants from each group advance to the
    /// knockout phase.
    int qualifiersPerGroup = 2,
  }) {
    final active = entrants.where((e) => !e.withdrawn).toList();
    if (active.length < 2) return const [];

    return switch (format) {
      CompetitionFormat.roundRobin ||
      CompetitionFormat.leagueTable =>
        _roundRobinFixtures(active, doubleLegged: doubleRoundRobin),
      CompetitionFormat.knockout => _knockout(active, shuffleSeed),
      CompetitionFormat.doubleElimination => _doubleElimination(
          active,
          shuffleSeed,
          bracketReset: bracketReset,
        ),
      CompetitionFormat.groupThenKnockout => _groupThenKnockout(
          active,
          shuffleSeed,
          groupSize: groupSize,
          numGroups: numGroups,
          qualifiersPerGroup: qualifiersPerGroup,
        ),
      CompetitionFormat.swiss => _swissFirstRound(active, shuffleSeed),
      CompetitionFormat.finalOnly ||
      CompetitionFormat.heatsThenFinal =>
        const [],
    };
  }

  // ---------------------------------------------------------------------
  // Round robin (single and double)
  // ---------------------------------------------------------------------

  /// Runs [_roundRobin] once, and — when [doubleLegged] — a second time with
  /// each fixture's sides swapped, appended as a second block of rounds.
  ///
  /// The reverse leg is built by mirroring the already-generated first leg
  /// rather than re-running the circle method with entrants reversed:
  /// mirroring guarantees the exact same pairing order (so "leg 2, round 3"
  /// is unambiguously the reverse of "leg 1, round 3"), which matters for
  /// organizers who want the second leg to mirror the first for scheduling
  /// symmetry — e.g. playing it at the other side's venue.
  List<PlannedFixture> _roundRobinFixtures(
    List<Entrant> entrants, {
    required bool doubleLegged,
  }) {
    final firstLeg = _roundRobin(entrants);
    if (!doubleLegged || firstLeg.isEmpty) return firstLeg;

    final singleLegRounds =
        firstLeg.map((f) => f.round).reduce((a, b) => a > b ? a : b);

    var matchIndex = firstLeg.length;
    final secondLeg = <PlannedFixture>[
      for (final f in firstLeg)
        PlannedFixture(
          round: f.round + singleLegRounds,
          matchIndex: matchIndex++,
          roundLabel: 'Round ${f.round + singleLegRounds}',
          // Reversed: whoever was away in leg one is home in leg two.
          entrantA: f.entrantB,
          entrantB: f.entrantA,
        ),
    ];

    return [...firstLeg, ...secondLeg];
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

  // ---------------------------------------------------------------------
  // Shared seeding / bracket-shape helpers
  // ---------------------------------------------------------------------

  /// Seeds when any entrant carries one; otherwise a deterministic shuffle.
  /// Shared by every bracket format so "seeded if seeds exist, else a fixed
  /// shuffle" is a single rule rather than three copies that could drift.
  List<Entrant> _seedOrShuffle(List<Entrant> entrants, int? shuffleSeed) {
    final list = List<Entrant>.from(entrants);
    final anySeeded = list.any((e) => e.seed != null);
    if (anySeeded) {
      list.sort((a, b) => (a.seed ?? 1 << 20).compareTo(b.seed ?? 1 << 20));
    } else {
      list.shuffle(Random(shuffleSeed ?? 42));
    }
    return list;
  }

  int _nextPow2(int n) {
    var size = 1;
    while (size < n) {
      size *= 2;
    }
    return size;
  }

  /// Standard bracket slot order, built by repeatedly mirroring, so that
  /// seed 1 and seed 2 land in opposite halves and can only meet in the
  /// final. Random pairing here is the difference between a real tournament
  /// and a raffle.
  List<int> _mirrorSlots(int bracketSize) {
    var slots = <int>[0, 1];
    while (slots.length < bracketSize) {
      final size = slots.length * 2;
      slots = [
        for (final s in slots) ...[s, size - 1 - s],
      ];
    }
    return slots;
  }

  /// Builds a single-elimination ladder over [round1Slots] (already seeded —
  /// one array slot per bracket position, `null` = an empty pad slot with no
  /// entrant) and appends it to [fixtures] starting at absolute list
  /// position [startIndex].
  ///
  /// Shared by plain knockout, the winners bracket of double elimination,
  /// and the knockout phase of groups+knockout — all three are "take a
  /// power-of-two number of pre-seeded slots, mirror-pair them round by
  /// round." What differs between callers is only how the slots were
  /// seeded, the label prefix, and the [Bracket] tag.
  ///
  /// ## Byes only auto-advance one round
  ///
  /// Round one can contain a genuine bye: a slot that is `null` because
  /// there was never an entrant there (padding to the next power of two),
  /// not because a match hasn't been played. When exactly one side of a
  /// round-one match is such a slot, the present entrant is carried straight
  /// into the next round's corresponding slot — that is what makes the
  /// existing `feedsWinnerToFixtureId` mechanism actually show the advanced
  /// player instead of a permanent "TBD" once results start coming in.
  ///
  /// No round after the first ever gets this treatment, even though a
  /// round-two-plus match can easily show one known side and one `null`
  /// side (because that known side arrived via a round-one bye). That
  /// `null` side is *not* an empty slot — it is a real opponent who simply
  /// hasn't been decided yet, because their own earlier match hasn't been
  /// played. Auto-advancing there would silently skip a match that is
  /// supposed to happen. The two look identical in the data (`entrantB ==
  /// null`) and are only distinguishable by which round produced them, which
  /// is exactly why this method — not a generic "isBye" check — is the only
  /// place this decision is made.
  void _buildKnockoutFixtures({
    required List<PlannedFixture> fixtures,
    required List<Entrant?> round1Slots,
    List<QualifierSource?>? round1Qualifiers,
    required int startIndex,
    required Bracket bracket,
    required String Function(int round, int totalRounds) roundLabelFn,
  }) {
    final bracketSize = round1Slots.length;
    if (bracketSize < 2) return;
    final totalRounds = (log(bracketSize) / log(2)).round();

    var slots = round1Slots;
    var qualifierSlots = round1Qualifiers;
    var indexOfRoundStart = startIndex;

    for (var r = 1; r <= totalRounds; r++) {
      final matchesInRound = slots.length ~/ 2;
      final nextRoundStart = indexOfRoundStart + matchesInRound;
      final isFinal = r == totalRounds;

      // One advancing entrant per match this round — becomes half of one
      // slot-pair feeding round r+1.
      final advancing = List<Entrant?>.filled(matchesInRound, null);
      final advancingQualifiers =
          List<QualifierSource?>.filled(matchesInRound, null);

      for (var i = 0; i < matchesInRound; i++) {
        final a = slots[i * 2];
        final b = slots[i * 2 + 1];
        final qa = qualifierSlots?[i * 2];
        final qb = qualifierSlots?[i * 2 + 1];

        fixtures.add(PlannedFixture(
          round: r,
          matchIndex: indexOfRoundStart + i,
          roundLabel: roundLabelFn(r, totalRounds),
          entrantA: a,
          entrantB: b,
          bracket: bracket,
          qualifierA: qa,
          qualifierB: qb,
          feedsWinnerToIndex: isFinal ? null : nextRoundStart + (i ~/ 2),
          feedsWinnerToSlot: isFinal ? null : (i.isEven ? 'a' : 'b'),
        ));

        if (r == 1 && (a == null) != (b == null)) {
          advancing[i] = a ?? b;
          advancingQualifiers[i] = a != null ? qa : qb;
        }
      }

      slots = advancing;
      qualifierSlots = advancingQualifiers;
      indexOfRoundStart = nextRoundStart;
    }
  }

  // ---------------------------------------------------------------------
  // Knockout
  // ---------------------------------------------------------------------

  /// Single-elimination bracket sized to the next power of two.
  List<PlannedFixture> _knockout(List<Entrant> entrants, int? shuffleSeed) {
    final seeded = _seedOrShuffle(entrants, shuffleSeed);
    final bracketSize = _nextPow2(seeded.length);
    final slotOrder = _mirrorSlots(bracketSize);
    final placed = List<Entrant?>.generate(
      bracketSize,
      (i) => slotOrder[i] < seeded.length ? seeded[slotOrder[i]] : null,
    );

    final fixtures = <PlannedFixture>[];
    _buildKnockoutFixtures(
      fixtures: fixtures,
      round1Slots: placed,
      startIndex: 0,
      bracket: Bracket.knockout,
      roundLabelFn: _roundLabel,
    );
    return fixtures;
  }

  // ---------------------------------------------------------------------
  // Double elimination
  // ---------------------------------------------------------------------

  /// Winners bracket + losers bracket + grand final (+ optional reset).
  ///
  /// ## Why the whole thing can be wired before anyone has played
  ///
  /// A double-elimination bracket's *shape* — which match's winner advances
  /// where, and which match's loser drops where — is fixed by the entrant
  /// count alone, exactly like a plain knockout's shape is. This method
  /// builds that whole shape in one pass using precomputed round sizes, the
  /// same technique the plain knockout bracket uses for
  /// `feedsWinnerToIndex` (each round's start index is known before the
  /// round is built, because round sizes never depend on results).
  ///
  /// ## Bracket geometry
  ///
  /// For a winners bracket of `k = log2(size)` rounds, the losers bracket
  /// has `2(k−1)` rounds, built here as `k−1` pairs indexed by `j = 1..k−1`:
  ///
  /// - Round `2j−1` ("consolidation"): losers-bracket survivors from the
  ///   previous pair play each other. For `j = 1` there is no previous
  ///   pair, so this round instead consolidates the *winners*-bracket round
  ///   1 losers directly — the losers bracket's very first arrivals.
  /// - Round `2j` ("drop-down"): the consolidation round's winners meet that
  ///   round's fresh arrivals — the losers of winners-bracket round `j+1`.
  ///
  /// Both rounds in a pair always have exactly `size / 2^(j+1)` matches
  /// (the counts are equal by construction — the consolidation round's
  /// winners and the freshly-dropped losers arrive in equal numbers — so
  /// pairing them 1:1 needs no further seeding logic). The final pair
  /// (`j = k−1`) has exactly one match per round: round `2(k−1)` is the
  /// losers-bracket final, fed by the winners-bracket final's loser.
  ///
  /// This produces the textbook match count: `size−1` winners-bracket
  /// matches, `size−2` losers-bracket matches, 1 grand final — `2·size−2`
  /// total, or `2·size−1` with a reset.
  ///
  /// ## The reset match is a placeholder, not a resolved fixture
  ///
  /// Whether a bracket reset is actually needed depends on *which side* of
  /// the grand final wins — the winners-bracket entrant winning ends the
  /// tournament immediately; the losers-bracket entrant winning forces a
  /// second, decisive match. That is a conditional, results-dependent
  /// decision this pure structural generator cannot make (it does not know
  /// who wins anything). So when [bracketReset] is true this method emits
  /// an empty [Bracket.grandFinalReset] fixture unconditionally; the
  /// application layer is responsible for only actually using it — or for
  /// deleting/hiding it — once the grand final's actual result is known and
  /// shows the losers-bracket side won game one.
  ///
  /// ## Byes
  ///
  /// Only winners-bracket round one can contain a genuine bye (see
  /// [_buildKnockoutFixtures]), and only for entrant counts that are not
  /// already a power of two. A winners-bracket bye produces no real loser,
  /// so the losers-bracket slot it would otherwise feed is simply left
  /// empty (both sides `null`) rather than attempting to cascade a phantom
  /// bye through the losers bracket as well — that cascade can itself
  /// collapse further rounds and is not needed for the power-of-two field
  /// sizes (8, 16, …) double elimination is normally run with. An organizer
  /// running a non-power-of-two double-elimination field should expect a
  /// few permanently-empty losers-bracket placeholders that a human prunes.
  List<PlannedFixture> _doubleElimination(
    List<Entrant> entrants,
    int? shuffleSeed, {
    required bool bracketReset,
  }) {
    final seeded = _seedOrShuffle(entrants, shuffleSeed);
    final size = _nextPow2(seeded.length);

    // A losers bracket only means something once there is more than one
    // match to lose from. Below four entrants it collapses to a single
    // decisive match, so fall back to a plain knockout rather than emitting
    // a losers bracket with zero matches plus a grand final that is really
    // just a second, redundant final.
    if (size < 4) return _knockout(entrants, shuffleSeed);

    final k = (log(size) / log(2)).round();
    final slotOrder = _mirrorSlots(size);
    final placed = List<Entrant?>.generate(
      size,
      (i) => slotOrder[i] < seeded.length ? seeded[slotOrder[i]] : null,
    );

    // ---- Precompute every round's size and absolute start index. ----
    final wbRoundSize = <int, int>{
      for (var r = 1; r <= k; r++) r: size ~/ (1 << r),
    };
    final wbRoundStart = <int, int>{};
    var cursor = 0;
    for (var r = 1; r <= k; r++) {
      wbRoundStart[r] = cursor;
      cursor += wbRoundSize[r]!;
    }
    final wbTotal = cursor; // == size - 1

    final lbRoundSize = <int, int>{};
    final lbRoundStart = <int, int>{};
    cursor = wbTotal;
    for (var j = 1; j <= k - 1; j++) {
      final count = size ~/ (1 << (j + 1));
      lbRoundStart[2 * j - 1] = cursor;
      lbRoundSize[2 * j - 1] = count;
      cursor += count;
      lbRoundStart[2 * j] = cursor;
      lbRoundSize[2 * j] = count;
      cursor += count;
    }
    final lbTotal = cursor - wbTotal; // == size - 2

    final gfIndex = wbTotal + lbTotal;
    final resetIndex = bracketReset ? gfIndex + 1 : null;

    final fixtures = <PlannedFixture>[];

    // ---- Winners bracket. ----
    var wbSlots = placed;
    for (var r = 1; r <= k; r++) {
      final matches = wbRoundSize[r]!;
      final start = wbRoundStart[r]!;
      final isFinal = r == k;
      final advancing = List<Entrant?>.filled(matches, null);

      // Round 1 losers consolidate against each other, two matches' worth
      // of losers per losers-round-1 match. Every later round's loser drops
      // straight into that round's timed drop-down match instead.
      final loserTargetRound = r == 1 ? 1 : 2 * (r - 1);

      for (var i = 0; i < matches; i++) {
        final a = wbSlots[i * 2];
        final b = wbSlots[i * 2 + 1];
        final global = start + i;

        final loserTargetIndex =
            lbRoundStart[loserTargetRound]! + (r == 1 ? i ~/ 2 : i);
        final loserTargetSlot = r == 1 ? (i.isEven ? 'a' : 'b') : 'b';

        fixtures.add(PlannedFixture(
          round: r,
          matchIndex: global,
          roundLabel: isFinal ? 'Winners Final' : 'Winners Round $r',
          entrantA: a,
          entrantB: b,
          bracket: Bracket.winners,
          feedsWinnerToIndex:
              isFinal ? gfIndex : wbRoundStart[r + 1]! + (i ~/ 2),
          // The winners-bracket champion always occupies grand-final slot
          // 'a' — see the class doc for why that convention matters (it is
          // what lets application code tell which side, if either, needs a
          // reset).
          feedsWinnerToSlot: isFinal ? 'a' : (i.isEven ? 'a' : 'b'),
          feedsLoserToIndex: loserTargetIndex,
          feedsLoserToSlot: loserTargetSlot,
        ));

        if (r == 1 && (a == null) != (b == null)) {
          advancing[i] = a ?? b;
        }
      }
      wbSlots = advancing;
    }

    // ---- Losers bracket. ----
    for (var j = 1; j <= k - 1; j++) {
      final consolidationRound = 2 * j - 1;
      final dropRound = 2 * j;
      final consolidationMatches = lbRoundSize[consolidationRound]!;
      final dropMatches = lbRoundSize[dropRound]!;
      final consolidationStart = lbRoundStart[consolidationRound]!;
      final dropStart = lbRoundStart[dropRound]!;
      final isLbFinal = j == k - 1;

      for (var i = 0; i < consolidationMatches; i++) {
        fixtures.add(PlannedFixture(
          round: consolidationRound,
          matchIndex: consolidationStart + i,
          roundLabel: 'Losers Round $consolidationRound',
          bracket: Bracket.losers,
          // Consolidation-round winners always land in the drop-down
          // round's 'a' slot; that round's freshly-dropped winners-bracket
          // loser takes 'b' (wired above, from the winners-bracket loop).
          feedsWinnerToIndex: dropStart + i,
          feedsWinnerToSlot: 'a',
        ));
      }

      for (var i = 0; i < dropMatches; i++) {
        fixtures.add(PlannedFixture(
          round: dropRound,
          matchIndex: dropStart + i,
          roundLabel: isLbFinal ? 'Losers Final' : 'Losers Round $dropRound',
          bracket: Bracket.losers,
          feedsWinnerToIndex:
              isLbFinal ? gfIndex : lbRoundStart[dropRound + 1]! + (i ~/ 2),
          // The losers-bracket champion always occupies grand-final slot
          // 'b'.
          feedsWinnerToSlot: isLbFinal ? 'b' : (i.isEven ? 'a' : 'b'),
        ));
      }
    }

    // ---- Grand final (+ optional reset). ----
    fixtures.add(PlannedFixture(
      round: k + 1,
      matchIndex: gfIndex,
      roundLabel: 'Grand Final',
      bracket: Bracket.grandFinal,
    ));

    if (bracketReset) {
      fixtures.add(PlannedFixture(
        round: k + 2,
        matchIndex: resetIndex!,
        roundLabel: 'Grand Final (Reset)',
        bracket: Bracket.grandFinalReset,
      ));
    }

    return fixtures;
  }

  // ---------------------------------------------------------------------
  // Groups + knockout
  // ---------------------------------------------------------------------

  /// Splits entrants into groups (snake-seeded so no single group collects
  /// all the top seeds), runs a round robin inside each, then cross-seeds
  /// the qualifiers into a knockout bracket.
  ///
  /// ## Cross-seeding
  ///
  /// The knockout phase is built exactly like [_knockout], over a virtual
  /// seed list ordered qualifying-position-first — every group's winner (in
  /// group order), then every group's runner-up, and so on — instead of
  /// over real entrants. Running the same standard mirror-pairing algorithm
  /// over that list is what produces the textbook cross-seed pattern for
  /// free: for 2 groups × 2 qualifiers, the virtual seed order is
  /// `[A1, B1, A2, B2]`, and mirror-pairing a bracket of 4 from that list
  /// gives `(A1 v B2)` and `(B1 v A2)` — group winners never face their own
  /// group's runner-up in the first knockout round.
  ///
  /// Because no group has been played yet, every knockout-phase entrant is
  /// unknown at generation time — `entrantA`/`entrantB` are always `null`
  /// here, tagged instead with [QualifierSource] so application code knows
  /// which table position must fill the slot once standings exist. If the
  /// qualifier count is not itself a power of two, the padding slots get no
  /// [QualifierSource] either — a "bye" for whichever qualifier lands there
  /// cannot be resolved before groups are played, so it is left for
  /// application code to recognise (one side tagged, one side blank) and
  /// treat as a bye once it can.
  List<PlannedFixture> _groupThenKnockout(
    List<Entrant> entrants,
    int? shuffleSeed, {
    int? groupSize,
    int? numGroups,
    required int qualifiersPerGroup,
  }) {
    // Too small a field to bother splitting — a "group of 3" that then
    // feeds a knockout of 3 qualifiers is more ceremony than a plain
    // knockout would have been.
    if (entrants.length < 4) return _knockout(entrants, shuffleSeed);

    final seeded = _seedOrShuffle(entrants, shuffleSeed);

    var groups = numGroups ??
        (groupSize != null
            ? (seeded.length / groupSize).ceil()
            : max(1, (seeded.length / 4).ceil()));
    // Every group needs at least 2 entrants to play a match, and at least
    // `qualifiersPerGroup` so the knockout phase has someone to seed.
    final maxGroups = max(1, seeded.length ~/ max(2, qualifiersPerGroup));
    groups = groups.clamp(1, maxGroups);

    final buckets = List.generate(groups, (_) => <Entrant>[]);
    // Snake draft: fills group 0..G-1 left to right, then G-1..0 right to
    // left, and so on — the standard way to give every group a comparable
    // overall strength instead of stacking the top seeds into one group.
    var idx = 0;
    var row = 0;
    while (idx < seeded.length) {
      final order = row.isEven
          ? List<int>.generate(groups, (i) => i)
          : List<int>.generate(groups, (i) => groups - 1 - i);
      for (final g in order) {
        if (idx >= seeded.length) break;
        buckets[g].add(seeded[idx]);
        idx++;
      }
      row++;
    }

    final groupIds = List.generate(groups, (i) => String.fromCharCode(65 + i));
    final fixtures = <PlannedFixture>[];

    for (var g = 0; g < groups; g++) {
      final groupFixtures = _roundRobin(buckets[g]);
      final start = fixtures.length;
      for (var i = 0; i < groupFixtures.length; i++) {
        final f = groupFixtures[i];
        fixtures.add(PlannedFixture(
          round: f.round,
          matchIndex: start + i,
          roundLabel: 'Group ${groupIds[g]} · ${f.roundLabel}',
          entrantA: f.entrantA,
          entrantB: f.entrantB,
          bracket: Bracket.group,
          groupId: groupIds[g],
        ));
      }
    }

    final qualifierOrder = <QualifierSource>[
      for (var pos = 1; pos <= qualifiersPerGroup; pos++)
        for (var g = 0; g < groups; g++)
          QualifierSource(groupId: groupIds[g], position: pos),
    ];

    final koSize = _nextPow2(qualifierOrder.length);
    if (koSize >= 2) {
      final koSlotOrder = _mirrorSlots(koSize);
      final koQualifiers = List<QualifierSource?>.generate(
        koSize,
        (i) => koSlotOrder[i] < qualifierOrder.length
            ? qualifierOrder[koSlotOrder[i]]
            : null,
      );
      // Always unknown at generation time — see class doc.
      final koEntrants = List<Entrant?>.filled(koSize, null);

      _buildKnockoutFixtures(
        fixtures: fixtures,
        round1Slots: koEntrants,
        round1Qualifiers: koQualifiers,
        startIndex: fixtures.length,
        bracket: Bracket.knockout,
        roundLabelFn: (r, total) => 'Qualifiers · ${_roundLabel(r, total)}',
      );
    }

    return fixtures;
  }

  // ---------------------------------------------------------------------
  // Swiss — round 1 only. See swiss_pairing.dart for subsequent rounds.
  // ---------------------------------------------------------------------

  /// Swiss pairs by current standing each round, so only round one can be
  /// generated up front — before anyone has a score to pair by, seeding
  /// order (or a fixed shuffle) is the only available signal, so the field
  /// is simply split top half vs. bottom half. Subsequent rounds are built
  /// by `nextSwissRound` in swiss_pairing.dart once results exist.
  List<PlannedFixture> _swissFirstRound(List<Entrant> entrants, int? seed) {
    final ordered = _seedOrShuffle(entrants, seed);
    final fixtures = <PlannedFixture>[];
    var matchIndex = 0;
    var pool = ordered;

    if (pool.length.isOdd) {
      // With no standings to rank by yet, the lowest seed (or the last
      // entrant of a fixed shuffle when nobody is seeded) sits out — the
      // only defensible "lowest score" available before a ball is played.
      final byePlayer = pool.last;
      pool = pool.sublist(0, pool.length - 1);
      fixtures.add(PlannedFixture(
        round: 1,
        matchIndex: matchIndex++,
        roundLabel: 'Swiss Round 1',
        entrantA: byePlayer,
      ));
    }

    // Top half plays bottom half.
    final half = pool.length ~/ 2;
    for (var i = 0; i < half; i++) {
      fixtures.add(PlannedFixture(
        round: 1,
        matchIndex: matchIndex++,
        roundLabel: 'Swiss Round 1',
        entrantA: pool[i],
        entrantB: pool[i + half],
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
