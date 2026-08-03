import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/standings/standings_calculator.dart';

/// A match could only ever end one way: `winnerEntrantId` plus `isDraw`.
///
/// That made a walkover, a retirement and a straight-games win the same
/// document once written, so a scorecard could not say "RET" a season later,
/// and the three different questions a result gets asked — does it award
/// league points, does it move a rating, does it belong on a career profile —
/// were all answered by one flag that could not distinguish them.
void main() {
  const calc = StandingsCalculator();

  Competition competition() => const Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'League',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.leagueTable,
        status: CompetitionStatus.inProgress,
        category: CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
      );

  List<Entrant> entrants(List<String> names) => [
        for (final n in names)
          Entrant(id: n, displayName: n, entrantType: EntrantType.individual),
      ];

  Fixture result(
    String a,
    String b, {
    required String? winner,
    required FixtureStatus status,
    required MatchResultType type,
    int scoreA = 2,
    int scoreB = 0,
  }) =>
      Fixture(
        id: '$a-$b',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: status,
        resultType: type,
        scoringPluginKey: 'goal_based',
        scoreState: {
          'a': scoreA,
          'b': scoreB,
          'period': 1,
          'complete': true,
          'draw': false,
          'winner': scoreA > scoreB ? 'a' : 'b',
        },
        winnerEntrantId: winner,
      );

  group('what each result type counts towards', () {
    test('a walkover awards points but moves no rating', () {
      // Both halves matter. A table that ignored walkovers would let a team
      // improve its position by not turning up; a rating that counted them
      // would let a player climb on opponents' flat tyres.
      const wo = MatchResultType.walkover;
      expect(wo.countsForStandings, isTrue);
      expect(wo.countsForRating, isFalse);
      expect(wo.countsForCareerStats, isFalse);
    });

    test('a retirement counts everywhere — somebody actually played', () {
      const ret = MatchResultType.retired;
      expect(ret.countsForStandings, isTrue);
      expect(ret.countsForRating, isTrue);
      expect(ret.countsForCareerStats, isTrue);
    });

    test('a disqualification stands as a result but is not skill evidence',
        () {
      const dsq = MatchResultType.disqualified;
      expect(dsq.countsForStandings, isTrue);
      expect(dsq.countsForRating, isFalse);
    });

    test('nothing counts when nobody turned up, or nothing was finished', () {
      for (final t in [MatchResultType.noShow, MatchResultType.abandoned]) {
        expect(t.countsForStandings, isFalse, reason: '${t.wire} standings');
        expect(t.countsForRating, isFalse, reason: '${t.wire} rating');
      }
    });

    test('a concession awards the match to whoever remained', () {
      expect(MatchResultType.conceded.countsForStandings, isTrue);
      expect(MatchResultType.conceded.countsForRating, isFalse);
    });

    test('only a normal result needs no explanation', () {
      expect(MatchResultType.normal.wantsNote, isFalse);
      expect(MatchResultType.retired.wantsNote, isTrue);
    });
  });

  group('the wire format survives older documents', () {
    test('a fixture written before result types reads as a normal result', () {
      // Every fixture already in Firestore has no `resultType` key. Anything
      // unusual went through `forceResult`, which set a distinct status — so
      // "normal" is the only correct reading of a missing field.
      expect(MatchResultType.fromWire(null), MatchResultType.normal);
      expect(MatchResultType.fromWire(''), MatchResultType.normal);
      expect(MatchResultType.fromWire('nonsense'), MatchResultType.normal);
    });

    test('every type round-trips through its wire token', () {
      for (final t in MatchResultType.values) {
        expect(MatchResultType.fromWire(t.wire), t, reason: t.name);
      }
    });

    test('the note round-trips onto the fixture', () {
      // `forceResult` has always written `resultNote` and no model has ever
      // read it, so an organizer's explanation went into Firestore and was
      // visible nowhere.
      const f = Fixture(
        id: 'f1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'A',
        entrantBId: 'B',
        entrantAName: 'A',
        entrantBName: 'B',
        status: FixtureStatus.walkover,
        resultType: MatchResultType.walkover,
        resultNote: 'Did not arrive by the 20-minute cut-off.',
      );
      expect(f.toCreate()['resultType'], 'walkover');
      expect(
        f.toCreate()['resultNote'],
        'Did not arrive by the 20-minute cut-off.',
      );
    });

    test('copyWith carries the result type through a score update', () {
      // copyWith runs on every scoring event. Dropping the result type there
      // would silently reclassify a retirement as an ordinary win partway
      // through the match it describes.
      const f = Fixture(
        id: 'f1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'A',
        entrantBId: 'B',
        entrantAName: 'A',
        entrantBName: 'B',
        status: FixtureStatus.completed,
        resultType: MatchResultType.retired,
        resultNote: 'Ankle, game 2.',
      );
      final updated = f.copyWith(lastSeq: 12);
      expect(updated.resultType, MatchResultType.retired);
      expect(updated.resultNote, 'Ankle, game 2.');
    });
  });

  group('the league table respects the result type', () {
    test('a walkover awards the winner full points', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [
          result(
            'Alpha',
            'Beta',
            winner: 'Alpha',
            status: FixtureStatus.walkover,
            type: MatchResultType.walkover,
          ),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'Alpha').points, 3);
      expect(table.firstWhere((r) => r.entrantId == 'Beta').played, 1);
    });

    test('a no-show awards nothing to anybody', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [
          result(
            'Alpha',
            'Beta',
            winner: null,
            status: FixtureStatus.walkover,
            type: MatchResultType.noShow,
          ),
        ],
      );
      for (final row in table) {
        expect(row.played, 0, reason: '${row.entrantId} played');
        expect(row.points, 0, reason: '${row.entrantId} points');
      }
    });

    test('an abandoned match is not a draw', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [
          result(
            'Alpha',
            'Beta',
            winner: null,
            status: FixtureStatus.abandoned,
            type: MatchResultType.abandoned,
          ),
        ],
      );
      // Treating it as a draw would silently award a point nobody earned.
      expect(table.every((r) => r.points == 0), isTrue);
      expect(table.every((r) => r.drawn == 0), isTrue);
    });

    test('a retirement is a played match with a real winner', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [
          result(
            'Alpha',
            'Beta',
            winner: 'Alpha',
            status: FixtureStatus.completed,
            type: MatchResultType.retired,
          ),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'Alpha').won, 1);
      expect(table.firstWhere((r) => r.entrantId == 'Beta').lost, 1);
    });

    test('a group is complete even when a match was conceded', () {
      // A concession is a decided match. A group waiting on it forever would
      // block the whole knockout stage behind one team that went home.
      final fixtures = [
        const Fixture(
          id: 'g1',
          orgId: 'o1',
          compId: 'c1',
          entrantAId: 'A',
          entrantBId: 'B',
          entrantAName: 'A',
          entrantBName: 'B',
          status: FixtureStatus.walkover,
          resultType: MatchResultType.conceded,
          bracket: Bracket.group,
          groupId: 'A',
          winnerEntrantId: 'A',
        ),
      ];
      expect(calc.isGroupComplete('A', fixtures), isTrue);
    });
  });
}
