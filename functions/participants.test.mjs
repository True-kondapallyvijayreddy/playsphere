/**
 * The participation contract, on the JS side of the fence.
 *
 * `soloUidOf` mirrors `Entrant.soloUid` and `participantsOf` mirrors
 * `Fixture.playerUids` in `lib/core/models/`. A drift between the two is
 * exactly the bug this module exists to close — the backfill writing one
 * answer while the app derives another would put the database back into the
 * disagreement it was written to repair — so these assert the rules the Dart
 * tests assert, in the same shapes.
 *
 * Run: `node --test functions/participants.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import { participantsOf, soloUidOf } from './participants.js';

describe('soloUidOf', () => {
  test('an individual entrant is their own account', () => {
    assert.equal(
      soloUidOf({ entrantType: 'individual', uid: 'uid_alice' }),
      'uid_alice',
    );
  });

  test('a team is never one person, however small its roster', () => {
    assert.equal(
      soloUidOf({
        entrantType: 'team',
        uid: 'uid_captain',
        memberUids: ['uid_captain', 'uid_partner'],
      }),
      null,
    );
  });

  test('an unrecognised type is not proof of an individual', () => {
    // `EntrantType.fromWire` falls back to `individual`, so the type alone
    // cannot be trusted — the uid has to be there too.
    assert.equal(soloUidOf({ entrantType: 'squad', uid: 'uid_alice' }), null);
    assert.equal(soloUidOf({ entrantType: 'individual', uid: '' }), null);
    assert.equal(soloUidOf({ entrantType: 'individual' }), null);
    assert.equal(soloUidOf(null), null);
  });
});

describe('participantsOf', () => {
  const noLineups = { lineupA: [], lineupB: [] };

  test('an individual draw is carried entirely by the entrant uids', () => {
    // The case the whole fix exists for: no line-up will ever be filled, so
    // without the entrant uids this fixture names nobody at all.
    assert.deepEqual(
      participantsOf(noLineups, 'uid_alice', 'uid_bhavya').sort(),
      ['uid_alice', 'uid_bhavya'],
    );
  });

  test('a team match still reads from the line-ups alone', () => {
    const fixture = {
      lineupA: [{ uid: 'uid_1' }, { uid: 'uid_2' }],
      lineupB: [{ uid: 'uid_3' }],
    };
    assert.deepEqual(
      participantsOf(fixture, null, null).sort(),
      ['uid_1', 'uid_2', 'uid_3'],
    );
  });

  test('a mixed fixture keeps both halves', () => {
    // A club team against a lone qualifier is a real shape, and taking only
    // one source would silently drop half the match.
    const fixture = { lineupA: [{ uid: 'uid_1' }, { uid: 'uid_2' }], lineupB: [] };
    assert.deepEqual(
      participantsOf(fixture, null, 'uid_solo').sort(),
      ['uid_1', 'uid_2', 'uid_solo'],
    );
  });

  test('guests contribute nothing — there is no profile to credit', () => {
    const fixture = {
      lineupA: [{ uid: 'uid_1' }, { id: 'guest_7' }, { uid: null }],
      lineupB: [{ uid: '' }],
    };
    assert.deepEqual(participantsOf(fixture, null, null), ['uid_1']);
  });

  test('a player named twice is counted once', () => {
    const fixture = { lineupA: [{ uid: 'uid_1' }], lineupB: [] };
    assert.deepEqual(participantsOf(fixture, 'uid_1', null), ['uid_1']);
  });

  test('missing line-ups are absent, not malformed', () => {
    assert.deepEqual(participantsOf({}, 'uid_alice', null), ['uid_alice']);
    assert.deepEqual(participantsOf({ lineupA: null }, null, null), []);
  });
});
