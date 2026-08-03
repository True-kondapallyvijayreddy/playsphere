import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/domain/ranking/ranking_points.dart';

/// Glicko says how good you are; ranking points say what you have won. Every
/// selection meeting in the world turns on the second, and without it winning
/// a district championship changes nothing anybody can see — which is the
/// complaint that started this work.
void main() {
  Tournament tournament(TournamentGrade grade) => Tournament(
        id: 't1',
        orgId: 'o1',
        name: 'Championship',
        status: TournamentStatus.completed,
        grade: grade,
      );

  Competition event({
    CompetitionFormat format = CompetitionFormat.knockout,
  }) =>
      Competition(
        id: 'e1',
        orgId: 'o1',
        name: 'Singles',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: format,
        status: CompetitionStatus.completed,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
      );

  Fixture match(
    int index,
    String a,
    String b, {
    required String winner,
    int round = 1,
    Bracket bracket = Bracket.knockout,
    String? groupId,
  }) =>
      Fixture(
        id: 'f$index',
        orgId: 'o1',
        compId: 'e1',
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: FixtureStatus.completed,
        round: round,
        matchIndex: index,
        bracket: bracket,
        groupId: groupId,
        winnerEntrantId: winner,
      );

  /// An 8-player knockout: 4 quarters, 2 semis, 1 final.
  List<Fixture> knockout8() => [
        match(0, 'A', 'B', winner: 'A'),
        match(1, 'C', 'D', winner: 'C'),
        match(2, 'E', 'F', winner: 'E'),
        match(3, 'G', 'H', winner: 'G'),
        match(4, 'A', 'C', winner: 'A', round: 2),
        match(5, 'E', 'G', winner: 'E', round: 2),
        match(6, 'A', 'E', winner: 'A', round: 3),
      ];

  group('grade multiplies the finish', () {
    test('a national title is worth far more than a club one', () {
      // Grade multiplies rather than adds, because an additive scheme cannot
      // make a national title outweigh several club ones without absurd
      // numbers at the bottom.
      final club = RankingPoints.pointsFor(
        grade: TournamentGrade.club,
        round: FinishingRound.winner,
      );
      final national = RankingPoints.pointsFor(
        grade: TournamentGrade.national,
        round: FinishingRound.winner,
      );
      expect(national, greaterThan(club * 5));
    });

    test('winning outweighs losing the final by a clear margin', () {
      final win = RankingPoints.pointsFor(
        grade: TournamentGrade.district,
        round: FinishingRound.winner,
      );
      final lose = RankingPoints.pointsFor(
        grade: TournamentGrade.district,
        round: FinishingRound.runnerUp,
      );
      expect(win, greaterThan(lose));
      expect(win - lose, greaterThan(lose - RankingPoints.pointsFor(
        grade: TournamentGrade.district,
        round: FinishingRound.semiFinal,
      )));
    });

    test('each round out is worth less than the one before', () {
      const order = [
        FinishingRound.winner,
        FinishingRound.runnerUp,
        FinishingRound.semiFinal,
        FinishingRound.quarterFinal,
        FinishingRound.lastSixteen,
        FinishingRound.lastThirtyTwo,
        FinishingRound.groupStage,
        FinishingRound.participated,
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i].share,
          lessThan(order[i - 1].share),
          reason: '${order[i].wire} vs ${order[i - 1].wire}',
        );
      }
    });
  });

  group('how far everyone actually got', () {
    test('an 8-draw awards winner, runner-up, semis and quarters', () {
      final awards = RankingPoints.award(
        tournament: tournament(TournamentGrade.district),
        event: event(),
        fixtures: knockout8(),
      );
      final byId = {for (final a in awards) a.entrantId: a.round};

      expect(byId['A'], FinishingRound.winner);
      expect(byId['E'], FinishingRound.runnerUp);
      expect(byId['C'], FinishingRound.semiFinal);
      expect(byId['G'], FinishingRound.semiFinal);
      expect(byId['B'], FinishingRound.quarterFinal);
      expect(byId['H'], FinishingRound.quarterFinal);
    });

    test('everyone who played is awarded something', () {
      final awards = RankingPoints.award(
        tournament: tournament(TournamentGrade.club),
        event: event(),
        fixtures: knockout8(),
      );
      expect(awards.length, 8);
      expect(awards.every((a) => a.points > 0), isTrue);
    });

    test('the same finish is worth less in a smaller draw', () {
      // "Semi-finalist" means something different in a draw of 4 and a draw
      // of 128; a scheme that ignored that would let anyone farm points from
      // tiny events.
      final small = RankingPoints.award(
        tournament: tournament(TournamentGrade.club),
        event: event(),
        fixtures: [
          match(0, 'A', 'B', winner: 'A'),
          match(1, 'C', 'D', winner: 'C'),
          match(2, 'A', 'C', winner: 'A', round: 2),
        ],
      );
      final big = RankingPoints.award(
        tournament: tournament(TournamentGrade.club),
        event: event(),
        fixtures: knockout8(),
      );

      // B lost round 1 of a 4-draw: that is the semi-final.
      expect(
        small.firstWhere((a) => a.entrantId == 'B').round,
        FinishingRound.semiFinal,
      );
      // B lost round 1 of an 8-draw: that is only the quarter-final.
      expect(
        big.firstWhere((a) => a.entrantId == 'B').round,
        FinishingRound.quarterFinal,
      );
    });

    test('awards are ordered by points, best first', () {
      final awards = RankingPoints.award(
        tournament: tournament(TournamentGrade.state),
        event: event(),
        fixtures: knockout8(),
      );
      expect(awards.first.entrantId, 'A');
      for (var i = 1; i < awards.length; i++) {
        expect(awards[i].points, lessThanOrEqualTo(awards[i - 1].points));
      }
    });
  });

  group('formats that have no final', () {
    test('a league crowns nobody a runner-up', () {
      // Nobody is "runner-up" of a round robin in the sense a ranking table
      // means, so the deciding-match logic must not invent one.
      final awards = RankingPoints.award(
        tournament: tournament(TournamentGrade.district),
        event: event(format: CompetitionFormat.roundRobin),
        fixtures: [
          match(0, 'A', 'B', winner: 'A'),
          match(1, 'A', 'C', winner: 'A'),
          match(2, 'B', 'C', winner: 'B', round: 2),
        ],
      );
      expect(awards.any((a) => a.round == FinishingRound.winner), isFalse);
      expect(awards.any((a) => a.round == FinishingRound.runnerUp), isFalse);
    });

    test('a group-stage exit is scored as a group-stage exit', () {
      final awards = RankingPoints.award(
        tournament: tournament(TournamentGrade.district),
        event: event(format: CompetitionFormat.groupThenKnockout),
        fixtures: [
          match(0, 'A', 'B',
              winner: 'A', bracket: Bracket.group, groupId: 'A'),
          match(1, 'C', 'D',
              winner: 'C', bracket: Bracket.group, groupId: 'B'),
          match(2, 'A', 'C', winner: 'A', round: 1),
        ],
      );
      final byId = {for (final a in awards) a.entrantId: a.round};
      expect(byId['A'], FinishingRound.winner);
      expect(byId['C'], FinishingRound.runnerUp);
      expect(
        byId['B'],
        FinishingRound.participated,
        reason: 'B lost their only group match and won nothing',
      );
      expect(
        byId['D'],
        FinishingRound.participated,
      );
    });
  });

  group('honest edges', () {
    test('an event with no results awards nothing', () {
      expect(
        RankingPoints.award(
          tournament: tournament(TournamentGrade.club),
          event: event(),
          fixtures: const [],
        ),
        isEmpty,
      );
    });

    test('unresolved placeholders do not become competitors', () {
      final awards = RankingPoints.award(
        tournament: tournament(TournamentGrade.club),
        event: event(),
        fixtures: [
          match(0, 'A', 'B', winner: 'A'),
          const Fixture(
            id: 'tbd',
            orgId: 'o1',
            compId: 'e1',
            entrantAId: '',
            entrantBId: '',
            entrantAName: 'To be decided',
            entrantBName: 'To be decided',
            status: FixtureStatus.scheduled,
          ),
        ],
      );
      expect(awards.map((a) => a.entrantId).toSet(), {'A', 'B'});
    });

    test('every wire token round-trips', () {
      for (final r in FinishingRound.values) {
        expect(FinishingRound.fromWire(r.wire), r, reason: r.name);
      }
      expect(FinishingRound.fromWire(null), FinishingRound.participated);
    });
  });
}
