import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/career/club_record.dart';
import 'package:playsphere/domain/scoring/match_award.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';

/// A club's record — what it played, how it did when it played somebody else,
/// and who did the scoring.
///
/// The property that matters and is easy to get wrong: a club's own two sides
/// playing each other is a match PLAYED with no result to credit either way,
/// while an accepted challenge names the two clubs as the two entrants and is
/// a real won or lost. Folding the first into the second is how a school with
/// forty house matches ends up looking like it has lost forty games.
void main() {
  /// A match between two of the club's own sides — the house-match shape.
  Fixture internal({
    required String id,
    String sportId = 'cricket',
    FixtureStatus status = FixtureStatus.completed,
    MatchResultState resultState = MatchResultState.none,
    Map<String, num> aTally = const {'runsScored': 40},
    Map<String, num> bTally = const {'runsScored': 30},
    String? winnerEntrantId = 'side_a',
  }) {
    var state = PlayerTally.addAll({}, 'uid_a', aTally);
    state = PlayerTally.addAll(state, 'uid_b', bTally);
    return Fixture(
      id: id,
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'side_a',
      entrantBId: 'side_b',
      entrantAName: 'Warriors A',
      entrantBName: 'Warriors B',
      status: status,
      sportId: sportId,
      sourceType: MatchSource.season,
      sourceId: 'src_$id',
      winnerEntrantId: winnerEntrantId,
      resultState: resultState,
      lineupA: const [MatchPlayer(id: 'uid_a', name: 'A', uid: 'uid_a')],
      lineupB: const [MatchPlayer(id: 'uid_b', name: 'B', uid: 'uid_b')],
      scoreState: state,
    );
  }

  /// An accepted challenge — the two entrants ARE the two clubs, exactly as
  /// `CommunityRepository.acceptChallenge` writes them.
  Fixture interClub({
    required String id,
    String sportId = 'cricket',
    String? winner = 'org1',
    bool isDraw = false,
    Map<String, num> homeTally = const {'runsScored': 55},
    Map<String, num> awayTally = const {'runsScored': 20},
  }) {
    var state = PlayerTally.addAll({}, 'uid_home', homeTally);
    state = PlayerTally.addAll(state, 'uid_away', awayTally);
    return Fixture(
      id: id,
      orgId: 'org1',
      compId: 'comp_$id',
      entrantAId: 'org1',
      entrantBId: 'org2',
      entrantAName: 'Warriors',
      entrantBName: 'Rivals',
      status: FixtureStatus.completed,
      sportId: sportId,
      sourceType: MatchSource.challenge,
      sourceId: 'ch_$id',
      participantOrgIds: const ['org1', 'org2'],
      winnerEntrantId: winner,
      isDraw: isDraw,
      lineupA: const [
        MatchPlayer(id: 'uid_home', name: 'Ravi', uid: 'uid_home'),
      ],
      lineupB: const [
        MatchPlayer(id: 'uid_away', name: 'Opponent', uid: 'uid_away'),
      ],
      scoreState: state,
    );
  }

  ClubRecord recordOf(List<Fixture> fixtures) =>
      ClubRecord.forFixtures(fixtures: fixtures, orgId: 'org1');

  group('what counts as played', () {
    test('one row per sport, most-played first', () {
      final record = recordOf([
        internal(id: 'f1'),
        internal(id: 'f2', sportId: 'badminton'),
        internal(id: 'f3', sportId: 'badminton'),
      ]);
      expect(record.sports.map((s) => s.sportId).toList(),
          ['badminton', 'cricket']);
      expect(record.sports.first.matches, 2);
      expect(record.matches, 3);
    });

    test('an unfinished match is not a performance', () {
      final record = recordOf([
        internal(id: 'f1', status: FixtureStatus.live),
        internal(id: 'f2', status: FixtureStatus.scheduled),
      ]);
      expect(record.isEmpty, isTrue);
    });

    test('a result still awaiting verification is not yet a fact', () {
      final record = recordOf([
        internal(id: 'f1', resultState: MatchResultState.awaitingApproval),
      ]);
      expect(record.isEmpty, isTrue);
    });

    test('chess time controls collapse into one sport', () {
      final record = recordOf([
        internal(id: 'f1', sportId: 'chess'),
        internal(id: 'f2', sportId: 'chess'),
      ]);
      expect(record.sports, hasLength(1));
      expect(record.sports.single.sportId, 'chess');
      expect(record.sports.single.matches, 2);
    });
  });

  group('won, lost and drawn', () {
    test('a club playing itself is played but not won or lost', () {
      final record = recordOf([internal(id: 'f1'), internal(id: 'f2')]);
      expect(record.matches, 2);
      expect(record.internal, 2);
      expect(record.won, 0);
      expect(record.lost, 0);
      expect(record.decided, 0);
      expect(record.winRate, isNull);
    });

    test('an accepted challenge is a real result for the club', () {
      final record = recordOf([
        interClub(id: 'c1', winner: 'org1'),
        interClub(id: 'c2', winner: 'org2'),
        interClub(id: 'c3', winner: 'org1'),
      ]);
      expect(record.won, 2);
      expect(record.lost, 1);
      expect(record.internal, 0);
      expect(record.winRate, closeTo(2 / 3, 0.0001));
    });

    test('a draw is its own outcome and stays out of the win rate', () {
      final record = recordOf([
        interClub(id: 'c1', winner: 'org1'),
        interClub(id: 'c2', winner: null, isDraw: true),
      ]);
      expect(record.won, 1);
      expect(record.lost, 0);
      expect(record.drawn, 1);
      expect(record.decided, 2);
      // One win from one settled match — the draw is not half a loss.
      expect(record.winRate, 1.0);
    });

    test('internal and club-vs-club matches are both played, separately '
        'accounted', () {
      final record = recordOf([
        internal(id: 'f1'),
        internal(id: 'f2'),
        interClub(id: 'c1', winner: 'org1'),
      ]);
      expect(record.matches, 3);
      expect(record.internal, 2);
      expect(record.decided, 1);
      expect(record.won, 1);
    });

    test('a finished match with no winner recorded claims nothing', () {
      final record = recordOf([interClub(id: 'c1', winner: null)]);
      expect(record.matches, 1);
      expect(record.won, 0);
      expect(record.lost, 0);
      expect(record.drawn, 0);
    });
  });

  group('who represented the club', () {
    test('an internal match credits both team sheets', () {
      final record = recordOf([internal(id: 'f1')]);
      final cricket = record.forSport('cricket')!;
      expect(cricket.players.map((p) => p.id).toSet(), {'uid_a', 'uid_b'});
      expect(cricket.tally['runsScored'], 70); // 40 + 30
    });

    test('a club-vs-club match credits only the club\'s own players', () {
      final record = recordOf([interClub(id: 'c1')]);
      final cricket = record.forSport('cricket')!;
      expect(cricket.players.map((p) => p.id).toList(), ['uid_home']);
      // 55, not 75 — the opponent's runs are not this club's figures.
      expect(cricket.tally['runsScored'], 55);
    });

    test('the away club sees the same match from its own side', () {
      final record = ClubRecord.forFixtures(
        fixtures: [interClub(id: 'c1', winner: 'org1')],
        orgId: 'org2',
      );
      expect(record.won, 0);
      expect(record.lost, 1);
      expect(record.forSport('cricket')!.players.single.id, 'uid_away');
    });

    test('players are counted once across sports', () {
      final record = recordOf([
        internal(id: 'f1'),
        internal(id: 'f2', sportId: 'badminton'),
      ]);
      // uid_a and uid_b, in both sports, are two people not four.
      expect(record.playerCount, 2);
    });

    test('an individual entrant with no line-up still counts', () {
      final state = PlayerTally.addAll({}, 'uid_solo', {'pointsWon': 21});
      final record = recordOf([
        Fixture(
          id: 'solo',
          orgId: 'org1',
          compId: 'comp1',
          entrantAId: 'entrant_1',
          entrantBId: 'entrant_2',
          entrantAName: 'Priya',
          entrantBName: 'Anita',
          entrantAUid: 'uid_solo',
          entrantBUid: 'uid_other',
          status: FixtureStatus.completed,
          sportId: 'badminton',
          winnerEntrantId: 'entrant_1',
          scoreState: state,
        ),
      ]);
      final badminton = record.forSport('badminton')!;
      // Named on the entrant document, which is where a singles draw puts
      // its competitors — see `Fixture.entrantAUid`.
      expect(badminton.players.map((p) => p.id).toSet(),
          {'uid_solo', 'uid_other'});
      final priya =
          badminton.players.firstWhere((p) => p.id == 'uid_solo');
      expect(priya.name, 'Priya');
      expect(priya[('pointsWon')], 21);
      expect(priya.won, 1);
    });

    test('a guest is on the list and is marked as one', () {
      final state = PlayerTally.addAll({}, 'guest_7', {'runsScored': 60});
      final record = recordOf([
        Fixture(
          id: 'g1',
          orgId: 'org1',
          compId: 'comp1',
          entrantAId: 'side_a',
          entrantBId: 'side_b',
          entrantAName: 'A',
          entrantBName: 'B',
          status: FixtureStatus.completed,
          sportId: 'cricket',
          winnerEntrantId: 'side_a',
          lineupA: const [MatchPlayer(id: 'guest_7', name: 'Borrowed')],
          lineupB: const [
            MatchPlayer(id: 'uid_b', name: 'B', uid: 'uid_b'),
          ],
          scoreState: state,
        ),
      ]);
      final top = record.forSport('cricket')!.topPlayers().first;
      expect(top.name, 'Borrowed');
      expect(top.isRegistered, isFalse);
    });
  });

  group('top players', () {
    test('ranked on the sport\'s own headline stat', () {
      var state = PlayerTally.addAll({}, 'uid_a', {'runsScored': 10});
      state = PlayerTally.addAll(state, 'uid_b', {'runsScored': 90});
      final record = recordOf([
        internal(id: 'f1', aTally: const {'runsScored': 10}, bTally: const {
          'runsScored': 90,
        }),
      ]);
      final top = record.forSport('cricket')!.topPlayers();
      expect(top.first.id, 'uid_b');
      expect(top.first['runsScored'], 90);
    });

    test('somebody who registered nothing is not on a top-scorer list', () {
      final record = recordOf([
        internal(
          id: 'f1',
          aTally: const {'runsScored': 30},
          bTally: const {'runsScored': 0},
        ),
      ]);
      final top = record.forSport('cricket')!.topPlayers();
      expect(top.map((p) => p.id).toList(), ['uid_a']);
    });

    test('totals accumulate across matches', () {
      final record = recordOf([
        internal(id: 'f1', aTally: const {'runsScored': 30}),
        internal(id: 'f2', aTally: const {'runsScored': 45}),
      ]);
      final ravi = record
          .forSport('cricket')!
          .players
          .firstWhere((p) => p.id == 'uid_a');
      expect(ravi.matches, 2);
      expect(ravi['runsScored'], 75);
      expect(ravi.won, 2);
    });

    test('a sport with no headline stat ranks on appearances', () {
      // Athletics publishes no headline stat on purpose — summing personal
      // bests means nothing — so its top list is the club's regulars.
      final record = recordOf([
        internal(id: 'f1', sportId: 'athletics', aTally: const {}),
      ]);
      final athletics = record.forSport('athletics')!;
      expect(athletics.headlineStats, isEmpty);
      expect(athletics.topPlayers().map((p) => p.id).toSet(),
          {'uid_a', 'uid_b'});
    });
  });

  group('player-of-the-match awards', () {
    Fixture withMvp({required String id, required String playerId}) {
      var state = PlayerTally.addAll({}, 'uid_a', const {'runsScored': 40});
      state = PlayerTally.addAll(state, 'uid_b', const {'runsScored': 30});
      return Fixture(
        id: id,
        orgId: 'org1',
        compId: 'comp1',
        entrantAId: 'side_a',
        entrantBId: 'side_b',
        entrantAName: 'Warriors A',
        entrantBName: 'Warriors B',
        status: FixtureStatus.completed,
        sportId: 'cricket',
        winnerEntrantId: 'side_a',
        lineupA: const [MatchPlayer(id: 'uid_a', name: 'A', uid: 'uid_a')],
        lineupB: const [MatchPlayer(id: 'uid_b', name: 'B', uid: 'uid_b')],
        mvp: MatchAward(
          playerId: playerId,
          name: playerId,
          points: 40,
          onWinningSide: playerId == 'uid_a',
        ),
        scoreState: state,
      );
    }

    test('awards accrue to the player who won them', () {
      final record = recordOf([
        withMvp(id: 'f1', playerId: 'uid_a'),
        withMvp(id: 'f2', playerId: 'uid_a'),
        withMvp(id: 'f3', playerId: 'uid_b'),
      ]);
      final cricket = record.forSport('cricket')!;
      expect(cricket.mvps, 3);
      expect(record.mvps, 3);
      final leaders = cricket.mvpLeaders();
      expect(leaders.map((p) => p.id).toList(), ['uid_a', 'uid_b']);
      expect(leaders.first.mvps, 2);
    });

    test('an award can be won in a losing side', () {
      // uid_b was on the beaten side and still took the award, which is the
      // whole reason this is a separate board from the top scorers.
      final record = recordOf([withMvp(id: 'f1', playerId: 'uid_b')]);
      final leader = record.forSport('cricket')!.mvpLeaders().single;
      expect(leader.id, 'uid_b');
      expect(leader.won, 0);
    });

    test('nobody with no awards appears on the board', () {
      final record = recordOf([internal(id: 'f1')]);
      expect(record.forSport('cricket')!.mvpLeaders(), isEmpty);
      expect(record.mvps, 0);
    });

    test('an opponent\'s award is not credited to this club', () {
      final state = PlayerTally.addAll({}, 'uid_away', const {'runsScored': 90});
      final record = recordOf([
        Fixture(
          id: 'c1',
          orgId: 'org1',
          compId: 'comp1',
          entrantAId: 'org1',
          entrantBId: 'org2',
          entrantAName: 'Warriors',
          entrantBName: 'Rivals',
          status: FixtureStatus.completed,
          sportId: 'cricket',
          participantOrgIds: const ['org1', 'org2'],
          winnerEntrantId: 'org2',
          lineupA: const [
            MatchPlayer(id: 'uid_home', name: 'Ravi', uid: 'uid_home'),
          ],
          lineupB: const [
            MatchPlayer(id: 'uid_away', name: 'Their star', uid: 'uid_away'),
          ],
          mvp: const MatchAward(
            playerId: 'uid_away',
            name: 'Their star',
            points: 90,
            onWinningSide: true,
          ),
          scoreState: state,
        ),
      ]);
      expect(record.forSport('cricket')!.mvps, 0);
    });
  });
}
