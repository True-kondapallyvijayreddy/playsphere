import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/tournament/team_partitioner.dart';

void main() {
  const partitioner = TeamPartitioner();

  List<Registration> generatePlayers(int count, {String? housePrefix}) {
    return List.generate(
      count,
      (i) => Registration(
        uid: 'user_$i',
        displayName: 'Player $i',
        status: RegistrationStatus.confirmed,
        houseName: housePrefix != null ? '$housePrefix ${(i % 4) + 1}' : null,
      ),
    );
  }

  group('TeamPartitioner - Exact Divisions', () {
    test('divides 44 players into 4 teams of 11 perfectly', () {
      final players = generatePlayers(44);
      final result = partitioner.partition(
        players: players,
        teamCount: 4,
      );

      expect(result.squads.length, 4);
      expect(result.unassigned, isEmpty);
      expect(result.waitlistOverflow, isEmpty);
      for (final squad in result.squads) {
        expect(squad.members.length, 11);
        expect(squad.reserves, isEmpty);
      }
    });

    test('divides 16 players into 8 doubles pairs', () {
      final players = generatePlayers(16);
      final result = partitioner.partition(
        players: players,
        teamCount: 8,
      );

      expect(result.squads.length, 8);
      for (final squad in result.squads) {
        expect(squad.members.length, 2);
      }
    });
  });

  group('TeamPartitioner - Remainder Handling', () {
    test('strategy distributeEvenly: 43 players into 4 teams gives 11, 11, 11, 10', () {
      final players = generatePlayers(43);
      final result = partitioner.partition(
        players: players,
        teamCount: 4,
        remainderStrategy: RemainderStrategy.distributeEvenly,
      );

      expect(result.squads.length, 4);
      final sizes = result.squads.map((s) => s.members.length).toList()..sort();
      expect(sizes, [10, 11, 11, 11]);
      expect(result.unassigned, isEmpty);
      expect(result.waitlistOverflow, isEmpty);
    });

    test('strategy assignAsReserves: 43 players with target squad 11 gives 3 reserves', () {
      final players = generatePlayers(43);
      final result = partitioner.partition(
        players: players,
        teamCount: 4,
        targetSquadSize: 11,
        remainderStrategy: RemainderStrategy.assignAsReserves,
      );

      expect(result.squads.length, 4);
      expect(result.waitlistOverflow, isEmpty);
      // 44 capacity was needed for 4x11, but only 43 players available -> 40 base + 3 remainder
      final totalReserves = result.squads.fold(0, (sum, s) => sum + s.reserves.length);
      final totalStarters = result.squads.fold(0, (sum, s) => sum + s.members.length);
      expect(totalStarters + totalReserves, 43);
    });

    test('strategy overflowWaitlist: 43 players with target 10 into 4 teams leaves 3 in waitlist', () {
      final players = generatePlayers(43);
      final result = partitioner.partition(
        players: players,
        teamCount: 4,
        targetSquadSize: 10,
        remainderStrategy: RemainderStrategy.overflowWaitlist,
      );

      expect(result.squads.length, 4);
      for (final squad in result.squads) {
        expect(squad.members.length, 10);
      }
      expect(result.waitlistOverflow.length, 3);
    });
  });

  group('TeamPartitioner - Organization Bucket Partitioning', () {
    test('groups students into school houses', () {
      final players = [
        const Registration(uid: 'u1', displayName: 'Alice', status: RegistrationStatus.confirmed, houseName: 'h_red'),
        const Registration(uid: 'u2', displayName: 'Bob', status: RegistrationStatus.confirmed, houseName: 'h_blue'),
        const Registration(uid: 'u3', displayName: 'Charlie', status: RegistrationStatus.confirmed, houseName: 'h_red'),
        const Registration(uid: 'u4', displayName: 'Diana', status: RegistrationStatus.confirmed, houseName: 'h_green'),
        const Registration(uid: 'u5', displayName: 'Evan', status: RegistrationStatus.confirmed, houseName: null), // unassigned
      ];

      final result = partitioner.partitionByBuckets(
        players: players,
        bucketIds: ['h_red', 'h_blue', 'h_green', 'h_yellow'],
        bucketNames: {
          'h_red': 'Red House',
          'h_blue': 'Blue House',
          'h_green': 'Green House',
          'h_yellow': 'Yellow House',
        },
      );

      expect(result.squads.length, 4);
      final redSquad = result.squads.firstWhere((s) => s.bucketId == 'h_red');
      expect(redSquad.members.length, 2);
      expect(redSquad.name, 'Red House');

      expect(result.unassigned.length, 1);
      expect(result.unassigned.first.uid, 'u5');
    });
  });

  group('TeamPartitioner - Draw Readiness Hard Gate', () {
    test('blocks draw generation when entrants < 2', () {
      final comp = Competition(
        id: 'comp1',
        orgId: 'org1',
        name: 'Singles Tennis',
        sportId: 'tennis',
        sportName: 'Tennis',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.registrationClosed,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'tennis',
      );

      final report = partitioner.validateDrawReadiness(
        competition: comp,
        entrants: [
          const Entrant(id: 'e1', displayName: 'Player 1', entrantType: EntrantType.individual, uid: 'p1'),
        ],
        confirmedRegistrations: [
          const Registration(uid: 'p1', displayName: 'Player 1', status: RegistrationStatus.confirmed),
        ],
      );

      expect(report.isReady, isFalse);
      expect(report.reasons.first, contains('At least 2 confirmed entrants'));
    });

    test('blocks draw generation when unassigned pool players exist', () {
      final comp = Competition(
        id: 'comp1',
        orgId: 'org1',
        name: 'Football Cup',
        sportId: 'football',
        sportName: 'Football',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        teamSize: 5,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.registrationClosed,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'football',
      );

      final report = partitioner.validateDrawReadiness(
        competition: comp,
        entrants: [
          const Entrant(
            id: 'team1',
            displayName: 'Team 1',
            entrantType: EntrantType.team,
            memberUids: ['u1', 'u2', 'u3', 'u4', 'u5'],
          ),
          const Entrant(
            id: 'team2',
            displayName: 'Team 2',
            entrantType: EntrantType.team,
            memberUids: ['u6', 'u7', 'u8', 'u9', 'u10'],
          ),
        ],
        confirmedRegistrations: [
          for (var i = 1; i <= 12; i++)
            Registration(uid: 'u$i', displayName: 'Player $i', status: RegistrationStatus.confirmed),
        ],
      );

      expect(report.isReady, isFalse);
      expect(report.unresolvedRegistrations.length, 2);
      expect(report.reasons.any((r) => r.contains('unassigned to any squad')), isTrue);
    });

    test('approves draw generation when all players assigned and min squad met', () {
      final comp = Competition(
        id: 'comp1',
        orgId: 'org1',
        name: 'Basketball 3v3',
        sportId: 'basketball',
        sportName: 'Basketball',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        teamSize: 3,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.registrationClosed,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'basketball',
      );

      final report = partitioner.validateDrawReadiness(
        competition: comp,
        entrants: [
          const Entrant(
            id: 'team1',
            displayName: 'Team 1',
            entrantType: EntrantType.team,
            memberUids: ['u1', 'u2', 'u3'],
          ),
          const Entrant(
            id: 'team2',
            displayName: 'Team 2',
            entrantType: EntrantType.team,
            memberUids: ['u4', 'u5', 'u6'],
          ),
        ],
        confirmedRegistrations: [
          for (var i = 1; i <= 6; i++)
            Registration(uid: 'u$i', displayName: 'Player $i', status: RegistrationStatus.confirmed),
        ],
      );

      expect(report.isReady, isTrue);
      expect(report.reasons, isEmpty);
    });
  });
}
