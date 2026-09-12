/**
 * Run: `node --test functions/account.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import { deletionRefusalReason, redactedProfile } from './account.js';

describe('deletionRefusalReason', () => {
  test('an ordinary account may be deleted', () => {
    assert.equal(deletionRefusalReason({ displayName: 'Ramesh' }), null);
    assert.equal(deletionRefusalReason({ managedChildUids: [] }), null);
  });

  test('a profile that was never written may be deleted', () => {
    // The login exists, the document does not. There is nothing to scrub, and
    // refusing would trap somebody in an account they cannot use.
    assert.equal(deletionRefusalReason(null), null);
  });

  test('an account still managing children is refused, and says how many', () => {
    const one = deletionRefusalReason({ managedChildUids: ['uid_child'] });
    assert.equal(one[0], 'failed-precondition');
    assert.match(one[1], /1 child profile\b/);
    assert.doesNotMatch(one[1], /profiles/);

    const several = deletionRefusalReason({
      managedChildUids: ['uid_a', 'uid_b', 'uid_c'],
    });
    assert.equal(several[0], 'failed-precondition');
    assert.match(several[1], /3 child profiles/);
  });

  test('the refusal names the step that frees the account', () => {
    const [, message] = deletionRefusalReason({ managedChildUids: ['uid_child'] });
    assert.match(message, /Get code/);
  });
});

describe('redactedProfile', () => {
  test('erases every direct identifier', () => {
    const scrubbed = redactedProfile();
    assert.equal(scrubbed.displayName, 'Deleted player');
    assert.equal(scrubbed.email, '');
    assert.equal(scrubbed.phone, null);
    assert.equal(scrubbed.photoUrl, null);
    assert.deepEqual(scrubbed.geo, {});
  });

  test('hides the profile and marks it deleted', () => {
    const scrubbed = redactedProfile();
    assert.equal(scrubbed.profileVisibility, 'private');
    assert.equal(scrubbed.profileComplete, false);
    assert.ok(scrubbed.deletedAt, 'deletedAt is stamped');
  });

  test('does not touch dateOfBirth, uid or the plan', () => {
    // Age is what every minor-safety gate in firestore.rules reads, and the
    // uid is what the match records point at. Blanking either would make the
    // records this deliberately keeps unreadable rather than anonymous.
    const scrubbed = redactedProfile();
    assert.equal('dateOfBirth' in scrubbed, false);
    assert.equal('uid' in scrubbed, false);
    assert.equal('plan' in scrubbed, false);
  });
});
