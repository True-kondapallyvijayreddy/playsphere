import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/rating/glicko2.dart';
import 'package:playsphere/domain/team/team_balancer.dart';

/// AI Team Shuffle (CLAUDE.md §8.3): snake-draft by rating, then a
/// constraint-respecting local search to tighten balance.
void main() {
  BalancerPlayer player(String id, double rating, {Set<String> roles = const {}}) =>
      BalancerPlayer(id: id, rating: Rating(rating: rating), roles: roles);

  Set<String> teamOf(TeamShuffleResult r, String playerId) => {
        for (final t in r.teams)
          if (t.players.any((p) => p.id == playerId)) t.name,
      };

  group('snake draft', () {
    test('deals players in a boustrophedon pattern, extra to the front team',
        () {
      // maxIterations: 0 disables both the repair and optimise loops (their
      // `while (... < maxIterations)` guards never enter), isolating the
      // pure draft output.
      const balancer = TeamBalancer(maxIterations: 0);
      final pool = [
        player('p1', 2000),
        player('p2', 1900),
        player('p3', 1800),
        player('p4', 1700),
        player('p5', 1600),
        player('p6', 1500),
        player('p7', 1400),
      ];
      final result = balancer.shuffle(players: pool, teamCount: 3);

      // Deal order by index: 0,1,2,2,1,0,0 — team 0 gets p1, p6, p7; team 1
      // gets p2, p5; team 2 gets p3, p4.
      expect(result.teams[0].players.map((p) => p.id), ['p1', 'p6', 'p7']);
      expect(result.teams[1].players.map((p) => p.id), ['p2', 'p5']);
      expect(result.teams[2].players.map((p) => p.id), ['p3', 'p4']);
    });

    test('sorts by rating regardless of input order, ties broken by id', () {
      const balancer = TeamBalancer(maxIterations: 0);
      final shuffledInput = [
        player('b', 1000),
        player('a', 1000),
        player('c', 2000),
      ];
      final result = balancer.shuffle(players: shuffledInput, teamCount: 2);
      // c (2000) drafts first regardless of position in the input list; the
      // tied pair (a, b, both 1000) break by id so the draft is deterministic
      // even when two players are rated identically.
      expect(result.teams[0].players.first.id, 'c');
      expect(result.teams[1].players.first.id, 'a');
    });
  });

  group('local search improves balance', () {
    test('optimisation never leaves balance worse than the raw draft', () {
      const draftOnly = TeamBalancer(maxIterations: 0);
      const optimised = TeamBalancer();
      final pool = [
        player('p1', 100),
        player('p2', 95),
        player('p3', 60),
        player('p4', 55),
        player('p5', 50),
        player('p6', 45),
        player('p7', 20),
        player('p8', 15),
        player('p9', 5),
      ];
      final draftResult = draftOnly.shuffle(players: pool, teamCount: 3);
      final optimisedResult = optimised.shuffle(players: pool, teamCount: 3);

      expect(
        optimisedResult.balancePercent,
        greaterThanOrEqualTo(draftResult.balancePercent),
      );
    });

    test('a swap-improvable draft is actually improved', () {
      // This pool's snake draft leaves one team well ahead of the others
      // (165/160/120 — see the totals asserted below); swaps can close that
      // gap substantially, so this demonstrates real, strict improvement
      // rather than just "no worse."
      const draftOnly = TeamBalancer(maxIterations: 0);
      const optimised = TeamBalancer();
      final pool = [
        player('p1', 100),
        player('p2', 95),
        player('p3', 60),
        player('p4', 55),
        player('p5', 50),
        player('p6', 45),
        player('p7', 20),
        player('p8', 15),
        player('p9', 5),
      ];
      final draftResult = draftOnly.shuffle(players: pool, teamCount: 3);
      final optimisedResult = optimised.shuffle(players: pool, teamCount: 3);

      double spread(TeamShuffleResult r) {
        final totals = r.teams.map((t) => t.totalStrength).toList();
        return totals.reduce((a, b) => a > b ? a : b) -
            totals.reduce((a, b) => a < b ? a : b);
      }

      expect(draftResult.teams.map((t) => t.totalStrength), [165, 160, 120]);
      expect(spread(optimisedResult), lessThan(spread(draftResult)));
      expect(optimisedResult.balancePercent,
          greaterThan(draftResult.balancePercent));
    });
  });

  group('constraints', () {
    test('keep-together pairs end up on the same team', () {
      const balancer = TeamBalancer();
      final pool = [
        player('a', 100),
        player('b', 90),
        player('c', 80),
        player('d', 70),
        player('e', 60),
        player('f', 50),
      ];
      final result = balancer.shuffle(
        players: pool,
        teamCount: 2,
        constraints: const TeamConstraints(keepTogether: [('a', 'b')]),
      );

      expect(result.constraintViolations, 0);
      expect(teamOf(result, 'a'), teamOf(result, 'b'));
    });

    test('keep-apart pairs never end up on the same team', () {
      const balancer = TeamBalancer();
      final pool = [
        player('a', 100),
        player('b', 90),
        player('c', 80),
        player('d', 70),
        player('e', 60),
        player('f', 50),
      ];
      final result = balancer.shuffle(
        players: pool,
        teamCount: 2,
        constraints: const TeamConstraints(keepApart: [('a', 'd')]),
      );

      expect(result.constraintViolations, 0);
      expect(teamOf(result, 'a'), isNot(teamOf(result, 'd')));
    });

    test('role coverage: every team gets at least one goalkeeper', () {
      const balancer = TeamBalancer();
      final pool = [
        player('a', 100, roles: {'goalkeeper'}),
        player('b', 90),
        player('c', 80),
        player('d', 70, roles: {'goalkeeper'}),
      ];
      final result = balancer.shuffle(
        players: pool,
        teamCount: 2,
        constraints:
            const TeamConstraints(requiredRoles: {'goalkeeper': 1}),
      );

      expect(result.constraintViolations, 0);
      for (final team in result.teams) {
        expect(
          team.players.where((p) => p.roles.contains('goalkeeper')),
          isNotEmpty,
          reason: '${team.name} has no goalkeeper',
        );
      }
    });

    test('constraints are honoured together, not traded off against balance',
        () {
      const balancer = TeamBalancer();
      final pool = [
        player('a', 100, roles: {'goalkeeper'}),
        player('b', 95),
        player('c', 90),
        player('d', 85, roles: {'goalkeeper'}),
        player('e', 40),
        player('f', 35),
        player('g', 30),
        player('h', 25),
      ];
      final result = balancer.shuffle(
        players: pool,
        teamCount: 2,
        constraints: const TeamConstraints(
          keepTogether: [('e', 'f')],
          keepApart: [('a', 'd')],
          requiredRoles: {'goalkeeper': 1},
        ),
      );

      expect(result.constraintViolations, 0);
      expect(teamOf(result, 'e'), teamOf(result, 'f'));
      expect(teamOf(result, 'a'), isNot(teamOf(result, 'd')));
      for (final team in result.teams) {
        expect(team.players.where((p) => p.roles.contains('goalkeeper')),
            isNotEmpty);
      }
    });
  });

  group('determinism', () {
    test('the same pool and seed always produce the same teams', () {
      const balancer = TeamBalancer();
      final pool = [
        for (var i = 0; i < 13; i++) player('p$i', 1000 + i * 37.0),
      ];
      final first = balancer.shuffle(players: pool, teamCount: 4, seed: 42);
      final second = balancer.shuffle(players: pool, teamCount: 4, seed: 42);

      for (var i = 0; i < first.teams.length; i++) {
        expect(
          second.teams[i].players.map((p) => p.id),
          first.teams[i].players.map((p) => p.id),
        );
      }
      expect(second.balancePercent, first.balancePercent);
    });
  });

  group('uneven pools', () {
    test('team sizes differ by at most one player', () {
      const balancer = TeamBalancer();
      final pool = [for (var i = 0; i < 11; i++) player('p$i', 1000 + i * 7.0)];
      final result = balancer.shuffle(players: pool, teamCount: 3);

      final sizes = result.teams.map((t) => t.players.length).toList();
      expect(sizes.reduce((a, b) => a + b), 11);
      expect(
        sizes.reduce((a, b) => a > b ? a : b) -
            sizes.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(1),
      );
    });

    test('an empty pool still returns the requested number of empty teams',
        () {
      const balancer = TeamBalancer();
      final result = balancer.shuffle(players: const [], teamCount: 4);
      expect(result.teams, hasLength(4));
      expect(result.teams.every((t) => t.players.isEmpty), isTrue);
      expect(result.balancePercent, 100);
    });
  });

  group('team strength reporting', () {
    test('total and average strength are exposed for the UI', () {
      const balancer = TeamBalancer(maxIterations: 0);
      final pool = [player('a', 100), player('b', 200)];
      final result = balancer.shuffle(players: pool, teamCount: 2);
      final team = result.teams.first;
      expect(team.totalStrength, team.players.first.rating.rating);
      expect(team.averageStrength, team.totalStrength / team.players.length);
    });

    test('balance percent is 0-100', () {
      const balancer = TeamBalancer();
      final pool = [for (var i = 0; i < 8; i++) player('p$i', 1000 + i * 90.0)];
      final result = balancer.shuffle(players: pool, teamCount: 2);
      expect(result.balancePercent, greaterThanOrEqualTo(0));
      expect(result.balancePercent, lessThanOrEqualTo(100));
    });
  });
}
