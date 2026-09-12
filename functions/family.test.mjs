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

import {
  MAX_MANAGED_CHILDREN,
  childIsClaimable,
  generatePlayerCode,
  guardianRefusalReason,
  normalizeClaimCode,
  resolveClaim,
  validateChildInput,
} from './family.js';

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

describe('normalizeClaimCode', () => {
  test('forgives case, dashes and spaces', () => {
    assert.equal(normalizeClaimCode(' k7m2-q4xp-z9ab '), 'K7M2Q4XPZ9AB');
    assert.equal(normalizeClaimCode('K7M2 Q4XP Z9AB'), 'K7M2Q4XPZ9AB');
  });

  test('reads O as zero and I or L as one, exactly as ClaimCode.normalize does', () => {
    assert.equal(normalizeClaimCode('O0I1-L0O1-ABCD'), '00111001ABCD');
  });

  test('refuses the old six-digit codes and any other length', () => {
    // Six digits is the whole vulnerability: 900,000 guesses against a
    // function reachable signed out. None may reach a Firestore read.
    assert.equal(normalizeClaimCode('482913'), null);
    assert.equal(normalizeClaimCode('K7M2Q4XPZ9A'), null);
    assert.equal(normalizeClaimCode('K7M2Q4XPZ9ABC'), null);
  });

  test('refuses U, which the alphabet leaves out', () => {
    assert.equal(normalizeClaimCode('UUUU-UUUU-UUUU'), null);
  });

  test('handles missing and non-string input without throwing', () => {
    assert.equal(normalizeClaimCode(undefined), null);
    assert.equal(normalizeClaimCode(null), null);
    // `String({})` is "[object Object]", which strips to twelve valid
    // characters — so the type is checked before anything is coerced.
    assert.equal(normalizeClaimCode({}), null);
    // A callable payload can carry a number; twelve digits is a valid code.
    assert.equal(normalizeClaimCode(123456789012), '123456789012');
  });
});

describe('childIsClaimable', () => {
  const child = { custodianUid: 'uid_guardian', claimedAt: null };

  test('an unclaimed child in the minting guardian\'s custody is claimable', () => {
    assert.equal(childIsClaimable(child, 'uid_guardian'), true);
  });

  test('a child who has already claimed is not, whatever the code says', () => {
    // The leftover-code case: a second, unused code from before the claim
    // must not hand the now-claimed account to whoever holds it.
    assert.equal(
      childIsClaimable({ ...child, claimedAt: new Date('2026-01-01') }, 'uid_guardian'),
      false,
    );
  });

  test('a code minted by somebody who is not the custodian is not', () => {
    assert.equal(childIsClaimable(child, 'uid_someone_else'), false);
    assert.equal(childIsClaimable(child, undefined), false);
  });

  test('a missing child document is not', () => {
    assert.equal(childIsClaimable(null, 'uid_guardian'), false);
  });

  test('an ordinary account with no custodian is not', () => {
    assert.equal(
      childIsClaimable({ custodianUid: null, claimedAt: null }, null),
      false,
    );
  });
});

describe('guardianRefusalReason', () => {
  const now = new Date('2026-01-01T00:00:00Z');
  const adult = {
    dateOfBirth: new Date('1990-01-01'),
    managedChildUids: [],
  };

  test('an adult with room may add a child', () => {
    assert.equal(guardianRefusalReason(adult, now), null);
  });

  test('an account with no profile document yet is refused', () => {
    const [code] = guardianRefusalReason(null, now);
    assert.equal(code, 'failed-precondition');
  });

  test('a minor cannot create or manage a child profile', () => {
    const child = { ...adult, dateOfBirth: new Date('2012-01-01') };
    const [code, message] = guardianRefusalReason(child, now);
    assert.equal(code, 'failed-precondition');
    assert.match(message, /adult/i);
  });

  test('the age boundary is eighteen', () => {
    const justEighteen = { ...adult, dateOfBirth: new Date('2007-12-30') };
    assert.equal(guardianRefusalReason(justEighteen, now), null);

    const nearlyEighteen = { ...adult, dateOfBirth: new Date('2008-06-01') };
    assert.equal(guardianRefusalReason(nearlyEighteen, now)[0], 'failed-precondition');
  });

  test('reads a Firestore Timestamp as happily as a Date', () => {
    const stamped = {
      ...adult,
      dateOfBirth: { toDate: () => new Date('2012-01-01') },
    };
    assert.equal(guardianRefusalReason(stamped, now)[0], 'failed-precondition');
  });

  test('an account with no date of birth on file is treated as an adult', () => {
    // The field is required at signup and frozen afterwards, so the only
    // accounts missing it predate that rule. Refusing them would block a real
    // guardian over a gap they cannot fix.
    const legacy = { managedChildUids: [] };
    assert.equal(guardianRefusalReason(legacy, now), null);
  });

  test('the cap is a ceiling on profiles currently being managed', () => {
    const atCap = {
      ...adult,
      managedChildUids: Array.from({ length: MAX_MANAGED_CHILDREN }, (_, i) => `uid_${i}`),
    };
    const [code, message] = guardianRefusalReason(atCap, now);
    assert.equal(code, 'resource-exhausted');
    assert.match(message, new RegExp(String(MAX_MANAGED_CHILDREN)));

    const oneBelow = {
      ...adult,
      managedChildUids: Array.from({ length: MAX_MANAGED_CHILDREN - 1 }, (_, i) => `uid_${i}`),
    };
    assert.equal(guardianRefusalReason(oneBelow, now), null);
  });

  test('the cap is configurable, so the rule is testable without ten fixtures', () => {
    const two = { ...adult, managedChildUids: ['uid_a', 'uid_b'] };
    assert.equal(guardianRefusalReason(two, now, { cap: 2 })[0], 'resource-exhausted');
    assert.equal(guardianRefusalReason(two, now, { cap: 3 }), null);
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
