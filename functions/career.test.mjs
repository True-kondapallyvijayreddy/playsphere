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
