import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';
import 'package:playsphere/domain/standings/standings_calculator.dart';

/// The draw engine has always produced a fully-wired groups+knockout bracket
/// and the persistence layer has always thrown most of it away, so a
/// tournament ran its groups and then sat at "To be decided" forever while the
/// organizer worked the promotion out on paper.
///
/// These tests pin the pieces that close that gap: the wire format that lets a
/// fixture remember which group it belongs to and which table position it is
/// waiting on, and the per-group tables that turn a finished group into a
/// named quarter-finalist.
void main() {
  const calc = StandingsCalculator();

  Competition competition() => const Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'District Championship',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.groupThenKnockout,
        status: CompetitionStatus.inProgress,
        category: CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
      );

  List<Entrant> entrants(List<String> names) => [
        for (final n in names)
          Entrant(id: n, displayName: n, entrantType: EntrantType.individual),
      ];

  Fixture groupMatch(
    String groupId,
    String a,
    String b, {
    int scoreA = 0,
    int scoreB = 0,
    bool played = true,
  }) =>
      Fixture(
        id: '$groupId-$a-$b',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: played ? FixtureStatus.completed : FixtureStatus.scheduled,
        bracket: Bracket.group,
        groupId: groupId,
        scoringPluginKey: 'goal_based',
        scoreState: {
          'a': scoreA,
          'b': scoreB,
          'period': 1,
          'complete': played,
          'draw': false,
          'winner': scoreA > scoreB ? 'a' : 'b',
        },
        winnerEntrantId: played ? (scoreA > scoreB ? a : b) : null,
      );

  group('draw slot wire format', () {
    test('a qualifier round-trips through its compact wire string', () {
      const source = QualifierSource(groupId: 'B', position: 2);
      expect(source.wire, 'B#2');
      expect(QualifierSource.fromWire('B#2'), source);
    });

    test('a malformed qualifier reads as absent rather than throwing', () {
      // A document hand-edited in the console, or written by a future version,
      // must not take down every screen that lists a fixture.
      expect(QualifierSource.fromWire(null), isNull);
      expect(QualifierSource.fromWire(''), isNull);
      expect(QualifierSource.fromWire('B'), isNull);
      expect(QualifierSource.fromWire('B#x'), isNull);
      expect(QualifierSource.fromWire('#1'), isNull);
    });

    test('a fixture written before brackets existed reads as a knockout', () {
      // Every fixture already in Firestore has no `bracket` key at all, and a
      // plain knockout is what those draws actually were. Defaulting anywhere
      // else would retroactively reclassify every historic match.
      expect(Bracket.fromWire(null), Bracket.knockout);
      expect(Bracket.fromWire('nonsense'), Bracket.knockout);
      expect(Bracket.fromWire('losers'), Bracket.losers);
    });

    test('only group matches claim to have a table', () {
      expect(Bracket.group.hasTable, isTrue);
      expect(Bracket.knockout.hasTable, isFalse);
      expect(Bracket.grandFinal.hasTable, isFalse);
    });

    test('an unresolved slot names the group it waits on, not "TBD"', () {
      final f = Fixture(
        id: 'qf1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: '',
        entrantBId: '',
        entrantAName: 'To be decided',
        entrantBName: 'To be decided',
        status: FixtureStatus.scheduled,
        qualifierA: const QualifierSource(groupId: 'A', position: 1),
        qualifierB: const QualifierSource(groupId: 'B', position: 2),
      );

      expect(f.displayNameA(), 'Group A winner');
      expect(f.displayNameB(), 'Group B runner-up');
      expect(f.hasBothEntrants, isFalse);
    });
  });

  group('per-group tables', () {
    // Two groups of three. A beats everyone in Group A; in Group B, P5 wins
    // both. The knockout phase should therefore draw P1 and P5 as winners.
    List<Fixture> twoCompleteGroups() => [
          groupMatch('A', 'P1', 'P2', scoreA: 2, scoreB: 0),
          groupMatch('A', 'P1', 'P3', scoreA: 2, scoreB: 1),
          groupMatch('A', 'P2', 'P3', scoreA: 3, scoreB: 1),
          groupMatch('B', 'P4', 'P5', scoreA: 0, scoreB: 2),
          groupMatch('B', 'P4', 'P6', scoreA: 2, scoreB: 1),
          groupMatch('B', 'P5', 'P6', scoreA: 2, scoreB: 0),
        ];

    test('each group gets its own table, with only its own entrants', () {
      final tables = calc.computeGroups(
        competition: competition(),
        entrants: entrants(['P1', 'P2', 'P3', 'P4', 'P5', 'P6']),
        fixtures: twoCompleteGroups(),
      );

      expect(tables.keys.toList()..sort(), ['A', 'B']);
      expect(
        tables['A']!.map((s) => s.entrantId).toSet(),
        {'P1', 'P2', 'P3'},
        reason: 'a table that lists the other group\'s players is not a group '
            'table — those players have never met',
      );
      expect(tables['B']!.map((s) => s.entrantId).toSet(), {'P4', 'P5', 'P6'});
    });

    test('the group winner is the row a quarter-final promotes from', () {
      final tables = calc.computeGroups(
        competition: competition(),
        entrants: entrants(['P1', 'P2', 'P3', 'P4', 'P5', 'P6']),
        fixtures: twoCompleteGroups(),
      );

      expect(tables['A']!.first.entrantId, 'P1');
      expect(tables['A']![1].entrantId, 'P2');
      expect(tables['B']!.first.entrantId, 'P5');
    });

    test('knockout fixtures contribute to no table at all', () {
      final fixtures = [
        ...twoCompleteGroups(),
        Fixture(
          id: 'sf1',
          orgId: 'o1',
          compId: 'c1',
          entrantAId: 'P1',
          entrantBId: 'P5',
          entrantAName: 'P1',
          entrantBName: 'P5',
          status: FixtureStatus.completed,
          winnerEntrantId: 'P1',
        ),
      ];

      final tables = calc.computeGroups(
        competition: competition(),
        entrants: entrants(['P1', 'P2', 'P3', 'P4', 'P5', 'P6']),
        fixtures: fixtures,
      );

      // P1 played three group matches and one semi-final; only the three count.
      final p1 = tables['A']!.firstWhere((s) => s.entrantId == 'P1');
      expect(p1.played, 2);
      expect(tables.keys.length, 2);
    });
  });

  group('a group only promotes once it is finished', () {
    test('an unplayed match leaves the group incomplete', () {
      final fixtures = [
        groupMatch('A', 'P1', 'P2', scoreA: 2, scoreB: 0),
        groupMatch('A', 'P1', 'P3', played: false),
        groupMatch('A', 'P2', 'P3', scoreA: 1, scoreB: 0),
      ];

      expect(
        calc.isGroupComplete('A', fixtures),
        isFalse,
        reason: 'half a group has a leader, not a winner — promoting one would '
            'stick, because nothing moves them back out when the last match '
            'reverses the table',
      );
    });

    test('every match played makes the group complete', () {
      final fixtures = [
        groupMatch('A', 'P1', 'P2', scoreA: 2, scoreB: 0),
        groupMatch('A', 'P1', 'P3', scoreA: 2, scoreB: 1),
        groupMatch('A', 'P2', 'P3', scoreA: 1, scoreB: 0),
      ];
      expect(calc.isGroupComplete('A', fixtures), isTrue);
    });

    test('a group nobody was drawn into is not vacuously complete', () {
      expect(calc.isGroupComplete('Z', []), isFalse);
    });
  });

  group('draw configuration reaches the generator', () {
    test('the organizer\'s group count is what actually gets drawn', () {
      // The bug this pins: `generateDraw` called the generator with only
      // format and entrants, so every groups+knockout draw silently took the
      // fallback of roughly four per group no matter what was asked for.
      const generator = FixtureGenerator();
      final field = [
        for (var i = 1; i <= 16; i++)
          Entrant(
            id: 'P$i',
            displayName: 'P$i',
            entrantType: EntrantType.individual,
            seed: i,
          ),
      ];

      final fixtures = generator.generate(
        format: CompetitionFormat.groupThenKnockout,
        entrants: field,
        numGroups: 4,
        qualifiersPerGroup: 2,
      );

      final groupIds = fixtures
          .where((f) => f.bracket == Bracket.group)
          .map((f) => f.groupId)
          .toSet();
      expect(groupIds, {'A', 'B', 'C', 'D'});

      // 8 qualifiers → a knockout of 8: 4 quarters + 2 semis + 1 final.
      final knockout =
          fixtures.where((f) => f.bracket == Bracket.knockout).toList();
      expect(knockout.length, 7);
    });

    test('config round-trips, and bracketReset survives a missing key', () {
      const cfg = DrawConfig(
        numGroups: 4,
        qualifiersPerGroup: 2,
        doubleRoundRobin: true,
        bracketReset: false,
        shuffleSeed: 7,
      );
      final back = DrawConfig.fromMap(
        cfg.toMap().map((k, v) => MapEntry(k, v as dynamic)),
      );

      expect(back.numGroups, 4);
      expect(back.qualifiersPerGroup, 2);
      expect(back.doubleRoundRobin, isTrue);
      expect(back.bracketReset, isFalse);
      expect(back.shuffleSeed, 7);

      // Defaults true, so an older document with no key must not read as
      // false and silently drop the decider from every double-elim draw.
      expect(DrawConfig.fromMap(const {}).bracketReset, isTrue);
      expect(DrawConfig.fromMap(null).qualifiersPerGroup, 2);
    });

    test('a schedule spaces matches by length plus changeover', () {
      const cfg = ScheduleConfig(
        courts: ['Court 1', 'Court 2'],
        matchMinutes: 25,
        changeoverMinutes: 5,
      );
      expect(cfg.slotMinutes, 30);
      expect(cfg.hasCourts, isTrue);
      expect(const ScheduleConfig().hasCourts, isFalse);

      final back = ScheduleConfig.fromMap(
        cfg.toMap().map((k, v) => MapEntry(k, v as dynamic)),
      );
      expect(back.courts, ['Court 1', 'Court 2']);
      expect(back.slotMinutes, 30);
    });
  });

  group('double elimination keeps its losers', () {
    test('every winners-bracket match routes its loser somewhere', () {
      const generator = FixtureGenerator();
      final field = [
        for (var i = 1; i <= 8; i++)
          Entrant(
            id: 'P$i',
            displayName: 'P$i',
            entrantType: EntrantType.individual,
            seed: i,
          ),
      ];

      final fixtures = generator.generate(
        format: CompetitionFormat.doubleElimination,
        entrants: field,
      );

      final winners =
          fixtures.where((f) => f.bracket == Bracket.winners).toList();
      expect(winners, isNotEmpty);
      expect(
        winners.every((f) => f.feedsLoserToIndex != null),
        isTrue,
        reason: 'a winners-bracket loss is a transfer, not an elimination — '
            'until the fixture persisted this the losers bracket was written '
            'and nobody could ever arrive in it',
      );

      // A losers-bracket loss really is an elimination and goes nowhere.
      final losers = fixtures.where((f) => f.bracket == Bracket.losers);
      expect(losers.every((f) => f.feedsLoserToIndex == null), isTrue);
    });
  });
}
