import 'dart:math' as math;

import '../rating/glicko2.dart';

/// One player available to be drafted onto a team.
///
/// Carries the whole [Rating] rather than a bare number because a future
/// version of this balancer may want RD too (an evenly-matched pairing of
/// two provisional players is a very different promise than pairing two
/// well-established ones) — see CLAUDE.md §8.1. Today's balancer only reads
/// [Rating.rating], but keeping the full object means that change never
/// touches every call site.
class BalancerPlayer {
  const BalancerPlayer({
    required this.id,
    required this.rating,
    this.roles = const {},
  });

  final String id;
  final Rating rating;

  /// e.g. {'goalkeeper'}. Free-form on purpose — the balancer never
  /// hard-codes a sport's role vocabulary, matching the rest of the codebase
  /// treating sport specifics as configuration, not code.
  final Set<String> roles;
}

/// Hard rules the shuffle must never break, even to improve balance.
///
/// These are constraints, not preferences. A parent and child who must not
/// be split across the two most competitive teams, or a "these two do not
/// get along" pairing from a club admin, is a promise the organizer made
/// before opening the app — the algorithm breaking it silently to shave a
/// percentage point off the balance score would be a worse outcome than an
/// imperfectly balanced shuffle that keeps every promise.
class TeamConstraints {
  const TeamConstraints({
    this.keepTogether = const [],
    this.keepApart = const [],
    this.requiredRoles = const {},
  });

  /// Pairs of player ids that must land on the same team.
  final List<(String, String)> keepTogether;

  /// Pairs of player ids that must never land on the same team.
  final List<(String, String)> keepApart;

  /// Minimum count of each role required on EVERY team, e.g.
  /// `{'goalkeeper': 1}`. Uniform across teams — a per-team override isn't
  /// something an organizer picking "5-a-side, need a keeper each" needs.
  final Map<String, int> requiredRoles;
}

/// One drafted team.
class BalancedTeam {
  const BalancedTeam({required this.name, required this.players});

  final String name;
  final List<BalancerPlayer> players;

  /// Sum of ratings. What the balancer actually equalises across teams.
  double get totalStrength =>
      players.fold(0.0, (sum, p) => sum + p.rating.rating);

  /// Per-player average, for showing team quality independent of size —
  /// useful when pool sizes don't divide evenly and one team has an extra
  /// player.
  double get averageStrength =>
      players.isEmpty ? 0 : totalStrength / players.length;
}

/// The output of one shuffle: the teams, and enough about how they were
/// built for the UI to show a scorer "94% balanced" and let them decide
/// whether that's good enough before manually dragging anyone.
class TeamShuffleResult {
  const TeamShuffleResult({
    required this.teams,
    required this.balancePercent,
    required this.constraintViolations,
  });

  final List<BalancedTeam> teams;

  /// 0–100. 100 means every team's total strength is identical; lower means
  /// the strongest and weakest team are further apart. See
  /// [TeamBalancer._worstCaseSpread] for how the denominator is chosen.
  final double balancePercent;

  /// Constraints still unmet after the repair phase gave up (only possible
  /// on a genuinely infeasible constraint set, e.g. two keep-apart pairs
  /// that both need the same seat). Surfaced rather than hidden, so the UI
  /// can flag "couldn't honour everything" instead of quietly presenting a
  /// shuffle that broke a promise. Zero for any feasible pool + constraints.
  final int constraintViolations;
}

/// AI Team Shuffle per CLAUDE.md §8.3.
///
/// Two deliberately separate phases:
///
/// 1. **Snake draft.** Sort by rating, deal out 0,1,…,N-1,N-1,…,1,0,0,1,… A
///    single pass, no optimisation — its only job is a sane, explainable
///    starting point where the strongest players aren't all on one team.
///    Team sizes come out differing by at most one player for free: whichever
///    team is mid-lap when the pool runs out picks up the remainder.
///
/// 2. **Local search.** Single-player-for-single-player swaps between two
///    teams at a time, applied only when a swap strictly improves the
///    objective. One swap at a time rather than reshuffling several players
///    keeps every accepted move auditable — a scorer who re-opens the screen
///    can see the same deterministic result, not a black box.
///
/// The local search itself runs in two sub-phases: first minimise constraint
/// *violations* to zero (the snake draft above knows nothing about
/// constraints, so the starting point may well break one), then — and only
/// once the constraint baseline is clean — minimise the balance objective
/// while never letting violations exceed that baseline again. That ordering
/// is what makes "constraints are never broken to improve balance" true by
/// construction rather than by convention: the balance phase's candidate
/// filter simply excludes any swap that would regress the violation count.
///
/// "Max pairwise team-strength difference" for teams T1..TN is exactly
/// max(totals) − min(totals): the two teams furthest apart account for every
/// pairwise difference that matters, since any Ti between them differs from
/// each by less than the two extremes differ from each other.
class TeamBalancer {
  const TeamBalancer({this.maxIterations = 500});

  /// Caps both the repair and optimise loops. Each accepted swap strictly
  /// improves its objective on a finite discrete search space, so the loop
  /// always terminates on its own well under this — the cap exists purely
  /// as a guard against an unforeseen oscillation, not because convergence
  /// is expected to need it.
  final int maxIterations;

  /// Produces a balanced split of [players] into [teamCount] teams.
  ///
  /// [seed] makes the result reproducible: the same pool, constraints and
  /// seed always produce the same teams, which matters both for tests and
  /// for a scorer who backs out of the shuffle screen and reopens it
  /// expecting to see what they already showed the captains. A different
  /// seed explores different equally-good tie-breaks — useful as "shuffle
  /// again" without changing the balance quality on offer.
  TeamShuffleResult shuffle({
    required List<BalancerPlayer> players,
    required int teamCount,
    TeamConstraints constraints = const TeamConstraints(),
    int seed = 0,
  }) {
    if (teamCount < 1) {
      throw ArgumentError.value(teamCount, 'teamCount', 'must be at least 1');
    }
    if (players.isEmpty) {
      return TeamShuffleResult(
        teams: [
          for (var i = 0; i < teamCount; i++)
            BalancedTeam(name: 'Team ${i + 1}', players: const []),
        ],
        balancePercent: 100,
        constraintViolations: 0,
      );
    }

    final rng = math.Random(seed);

    // Stable full ordering (rating desc, id asc as tiebreak) so the draft
    // never depends on the incoming list's order or on sort stability, which
    // Dart's List.sort does not guarantee.
    final sorted = [...players]..sort((a, b) {
        final byRating = b.rating.rating.compareTo(a.rating.rating);
        return byRating != 0 ? byRating : a.id.compareTo(b.id);
      });

    var teams = _snakeDraft(sorted, teamCount);
    teams = _repairConstraints(teams, constraints, rng);
    final baselineViolations = _violationCount(teams, constraints);
    teams = _optimizeBalance(teams, constraints, rng, baselineViolations);

    final totals = _totals(teams);
    final maxDiff = _maxDiff(totals);
    final worst = _worstCaseSpread(
      sorted.map((p) => p.rating.rating).toList(),
      teams.map((t) => t.length).toList(),
    );
    final balance =
        worst <= 0 ? 100.0 : (100 * (1 - maxDiff / worst)).clamp(0.0, 100.0);

    return TeamShuffleResult(
      teams: [
        for (var i = 0; i < teams.length; i++)
          BalancedTeam(name: 'Team ${i + 1}', players: teams[i]),
      ],
      balancePercent: balance,
      constraintViolations: _violationCount(teams, constraints),
    );
  }

  // ---- Step 1: snake draft ------------------------------------------------

  List<List<BalancerPlayer>> _snakeDraft(
    List<BalancerPlayer> sortedDesc,
    int teamCount,
  ) {
    final teams = List.generate(teamCount, (_) => <BalancerPlayer>[]);
    var index = 0;
    var direction = 1;
    for (final player in sortedDesc) {
      teams[index].add(player);
      final next = index + direction;
      if (next < 0 || next >= teamCount) {
        // Bounce off the end instead of stepping out of range — this is the
        // "snake" in snake draft, and it's what keeps team sizes within one
        // of each other regardless of how the pool divides.
        direction = -direction;
      } else {
        index = next;
      }
    }
    return teams;
  }

  // ---- Step 2a: repair constraint violations ------------------------------

  List<List<BalancerPlayer>> _repairConstraints(
    List<List<BalancerPlayer>> start,
    TeamConstraints constraints,
    math.Random rng,
  ) {
    var teams = start;
    var iterations = 0;
    while (_violationCount(teams, constraints) > 0 && iterations < maxIterations) {
      iterations++;
      final currentViolations = _violationCount(teams, constraints);
      final swaps = _candidateSwaps(teams)..shuffle(rng);

      List<List<BalancerPlayer>>? best;
      var bestViolations = currentViolations;
      for (final swap in swaps) {
        final (ta, ia, tb, ib) = swap;
        final candidate = _swapped(teams, ta, ia, tb, ib);
        final v = _violationCount(candidate, constraints);
        if (v < bestViolations) {
          bestViolations = v;
          best = candidate;
        }
      }

      // Nothing helps — either the constraint set is infeasible (e.g. two
      // keep-apart pairs contending for the same seat) or the remainder is
      // as good as a single-swap search can do. Stop rather than spin.
      if (best == null) break;
      teams = best;
    }
    return teams;
  }

  // ---- Step 2b: optimise balance, never regressing violations -------------

  List<List<BalancerPlayer>> _optimizeBalance(
    List<List<BalancerPlayer>> start,
    TeamConstraints constraints,
    math.Random rng,
    int baselineViolations,
  ) {
    var teams = start;
    var bestDiffSoFar = _maxDiff(_totals(teams));
    var iterations = 0;
    while (iterations < maxIterations) {
      iterations++;
      final swaps = _candidateSwaps(teams)..shuffle(rng);

      List<List<BalancerPlayer>>? best;
      var bestDiff = bestDiffSoFar;
      for (final swap in swaps) {
        final (ta, ia, tb, ib) = swap;
        final candidate = _swapped(teams, ta, ia, tb, ib);
        // The one rule this phase may never break: a swap that improves
        // balance but reopens a constraint the repair phase already closed
        // (or worsens one it couldn't close) is rejected outright, full
        // stop — never accepted "because it's close enough."
        if (_violationCount(candidate, constraints) > baselineViolations) {
          continue;
        }
        final diff = _maxDiff(_totals(candidate));
        if (diff < bestDiff) {
          bestDiff = diff;
          best = candidate;
        }
      }

      if (best == null) break; // local optimum
      teams = best;
      bestDiffSoFar = bestDiff;
    }
    return teams;
  }

  // ---- shared helpers -------------------------------------------------

  List<List<BalancerPlayer>> _cloneTeams(List<List<BalancerPlayer>> teams) =>
      [for (final t in teams) [...t]];

  List<List<BalancerPlayer>> _swapped(
    List<List<BalancerPlayer>> teams,
    int teamA,
    int indexA,
    int teamB,
    int indexB,
  ) {
    final next = _cloneTeams(teams);
    final playerA = next[teamA][indexA];
    final playerB = next[teamB][indexB];
    next[teamA][indexA] = playerB;
    next[teamB][indexB] = playerA;
    return next;
  }

  /// Every (teamA, indexInA, teamB, indexInB) pair with teamA < teamB — i.e.
  /// every possible single-for-single swap between two different teams.
  List<(int, int, int, int)> _candidateSwaps(List<List<BalancerPlayer>> teams) {
    final out = <(int, int, int, int)>[];
    for (var ta = 0; ta < teams.length; ta++) {
      for (var tb = ta + 1; tb < teams.length; tb++) {
        for (var ia = 0; ia < teams[ta].length; ia++) {
          for (var ib = 0; ib < teams[tb].length; ib++) {
            out.add((ta, ia, tb, ib));
          }
        }
      }
    }
    return out;
  }

  List<double> _totals(List<List<BalancerPlayer>> teams) => [
        for (final t in teams) t.fold(0.0, (sum, p) => sum + p.rating.rating),
      ];

  double _maxDiff(List<double> totals) {
    if (totals.isEmpty) return 0;
    return totals.reduce(math.max) - totals.reduce(math.min);
  }

  /// How far apart the strongest and weakest team COULD be, given these
  /// exact players split into these exact team sizes. This is what
  /// [TeamShuffleResult.balancePercent] measures the actual spread against:
  /// putting every top rating into the largest team and every bottom rating
  /// into the smallest team is the worst any assignment of this pool could
  /// do, so it's the only denominator that makes "100%" mean "as good as
  /// this pool can possibly be arranged" rather than an arbitrary scale that
  /// happens to make the number look good.
  double _worstCaseSpread(List<double> ratings, List<int> teamSizes) {
    if (ratings.isEmpty || teamSizes.isEmpty) return 0;
    final sorted = [...ratings]..sort();
    final maxSize = teamSizes.reduce(math.max);
    final minSize = teamSizes.reduce(math.min);
    final topSum = sorted.reversed.take(maxSize).fold(0.0, (a, b) => a + b);
    final bottomSum = sorted.take(minSize).fold(0.0, (a, b) => a + b);
    return topSum - bottomSum;
  }

  int _violationCount(List<List<BalancerPlayer>> teams, TeamConstraints c) {
    final teamOf = <String, int>{};
    for (var t = 0; t < teams.length; t++) {
      for (final p in teams[t]) {
        teamOf[p.id] = t;
      }
    }

    var violations = 0;
    for (final (a, b) in c.keepTogether) {
      final ta = teamOf[a];
      final tb = teamOf[b];
      if (ta != null && tb != null && ta != tb) violations++;
    }
    for (final (a, b) in c.keepApart) {
      final ta = teamOf[a];
      final tb = teamOf[b];
      if (ta != null && tb != null && ta == tb) violations++;
    }
    for (final team in teams) {
      for (final role in c.requiredRoles.entries) {
        final have = team.where((p) => p.roles.contains(role.key)).length;
        if (have < role.value) violations += role.value - have;
      }
    }
    return violations;
  }
}
