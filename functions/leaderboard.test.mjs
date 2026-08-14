/**
 * The pure half of the leaderboard builder — everything that does not touch
 * Firestore.
 *
 * Run: `node --test functions/leaderboard.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import { buildLeaderboards } from './leaderboard.js';
import { HEADLINE_STATS, headlineStatsFor } from './headline_stats.js';

function player(uid, sportId, tally, extra = {}) {
  return { uid, displayName: uid, photoUrl: null, sportId, tally, ...extra };
}

describe('headlineStatsFor', () => {
  test('strips a chess-style time-control qualifier', () => {
    assert.deepEqual(headlineStatsFor('chess:blitz'), HEADLINE_STATS.chess);
  });

  test('an unlisted sport is not ranked', () => {
    assert.deepEqual(headlineStatsFor('tug_of_war'), []);
    assert.deepEqual(headlineStatsFor(undefined), []);
  });

  test('athletics is deliberately absent — its number is a best, not a count', () => {
    assert.equal(HEADLINE_STATS.athletics, undefined);
  });
});

describe('buildLeaderboards', () => {
  test('ranks largest value first, within one sport and stat', () => {
    const boards = buildLeaderboards([
      player('low', 'cricket', { runsScored: 40, wickets: 0 }),
      player('high', 'cricket', { runsScored: 120, wickets: 1 }),
      player('mid', 'cricket', { runsScored: 75, wickets: 3 }),
    ]);

    const runs = boards.get('cricket:runsScored');
    assert.deepEqual(
      runs.map((r) => [r.uid, r.rank]),
      [['high', 1], ['mid', 2], ['low', 3]],
    );
    assert.equal(runs[0].value, 120);

    // wickets is cricket's second headline stat, ranked independently.
    const wickets = boards.get('cricket:wickets');
    assert.deepEqual(wickets.map((r) => r.uid), ['mid', 'high']);
  });

  test('a player absent from a key gets no row, not a zero row', () => {
    const boards = buildLeaderboards([
      player('bowler', 'cricket', { wickets: 4 }), // never batted
    ]);
    assert.equal(boards.has('cricket:runsScored'), false);
    assert.deepEqual(boards.get('cricket:wickets').map((r) => r.uid), ['bowler']);
  });

  test('zero and negative values are excluded, not ranked at the bottom', () => {
    const boards = buildLeaderboards([
      player('zero', 'football', { goals: 0 }),
      player('scorer', 'football', { goals: 2 }),
    ]);
    assert.deepEqual(boards.get('football:goals').map((r) => r.uid), ['scorer']);
  });

  test('a sport with no headline stats produces no board', () => {
    const boards = buildLeaderboards([
      player('athlete', 'athletics', { best: 9.58 }),
    ]);
    assert.equal(boards.size, 0);
  });

  test('caps a board at the top 50 and still ranks 1..50', () => {
    const candidates = Array.from({ length: 60 }, (_, i) =>
      player(`p${i}`, 'kabaddi', { raidPoints: i, tacklePoints: 0 }),
    );
    const board = buildLeaderboards(candidates).get('kabaddi:raidPoints');
    assert.equal(board.length, 50);
    assert.equal(board[0].uid, 'p59'); // highest raidPoints (59) ranked first
    assert.equal(board[0].rank, 1);
    assert.equal(board[49].rank, 50);
  });

  test('two headline stats for one sport (kabaddi) produce two boards', () => {
    const boards = buildLeaderboards([
      player('raider', 'kabaddi', { raidPoints: 30, tacklePoints: 2 }),
      player('defender', 'kabaddi', { raidPoints: 2, tacklePoints: 15 }),
    ]);
    assert.deepEqual(boards.get('kabaddi:raidPoints').map((r) => r.uid), [
      'raider',
      'defender',
    ]);
    assert.deepEqual(boards.get('kabaddi:tacklePoints').map((r) => r.uid), [
      'defender',
      'raider',
    ]);
  });
});
