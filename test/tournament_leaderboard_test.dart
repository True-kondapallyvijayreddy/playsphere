import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/tournament/tournament_leaderboard.dart';
import 'package:playsphere/domain/tournament/tournament_overview.dart';

/// A points table answers "who is winning this draw". Neither question people
/// actually ask at a tournament is answerable from one: how are the groups
/// doing overall, and who has had the best tournament across every event they
/// entered.
void main() {
  Competition event(
    String id,
    String name, {
    CompetitionFormat format = CompetitionFormat.knockout,
    int qualifiers = 2,
    String sportId = 'badminton',
    String sportName = 'Badminton',
  }) =>
      Competition(
        id: id,
        orgId: 'o1',
        name: name,
        sportId: sportId,
        sportName: sportName,
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: format,
        status: CompetitionStatus.inProgress,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        tournamentId: 't1',
        drawConfig: DrawConfig(qualifiersPerGroup: qualifiers),
      );

  Fixture played(
    String compId,
    int index,
    String a,
    String b, {
    required String winner,
    int round = 1,
    Bracket bracket = Bracket.knockout,
    String? groupId,
    MatchResultType type = MatchResultType.normal,
    FixtureStatus status = FixtureStatus.completed,
  }) =>
      Fixture(
        id: '$compId-$index',
        orgId: 'o1',
        compId: compId,
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: status,
        resultType: type,
        round: round,
        matchIndex: index,
        bracket: bracket,
        groupId: groupId,
        winnerEntrantId: winner,
        scoringPluginKey: 'goal_based',
        scoreState: const {
          'a': 2,
          'b': 0,
          'period': 1,
          'complete': true,
          'draw': false,
          'winner': 'a',
        },
        tournamentId: 't1',
      );

  group('the leaderboard spans every event', () {
    test('a player in two draws has one row, not two', () {
      // The whole reason this exists: in the singles table and the doubles
      // table the same person is two unrelated rows.
      final board = TournamentLeaderboard.from(
        events: [event('singles', 'Singles'), event('doubles', 'Doubles')],
        fixtures: [
          played('singles', 0, 'Ravi', 'Arun', winner: 'Ravi'),
          played('doubles', 0, 'Ravi', 'Kiran', winner: 'Ravi'),
        ],
      );

      final ravi = board.players.firstWhere((p) => p.entrantId == 'Ravi');
      expect(ravi.played, 2);
      expect(ravi.won, 2);
      expect(ravi.eventsEntered, 2);
    });

    test('titles rank above raw wins — a tournament is won, not accumulated',
        () {
      final board = TournamentLeaderboard.from(
        events: [
          event('a', 'Event A'),
          event('b', 'Event B', format: CompetitionFormat.roundRobin),
        ],
        fixtures: [
          // Champion of a two-match knockout.
          played('a', 0, 'Champ', 'X', winner: 'Champ'),
          played('a', 1, 'Y', 'Z', winner: 'Y'),
          played('a', 2, 'Champ', 'Y', winner: 'Champ', round: 2),
          // Somebody with more wins but no title, in an unfinished league.
          played('b', 0, 'Grinder', 'P', winner: 'Grinder'),
          played('b', 1, 'Grinder', 'Q', winner: 'Grinder'),
          played('b', 2, 'Grinder', 'R', winner: 'Grinder'),
          const Fixture(
            id: 'b-3',
            orgId: 'o1',
            compId: 'b',
            entrantAId: 'Grinder',
            entrantBId: 'S',
            entrantAName: 'Grinder',
            entrantBName: 'S',
            status: FixtureStatus.scheduled,
            tournamentId: 't1',
          ),
        ],
      );

      expect(board.players.first.entrantId, 'Champ');
      expect(board.players.first.titles, 1);
    });

    test('a walkover is not evidence of a good tournament', () {
      // The result stands in the draw; it just is not a win worth ranking, or
      // turning up would outrank playing well.
      final board = TournamentLeaderboard.from(
        events: [event('a', 'A')],
        fixtures: [
          played('a', 0, 'Lucky', 'Absent',
              winner: 'Lucky',
              status: FixtureStatus.walkover,
              type: MatchResultType.walkover),
        ],
      );
      expect(board.players, isEmpty);
    });

    test('a retirement counts — somebody played', () {
      final board = TournamentLeaderboard.from(
        events: [event('a', 'A')],
        fixtures: [
          played('a', 0, 'Winner', 'Injured',
              winner: 'Winner', type: MatchResultType.retired),
        ],
      );
      expect(board.players.first.won, 1);
    });

    test('a league awards no final, so nobody is credited one', () {
      // Crediting "a final" to whoever played in the last round of a round
      // robin would be meaningless.
      final board = TournamentLeaderboard.from(
        events: [event('l', 'League', format: CompetitionFormat.roundRobin)],
        fixtures: [
          played('l', 0, 'A', 'B', winner: 'A'),
          played('l', 1, 'A', 'C', winner: 'A'),
          played('l', 2, 'B', 'C', winner: 'B', round: 2),
        ],
      );
      expect(board.players.every((p) => p.finals == 0), isTrue);
      expect(board.players.every((p) => p.titles == 0), isTrue);
    });

    test('win rate stays blank below three matches', () {
      final board = TournamentLeaderboard.from(
        events: [event('a', 'A')],
        fixtures: [played('a', 0, 'One', 'Two', winner: 'One')],
      );
      final one = board.players.firstWhere((p) => p.entrantId == 'One');
      expect(
        one.winRate,
        isNull,
        reason: 'a player who won their only match is not on 100% in any '
            'sense worth printing',
      );
    });

    test('the board is stable rather than arbitrary on a full tie', () {
      final board = TournamentLeaderboard.from(
        events: [event('a', 'A', format: CompetitionFormat.roundRobin)],
        fixtures: [
          played('a', 0, 'Zed', 'Ann', winner: 'Zed'),
          played('a', 1, 'Ann', 'Zed', winner: 'Ann'),
        ],
      );
      expect(board.players.map((p) => p.entrantId), ['Ann', 'Zed']);
    });
  });

  group('group summaries', () {
    List<Fixture> twoGroups({bool finished = true}) => [
          played('g', 0, 'A1', 'A2',
              winner: 'A1', bracket: Bracket.group, groupId: 'A'),
          played('g', 1, 'A1', 'A3',
              winner: 'A1', bracket: Bracket.group, groupId: 'A'),
          if (finished)
            played('g', 2, 'A2', 'A3',
                winner: 'A2', bracket: Bracket.group, groupId: 'A')
          else
            const Fixture(
              id: 'g-2',
              orgId: 'o1',
              compId: 'g',
              entrantAId: 'A2',
              entrantBId: 'A3',
              entrantAName: 'A2',
              entrantBName: 'A3',
              status: FixtureStatus.scheduled,
              bracket: Bracket.group,
              groupId: 'A',
              tournamentId: 't1',
            ),
          played('g', 3, 'B1', 'B2',
              winner: 'B1', bracket: Bracket.group, groupId: 'B'),
        ];

    test('every group appears without opening its event', () {
      final board = TournamentLeaderboard.from(
        events: [
          event('g', 'U13 Singles', format: CompetitionFormat.groupThenKnockout)
        ],
        fixtures: twoGroups(),
      );
      expect(board.groups.map((g) => g.groupId), ['A', 'B']);
      expect(board.groups.first.eventName, 'U13 Singles');
    });

    test('the leader and their points are reported', () {
      final board = TournamentLeaderboard.from(
        events: [
          event('g', 'E', format: CompetitionFormat.groupThenKnockout)
        ],
        fixtures: twoGroups(),
      );
      final a = board.groups.firstWhere((g) => g.groupId == 'A');
      expect(a.leader, 'A1');
      expect(a.leaderPoints, 6);
      expect(a.played, 3);
      expect(a.total, 3);
      expect(a.isComplete, isTrue);
    });

    test('an unfinished group is reported as still to play', () {
      final board = TournamentLeaderboard.from(
        events: [
          event('g', 'E', format: CompetitionFormat.groupThenKnockout)
        ],
        fixtures: twoGroups(finished: false),
      );
      final a = board.groups.firstWhere((g) => g.groupId == 'A');
      expect(a.isComplete, isFalse);
      expect(a.remaining, 1);
    });

    test('a group with more qualifying places than players is decided', () {
      final board = TournamentLeaderboard.from(
        events: [
          event('g', 'E',
              format: CompetitionFormat.groupThenKnockout, qualifiers: 4)
        ],
        fixtures: twoGroups(finished: false),
      );
      expect(board.groups.every((g) => g.isDecided), isTrue);
    });

    test('knockout matches produce no group rows', () {
      final board = TournamentLeaderboard.from(
        events: [event('k', 'Knockout')],
        fixtures: [played('k', 0, 'A', 'B', winner: 'A')],
      );
      expect(board.hasGroups, isFalse);
    });
  });

  group('who won an event', () {
    test('a league is decided by its table, not by its last match', () {
      // The bug this pins: "deepest resulted round" in a round robin is just
      // the final round of fixtures, and its winner is very often not the team
      // top of the table.
      final overview = TournamentOverview.from(
        events: [
          event('l', 'League', format: CompetitionFormat.roundRobin)
        ],
        fixtures: [
          played('l', 0, 'Dominant', 'B', winner: 'Dominant'),
          played('l', 1, 'Dominant', 'C', winner: 'Dominant'),
          // Last match of the league, won by a team with one win overall.
          played('l', 2, 'B', 'C', winner: 'B', round: 2),
        ],
      );

      expect(
        overview.events.single.champion,
        'Dominant',
        reason: 'B won the last match; Dominant won the league',
      );
    });

    test('a knockout is still decided by its deepest match', () {
      final overview = TournamentOverview.from(
        events: [event('k', 'Knockout')],
        fixtures: [
          played('k', 0, 'A', 'B', winner: 'A'),
          played('k', 1, 'C', 'D', winner: 'C'),
          played('k', 2, 'A', 'C', winner: 'C', round: 2),
        ],
      );
      expect(overview.events.single.champion, 'C');
    });
  });

  group('the sport filter', () {
    test('a single-sport season offers no filter at all', () {
      // A control with one option costs a read and answers nothing.
      final board = TournamentLeaderboard.from(
        events: [event('e1', 'Singles')],
        fixtures: [played('e1', 0, 'A', 'B', winner: 'A')],
      );
      expect(board.isMultiSport, isFalse);
      expect(board.sportIds, ['badminton']);
    });

    test("a sport's board counts only that sport's matches", () {
      // The whole reason this is not the combined board filtered: a filtered
      // row would print 3 played for somebody who played 2 of that sport.
      final board = TournamentLeaderboard.from(
        events: [
          event('b1', 'Badminton Singles'),
          event('k1', 'Kabaddi',
              sportId: 'kabaddi', sportName: 'Kabaddi'),
        ],
        fixtures: [
          played('b1', 0, 'Ravi', 'X', winner: 'Ravi'),
          played('b1', 1, 'Ravi', 'Y', winner: 'Ravi'),
          played('k1', 0, 'Ravi', 'Z', winner: 'Z'),
        ],
      );

      final combined =
          board.players.firstWhere((p) => p.entrantId == 'Ravi');
      expect(combined.played, 3);
      expect(combined.won, 2);

      final badminton =
          board.playersFor('badminton').firstWhere((p) => p.entrantId == 'Ravi');
      expect(badminton.played, 2);
      expect(badminton.won, 2);
      expect(badminton.lost, 0);

      final kabaddi =
          board.playersFor('kabaddi').firstWhere((p) => p.entrantId == 'Ravi');
      expect(kabaddi.played, 1);
      expect(kabaddi.won, 0);
      expect(kabaddi.lost, 1);
    });

    test('a title counts in its own sport, not in every sport', () {
      final board = TournamentLeaderboard.from(
        events: [
          event('b1', 'Badminton'),
          event('k1', 'Kabaddi',
              sportId: 'kabaddi', sportName: 'Kabaddi'),
        ],
        fixtures: [
          played('b1', 0, 'Ravi', 'X', winner: 'Ravi', round: 2),
          played('k1', 0, 'Ravi', 'Z', winner: 'Z', round: 2),
        ],
      );
      expect(
        board.playersFor('badminton').firstWhere((p) => p.entrantId == 'Ravi').titles,
        1,
      );
      expect(
        board.playersFor('kabaddi').firstWhere((p) => p.entrantId == 'Ravi').titles,
        0,
      );
    });

    test('a null sport is the combined board', () {
      final board = TournamentLeaderboard.from(
        events: [event('e1', 'Singles')],
        fixtures: [played('e1', 0, 'A', 'B', winner: 'A')],
      );
      expect(board.playersFor(null), board.players);
    });

    test('records carry the sports they were earned in', () {
      final board = TournamentLeaderboard.from(
        events: [
          event('b1', 'Badminton'),
          event('k1', 'Kabaddi',
              sportId: 'kabaddi', sportName: 'Kabaddi'),
        ],
        fixtures: [
          played('b1', 0, 'Ravi', 'X', winner: 'Ravi'),
          played('k1', 0, 'Ravi', 'Z', winner: 'Z'),
        ],
      );
      final ravi = board.players.firstWhere((p) => p.entrantId == 'Ravi');
      expect(ravi.sportIds, {'badminton', 'kabaddi'});
      expect(board.isMultiSport, isTrue);
      expect(board.sportNames['kabaddi'], 'Kabaddi');
    });
  });
}
