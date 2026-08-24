/**
 * Guardian-managed child profiles, the parts of `family.js` that don't
 * require a live Admin SDK connection — the decision logic, not the I/O
 * around it. See `resolveClaim`/`validateChildInput`'s own doc comments for
 * why each is factored out this way.
 *
 * Run: `node --test functions/family.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import { generatePlayerCode, resolveClaim, validateChildInput } from './family.js';

describe('resolveClaim', () => {
  const now = new Date('2026-01-01T00:00:00Z');
  const validCode = {
    childUid: 'uid_child',
    usedAt: null,
    expiresAt: new Date('2026-01-01T00:20:00Z'),
  };

  test('a code that has not been used or expired resolves to its child', () => {
    assert.equal(resolveClaim(validCode, now), 'uid_child');
  });

  test('no such document is not a valid claim', () => {
    assert.equal(resolveClaim(null, now), null);
  });

  test('an already-used code cannot be redeemed twice', () => {
    assert.equal(
      resolveClaim({ ...validCode, usedAt: new Date('2026-01-01T00:05:00Z') }, now),
      null,
    );
  });

  test('an expired code is refused even though it was never used', () => {
    assert.equal(
      resolveClaim({ ...validCode, expiresAt: new Date('2025-12-31T23:59:59Z') }, now),
      null,
    );
  });

  test('a code expiring at exactly `now` has already expired', () => {
    // Strict inequality in resolveClaim — the same instant does not count as
    // still valid, closing the boundary rather than leaving it ambiguous.
    assert.equal(resolveClaim({ ...validCode, expiresAt: now }, now), null);
  });

  test('accepts a Firestore-Timestamp-shaped expiresAt via toDate()', () => {
    const timestampLike = { toDate: () => new Date('2026-01-01T00:20:00Z') };
    assert.equal(
      resolveClaim({ ...validCode, expiresAt: timestampLike }, now),
      'uid_child',
    );
  });

  test('a document with no childUid is not a valid claim, even if fresh', () => {
    assert.equal(resolveClaim({ ...validCode, childUid: undefined }, now), null);
  });
});

describe('validateChildInput', () => {
  const now = new Date('2026-01-01T00:00:00Z');
  const valid = {
    displayName: '  Asha Reddy  ',
    dateOfBirth: '2018-06-15T00:00:00Z',
    gender: 'female',
  };

  test('a well-formed child under 18 passes, and the name is trimmed', () => {
    const result = validateChildInput(valid, now);
    assert.equal(result.error, undefined);
    assert.equal(result.displayName, 'Asha Reddy');
    assert.equal(result.gender, 'female');
  });

  test('an empty or whitespace-only name is rejected', () => {
    assert.equal(
      validateChildInput({ ...valid, displayName: '   ' }, now).error[0],
      'invalid-argument',
    );
  });

  test('a missing or unparseable date of birth is rejected', () => {
    assert.equal(
      validateChildInput({ ...valid, dateOfBirth: undefined }, now).error[0],
      'invalid-argument',
    );
    assert.equal(
      validateChildInput({ ...valid, dateOfBirth: 'not a date' }, now).error[0],
      'invalid-argument',
    );
  });

  test('a date of birth in the future is rejected', () => {
    assert.equal(
      validateChildInput({ ...valid, dateOfBirth: '2027-01-01T00:00:00Z' }, now)
        .error[0],
      'invalid-argument',
    );
  });

  test('an unrecognised gender wire value is rejected', () => {
    assert.equal(
      validateChildInput({ ...valid, gender: 'nonbinary' }, now).error[0],
      'invalid-argument',
    );
  });

  test('an adult is refused — a managed profile is for a child only', () => {
    const result = validateChildInput(
      { ...valid, dateOfBirth: '2000-01-01T00:00:00Z' },
      now,
    );
    assert.equal(result.error[0], 'failed-precondition');
  });
});

describe('generatePlayerCode', () => {
  test('always PSOS- followed by 5 characters from the safe alphabet', () => {
    for (let i = 0; i < 200; i++) {
      const code = generatePlayerCode();
      // Mirrors CODE_ALPHABET exactly (and PlayerCode.dart's) — no I, L, O
      // or U, spelled out rather than as ranges so this can't quietly drift
      // from that alphabet by an off-by-one in a range boundary.
      assert.match(code, /^PSOS-[0-9ABCDEFGHJKMNPQRSTVWXYZ]{5}$/);
    }
  });
});
