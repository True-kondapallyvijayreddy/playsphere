/**
 * Run: `node --test functions/rating_eligibility.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import {
  RATED_SOURCE_TYPES,
  isRated,
  ratingWithheldReason,
} from './rating_eligibility.js';

/** A finished fixture from wherever `sourceType` says it came from. */
const fixture = (sourceType, overrides = {}) => ({
  sourceType,
  status: 'completed',
  resultType: 'normal',
  entrantAUid: 'uid_player_a',
  entrantBUid: 'uid_player_b',
  ...overrides,
});

describe('what carries a rating', () => {
  test('a season, a tournament and a league table are rated', () => {
    assert.equal(ratingWithheldReason(fixture('season')), null);
    assert.equal(ratingWithheldReason(fixture('tournament')), null);
    assert.equal(ratingWithheldReason(fixture('league')), null);
  });

  test('a challenge is never rated, however it ended', () => {
    // The rule this file exists for: challenges were rated until now.
    assert.equal(ratingWithheldReason(fixture('challenge')), 'challenge');
    assert.equal(
      ratingWithheldReason(fixture('challenge', { resultType: 'retired' })),
      'challenge',
    );
  });

  test('a single match is never rated', () => {
    assert.equal(ratingWithheldReason(fixture('single_match')), 'single_match');
  });

  test('a club event is not rated either', () => {
    assert.equal(ratingWithheldReason(fixture('club_event')), 'club_event');
  });

  test('the rated set is exactly season, tournament and league', () => {
    // Pinned, so adding a MatchSource value cannot quietly start rating it.
    assert.deepEqual(
      [...RATED_SOURCE_TYPES].sort(),
      ['league', 'season', 'tournament'],
    );
  });
});

describe('result types', () => {
  test('a retirement is rated — somebody played until they could not', () => {
    assert.equal(ratingWithheldReason(fixture('season', { resultType: 'retired' })), null);
  });

  test('a ruling is not a performance', () => {
    for (const ruled of ['walkover', 'abandoned', 'disqualified']) {
      assert.equal(
        ratingWithheldReason(fixture('tournament', { resultType: ruled })),
        ruled,
      );
    }
  });

  test('a missing resultType reads as normal', () => {
    const noType = fixture('season');
    delete noType.resultType;
    assert.equal(ratingWithheldReason(noType), null);
  });
});

describe('fixtures with no provenance', () => {
  test('an unstamped fixture is not rated', () => {
    const legacy = fixture('season');
    delete legacy.sourceType;
    assert.equal(ratingWithheldReason(legacy), 'unstamped');
    assert.equal(ratingWithheldReason(fixture('')), 'unstamped');
    assert.equal(ratingWithheldReason(fixture(null)), 'unstamped');
  });

  test('a missing fixture is withheld rather than thrown over', () => {
    assert.equal(ratingWithheldReason(null), 'missing');
    assert.equal(ratingWithheldReason(undefined), 'missing');
  });
});

describe('isRated', () => {
  test('is the positive form of the same question', () => {
    assert.equal(isRated(fixture('tournament')), true);
    assert.equal(isRated(fixture('challenge')), false);
  });
});
