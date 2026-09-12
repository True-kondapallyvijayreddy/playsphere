/**
 * The pure half of settlement.js — what a credit moves, and what it writes
 * down so the reversal can be exact. The transactional half needs an emulator
 * and is covered by the rules suite's fixtures instead.
 *
 * Run: `node --test functions/settlement.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import { FieldValue } from 'firebase-admin/firestore';

import { careerMovement, settlementRecord } from './settlement.js';

const contribution = (overrides = {}) => ({
  uid: 'uid_player',
  sportId: 'cricket',
  outcome: 'won',
  tally: { runs: 45, wickets: 2 },
  playedAt: new Date('2026-01-01'),
  ...overrides,
});

describe('careerMovement', () => {
  test('credits an appearance and the outcome it was', () => {
    const forward = careerMovement(contribution(), 1);
    assert.deepEqual(forward.matchesPlayed, FieldValue.increment(1));
    assert.deepEqual(forward.wins, FieldValue.increment(1));
    assert.deepEqual(forward.draws, FieldValue.increment(0));
    assert.deepEqual(forward.losses, FieldValue.increment(0));
  });

  test('reverses exactly what it credited', () => {
    // One function for both directions, so the two cannot drift apart the way
    // two hand-written blocks did.
    const back = careerMovement(contribution(), -1);
    assert.deepEqual(back.matchesPlayed, FieldValue.increment(-1));
    assert.deepEqual(back.wins, FieldValue.increment(-1));
    assert.deepEqual(back.tally.runs, FieldValue.increment(-45));
    assert.deepEqual(back.tally.wickets, FieldValue.increment(-2));
  });

  test('moves the outcome counter that matches, and only that one', () => {
    const drawn = careerMovement(contribution({ outcome: 'drawn' }), 1);
    assert.deepEqual(drawn.draws, FieldValue.increment(1));
    assert.deepEqual(drawn.wins, FieldValue.increment(0));
    assert.deepEqual(drawn.losses, FieldValue.increment(0));

    const lost = careerMovement(contribution({ outcome: 'lost' }), 1);
    assert.deepEqual(lost.losses, FieldValue.increment(1));
    assert.deepEqual(lost.wins, FieldValue.increment(0));
  });

  test('carries the sport tally forward', () => {
    const forward = careerMovement(contribution(), 1);
    assert.deepEqual(forward.tally.runs, FieldValue.increment(45));
    assert.deepEqual(forward.tally.wickets, FieldValue.increment(2));
  });

  test('omits the tally entirely when there is nothing in it', () => {
    // A nested empty map under merge would still write a `tally` key, which is
    // how a player with no recorded contribution ends up with an empty object
    // where a screen expects numbers.
    assert.equal('tally' in careerMovement(contribution({ tally: {} }), 1), false);
    assert.equal('tally' in careerMovement(contribution({ tally: undefined }), 1), false);
  });

  test('drops zero entries rather than writing no-op increments', () => {
    const zeroes = careerMovement(contribution({ tally: { runs: 0, wickets: 3 } }), 1);
    assert.equal('runs' in zeroes.tally, false);
    assert.deepEqual(zeroes.tally.wickets, FieldValue.increment(3));
  });
});

describe('settlementRecord', () => {
  test('records what a reversal needs, and nothing it does not', () => {
    const [row] = settlementRecord([contribution()]);
    assert.deepEqual(row, {
      uid: 'uid_player',
      sportId: 'cricket',
      outcome: 'won',
      tally: { runs: 45, wickets: 2 },
    });
    // `playedAt` is a fact about the match, not about what was credited.
    assert.equal('playedAt' in row, false);
  });

  test('defaults a missing tally to an empty map', () => {
    const [row] = settlementRecord([contribution({ tally: undefined })]);
    assert.deepEqual(row.tally, {});
  });

  test('keeps one row per contribution, in order', () => {
    const record = settlementRecord([
      contribution({ uid: 'uid_a' }),
      contribution({ uid: 'uid_b', outcome: 'lost' }),
    ]);
    assert.equal(record.length, 2);
    assert.equal(record[0].uid, 'uid_a');
    assert.equal(record[1].outcome, 'lost');
  });

  test('an empty settlement records nothing', () => {
    assert.deepEqual(settlementRecord([]), []);
  });
});
