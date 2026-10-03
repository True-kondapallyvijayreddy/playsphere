import { test } from 'node:test';
import assert from 'node:assert/strict';

import { addedMembers, sameRoster } from './team_roster.js';

test('addedMembers: only the people who were not there before', () => {
  assert.deepEqual(addedMembers(['a', 'b'], ['b', 'c', 'a', 'd']), ['c', 'd']);
  assert.deepEqual(addedMembers(undefined, ['a']), ['a']);
  assert.deepEqual(addedMembers(['a'], ['a']), []);
});

test('addedMembers: removals and junk are not additions', () => {
  assert.deepEqual(addedMembers(['a', 'b'], ['a']), []);
  assert.deepEqual(addedMembers([], ['a', null, 3]), ['a']);
});

test('sameRoster ignores order but not membership', () => {
  assert.equal(sameRoster(['a', 'b'], ['b', 'a']), true);
  assert.equal(sameRoster(['a', 'b'], ['a']), false);
  assert.equal(sameRoster(['a', 'b'], ['a', 'c']), false);
  assert.equal(sameRoster(undefined, []), true);
});

import { lineupUids } from './team_eligibility.js';

test('lineupUids: account holders only, once each — guests have no uid', () => {
  assert.deepEqual(
    lineupUids([{ id: 'a', uid: 'a' }, { id: 'g', name: 'Guest', uid: null }, { id: 'a', uid: 'a' }, null]),
    ['a'],
  );
  assert.deepEqual(lineupUids(undefined), []);
});
