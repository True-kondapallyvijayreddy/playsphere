import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/career/club_stats.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';

/// A club's record — matches played and the summed tally of every player on
/// either side. The property that matters: it credits everyone who played
/// under the club's `orgId`, not any one player's own line, and it never
/// invents a won/lost record (see `ClubSportStats`'s own doc for why).
void main() {
  Fixture fixtureWhere({
    required String id,
    String sportId = 'cricket',
    FixtureStatus status = FixtureStatus.completed,
    MatchResultState resultState = MatchResultState.none,
    Map<String, num> aTally = const {'runsScored': 40},
    Map<String, num> bTally = const {'runsScored': 30},
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
      winnerEntrantId: 'side_a',
      resultState: resultState,
      lineupA: const [MatchPlayer(id: 'uid_a', name: 'A', uid: 'uid_a')],
      lineupB: const [MatchPlayer(id: 'uid_b', name: 'B', uid: 'uid_b')],
      scoreState: state,
    );
  }

  test('sums every player on either side into one club tally', () {
    final rows = ClubSportStats.forFixtures([fixtureWhere(id: 'f1')]);
    expect(rows, hasLength(1));
    expect(rows.single.sportId, 'cricket');
    expect(rows.single.matches, 1);
    expect(rows.single.tally['runsScored'], 70); // 40 + 30, both sides
  });

  test('two sports produce two rows, most-played first', () {
    final rows = ClubSportStats.forFixtures([
      fixtureWhere(id: 'f1', sportId: 'cricket'),
      fixtureWhere(id: 'f2', sportId: 'badminton', aTally: {'pointsWon': 21}, bTally: {'pointsWon': 15}),
      fixtureWhere(id: 'f3', sportId: 'badminton', aTally: {'pointsWon': 21}, bTally: {'pointsWon': 18}),
    ]);
    expect(rows.map((r) => r.sportId).toList(), ['badminton', 'cricket']);
    expect(rows.first.matches, 2);
    expect(rows.first.tally['pointsWon'], 21 + 15 + 21 + 18);
  });

  test('an unfinished match is excluded', () {
    final rows = ClubSportStats.forFixtures([
      fixtureWhere(id: 'f1', status: FixtureStatus.live),
    ]);
    expect(rows, isEmpty);
  });

  test('a result still awaiting official approval is excluded', () {
    final rows = ClubSportStats.forFixtures([
      fixtureWhere(id: 'f1', resultState: MatchResultState.awaitingApproval),
    ]);
    expect(rows, isEmpty);
  });

  test('chess time-control qualifiers roll up into one sport row', () {
    final rows = ClubSportStats.forFixtures([
      fixtureWhere(id: 'f1', sportId: 'chess:blitz', aTally: {'points': 1}, bTally: {'points': 0}),
      fixtureWhere(id: 'f2', sportId: 'chess:classical', aTally: {'points': 1}, bTally: {'points': 0}),
    ]);
    expect(rows, hasLength(1));
    expect(rows.single.sportId, 'chess');
    expect(rows.single.matches, 2);
  });

  test('an empty fixture list produces no rows', () {
    expect(ClubSportStats.forFixtures(const []), isEmpty);
  });
}
