/**
 * Tests for the personal-data inventory.
 *
 * The inventory's whole value is that it is complete, so these tests are less
 * about arithmetic than about keeping it honest: every row has to be
 * well-formed, every disposition has to carry a reason, and the two consumers
 * (erasure and export) have to be derived from the same list rather than
 * drifting apart.
 *
 * The last test is the one that matters most. It reads the source of every
 * other functions module, finds the collections they write, and fails when one
 * of them is missing from the inventory — which is the failure that put nine
 * collections outside `deleteMyAccount` in the first place. A new feature that
 * stores something about a person now fails CI until it says so here.
 */

import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  DISPOSITION,
  LOOKUP,
  SUBJECT_DATA,
  erasureRows,
  exportRows,
  subjectDataPlan,
} from './subject_data.js';

test('every row is well-formed', () => {
  const ids = new Set();
  for (const row of SUBJECT_DATA) {
    assert.ok(row.id, 'row needs an id');
    assert.ok(!ids.has(row.id), `duplicate row id "${row.id}"`);
    ids.add(row.id);

    assert.ok(row.collection, `${row.id} needs a collection`);
    assert.ok(
      Object.values(LOOKUP).includes(row.lookup),
      `${row.id} has an unknown lookup "${row.lookup}"`,
    );
    assert.ok(
      Object.values(DISPOSITION).includes(row.disposition),
      `${row.id} has an unknown disposition "${row.disposition}"`,
    );

    // A disposition without a stated reason is an assertion nobody can audit.
    assert.ok(
      typeof row.reason === 'string' && row.reason.length > 20,
      `${row.id} needs a reason worth reading`,
    );

    if (row.lookup === LOOKUP.field || row.lookup === LOOKUP.group) {
      assert.ok(row.field, `${row.id} needs the field its lookup queries`);
    }
    if (row.lookup === LOOKUP.sub) {
      assert.ok(row.subcollection, `${row.id} needs a subcollection name`);
    }
    if (row.disposition === DISPOSITION.scrub && row.id !== 'profile') {
      // The profile's replacement comes from account.js, which owns its shape;
      // every other scrub has to say what it writes.
      assert.ok(row.scrubTo, `${row.id} scrubs but names no replacement fields`);
    }
  }
});

test('erasure covers every row that is not deliberately kept', () => {
  const kept = SUBJECT_DATA.filter((r) => r.disposition === DISPOSITION.keep);
  assert.equal(erasureRows().length, SUBJECT_DATA.length - kept.length);
  // Retention is a decision, so it has to be an explicit one somebody made.
  assert.ok(kept.length > 0, 'expected some rows to be deliberately retained');
  for (const row of kept) {
    assert.match(row.reason, /^Kept:/, `${row.id} is kept without saying why`);
  }
});

test('export keys are unique', () => {
  const keys = exportRows().map((r) => r.export);
  assert.equal(new Set(keys).size, keys.length, 'two rows share an export key');
});

test('export never collides with the envelope keys', () => {
  // `_subject`, `_generatedAt` and `_problems` are the runner's own.
  for (const row of exportRows()) {
    assert.ok(
      !String(row.export).startsWith('_'),
      `${row.id} exports under a reserved key`,
    );
  }
});

test('the profile itself is scrubbed, never deleted', () => {
  // Every scorecard the player appears on points at this document.
  const profile = SUBJECT_DATA.find((r) => r.id === 'profile');
  assert.equal(profile.disposition, DISPOSITION.scrub);
});

test('the sensitive rows are erased rather than kept', () => {
  // These are the ones the review found outliving the account. A future edit
  // that quietly downgrades one of them to `keep` fails here.
  for (const id of [
    'checkIns',
    'groundVerification',
    'coachListing',
    'medicListing',
    'shopListing',
    'umpireProfile',
    'devices',
    'notifications',
    'memories',
  ]) {
    const row = SUBJECT_DATA.find((r) => r.id === id);
    assert.ok(row, `inventory lost the "${id}" row`);
    assert.equal(row.disposition, DISPOSITION.delete, `${id} must be deleted`);
  }
});

test('rows pointing at Storage declare the field that holds the path', () => {
  // A photo whose document is deleted and whose bytes are not is a photo that
  // outlived the account.
  const memories = SUBJECT_DATA.find((r) => r.id === 'memories');
  assert.equal(memories.storagePathField, 'storagePath');
});

test('subjectDataPlan resolves a concrete target for every row', () => {
  const plan = subjectDataPlan('u1');
  assert.equal(plan.length, SUBJECT_DATA.length);
  assert.ok(plan.every((r) => typeof r.target === 'string' && r.target.includes('u1')));
  assert.ok(plan.some((r) => r.target === 'coaches/u1'));
  assert.ok(plan.some((r) => r.target === 'users/u1/devices'));
  assert.ok(plan.some((r) => r.target.startsWith('group:checkIns.uid ==')));
});

test('subjectDataPlan refuses a missing uid', () => {
  assert.throws(() => subjectDataPlan(''), TypeError);
  assert.throws(() => subjectDataPlan(undefined), TypeError);
});

test('no functions module writes a uid-keyed collection the inventory omits', () => {
  // The structural guard. Anything a function writes into, keyed by a field
  // that names a person, has to appear above — otherwise it is data nobody's
  // deletion request reaches.
  //
  // Deliberately a literal allow-list of exemptions rather than a clever
  // heuristic: each entry is a collection that genuinely holds no personal
  // data, and writing it down is cheaper to review than a regex that decides
  // the same thing invisibly.
  const notPersonal = new Set([
    // Server-computed aggregates, keyed by sport/district/board, not by person.
    'leaderboards', 'sportStats', 'gov_aggregates', 'talentBoards',
    'clubStandings', 'rankingEntries', 'give', 'impactStats',
    // Club- and event-scoped records, not subject data.
    'orgs', 'competitions', 'fixtures', 'events', 'entrants', 'standings',
    'attempts', 'tournaments', 'venues', 'venuePlans', 'members', 'followers',
    'announcements', 'messages', 'subgroups', 'files', 'auditLogs',
    'clubThreads', 'ownerProposals', 'seasonInterest', 'squadEntries',
    'scoringRequests', 'disputes', 'cheers', 'groupEntries', 'teams',
    'joinRequests', 'challenges', 'tournamentInvites', 'inviteCodes',
    'lookingForPosts', 'sports', 'sportRules', 'products', 'clubProducts',
    'giveCollectionCenters', 'giveNeeds', 'platformStaff', 'adCampaigns',
    'sponsorshipListings', 'grounds', 'bookings', 'hourHolds',
    'groundMenuItems', 'auctions', 'auctionCodes', 'lots', 'bids', 'trades',
    'participants', 'arenaMatches', 'claimCodes', 'notificationDigest',
  ]);

  const inventoried = new Set(
    SUBJECT_DATA.flatMap((r) => [r.collection, r.subcollection].filter(Boolean)),
  );

  const files = readdirSync('.').filter(
    (f) => f.endsWith('.js') && !f.endsWith('.test.mjs'),
  );

  const missing = new Set();
  for (const file of files) {
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/\.collection(?:Group)?\(\s*'([a-zA-Z_]+)'/g)) {
      const name = m[1];
      if (inventoried.has(name) || notPersonal.has(name)) continue;
      missing.add(`${name} (${file})`);
    }
  }

  assert.deepEqual(
    [...missing].sort(),
    [],
    'collections written by a function but absent from the personal-data ' +
      'inventory. Add a row to subject_data.js, or add it to this test\'s ' +
      'notPersonal list with a reason.',
  );
});
