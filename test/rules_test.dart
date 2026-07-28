import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/app_user.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/firestore_codec.dart';
import 'package:playsphere/core/permissions/capability.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';

AppUser userBorn(int year, int month, int day, {Gender gender = Gender.male}) =>
    AppUser(
      uid: 'u',
      displayName: 'Test',
      email: 't@example.com',
      dateOfBirth: DateTime(year, month, day),
      gender: gender,
    );

Entrant entrant(String id, {int? seed}) => Entrant(
      id: id,
      displayName: id,
      entrantType: EntrantType.individual,
      seed: seed,
    );

void main() {
  group('age calculation', () {
    test('a birthday that has not happened yet does not count', () {
      // Born 31 Dec 2010, measured 1 Jan 2026 -> 15, not 16.
      expect(ageOnDate(DateTime(2010, 12, 31), DateTime(2026, 1, 1)), 15);
    });

    test('a birthday on the reference date counts', () {
      expect(ageOnDate(DateTime(2010, 6, 15), DateTime(2026, 6, 15)), 16);
    });

    test('the day before a birthday does not count', () {
      expect(ageOnDate(DateTime(2010, 6, 15), DateTime(2026, 6, 14)), 15);
    });
  });

  group('category eligibility', () {
    final cutOff = DateTime(2026, 1, 1);

    test('an under-17 category admits a 16 year old', () {
      final category = CompetitionCategory(
        label: 'U-17 Boys',
        dimensions: const {CategoryDimension.age, CategoryDimension.gender},
        maxAge: 17,
        ageCutOffDate: cutOff,
        allowedGenders: const {Gender.male},
      );
      final result = category.check(userBorn(2009, 5, 1));
      expect(result.isEligible, isTrue);
    });

    test('an under-17 category rejects an 18 year old, with a reason', () {
      final category = CompetitionCategory(
        label: 'U-17 Boys',
        dimensions: const {CategoryDimension.age},
        maxAge: 17,
        ageCutOffDate: cutOff,
      );
      final result = category.check(userBorn(2007, 5, 1));
      expect(result.isEligible, isFalse);
      expect(result.reason, contains('17 or under'));
    });

    test('eligibility is pinned to the cut-off date, not today', () {
      // Born 1 March 2009. On the 1 Jan 2026 cut-off they are 16 and eligible
      // for U-17, and they must STAY eligible even after their March birthday
      // takes them to 17 — a birthday mid-season cannot re-classify a player.
      final category = CompetitionCategory(
        label: 'U-17',
        dimensions: const {CategoryDimension.age},
        maxAge: 16,
        ageCutOffDate: cutOff,
      );
      final player = userBorn(2009, 3, 1);
      expect(category.check(player).isEligible, isTrue);
    });

    test('a gender category rejects the wrong gender with a reason', () {
      const category = CompetitionCategory(
        label: 'Girls',
        dimensions: {CategoryDimension.gender},
        allowedGenders: {Gender.female},
      );
      final result = category.check(userBorn(2008, 1, 1));
      expect(result.isEligible, isFalse);
      expect(result.reason, contains('Female'));
    });

    test('an open category admits everyone', () {
      const category = CompetitionCategory(label: 'Open');
      expect(category.check(userBorn(1980, 1, 1)).isEligible, isTrue);
      expect(
        category.check(userBorn(2015, 1, 1, gender: Gender.female)).isEligible,
        isTrue,
      );
    });
  });

  group('permission matrix', () {
    test('an owner holds every capability', () {
      for (final c in Capability.values) {
        expect(PermissionMatrix.can(MembershipRole.owner, c), isTrue,
            reason: 'owner should hold $c');
      }
    });

    test('an admin cannot manage the organization itself', () {
      // Deleting or transferring an org stays with the owner, so a
      // compromised admin account cannot cost a school its history.
      expect(
        PermissionMatrix.can(MembershipRole.admin, Capability.manageOrganization),
        isFalse,
      );
      expect(
        PermissionMatrix.can(MembershipRole.admin, Capability.manageMembers),
        isTrue,
      );
    });

    test('an event manager has no authority over people', () {
      expect(
        PermissionMatrix.can(
            MembershipRole.eventManager, Capability.manageMembers),
        isFalse,
      );
      expect(
        PermissionMatrix.can(
            MembershipRole.eventManager, Capability.manageCompetitions),
        isTrue,
      );
    });

    test('a scorer can only score and enter events', () {
      expect(
        PermissionMatrix.capabilitiesOf(MembershipRole.judgeScorer),
        {Capability.scoreMatches, Capability.registerSelf},
      );
    });

    test('a plain member can only enter events', () {
      expect(
        PermissionMatrix.capabilitiesOf(MembershipRole.member),
        {Capability.registerSelf},
      );
    });

    test('nobody can grant a role at or above their own rank', () {
      // This is the privilege-escalation guard: an admin promoting themselves
      // or a peer to owner is the classic path to taking over a tenant.
      expect(
        PermissionMatrix.assignableBy(MembershipRole.admin),
        isNot(contains(MembershipRole.owner)),
      );
      expect(
        PermissionMatrix.assignableBy(MembershipRole.admin),
        isNot(contains(MembershipRole.admin)),
      );
      expect(
        PermissionMatrix.assignableBy(MembershipRole.eventManager),
        isEmpty,
        reason: 'an event manager manages events, not people',
      );
    });

    test('only an owner may appoint an admin', () {
      expect(
        PermissionMatrix.assignableBy(MembershipRole.owner),
        contains(MembershipRole.admin),
      );
    });
  });

  group('fixture generation — round robin', () {
    const generator = FixtureGenerator();

    test('four entrants produce six matches, everyone plays everyone', () {
      final entrants = [entrant('A'), entrant('B'), entrant('C'), entrant('D')];
      final fixtures = generator.generate(
        format: CompetitionFormat.roundRobin,
        entrants: entrants,
      );

      expect(fixtures.length, 6);

      final pairs = fixtures
          .map((f) => {f.entrantA!.id, f.entrantB!.id})
          .toList();
      for (var i = 0; i < entrants.length; i++) {
        for (var j = i + 1; j < entrants.length; j++) {
          expect(
            pairs.any((p) => p.containsAll({entrants[i].id, entrants[j].id})),
            isTrue,
            reason: '${entrants[i].id} must play ${entrants[j].id}',
          );
        }
      }
    });

    test('an odd number of entrants gives everyone the same number of games',
        () {
      // With five entrants each should play four matches. Getting this wrong
      // means someone plays fewer games and the league table is invalid.
      final entrants = ['A', 'B', 'C', 'D', 'E'].map(entrant).toList();
      final fixtures = generator.generate(
        format: CompetitionFormat.roundRobin,
        entrants: entrants,
      );

      expect(fixtures.length, 10);

      for (final e in entrants) {
        final played = fixtures
            .where((f) => f.entrantA?.id == e.id || f.entrantB?.id == e.id)
            .length;
        expect(played, 4, reason: '${e.id} should play 4 matches');
      }
    });

    test('no entrant is ever drawn against itself', () {
      final entrants = ['A', 'B', 'C', 'D', 'E', 'F', 'G'].map(entrant).toList();
      final fixtures = generator.generate(
        format: CompetitionFormat.roundRobin,
        entrants: entrants,
      );
      for (final f in fixtures) {
        expect(f.entrantA!.id, isNot(f.entrantB!.id));
      }
    });

    test('fewer than two entrants produces no draw at all', () {
      expect(
        generator.generate(
          format: CompetitionFormat.roundRobin,
          entrants: [entrant('A')],
        ),
        isEmpty,
      );
    });
  });

  group('fixture generation — knockout', () {
    const generator = FixtureGenerator();

    test('eight entrants produce a full seven match bracket', () {
      final entrants = List.generate(8, (i) => entrant('P$i', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
      );
      // 4 + 2 + 1 = 7.
      expect(fixtures.length, 7);
      expect(fixtures.where((f) => f.roundLabel == 'Final').length, 1);
      expect(fixtures.where((f) => f.roundLabel == 'Semi-final').length, 2);
      expect(fixtures.where((f) => f.roundLabel == 'Quarter-final').length, 4);
    });

    test('the top two seeds cannot meet before the final', () {
      // Standard bracket pairing. If seeds 1 and 2 land in the same half, the
      // tournament is a raffle rather than a seeded draw.
      final entrants = List.generate(8, (i) => entrant('P${i + 1}', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
      );

      final firstRound = fixtures.where((f) => f.round == 1).toList();
      final seed1Match =
          firstRound.indexWhere((f) => [f.entrantA?.id, f.entrantB?.id].contains('P1'));
      final seed2Match =
          firstRound.indexWhere((f) => [f.entrantA?.id, f.entrantB?.id].contains('P2'));

      // Four first-round matches: 0,1 feed one semi; 2,3 feed the other.
      expect(seed1Match ~/ 2, isNot(seed2Match ~/ 2),
          reason: 'seeds 1 and 2 must start in opposite halves');
    });

    test('a non power of two field is padded with byes, not dropped', () {
      final entrants = List.generate(5, (i) => entrant('P$i', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
      );

      // Bracket of 8: 4 + 2 + 1 = 7 slots.
      expect(fixtures.length, 7);

      final named = fixtures
          .where((f) => f.round == 1)
          .expand((f) => [f.entrantA?.id, f.entrantB?.id])
          .whereType<String>()
          .toSet();
      expect(named.length, 5, reason: 'every entrant must appear exactly once');
    });

    test('every non-final match feeds a later one', () {
      final entrants = List.generate(4, (i) => entrant('P$i', seed: i + 1));
      final fixtures = generator.generate(
        format: CompetitionFormat.knockout,
        entrants: entrants,
      );
      final finals = fixtures.where((f) => f.feedsWinnerToIndex == null);
      expect(finals.length, 1, reason: 'only the final leads nowhere');
    });
  });
}
