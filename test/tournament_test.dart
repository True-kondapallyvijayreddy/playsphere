import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';
import 'package:playsphere/domain/draw/match_scheduler.dart';
import 'package:playsphere/domain/draw/swiss_pairing.dart';

Entrant entrant(String id, {int? seed}) => Entrant(
      id: id,
      displayName: id,
      entrantType: EntrantType.individual,
      seed: seed,
    );

/// Deterministic "who would win" rule used across simulations below: lower
/// seed is always the stronger player. Real results are of course not this
/// predictable — the point is a fixed, checkable ground truth to replay the
/// generated wiring against.
Entrant _stronger(Entrant a, Entrant b) =>
    (a.seed ?? 1 << 20) <= (b.seed ?? 1 << 20) ? a : b;
Entrant _weaker(Entrant a, Entrant b) => _stronger(a, b).id == a.id ? b : a;

void main() {
  const generator = FixtureGenerator();

  // =====================================================================
  // Double elimination
  // =====================================================================
  group('double elimination', () {
    test('8 entrants: 14 matches without reset, 15 with', () {
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));

      final withoutReset = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
        bracketReset: false,
      );
      final withReset = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );

      expect(withoutReset.length, 14, reason: '2N-2 for N=8');
      expect(withReset.length, 15, reason: '2N-1 with a reset slot');
    });

    test('16 entrants: 30 matches without reset, 31 with', () {
      final entrants =
          List.generate(16, (i) => entrant('P${i + 1}', seed: i + 1));

      final withoutReset = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
        bracketReset: false,
      );
      final withReset = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );

      expect(withoutReset.length, 30);
      expect(withReset.length, 31);

      final winners =
          withReset.where((f) => f.bracket == Bracket.winners).length;
      final losers =
          withReset.where((f) => f.bracket == Bracket.losers).length;
      final grandFinals =
          withReset.where((f) => f.bracket == Bracket.grandFinal).length;
      final resets =
          withReset.where((f) => f.bracket == Bracket.grandFinalReset).length;

      expect(winners, 15, reason: 'size - 1');
      expect(losers, 14, reason: 'size - 2');
      expect(grandFinals, 1);
      expect(resets, 1);
    });

    test('seeds 1 and 2 start in opposite halves of the winners bracket', () {
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );

      final wbRound1 = fixtures
          .where((f) => f.bracket == Bracket.winners && f.round == 1)
          .toList();
      final seed1Match = wbRound1.indexWhere(
          (f) => [f.entrantA?.id, f.entrantB?.id].contains('P1'));
      final seed2Match = wbRound1.indexWhere(
          (f) => [f.entrantA?.id, f.entrantB?.id].contains('P2'));

      expect(seed1Match ~/ 2, isNot(seed2Match ~/ 2));
    });

    test('every fixture matchIndex equals its position in the list', () {
      final entrants = List.generate(11, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );
      for (var i = 0; i < fixtures.length; i++) {
        expect(fixtures[i].matchIndex, i);
      }
    });

    test(
        'simulated tournament: the eventual champion always comes from '
        'replaying winner/loser wiring forward', () {
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );

      final result = _simulateDoubleElimination(fixtures);

      // P1 never loses under the `_stronger` rule, so P1 must be the
      // winners-bracket champion and must win the grand final outright —
      // no reset needed, but the reset fixture still exists as a
      // placeholder (the engine never conditionally omits it).
      final gf = fixtures.firstWhere((f) => f.bracket == Bracket.grandFinal);
      expect(result.entrantAt(gf.matchIndex, 'a')?.id, 'P1');
      expect(result.winnerAt(gf.matchIndex)?.id, 'P1');

      final resetFixture =
          fixtures.firstWhere((f) => f.bracket == Bracket.grandFinalReset);
      expect(resetFixture.entrantA, isNull,
          reason: 'the engine never conditionally resolves the reset match');
      expect(resetFixture.entrantB, isNull);
    });

    test('bracket reset: the losers-bracket side can force a decider', () {
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );
      final result = _simulateDoubleElimination(fixtures);

      final gf = fixtures.firstWhere((f) => f.bracket == Bracket.grandFinal);
      final wbSide = result.entrantAt(gf.matchIndex, 'a')!; // WB champion
      final lbSide = result.entrantAt(gf.matchIndex, 'b')!; // LB champion

      // Application-layer logic (not the generator's job — see the class
      // doc on `_doubleElimination`): the losers-bracket side wins game
      // one, so a reset is required. Confirm the placeholder the generator
      // reserved is usable for exactly that.
      final resetFixture =
          fixtures.firstWhere((f) => f.bracket == Bracket.grandFinalReset);
      expect(resetFixture.bracket, Bracket.grandFinalReset);

      // Play the reset with the same ground truth: the objectively
      // stronger player (lower seed) wins it, deciding the title.
      final decider = _stronger(wbSide, lbSide);
      expect(decider.id, wbSide.id,
          reason:
              'P1 (the WB side in this bracket) is stronger than whoever '
              'fought back through the losers bracket');
    });

    test('below 4 entrants falls back to a plain knockout, no losers bracket',
        () {
      final entrants = [entrant('A', seed: 1), entrant('B', seed: 2)];
      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );
      expect(fixtures.length, 1);
      expect(fixtures.every((f) => f.bracket == Bracket.knockout), isTrue);
    });

    test('winners-bracket byes auto-advance one round (5 entrants)', () {
      final entrants = List.generate(5, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: entrants,
      );

      final wbRound1 = fixtures
          .where((f) => f.bracket == Bracket.winners && f.round == 1)
          .toList();
      final byeMatch = wbRound1.firstWhere((f) => f.isBye);
      final advanced = (byeMatch.entrantA ?? byeMatch.entrantB)!;

      final wbRound2 = fixtures
          .where((f) => f.bracket == Bracket.winners && f.round == 2)
          .toList();
      final prefilled = wbRound2.any(
        (f) => f.entrantA?.id == advanced.id || f.entrantB?.id == advanced.id,
      );
      expect(prefilled, isTrue,
          reason: 'the bye winner must already occupy their round-2 slot');
    });
  });

  // =====================================================================
  // Swiss
  // =====================================================================
  group('swiss', () {
    test('4+ rounds over 8 entrants never repeats a pairing', () {
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));
      const swiss = SwissPairing();

      final score = {for (final e in entrants) e.id: 0.0};
      final hadBye = {for (final e in entrants) e.id: false};
      final pairCount = <EntrantPair, int>{};

      void applyResults(List<PlannedFixture> roundFixtures) {
        for (final f in roundFixtures) {
          if (f.entrantB == null) {
            score[f.entrantA!.id] = score[f.entrantA!.id]! + 1;
            hadBye[f.entrantA!.id] = true;
            continue;
          }
          final pair = EntrantPair(f.entrantA!.id, f.entrantB!.id);
          pairCount[pair] = (pairCount[pair] ?? 0) + 1;
          final winner = _stronger(f.entrantA!, f.entrantB!);
          score[winner.id] = score[winner.id]! + 1;
        }
      }

      final round1 = generator.generate(
        format: CompetitionFormat.swiss,
        entrants: entrants,
        shuffleSeed: 7,
      );
      expect(round1.length, 4, reason: '8 entrants, no byes needed');
      applyResults(round1);

      final played = <EntrantPair>{...pairCount.keys};

      for (var round = 2; round <= 4; round++) {
        final standings = entrants
            .map((e) => SwissStanding(
                  entrant: e,
                  score: score[e.id]!,
                  hadBye: hadBye[e.id]!,
                ))
            .toList();
        final roundFixtures = swiss.nextSwissRound(
          standings: standings,
          playedPairs: played,
          round: round,
        );
        expect(roundFixtures.length, 4,
            reason: 'even field, every round pairs everyone');
        applyResults(roundFixtures);
        played.addAll(pairCount.keys);
      }

      expect(pairCount.values.every((count) => count == 1), isTrue,
          reason: 'no pairing should recur across 4 rounds for 8 entrants');
    });

    test('odd field gives a bye each round, never repeating a player early',
        () {
      final entrants = List.generate(7, (i) => entrant('P${i + 1}', seed: i + 1));
      const swiss = SwissPairing();

      final score = {for (final e in entrants) e.id: 0.0};
      final hadBye = {for (final e in entrants) e.id: false};
      final byeRecipients = <String>[];

      void applyResults(List<PlannedFixture> roundFixtures) {
        for (final f in roundFixtures) {
          if (f.entrantB == null) {
            score[f.entrantA!.id] = score[f.entrantA!.id]! + 1;
            hadBye[f.entrantA!.id] = true;
            byeRecipients.add(f.entrantA!.id);
            continue;
          }
          final winner = _stronger(f.entrantA!, f.entrantB!);
          score[winner.id] = score[winner.id]! + 1;
        }
      }

      final round1 = generator.generate(
        format: CompetitionFormat.swiss,
        entrants: entrants,
        shuffleSeed: 3,
      );
      expect(round1.where((f) => f.entrantB == null).length, 1);
      applyResults(round1);

      final played = <EntrantPair>{
        for (final f in round1)
          if (f.entrantB != null) EntrantPair(f.entrantA!.id, f.entrantB!.id),
      };

      for (var round = 2; round <= 4; round++) {
        final standings = entrants
            .map((e) => SwissStanding(
                  entrant: e,
                  score: score[e.id]!,
                  hadBye: hadBye[e.id]!,
                ))
            .toList();
        final roundFixtures = swiss.nextSwissRound(
          standings: standings,
          playedPairs: played,
          round: round,
        );
        expect(roundFixtures.where((f) => f.entrantB == null).length, 1,
            reason: 'still an odd field, still exactly one bye');
        applyResults(roundFixtures);
        for (final f in roundFixtures) {
          if (f.entrantB != null) {
            played.add(EntrantPair(f.entrantA!.id, f.entrantB!.id));
          }
        }
      }

      expect(byeRecipients.toSet().length, byeRecipients.length,
          reason: 'no player should get a second bye before everyone has '
              'had a first (4 rounds <= 7 entrants)');
    });

    test('recommendedRoundCount is ceil(log2 N), override wins', () {
      const swiss = SwissPairing();
      expect(swiss.recommendedRoundCount(8), 3);
      expect(swiss.recommendedRoundCount(9), 4);
      expect(swiss.recommendedRoundCount(16), 4);
      expect(swiss.recommendedRoundCount(30, override: 5), 5);
    });

    test('buchholz sums opponents’ scores', () {
      final a = entrant('A');
      final b = entrant('B');
      final c = entrant('C');
      final standings = [
        SwissStanding(entrant: a, score: 2),
        SwissStanding(entrant: b, score: 1),
        SwissStanding(entrant: c, score: 0.5),
      ];
      final result = const SwissPairing().buchholz(
        standings: standings,
        opponentsByEntrantId: {
          'A': ['B', 'C'],
          'B': ['A'],
          'C': ['A'],
        },
      );
      expect(result['A'], 1.5); // B(1) + C(0.5)
      expect(result['B'], 2.0); // A(2)
      expect(result['C'], 2.0); // A(2)
    });
  });

  // =====================================================================
  // Groups + knockout
  // =====================================================================
  group('groups + knockout', () {
    test('8 entrants, 2 groups of 4, cross-seeded into a 4-team knockout',
        () {
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.groupThenKnockout,
        entrants: entrants,
        numGroups: 2,
        qualifiersPerGroup: 2,
      );

      final groupA = fixtures
          .where((f) => f.bracket == Bracket.group && f.groupId == 'A')
          .toList();
      final groupB = fixtures
          .where((f) => f.bracket == Bracket.group && f.groupId == 'B')
          .toList();
      expect(groupA.length, 6, reason: 'round robin of 4 = 6 matches');
      expect(groupB.length, 6);

      final koRound1 = fixtures
          .where((f) => f.bracket == Bracket.knockout && f.round == 1)
          .toList();
      expect(koRound1.length, 2);

      final pairs = koRound1
          .map((f) => {f.qualifierA, f.qualifierB})
          .toList();
      expect(
        pairs.any((p) =>
            p.contains(const QualifierSource(groupId: 'A', position: 1)) &&
            p.contains(const QualifierSource(groupId: 'B', position: 2))),
        isTrue,
        reason: 'Group A winner should face Group B runner-up',
      );
      expect(
        pairs.any((p) =>
            p.contains(const QualifierSource(groupId: 'B', position: 1)) &&
            p.contains(const QualifierSource(groupId: 'A', position: 2))),
        isTrue,
        reason: 'Group B winner should face Group A runner-up, not their '
            'own group’s runner-up',
      );

      final koFinal = fixtures
          .where((f) => f.bracket == Bracket.knockout && f.round == 2)
          .single;
      expect(koFinal.qualifierA, isNull,
          reason: 'the final is decided by who wins the semis, not by a '
              'fixed table position');
      expect(koFinal.entrantA, isNull);

      expect(fixtures.length, 6 + 6 + 2 + 1);

      for (var i = 0; i < fixtures.length; i++) {
        expect(fixtures[i].matchIndex, i);
      }
    });

    test('fewer than 4 entrants falls back to a plain knockout', () {
      final entrants = [entrant('A'), entrant('B'), entrant('C')];
      final fixtures = generator.generate(
        format: CompetitionFormat.groupThenKnockout,
        entrants: entrants,
      );
      expect(fixtures.every((f) => f.bracket == Bracket.knockout), isTrue);
    });
  });

  // =====================================================================
  // Double round-robin
  // =====================================================================
  group('double round-robin', () {
    for (final n in [4, 5, 6]) {
      test('$n entrants play N*(N-1) fixtures, everyone home and away', () {
        final entrants = List.generate(n, (i) => entrant('P${i + 1}'));
        final single = generator.generate(
          format: CompetitionFormat.roundRobin,
          entrants: entrants,
        );
        final double_ = generator.generate(
          format: CompetitionFormat.roundRobin,
          entrants: entrants,
          doubleRoundRobin: true,
        );

        expect(single.length, n * (n - 1) ~/ 2);
        expect(double_.length, n * (n - 1));

        for (final e in entrants) {
          final played = double_
              .where((f) => f.entrantA?.id == e.id || f.entrantB?.id == e.id)
              .length;
          expect(played, 2 * (n - 1));
        }

        // Every ordered pair (home, away) appears exactly once.
        final orderedPairs = double_.map((f) => '${f.entrantA!.id}>${f.entrantB!.id}');
        expect(orderedPairs.toSet().length, orderedPairs.length);
        for (var i = 0; i < entrants.length; i++) {
          for (var j = 0; j < entrants.length; j++) {
            if (i == j) continue;
            expect(
              double_.any((f) =>
                  f.entrantA!.id == entrants[i].id &&
                  f.entrantB!.id == entrants[j].id),
              isTrue,
              reason: '${entrants[i].id} must host ${entrants[j].id} once',
            );
          }
        }
      });
    }
  });

  // =====================================================================
  // Bye auto-advancement (plain knockout)
  // =====================================================================
  group('bye auto-advancement', () {
    test('a round-1 bye winner already occupies their round-2 slot', () {
      final entrants = List.generate(5, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
      );

      final round1 = fixtures.where((f) => f.round == 1).toList();
      final byes = round1.where((f) => f.isBye).toList();
      expect(byes, isNotEmpty);

      for (final bye in byes) {
        final advanced = bye.entrantA ?? bye.entrantB;
        final target = fixtures[bye.feedsWinnerToIndex!];
        final side =
            bye.feedsWinnerToSlot == 'a' ? target.entrantA : target.entrantB;
        expect(side?.id, advanced!.id,
            reason: 'the generator must resolve the bye itself, not leave '
                'the next round showing TBD for a player with no opponent');
      }
    });

    test('a round-2 TBD-vs-TBD placeholder is not treated as a bye', () {
      // 4 entrants: no byes at all. Every round-1 match is real, so round 2
      // (the final) must start fully blank, not auto-resolved.
      final entrants = List.generate(4, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
      );
      final finalMatch = fixtures.firstWhere((f) => f.round == 2);
      expect(finalMatch.entrantA, isNull);
      expect(finalMatch.entrantB, isNull);
    });
  });

  // =====================================================================
  // Scheduler
  // =====================================================================
  group('match scheduler', () {
    const scheduler = MatchScheduler();

    PlannedFixture match(String a, String b, {int round = 1, int index = 0}) =>
        PlannedFixture(
          round: round,
          matchIndex: index,
          roundLabel: 'Round $round',
          entrantA: entrant(a),
          entrantB: entrant(b),
        );

    test('places independent matches into different venues, same slot', () {
      final slot = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final venues = [
        const Venue(id: 'v1', name: 'Court 1'),
        const Venue(id: 'v2', name: 'Court 2'),
      ];
      final result = scheduler.schedule(
        fixtures: [match('A', 'B'), match('C', 'D')],
        venues: venues,
        slots: [slot],
      );
      expect(result.scheduled.length, 2);
      expect(result.unscheduled, isEmpty);
      expect(
        result.scheduled.map((s) => s.venue.id).toSet(),
        {'v1', 'v2'},
      );
    });

    test('detects an entrant clash: same player, overlapping slot', () {
      final slot = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final venues = [
        const Venue(id: 'v1', name: 'Court 1', capacity: 5),
      ];
      // B plays both A and C in the same slot — physically impossible.
      final result = scheduler.schedule(
        fixtures: [match('A', 'B'), match('B', 'C')],
        venues: venues,
        slots: [slot],
      );
      expect(result.scheduled.length, 1);
      expect(result.unscheduled.length, 1);
      expect(result.unscheduled.single.reason, contains('clashing'));
    });

    test('enforces a minimum rest gap between an entrant’s matches', () {
      final slot1 = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final slot2 = TimeSlot(
        start: DateTime(2026, 1, 1, 10, 15),
        end: DateTime(2026, 1, 1, 11, 15),
      );
      final venues = [const Venue(id: 'v1', name: 'Court 1', capacity: 5)];

      final result = scheduler.schedule(
        fixtures: [match('A', 'B'), match('A', 'C')],
        venues: venues,
        slots: [slot1, slot2],
        minRestBetweenMatches: const Duration(minutes: 30),
      );

      // Only a 15-minute gap exists between the slots but 30 is required —
      // A's second match cannot be placed in either slot.
      expect(result.scheduled.length, 1);
      expect(result.unscheduled.length, 1);
      expect(result.unscheduled.single.reason, contains('rest gap'));
    });

    test('a rest gap of zero allows back-to-back matches', () {
      final slot1 = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final slot2 = TimeSlot(
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 11),
      );
      final venues = [const Venue(id: 'v1', name: 'Court 1', capacity: 5)];

      final result = scheduler.schedule(
        fixtures: [match('A', 'B'), match('A', 'C')],
        venues: venues,
        slots: [slot1, slot2],
      );
      expect(result.scheduled.length, 2);
      expect(result.unscheduled, isEmpty);
    });

    test('reports venue capacity as the blocking reason when entrants are '
        'free but every court is full', () {
      final slot = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final venues = [const Venue(id: 'v1', name: 'Court 1')]; // capacity 1

      final result = scheduler.schedule(
        fixtures: [match('A', 'B'), match('C', 'D'), match('E', 'F')],
        venues: venues,
        slots: [slot],
      );
      expect(result.scheduled.length, 1);
      expect(result.unscheduled.length, 2);
      for (final u in result.unscheduled) {
        expect(u.reason, contains('capacity'));
      }
    });

    test('a venue with capacity 2 hosts two matches in the same slot', () {
      final slot = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final venues = [const Venue(id: 'v1', name: 'Hall', capacity: 2)];
      final result = scheduler.schedule(
        fixtures: [match('A', 'B'), match('C', 'D')],
        venues: venues,
        slots: [slot],
      );
      expect(result.scheduled.length, 2);
      expect(result.unscheduled, isEmpty);
    });

    test('byes and unresolved placeholders are skipped, not reported as '
        'failures', () {
      final slot = TimeSlot(
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
      );
      final venues = [const Venue(id: 'v1', name: 'Court 1')];
      final bye = PlannedFixture(
        round: 1,
        matchIndex: 0,
        roundLabel: 'Round 1',
        entrantA: entrant('A'),
      );
      const tbd = PlannedFixture(
        round: 2,
        matchIndex: 1,
        roundLabel: 'Final',
      );

      final result = scheduler.schedule(
        fixtures: [bye, tbd],
        venues: venues,
        slots: [slot],
      );
      expect(result.scheduled, isEmpty);
      expect(result.unscheduled, isEmpty);
    });

    test('never throws when there are no venues or slots at all', () {
      expect(
        () => scheduler.schedule(fixtures: [match('A', 'B')], venues: const [], slots: const []),
        returnsNormally,
      );
      final result = scheduler.schedule(
        fixtures: [match('A', 'B')],
        venues: const [],
        slots: const [],
      );
      expect(result.unscheduled.single.fixture.entrantA?.id, 'A');
    });
  });
}

/// Minimal double-elimination simulator: replays a generated bracket forward
/// using its own `feedsWinnerToIndex`/`feedsLoserToIndex` wiring, so tests
/// can assert on the eventual shape of the tournament rather than just on
/// the static structure. Winners are decided by [_stronger] — deterministic,
/// not a real scoring engine, which is exactly what a pure structural test
/// needs.
class _SimResult {
  _SimResult(this._entrantAt, this._winnerAt);

  final Map<String, Entrant?> _entrantAt; // 'index:slot' -> entrant
  final Map<int, Entrant?> _winnerAt;

  Entrant? entrantAt(int index, String slot) => _entrantAt['$index:$slot'];
  Entrant? winnerAt(int index) => _winnerAt[index];
}

_SimResult _simulateDoubleElimination(List<PlannedFixture> fixtures) {
  final entrantA = <int, Entrant?>{};
  final entrantB = <int, Entrant?>{};
  for (final f in fixtures) {
    entrantA[f.matchIndex] = f.entrantA;
    entrantB[f.matchIndex] = f.entrantB;
  }
  final winnerAt = <int, Entrant?>{};

  void place(int? index, String? slot, Entrant? who) {
    if (index == null || slot == null || who == null) return;
    if (slot == 'a') {
      entrantA[index] = who;
    } else {
      entrantB[index] = who;
    }
  }

  for (final f in fixtures) {
    final a = entrantA[f.matchIndex];
    final b = entrantB[f.matchIndex];
    if (a == null || b == null) {
      // Bye, or a placeholder not yet reachable in this pass (should not
      // happen: construction guarantees forward-only dependencies for a
      // power-of-two field with no byes, which every test using this
      // simulator uses).
      final survivor = a ?? b;
      winnerAt[f.matchIndex] = survivor;
      if (survivor != null) {
        place(f.feedsWinnerToIndex, f.feedsWinnerToSlot, survivor);
      }
      continue;
    }
    final winner = _stronger(a, b);
    final loser = _weaker(a, b);
    winnerAt[f.matchIndex] = winner;
    place(f.feedsWinnerToIndex, f.feedsWinnerToSlot, winner);
    place(f.feedsLoserToIndex, f.feedsLoserToSlot, loser);
  }

  final entrantAtBySlot = <String, Entrant?>{
    for (final index in entrantA.keys) '$index:a': entrantA[index],
    for (final index in entrantB.keys) '$index:b': entrantB[index],
  };
  return _SimResult(entrantAtBySlot, winnerAt);
}
