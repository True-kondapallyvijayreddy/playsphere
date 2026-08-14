/**
 * The JS half of the per-player tally contract. Mirrors the Dart tests for
 * `PlayerTally.of` — same shape, same `players` state key, so a change here
 * that drifts from the Dart reader would show up as a silent mismatch
 * nowhere else catches.
 *
 * Run: `node --test functions/career.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import { playerTally } from './career.js';

describe('playerTally', () => {
  test("reads one player's counters from the shared state shape", () => {
    const state = {
      players: {
        A1: { runsScored: 24, ballsFaced: 18 },
        B1: { wickets: 2 },
      },
    };
    assert.deepEqual(playerTally(state, 'A1'), { runsScored: 24, ballsFaced: 18 });
  });

  test('a player with no tally yet returns empty, not throws', () => {
    assert.deepEqual(playerTally({}, 'A1'), {});
    assert.deepEqual(playerTally({ players: {} }, 'A1'), {});
    assert.deepEqual(playerTally(undefined, 'A1'), {});
  });

  test('non-numeric values are dropped rather than passed through', () => {
    const state = { players: { A1: { runsScored: 4, note: 'not a number' } } };
    assert.deepEqual(playerTally(state, 'A1'), { runsScored: 4 });
  });
});

// ---------------------------------------------------------------------------
// Who a finished match credits.
//
// The rules these assert are the client's, in `Fixture.countsTowardsRecords`,
// `Fixture.outcomeForUid` and `ScopedStats.forPlayer`. A change on either side
// that drifts shows up as a career total that disagrees with the match list
// beside it, which is the exact bug this pair was written to close.
// ---------------------------------------------------------------------------

import {
  accumulateCareer,
  careerContributions,
  countsTowardsRecords,
  registeredSides,
} from './career.js';

/** A quick match: one registered player a side, plus whatever is passed. */
function fixture(overrides = {}) {
  return {
    status: 'completed',
    sportId: 'badminton',
    entrantAId: 'side_a',
    entrantBId: 'side_b',
    winnerEntrantId: 'side_a',
    lineupA: [{ id: 'uidA', uid: 'uidA' }],
    lineupB: [{ id: 'uidB', uid: 'uidB' }],
    scoreState: { players: { uidA: { pointsWon: 21 }, uidB: { pointsWon: 14 } } },
    ...overrides,
  };
}

describe('countsTowardsRecords', () => {
  test('a completed match counts, an unfinished one does not', () => {
    assert.equal(countsTowardsRecords(fixture()), true);
    assert.equal(countsTowardsRecords(fixture({ status: 'live' })), false);
    assert.equal(countsTowardsRecords(fixture({ status: 'scheduled' })), false);
  });

  test('a walkover counts — it is on the player\'s own match list', () => {
    assert.equal(countsTowardsRecords(fixture({ status: 'walkover' })), true);
  });

  test('a result still awaiting an official does not', () => {
    assert.equal(
      countsTowardsRecords(fixture({ resultState: 'awaitingApproval' })),
      false,
    );
  });
});

describe('registeredSides', () => {
  test('guests are on the scorecard and not in anybody\'s career', () => {
    const sides = registeredSides(
      fixture({ lineupB: [{ id: 'guest_1' }] }),
    );
    assert.deepEqual(sides.a, [{ uid: 'uidA', playerId: 'uidA' }]);
    assert.deepEqual(sides.b, []);
  });

  test('an individual entrant is their own team sheet', () => {
    const sides = registeredSides(
      fixture({ lineupA: [], lineupB: [], entrantAUid: 'x', entrantBUid: 'y' }),
    );
    assert.deepEqual(sides.a, [{ uid: 'x', playerId: 'x' }]);
    assert.deepEqual(sides.b, [{ uid: 'y', playerId: 'y' }]);
  });

  test('an entrant id is never mistaken for a uid', () => {
    // `side_a` and a registration document id both used to be read as uids
    // here, which wrote career records under user documents that do not exist.
    const sides = registeredSides(
      fixture({ lineupA: [], lineupB: [], entrantAId: 'side_a' }),
    );
    assert.deepEqual(sides.a, []);
  });
});

describe('careerContributions', () => {
  test('credits both sides, with the tally each player earned', () => {
    const [a, b] = careerContributions(fixture(), { orgId: 'org1' });
    assert.deepEqual(a, {
      uid: 'uidA',
      sportId: 'badminton',
      orgId: 'org1',
      side: 'a',
      outcome: 'won',
      tally: { pointsWon: 21 },
      playedAt: null,
    });
    assert.equal(b.outcome, 'lost');
    assert.deepEqual(b.tally, { pointsWon: 14 });
  });

  test('a match against a guest still counts for the registered player', () => {
    // The rating cannot be computed — Glicko needs a rated opponent — but the
    // twenty-one points are real and belong on the scorer's record.
    const out = careerContributions(
      fixture({ lineupB: [{ id: 'guest_1' }] }),
      { orgId: 'org1' },
    );
    assert.equal(out.length, 1);
    assert.equal(out[0].uid, 'uidA');
    assert.deepEqual(out[0].tally, { pointsWon: 21 });
  });

  test('a draw is drawn for both, not a loss for the second side', () => {
    const out = careerContributions(
      fixture({ isDraw: true, winnerEntrantId: null }),
    );
    assert.deepEqual(out.map((c) => c.outcome), ['drawn', 'drawn']);
  });

  test('an unfinished match credits nobody', () => {
    assert.deepEqual(careerContributions(fixture({ status: 'live' })), []);
  });
});

describe('accumulateCareer', () => {
  test('sums tallies per player per sport and counts the outcomes', () => {
    const records = accumulateCareer([
      ...careerContributions(fixture(), { orgId: 'org1' }),
      ...careerContributions(
        fixture({
          winnerEntrantId: 'side_b',
          scoreState: { players: { uidA: { pointsWon: 9 } } },
        }),
        { orgId: 'org2' },
      ),
    ]);

    const a = records.get('uidA::badminton');
    assert.equal(a.matchesPlayed, 2);
    assert.equal(a.wins, 1);
    assert.equal(a.losses, 1);
    assert.deepEqual(a.tally, { pointsWon: 30 });
    assert.deepEqual([...a.clubsPlayedFor].sort(), ['org1', 'org2']);
  });

  test('two sports never merge into one record', () => {
    const records = accumulateCareer([
      ...careerContributions(fixture(), { orgId: 'org1' }),
      ...careerContributions(
        fixture({
          sportId: 'cricket',
          scoreState: { players: { uidA: { runsScored: 52 } } },
        }),
        { orgId: 'org1' },
      ),
    ]);
    assert.equal(records.size, 4);
    assert.deepEqual(records.get('uidA::cricket').tally, { runsScored: 52 });
    assert.deepEqual(records.get('uidA::badminton').tally, { pointsWon: 21 });
  });
});
