import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/career/scoped_stats.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';

/// Per-scope career statistics — `docs/Heart_of_the_playsphere.md` §18.
///
/// The property that matters is that every scope is a *view* of one set of
/// matches, never a separate stored total. So the arithmetic worth protecting
/// is that the scopes partition correctly, that a match counted in "Season"
/// is also counted in "All", and that matches which should not count at all
/// — unfinished, unverified, somebody else's — stay out of every scope.
void main() {
  const me = 'uid_rahul';
  const them = 'uid_other';

  Fixture matchWhere({
    required String id,
    required MatchSource source,
    required String winnerEntrantId,
    Map<String, num> myTally = const {'runs': 50},
    FixtureStatus status = FixtureStatus.completed,
    MatchResultState resultState = MatchResultState.none,
    bool includeMe = true,
    String sportId = 'cricket',
  }) {
    return Fixture(
      id: id,
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'side_a',
      entrantBId: 'side_b',
      entrantAName: 'Warriors',
      entrantBName: 'Titans',
      status: status,
      sportId: sportId,
      sourceType: source,
      sourceId: 'src_$id',
      winnerEntrantId: winnerEntrantId,
      resultState: resultState,
      lineupA: [
        if (includeMe) const MatchPlayer(id: me, name: 'Rahul', uid: me),
        const MatchPlayer(id: them, name: 'Other', uid: them),
      ],
      lineupB: const [
        MatchPlayer(id: 'uid_c', name: 'C', uid: 'uid_c'),
      ],
      scoreState: PlayerTally.addAll({}, me, myTally),
    );
  }

  test('a match counts in its own scope and in All, and nowhere else', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.matches, 1);
    expect(stats[StatScope.tournament]!.matches, 1);
    expect(stats[StatScope.season]!.matches, 0);
    expect(stats[StatScope.challenge]!.matches, 0);
    expect(stats[StatScope.singleMatch]!.matches, 0);
  });

  test('All is the sum of the other scopes', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          myTally: const {'runs': 74},
        ),
        matchWhere(
          id: 'f2',
          source: MatchSource.challenge,
          winnerEntrantId: 'side_b',
          myTally: const {'runs': 42},
        ),
        matchWhere(
          id: 'f3',
          source: MatchSource.season,
          winnerEntrantId: 'side_a',
          myTally: const {'runs': 55},
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.matches, 3);
    // The §11 example: it does not matter where the match came from, the runs
    // are the player's.
    expect(stats[StatScope.all]!.tally['runs'], 171);
    expect(stats[StatScope.tournament]!.tally['runs'], 74);
    expect(stats[StatScope.challenge]!.tally['runs'], 42);
    expect(stats[StatScope.season]!.tally['runs'], 55);
  });

  test('wins and losses are read from the player\'s own side', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        // On side A, side A won.
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
        ),
        // On side A, side B won.
        matchWhere(
          id: 'f2',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_b',
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.won, 1);
    expect(stats[StatScope.all]!.lost, 1);
    expect(stats[StatScope.all]!.winRate, 0.5);
  });

  test('an unfinished match is not a performance', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          status: FixtureStatus.live,
        ),
      ],
      uid: me,
    );

    // Counting it would divide real runs by an imagined innings.
    expect(stats[StatScope.all]!.matches, 0);
    expect(stats[StatScope.all]!.tally['runs'], isNull);
  });

  test('a result awaiting verification does not count yet', () {
    // §23: a score on the sheet is not yet a fact until an official confirms
    // it, and the same gate the statistics engine applies must apply here or
    // the profile and the engine will disagree.
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          resultState: MatchResultState.awaitingApproval,
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.matches, 0);
  });

  test('a verified result does count', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          resultState: MatchResultState.finalized,
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.matches, 1);
  });

  test('a match this player did not appear in is excluded', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          includeMe: false,
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.matches, 0);
  });

  test('filtering by sport keeps other sports out', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          myTally: const {'runs': 74},
        ),
        matchWhere(
          id: 'f2',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
          sportId: 'badminton',
          myTally: const {'points': 21},
        ),
      ],
      uid: me,
      sportId: 'cricket',
    );

    expect(stats[StatScope.all]!.matches, 1);
    expect(stats[StatScope.all]!.tally['runs'], 74);
    // A badminton point must never land in a cricket total.
    expect(stats[StatScope.all]!.tally['points'], isNull);
  });

  test('a match with no recorded source still lands in a scope', () {
    // `resolvedSource` derives one, so years of matches predating the field
    // are not silently missing from every scope.
    final fixture = Fixture(
      id: 'legacy',
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'side_a',
      entrantBId: 'side_b',
      entrantAName: 'Warriors',
      entrantBName: 'Titans',
      status: FixtureStatus.completed,
      sportId: 'cricket',
      winnerEntrantId: 'side_a',
      lineupA: const [MatchPlayer(id: me, name: 'Rahul', uid: me)],
      lineupB: const [MatchPlayer(id: 'uid_c', name: 'C', uid: 'uid_c')],
      scoreState: PlayerTally.addAll({}, me, const {'runs': 30}),
    );

    final stats = ScopedStats.forPlayer(fixtures: [fixture], uid: me);

    expect(stats[StatScope.all]!.matches, 1);
    // No tournamentId, so it resolves to a standalone match.
    expect(stats[StatScope.singleMatch]!.matches, 1);
    expect(stats[StatScope.tournament]!.matches, 0);
  });

  test('win rate excludes draws from the denominator', () {
    final stats = ScopedStats.forPlayer(
      fixtures: [
        matchWhere(
          id: 'f1',
          source: MatchSource.tournament,
          winnerEntrantId: 'side_a',
        ),
        Fixture(
          id: 'f2',
          orgId: 'org1',
          compId: 'comp1',
          entrantAId: 'side_a',
          entrantBId: 'side_b',
          entrantAName: 'Warriors',
          entrantBName: 'Titans',
          status: FixtureStatus.completed,
          sportId: 'cricket',
          sourceType: MatchSource.tournament,
          isDraw: true,
          lineupA: const [MatchPlayer(id: me, name: 'Rahul', uid: me)],
          lineupB: const [MatchPlayer(id: 'uid_c', name: 'C', uid: 'uid_c')],
        ),
      ],
      uid: me,
    );

    expect(stats[StatScope.all]!.matches, 2);
    expect(stats[StatScope.all]!.drawn, 1);
    // One win, no losses — 100%, not 50%.
    expect(stats[StatScope.all]!.winRate, 1.0);
  });

  test('a player with no matches has a null win rate, not zero', () {
    final stats = ScopedStats.forPlayer(fixtures: const [], uid: me);
    // Zero would read as "never wins", which is a different claim from
    // "has not played".
    expect(stats[StatScope.all]!.winRate, isNull);
    expect(stats[StatScope.all]!.isEmpty, isTrue);
  });
}
