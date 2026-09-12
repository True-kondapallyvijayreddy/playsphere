import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  participantMayBeRated,
  ratingWithheldForParticipant,
  relevantOrgIds,
  splitParticipantsByTrust,
} from './participant_trust.js';

test('an active member of the organising club may be rated', () => {
  assert.equal(ratingWithheldForParticipant({ memberStatus: 'active' }), null);
  assert.equal(participantMayBeRated({ memberStatus: 'active' }), true);
});

test('somebody who registered themselves may be rated without a membership', () => {
  // The open-to-non-members case: a district championship a player enters
  // directly, with no club in between.
  assert.equal(
    ratingWithheldForParticipant({ memberStatus: null, selfRegistered: true }),
    null,
  );
});

test('a squad player named on a team entry may be rated', () => {
  // A team's players have no registration of their own — the document id is
  // the team's — so without this an entire cricket XI would go unrated.
  assert.equal(
    ratingWithheldForParticipant({ memberStatus: null, namedInTeamEntry: true }),
    null,
  );
});

test('a uid with no relationship to the competition is withheld', () => {
  // The forged fixture: an organizer naming a stranger's account.
  assert.equal(
    ratingWithheldForParticipant({ memberStatus: null }),
    'no_relationship',
  );
});

test('a pending application is not a relationship', () => {
  // Anybody may self-apply to any public club, so a `pending` row proves only
  // that a write happened. Naming the status makes the log line diagnosable.
  assert.equal(
    ratingWithheldForParticipant({ memberStatus: 'pending' }),
    'member_pending',
  );
});

test('a removed member is withheld', () => {
  assert.equal(
    ratingWithheldForParticipant({ memberStatus: 'removed' }),
    'member_removed',
  );
});

test('an organizer-written registration is not self-registration', () => {
  // `preselected: true` is the organizer entering somebody directly, which is
  // exactly the write a forgery makes. It proves an organizer wrote it, not
  // that the person agreed.
  assert.equal(
    ratingWithheldForParticipant({ memberStatus: null, selfRegistered: false }),
    'no_relationship',
  );
});

test('missing facts withhold rather than allow', () => {
  // A read that failed must not read as permission.
  assert.equal(ratingWithheldForParticipant(undefined), 'unknown');
  assert.equal(ratingWithheldForParticipant(null), 'unknown');
});

test('splitParticipantsByTrust separates the two groups', () => {
  const facts = new Map([
    ['keeper', { memberStatus: 'active' }],
    ['opener', { memberStatus: null, namedInTeamEntry: true }],
    ['stranger', { memberStatus: null }],
  ]);
  const { rated, withheld } = splitParticipantsByTrust(
    ['keeper', 'opener', 'stranger'],
    facts,
  );
  assert.deepEqual(rated, ['keeper', 'opener']);
  assert.deepEqual(withheld, [{ uid: 'stranger', reason: 'no_relationship' }]);
});

test('splitParticipantsByTrust withholds a uid it has no facts for', () => {
  const { rated, withheld } = splitParticipantsByTrust(['ghost'], new Map());
  assert.deepEqual(rated, []);
  assert.deepEqual(withheld, [{ uid: 'ghost', reason: 'unknown' }]);
});

test('splitParticipantsByTrust accepts a plain object too', () => {
  const { rated } = splitParticipantsByTrust(['a'], { a: { memberStatus: 'active' } });
  assert.deepEqual(rated, ['a']);
});

test('relevantOrgIds covers the host alone for an ordinary fixture', () => {
  assert.deepEqual(relevantOrgIds({}, 'host'), ['host']);
  assert.deepEqual(relevantOrgIds(null, 'host'), ['host']);
});

test('relevantOrgIds covers both clubs in an inter-club fixture', () => {
  // A visiting side's players are members of the visitor, not the host.
  // Checking only the host would leave every school-v-school match unrated.
  assert.deepEqual(
    relevantOrgIds({ participantOrgIds: ['host', 'guest'] }, 'host').sort(),
    ['guest', 'host'],
  );
});

test('relevantOrgIds ignores junk in participantOrgIds', () => {
  assert.deepEqual(
    relevantOrgIds({ participantOrgIds: ['', null, 42, 'guest'] }, 'host').sort(),
    ['guest', 'host'],
  );
});
