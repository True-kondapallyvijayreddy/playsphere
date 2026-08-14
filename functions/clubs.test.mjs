/**
 * The club ladder's arithmetic, without Firestore.
 *
 * The scan itself needs a database; the two decisions that actually determine
 * what a club's position means — which windows a result counts in, and how
 * ties break — are pure and are what these pin.
 *
 * Run: `node --test functions/clubs.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import {
  DRAW_POINTS,
  WIN_POINTS,
  rankRows,
  windowsFor,
} from './clubs.js';

const NOW = new Date('2026-08-11T12:00:00Z');
const daysAgo = (n) => new Date(NOW.getTime() - n * 86400000);

describe('windowsFor', () => {
  test('a result today counts in every window', () => {
    assert.deepEqual(windowsFor(daysAgo(0), NOW), ['all', 'd365', 'd90', 'd30']);
  });

  test('a result ages out of the narrow windows first', () => {
    assert.deepEqual(windowsFor(daysAgo(45), NOW), ['all', 'd365', 'd90']);
    assert.deepEqual(windowsFor(daysAgo(120), NOW), ['all', 'd365']);
    assert.deepEqual(windowsFor(daysAgo(500), NOW), ['all']);
  });

  test('the boundary day is still inside the window', () => {
    assert.ok(windowsFor(daysAgo(30), NOW).includes('d30'));
    assert.ok(!windowsFor(daysAgo(31), NOW).includes('d30'));
  });

  test('an undated result counts only all-time, never nothing', () => {
    // A fixture with no date is a real thing in this database — it predates
    // `completedAt`. Dropping it entirely would quietly under-report a club's
    // record; filing it under "all time" is the honest placement.
    assert.deepEqual(windowsFor(null, NOW), ['all']);
    assert.deepEqual(windowsFor(undefined, NOW), ['all']);
    assert.deepEqual(windowsFor(new Date('nonsense'), NOW), ['all']);
  });

  test('a future-dated result is treated as current, not expired', () => {
    // A clock problem is not a reason to erase a club's win from every
    // bounded window.
    const tomorrow = new Date(NOW.getTime() + 86400000);
    assert.deepEqual(windowsFor(tomorrow, NOW), ['all', 'd365', 'd90', 'd30']);
  });
});

describe('rankRows', () => {
  const club = (name, { points = 0, won = 0 } = {}) => ({
    clubId: name.toLowerCase(),
    name,
    all: { played: 0, won, drawn: 0, lost: 0, points },
  });

  test('highest points first', () => {
    const ranked = rankRows([
      club('Titans', { points: 6, won: 2 }),
      club('Warriors', { points: 12, won: 4 }),
      club('Strikers', { points: 9, won: 3 }),
    ]);
    assert.deepEqual(ranked.map((r) => r.name), ['Warriors', 'Strikers', 'Titans']);
  });

  test('equal points break on wins, then on name', () => {
    // Stability matters more than the rule chosen: a ladder that reshuffles
    // between two reads of the same data is one nobody trusts.
    const ranked = rankRows([
      club('Zephyr', { points: 6, won: 2 }),
      club('Alpha', { points: 6, won: 2 }),
      club('Mid', { points: 6, won: 3 }),
    ]);
    assert.deepEqual(ranked.map((r) => r.name), ['Mid', 'Alpha', 'Zephyr']);
  });

  test('does not mutate the list it was given', () => {
    const rows = [club('B', { points: 1 }), club('A', { points: 9 })];
    rankRows(rows);
    assert.equal(rows[0].name, 'B');
  });
});

describe('points convention', () => {
  test('three for a win, one for a draw', () => {
    // Pinned because the ladder is meaningless if this drifts from what the
    // screen tells people it is counting.
    assert.equal(WIN_POINTS, 3);
    assert.equal(DRAW_POINTS, 1);
  });
});
