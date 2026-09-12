/**
 * Run: `node --test functions/rating_eligibility.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import {
  RATED_SOURCE_TYPES,
  competitionRatingWithheldReason,
  isRated,
  ratingWithheldReason,
  sidesAreDistinct,
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

// ---------------------------------------------------------------------------
// The competition-level guard, and side distinctness.
//
// `ratingWithheldReason` above asks what KIND of match this is. It got the
// right answer for the wrong club: anybody may found an organization, so two
// accounts in a competition stamped `tournament` passed every check and the
// rating that came out travelled onto ranking boards and scout searches like a
// district championship's.
// ---------------------------------------------------------------------------

test('a real field is rated', () => {
  assert.equal(competitionRatingWithheldReason({ entrantCount: 16 }), null);
  assert.equal(competitionRatingWithheldReason({ entrantCount: 4 }), null);
});

test('a two-account competition is not rated', () => {
  // The forgery: found a club, enter yourself and one other account, score it.
  assert.equal(competitionRatingWithheldReason({ entrantCount: 2 }), 'field_of_2');
  assert.equal(competitionRatingWithheldReason({ entrantCount: 3 }), 'field_of_3');
});

test('a competition with no entrant count is withheld, not waved through', () => {
  // The same argument as an unstamped `sourceType`: the honest answer to
  // unknown provenance is not to rate it.
  assert.equal(
    competitionRatingWithheldReason({}),
    'entrant_count_missing',
  );
  assert.equal(competitionRatingWithheldReason(null), 'no_competition');
});

test('two different squads are distinct', () => {
  assert.equal(sidesAreDistinct(['a1', 'a2'], ['b1', 'b2']), true);
});

test('the same account on both sheets is not a contest', () => {
  assert.equal(sidesAreDistinct(['x'], ['x']), false);
  assert.equal(sidesAreDistinct(['a1', 'x'], ['b1', 'x']), false);
});

test('a shared custodian collapses two profiles into one person', () => {
  // A guardian farming a rating off a child's profile they manage. Both uids
  // are real, distinct accounts; only the custody link gives it away.
  assert.equal(
    sidesAreDistinct(['guardian'], ['child'], { child: 'guardian' }),
    false,
  );
  // Two children of the SAME guardian, likewise.
  assert.equal(
    sidesAreDistinct(['kidA'], ['kidB'], { kidA: 'g', kidB: 'g' }),
    false,
  );
  // Two children of DIFFERENT guardians are two different people.
  assert.equal(
    sidesAreDistinct(['kidA'], ['kidB'], { kidA: 'g1', kidB: 'g2' }),
    true,
  );
});

test('an empty side is never distinct', () => {
  assert.equal(sidesAreDistinct([], ['b1']), false);
  assert.equal(sidesAreDistinct(['a1'], []), false);
});
