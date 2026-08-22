import 'dart:math';

import '../../core/models/competition.dart';
import 'fixture_generator.dart';

/// An unordered pair of entrant ids, for tracking "have these two already
/// played" regardless of which side was A and which was B.
///
/// A plain `Set<String>` pair or a `(String, String)` record would silently
/// treat `(x, y)` and `(y, x)` as different keys unless every caller
/// remembers to normalize order first. Normalizing once, here, means a
/// caller can never get that wrong.
class EntrantPair {
  factory EntrantPair(String a, String b) =>
      a.compareTo(b) <= 0 ? EntrantPair._(a, b) : EntrantPair._(b, a);

  const EntrantPair._(this.a, this.b);

  final String a;
  final String b;

  @override
  bool operator ==(Object other) =>
      other is EntrantPair && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => '$a v $b';
}

/// One entrant's position going into a Swiss round.
///
/// [score] is on whatever scale the competition uses for match points (win
/// = 1, draw = 0.5, loss = 0 is the usual FIDE-style scale, but this class
/// does not assume it — the caller's points config, already modelled by
/// `Competition.pointsForWin` etc., decides that). [hadBye] must be tracked
/// across rounds by the caller and fed back in, because the "who gets the
/// next bye" rule specifically depends on bye history, not on score alone.
class SwissStanding {
  const SwissStanding({
    required this.entrant,
    required this.score,
    this.hadBye = false,
  });

  final Entrant entrant;
  final double score;
  final bool hadBye;
}

/// Swiss-system round generation for rounds after the first.
///
/// Round one (see `FixtureGenerator._swissFirstRound`) can only pair by seed
/// or a fixed shuffle, because nobody has a score yet. Every later round
/// pairs by current standing instead — this is what makes Swiss scale to
/// large fields without the round count exploding the way a round robin's
/// does: with `nextSwissRound` a 64-player field is fully ranked in about
/// six rounds (`⌈log2 64⌉`) instead of the 63 a round robin would need.
class SwissPairing {
  const SwissPairing();

  /// Rounds needed to produce a clear ranking of [entrantCount] players by
  /// score alone, per §9 ("rounds ≈ ⌈log2 N⌉, configurable"). [override], if
  /// given, always wins — an organizer running a fixed-length club night
  /// should not have the engine second-guess the round count they asked
  /// for.
  int recommendedRoundCount(int entrantCount, {int? override}) {
    if (override != null) return override;
    if (entrantCount <= 1) return 1;
    return max(1, (log(entrantCount) / log(2)).ceil());
  }

  /// Builds the next Swiss round from [standings] (every active entrant,
  /// any order) and [playedPairs] (every pairing that has already happened,
  /// in any previous round — including byes are *not* included here, a bye
  /// is tracked via [SwissStanding.hadBye] instead since it is not a pairing
  /// between two entrants).
  ///
  /// ## Pairing strategy
  ///
  /// This is a simplified Dutch-system pairing, not a full implementation of
  /// FIDE's Swiss pairing rules (which also balance colour/side allocation
  /// and float history far more precisely than this does). It is enough for
  /// club and school tournaments, which is everything §9 asks for:
  ///
  /// 1. Sort entrants by score, descending (ties broken by seed, then name,
  ///    for a deterministic and explainable order — an organizer asking
  ///    "why did these two get paired" should get the same answer every
  ///    time they re-run the draw).
  /// 2. If the field is odd, pull out a bye: the lowest-scoring entrant who
  ///    has not already had one. If everyone has already had a bye (only
  ///    possible in a field that has played more rounds than entrants),
  ///    fall back to the single lowest-scoring entrant — a repeat bye is a
  ///    better outcome than no round happening at all.
  /// 3. Pair the remaining, sorted pool with backtracking search: each
  ///    entrant, most-similar-score-first, tries the closest opponent they
  ///    have not yet played. On a dead end the search backtracks and tries
  ///    the next-closest candidate instead of failing outright — this is
  ///    the "never fails" fallback §9 and the task both ask for. It only
  ///    ever fails to find a repeat-free pairing when the field has
  ///    genuinely exhausted every possible opponent (e.g. the final round of
  ///    a near-complete double round robin played as Swiss); in that one
  ///    case pairing falls back to ignoring the no-rematch constraint rather
  ///    than refusing to produce a round.
  List<PlannedFixture> nextSwissRound({
    required List<SwissStanding> standings,
    required Set<EntrantPair> playedPairs,
    required int round,
    int? shuffleSeed,
  }) {
    if (standings.length < 2) return const [];

    final sorted = List<SwissStanding>.from(standings)
      ..sort((x, y) {
        final byScore = y.score.compareTo(x.score);
        if (byScore != 0) return byScore;
        final xSeed = x.entrant.seed ?? 1 << 20;
        final ySeed = y.entrant.seed ?? 1 << 20;
        final bySeed = xSeed.compareTo(ySeed);
        if (bySeed != 0) return bySeed;
        return x.entrant.displayName
            .toLowerCase()
            .compareTo(y.entrant.displayName.toLowerCase());
      });

    final fixtures = <PlannedFixture>[];
    var matchIndex = 0;
    var pool = sorted;

    if (pool.length.isOdd) {
      var byeAt = pool.lastIndexWhere((s) => !s.hadBye);
      // Everyone has already had a bye — still owe the field a round, so
      // repeat one rather than dropping a player.
      if (byeAt == -1) byeAt = pool.length - 1;

      final byeStanding = pool[byeAt];
      pool = [...pool]..removeAt(byeAt);
      fixtures.add(PlannedFixture(
        round: round,
        matchIndex: matchIndex++,
        roundLabel: 'Swiss Round $round',
        entrantA: byeStanding.entrant,
      ));
    }

    final entrantPool = pool.map((s) => s.entrant).toList();
    final pairs = _pairWithBacktracking(entrantPool, playedPairs) ??
        _pairIgnoringRematches(entrantPool);

    for (final pair in pairs) {
      fixtures.add(PlannedFixture(
        round: round,
        matchIndex: matchIndex++,
        roundLabel: 'Swiss Round $round',
        entrantA: pair.$1,
        entrantB: pair.$2,
      ));
    }

    return fixtures;
  }

  /// Who has already sat a round out, derived from who appeared in each
  /// round rather than from a stored flag.
  ///
  /// [entrantIdsByRound] maps a round number to every entrant that played a
  /// fixture in it. [activeEntrantIds] is the field still in the event.
  ///
  /// ## Why this is derived and not recorded
  ///
  /// A Swiss bye is one entrant left over from an odd field. There is no
  /// match, so `PlannedFixture.isWalkover` keeps it out of the database
  /// entirely — which means "had a bye in round 3" is exactly "was active,
  /// and appears in no fixture of round 3". Deriving it needs no extra field
  /// on the competition and, more to the point, cannot drift away from the
  /// fixtures it describes the way a separately-maintained list would.
  ///
  /// A round nobody appears in is skipped rather than treated as a round
  /// everybody sat out: an empty round is one that was never written, not a
  /// bye for the entire field.
  Set<String> byeRecipients({
    required Iterable<String> activeEntrantIds,
    required Map<int, Set<String>> entrantIdsByRound,
  }) {
    final active = activeEntrantIds.toList(growable: false);
    final out = <String>{};
    for (final played in entrantIdsByRound.values) {
      if (played.isEmpty) continue;
      for (final id in active) {
        if (!played.contains(id)) out.add(id);
      }
    }
    return out;
  }

  /// Sum of the scores of every opponent an entrant has faced.
  ///
  /// This mirrors — deliberately, not by coincidence — the Buchholz
  /// definition already codified as `Tiebreak.buchholz` in
  /// `domain/standings/tiebreak.dart` ("sum of the scores of everyone a team
  /// has played") and computed there for resulted fixtures inside
  /// `StandingsCalculator`. That calculator is wired to the Firestore
  /// `Fixture`/`Competition` models and is the right place to compute
  /// Buchholz once results are persisted; this pure variant exists because
  /// Swiss pairing needs the same figure from in-memory
  /// [SwissStanding]/opponent data *before* anything is written anywhere —
  /// e.g. to break ties when deciding who plays whom next, not just when
  /// rendering a final table.
  Map<String, double> buchholz({
    required List<SwissStanding> standings,
    required Map<String, List<String>> opponentsByEntrantId,
  }) {
    final scoreById = {
      for (final s in standings) s.entrant.id: s.score,
    };
    return {
      for (final s in standings)
        s.entrant.id: (opponentsByEntrantId[s.entrant.id] ?? const [])
            .fold<double>(0, (sum, oppId) => sum + (scoreById[oppId] ?? 0)),
    };
  }

  /// Tries to pair [pool] (already sorted by standing) with nobody meeting a
  /// previously-played opponent. Returns null if no such pairing exists.
  ///
  /// Each entrant tries opponents nearest in the standings first, so a
  /// successful pairing is also a *good* one — closest-available-score,
  /// which is the whole point of Swiss pairing — rather than merely a valid
  /// one. Backtracking (returning up the call stack to try the next
  /// candidate) only kicks in when a greedy nearest-first choice turns out
  /// to make a later entrant unpairable; for realistic tournament sizes this
  /// is rare, so the search is fast in the common case and still correct in
  /// the rare one.
  List<(Entrant, Entrant)>? _pairWithBacktracking(
    List<Entrant> pool,
    Set<EntrantPair> played,
  ) {
    if (pool.isEmpty) return [];
    final first = pool.first;
    final rest = pool.sublist(1);

    for (var i = 0; i < rest.length; i++) {
      final candidate = rest[i];
      if (played.contains(EntrantPair(first.id, candidate.id))) continue;

      final remaining = List<Entrant>.from(rest)..removeAt(i);
      final tail = _pairWithBacktracking(remaining, played);
      if (tail != null) {
        return [(first, candidate), ...tail];
      }
    }
    return null;
  }

  /// Last-resort pairing when no rematch-free arrangement exists at all —
  /// pairs the sorted pool sequentially (closest-score-first), accepting
  /// repeats. A repeat pairing is a worse outcome than avoiding one, but a
  /// round that fails to generate is worse still: an organizer standing in
  /// front of a hall full of players needs *a* pairing, every time.
  List<(Entrant, Entrant)> _pairIgnoringRematches(List<Entrant> pool) {
    final pairs = <(Entrant, Entrant)>[];
    for (var i = 0; i + 1 < pool.length; i += 2) {
      pairs.add((pool[i], pool[i + 1]));
    }
    return pairs;
  }
}
