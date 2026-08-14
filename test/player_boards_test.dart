import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/tournament/player_boards.dart';

/// Tournament and season player charts — §16/§17.
///
/// What is worth protecting is that the boards are discovered from what the
/// matches recorded rather than assumed, that unfinished and unverified
/// matches stay off them, and that the ordering is stable — a chart that
/// reshuffles between two reads of the same data is one nobody trusts.
void main() {
  Fixture match({
    required String id,
    required Map<String, Map<String, num>> tallies,
    FixtureStatus status = FixtureStatus.completed,
    MatchResultState resultState = MatchResultState.none,
  }) {
    var state = <String, dynamic>{};
    for (final entry in tallies.entries) {
      state = PlayerTally.addAll(state, entry.key, entry.value);
    }
    return Fixture(
      id: id,
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'a',
      entrantBId: 'b',
      entrantAName: 'Warriors',
      entrantBName: 'Titans',
      status: status,
      resultState: resultState,
      winnerEntrantId: 'a',
      lineupA: [
        for (final id in tallies.keys)
          MatchPlayer(id: id, name: id.toUpperCase(), uid: id),
      ],
      scoreState: state,
    );
  }

  test('builds one board per counter the matches recorded', () {
    final boards = PlayerBoards.from([
      match(id: 'f1', tallies: {
        'rahul': {'runs': 74, 'wickets': 2},
        'suresh': {'runs': 12, 'wickets': 3},
      }),
    ]);

    expect(boards.boardFor('runs'), isNotNull);
    expect(boards.boardFor('wickets'), isNotNull);
    // Nothing recorded goals, so there is no goals board — the counters are
    // discovered, not assumed.
    expect(boards.boardFor('goals'), isNull);
  });

  test('totals accumulate across matches and rank highest first', () {
    final boards = PlayerBoards.from([
      match(id: 'f1', tallies: {
        'rahul': {'runs': 74},
        'karthik': {'runs': 42},
      }),
      match(id: 'f2', tallies: {
        'rahul': {'runs': 30},
        'karthik': {'runs': 90},
      }),
    ]);

    final runs = boards.boardFor('runs')!;
    expect(runs.entries.first.displayName, 'KARTHIK');
    expect(runs.entries.first.value, 132);
    expect(runs.entries[1].value, 104);
    expect(runs.entries.first.matches, 2);
  });

  test('an unfinished match contributes nothing', () {
    final boards = PlayerBoards.from([
      match(
        id: 'f1',
        status: FixtureStatus.live,
        tallies: {
          'rahul': {'runs': 74},
        },
      ),
    ]);

    // A chart that moved while a match was being played, then moved again
    // when it was corrected, is one nobody can quote.
    expect(boards.isEmpty, isTrue);
  });

  test('a result awaiting verification contributes nothing', () {
    final boards = PlayerBoards.from([
      match(
        id: 'f1',
        resultState: MatchResultState.awaitingApproval,
        tallies: {
          'rahul': {'runs': 74},
        },
      ),
    ]);

    expect(boards.isEmpty, isTrue);
  });

  test('zero totals stay off a board', () {
    final boards = PlayerBoards.from([
      match(id: 'f1', tallies: {
        'rahul': {'runs': 74, 'wickets': 0},
        'suresh': {'runs': 0, 'wickets': 3},
      }),
    ]);

    // A batter who never bowled does not belong on the wickets chart.
    final wickets = boards.boardFor('wickets')!;
    expect(wickets.entries.length, 1);
    expect(wickets.entries.single.displayName, 'SURESH');

    final runs = boards.boardFor('runs')!;
    expect(runs.entries.length, 1);
    expect(runs.entries.single.displayName, 'RAHUL');
  });

  test('a tie is broken by fewer matches, then by name', () {
    final boards = PlayerBoards.from([
      match(id: 'f1', tallies: {
        'anil': {'runs': 50},
        'bala': {'runs': 25},
      }),
      match(id: 'f2', tallies: {
        'bala': {'runs': 25},
      }),
    ]);

    final runs = boards.boardFor('runs')!;
    // Both on 50; anil did it in one match.
    expect(runs.entries.first.displayName, 'ANIL');
    expect(runs.entries.first.matches, 1);
    expect(runs.entries[1].matches, 2);
  });

  test('the deepest board leads', () {
    final boards = PlayerBoards.from([
      match(id: 'f1', tallies: {
        'a': {'runs': 10, 'wickets': 1},
        'b': {'runs': 20},
        'c': {'runs': 30},
      }),
    ]);

    // Three players have runs, one has wickets — runs describes this sport
    // better and should be the first tab offered.
    expect(boards.boards.first.key, 'runs');
  });

  test('a guest with no account still ranks', () {
    final fixture = Fixture(
      id: 'f1',
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'a',
      entrantBId: 'b',
      entrantAName: 'Warriors',
      entrantBName: 'Titans',
      status: FixtureStatus.completed,
      winnerEntrantId: 'a',
      // No uid — somebody who turned up and played.
      lineupA: const [MatchPlayer(id: 'guest_1', name: 'Visitor')],
      scoreState: PlayerTally.addAll({}, 'guest_1', const {'runs': 88}),
    );

    final boards = PlayerBoards.from([fixture]);
    final runs = boards.boardFor('runs')!;
    expect(runs.entries.single.displayName, 'Visitor');
    expect(runs.entries.single.uid, isNull);
  });

  // An individual draw — badminton singles, chess, a tennis bracket — never
  // fills a line-up. Its competitors are named on the entrant document, and
  // the fixture carries them as `entrantAUid`/`entrantBUid`. Walking the two
  // sheets alone therefore found nobody and drew an empty chart for a draw
  // that had been played to a final.
  test('builds charts for an individual draw, which has no line-ups', () {
    var state = PlayerTally.addAll({}, 'uid_alice', const {'aces': 12});
    state = PlayerTally.addAll(state, 'uid_bhavya', const {'aces': 5});

    final fixture = Fixture(
      id: 'f1',
      orgId: 'org1',
      compId: 'comp1',
      // For an individual entrant the document id IS the uid, and the score
      // state is keyed under it — see `CompetitionRepository.closeEntries`.
      entrantAId: 'uid_alice',
      entrantBId: 'uid_bhavya',
      entrantAName: 'Alice',
      entrantBName: 'Bhavya',
      entrantAUid: 'uid_alice',
      entrantBUid: 'uid_bhavya',
      status: FixtureStatus.completed,
      winnerEntrantId: 'uid_alice',
      scoreState: state,
    );

    final aces = PlayerBoards.from([fixture]).boardFor('aces')!;
    expect(aces.entries.map((e) => e.displayName), ['Alice', 'Bhavya']);
    expect(aces.entries.first.value, 12);
    // The chart links back to a real profile, which is the whole point of
    // knowing the account rather than only the entrant.
    expect(aces.entries.first.uid, 'uid_alice');
  });

  test('a side with a line-up is not overridden by its entrant uid', () {
    // A mixed fixture: a club team on one side, a lone qualifier on the other.
    // The team sheet is the evidence for the team; the entrant uid must only
    // stand in where there is no sheet at all.
    var state = PlayerTally.addAll({}, 'uid_1', const {'runs': 40});
    state = PlayerTally.addAll(state, 'uid_solo', const {'runs': 61});

    final fixture = Fixture(
      id: 'f1',
      orgId: 'org1',
      compId: 'comp1',
      entrantAId: 'team_a',
      entrantBId: 'uid_solo',
      entrantAName: 'Warriors',
      entrantBName: 'Solo',
      entrantBUid: 'uid_solo',
      status: FixtureStatus.completed,
      winnerEntrantId: 'uid_solo',
      lineupA: const [MatchPlayer(id: 'uid_1', name: 'Rahul', uid: 'uid_1')],
      scoreState: state,
    );

    final runs = PlayerBoards.from([fixture]).boardFor('runs')!;
    expect(runs.entries.map((e) => e.displayName), ['Solo', 'Rahul']);
  });
}
