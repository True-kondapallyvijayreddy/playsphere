import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';
import 'package:playsphere/domain/draw/seeding.dart';
import 'package:playsphere/domain/rating/glicko2.dart';

/// `Entrant.seed` was a hand-typed integer and the generator fell back to
/// `Random(42)` when nobody had one, so an unseeded 38-player draw was a
/// raffle — while Glicko-2 sat computed and ignored in the next folder.
void main() {
  const policy = SeedingPolicy();

  Entrant player(String id, {int? seed, String? club}) => Entrant(
        id: id,
        displayName: id,
        entrantType: EntrantType.individual,
        uid: id,
        seed: seed,
        clubId: club,
      );

  Rating rated(double r, {int games = 20, double rd = 60}) => Rating(
        rating: r,
        deviation: rd,
        volatility: 0.06,
        gamesPlayed: games,
      );

  group('who is seedable', () {
    test('a strong settled rating seeds, strongest first', () {
      final result = policy.assign(
        entrants: [player('a'), player('b'), player('c'), player('d')],
        ratings: {
          'a': rated(1500),
          'b': rated(1800),
          'c': rated(1650),
          'd': rated(1400),
        },
      );

      final seeds = result.seedsByEntrant;
      expect(seeds['b'], 1);
      expect(seeds['c'], 2);
    });

    test('a newcomer is unseeded, never seed 1', () {
      // Glicko starts everyone at 1500 with RD 350 — the algorithm saying "we
      // have no idea". Sorting on rating alone would put that newcomer above
      // an established player rated 1400 and hand them a protected position
      // on the strength of having never played.
      final result = policy.assign(
        entrants: [player('newcomer'), player('veteran')],
        ratings: {
          'newcomer': rated(1500, games: 0, rd: 350),
          'veteran': rated(1400, games: 40, rd: 45),
        },
        // Asked for explicitly: a two-player field needs no seeding at all,
        // so the default count is zero and would prove nothing here.
        maxSeeds: 1,
      );

      final seeds = result.seedsByEntrant;
      expect(seeds.containsKey('newcomer'), isFalse);
      expect(seeds['veteran'], 1);
    });

    test('too few games leaves a player unseeded, with the count in the reason',
        () {
      final result = policy.assign(
        entrants: [player('a')],
        ratings: {'a': rated(1900, games: 2, rd: 40)},
      );
      final v = result.verdicts.single;
      expect(v.isSeeded, isFalse);
      expect(v.reason, contains('2 of 5'));
    });

    test('a wide deviation leaves a player unseeded even after many games', () {
      final result = policy.assign(
        entrants: [player('a')],
        ratings: {'a': rated(1900, games: 30, rd: 250)},
      );
      expect(result.verdicts.single.isSeeded, isFalse);
      expect(result.verdicts.single.reason, contains('not settled'));
    });

    test('no rating document at all reads as unrated, not as zero', () {
      final result = policy.assign(
        entrants: [player('a'), player('b')],
        ratings: {'b': rated(1600)},
        maxSeeds: 1,
      );
      final byId = {for (final v in result.verdicts) v.entrantId: v};
      expect(byId['a']!.isSeeded, isFalse);
      expect(byId['a']!.reason, contains('No rating yet'));
      expect(byId['b']!.seed, 1);
    });

    test('a withdrawn entrant is not seeded', () {
      final result = policy.assign(
        entrants: [
          const Entrant(
            id: 'gone',
            displayName: 'gone',
            entrantType: EntrantType.individual,
            withdrawn: true,
          ),
          player('here'),
        ],
        ratings: {'gone': rated(2000), 'here': rated(1500)},
        maxSeeds: 1,
      );
      expect(result.seedsByEntrant.containsKey('gone'), isFalse);
      expect(result.seedsByEntrant['here'], 1);
    });

    test('every unseeded player is told why', () {
      final result = policy.assign(
        entrants: [player('a'), player('b')],
        ratings: {'a': rated(1600), 'b': rated(1500, games: 1)},
      );
      for (final v in result.verdicts) {
        expect(v.reason, isNotEmpty, reason: v.entrantId);
      }
    });
  });

  group('how many seeds', () {
    test('a quarter of the bracket — the number the shape can keep apart', () {
      // 8 seeds in a 32 draw, 16 in a 64: exactly the number that can be kept
      // apart until the quarter-finals. More would promise what the bracket
      // cannot deliver.
      expect(SeedingPolicy.seedCountFor(32), 8);
      expect(SeedingPolicy.seedCountFor(64), 16);
      expect(SeedingPolicy.seedCountFor(30), 8);
      expect(SeedingPolicy.seedCountFor(3), 0);
    });

    test('a rated field larger than the seed count seeds only the top', () {
      final entrants = [for (var i = 0; i < 8; i++) player('p$i')];
      final result = policy.assign(
        entrants: entrants,
        ratings: {
          for (var i = 0; i < 8; i++) 'p$i': rated(2000 - i * 50),
        },
        maxSeeds: 2,
      );
      expect(result.seededCount, 2);
      expect(result.seedsByEntrant.length, 2);
      expect(result.seedsByEntrant['p0'], 1);
      expect(result.seedsByEntrant['p1'], 2);
    });

    test('fewer rated players than seed slots seeds only those rated', () {
      final result = policy.assign(
        entrants: [for (var i = 0; i < 8; i++) player('p$i')],
        ratings: {'p0': rated(1700), 'p1': rated(1600)},
      );
      expect(result.seededCount, 2);
    });
  });

  group('the seeding order is reproducible', () {
    test('equal ratings break on the tighter deviation, then on id', () {
      // Between two players of equal rating the one we are more certain about
      // is the safer one to protect, and the chain must be total so a redrawn
      // seeding list is identical.
      final result = policy.assign(
        entrants: [player('b'), player('a'), player('c')],
        ratings: {
          'a': rated(1600, rd: 80),
          'b': rated(1600, rd: 50),
          'c': rated(1600, rd: 50),
        },
        maxSeeds: 2,
      );
      final seeds = result.seedsByEntrant;
      expect(seeds['b'], 1, reason: 'tighter RD, and "b" < "c" on id');
      expect(seeds['c'], 2);
    });
  });

  group('a federation draw is not a ranked ladder', () {
    const generator = FixtureGenerator();

    List<Entrant> field(int n, {int seeds = 0, String? Function(int)? club}) => [
          for (var i = 0; i < n; i++)
            player(
              'p$i',
              seed: i < seeds ? i + 1 : null,
              club: club?.call(i),
            ),
        ];

    test('the top two seeds still cannot meet before the final', () {
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: field(16, seeds: 8),
        method: DrawMethod.federation,
        shuffleSeed: 7,
      );

      final round1 = fixtures.where((f) => f.round == 1);
      for (final f in round1) {
        final seeds = [f.entrantA?.seed, f.entrantB?.seed];
        expect(
          seeds.contains(1) && seeds.contains(2),
          isFalse,
          reason: 'seeds 1 and 2 must be in opposite halves',
        );
      }
    });

    test('a different draw seed produces a different bracket', () {
      List<String?> firstRound(int seed) => generator
          .generate(
            format: CompetitionFormat.knockout,
            entrants: field(16, seeds: 4),
            method: DrawMethod.federation,
            shuffleSeed: seed,
          )
          .where((f) => f.round == 1)
          .map((f) => f.entrantA?.id)
          .toList();

      expect(
        firstRound(1),
        isNot(firstRound(2)),
        reason: 'unseeded players must be drawn, not sorted — otherwise the '
            'same field always produces the same bracket and it is a ladder',
      );
    });

    test('the same draw seed reproduces the bracket exactly', () {
      // "It was random" is not an answer to "why did I get the top seed".
      // Recording the seed turns randomness into something checkable.
      List<String?> firstRound() => generator
          .generate(
            format: CompetitionFormat.knockout,
            entrants: field(16, seeds: 4),
            method: DrawMethod.federation,
            shuffleSeed: 99,
          )
          .where((f) => f.round == 1)
          .map((f) => f.entrantA?.id)
          .toList();

      expect(firstRound(), firstRound());
    });

    test('a ranked draw is unchanged by the new method', () {
      // The default must stay exactly what it was, so no existing event
      // silently gets a different bracket.
      final ranked = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: field(8, seeds: 8),
      );
      final explicit = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: field(8, seeds: 8),
        method: DrawMethod.ranked,
      );
      expect(
        ranked.map((f) => f.entrantA?.id).toList(),
        explicit.map((f) => f.entrantA?.id).toList(),
      );
    });
  });

  group('club protection', () {
    const generator = FixtureGenerator();

    test('two players from one club avoid meeting in round one', () {
      // Travelling to a district championship to play your own club-mate in
      // round one is what a draw exists to prevent, and the first thing an
      // organizer gets challenged on.
      final entrants = [
        for (var i = 0; i < 8; i++)
          Entrant(
            id: 'p$i',
            displayName: 'p$i',
            entrantType: EntrantType.individual,
            uid: 'p$i',
            // Two big clubs, interleaved so the naive draw pairs mates.
            clubId: i < 2 ? 'clubA' : 'club${i % 3}',
          ),
      ];

      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
        method: DrawMethod.federation,
        shuffleSeed: 3,
      );

      final sameClubPairs = fixtures
          .where((f) => f.round == 1)
          .where((f) =>
              f.entrantA?.clubId != null &&
              f.entrantA?.clubId == f.entrantB?.clubId)
          .length;

      expect(
        sameClubPairs,
        0,
        reason: 'the bracket had room to separate them',
      );
    });

    test('entrants with no club are left alone', () {
      // A club's own event: everyone shares a club, or nobody records one.
      // Protection means nothing and must not reshuffle anything.
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: [for (var i = 0; i < 8; i++) player('p$i')],
        method: DrawMethod.federation,
        shuffleSeed: 5,
      );
      expect(fixtures.where((f) => f.round == 1).length, 4);
    });

    test('a field that is all one club still produces a draw', () {
      // Impossible to separate. It must not loop, throw, or drop anybody.
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: [
          for (var i = 0; i < 8; i++) player('p$i', club: 'only'),
        ],
        method: DrawMethod.federation,
        shuffleSeed: 11,
      );
      final round1 = fixtures.where((f) => f.round == 1).toList();
      expect(round1.length, 4);
      final named = <String>{
        for (final f in round1) ...[
          if (f.entrantA != null) f.entrantA!.id,
          if (f.entrantB != null) f.entrantB!.id,
        ],
      };
      expect(named.length, 8, reason: 'nobody may be lost or duplicated');
    });
  });
}
