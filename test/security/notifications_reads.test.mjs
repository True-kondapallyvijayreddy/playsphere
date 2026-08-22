// The five reads behind the Notifications screen, as the rules see them.
//
// Every one of these failed at once on a founder's phone four seconds after
// they created their club, and the shape of that failure is the point: the
// server had not yet acknowledged the owner membership the client had already
// written locally, so `isActive()` was false and every org-scoped read was
// refused. The second group pins that mapping, so a rules change that widens
// or narrows it cannot pass unnoticed; the first pins the happy path a club
// owner must always have.
//
// The scoring-assignments query additionally needs a collection-group index
// on (scorerUids, status) that the emulator does not enforce and production
// does — see firestore.indexes.json.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, doc, getDocs, or, query,
  serverTimestamp, setDoc, where,
} from 'firebase/firestore';

let testEnv;
const OWNER = 'uid_owner';
const JOINER = 'uid_joiner';
const OTHER_ORG = 'org_other';
const ORG = 'org_mine';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-notifications',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
after(async () => { await testEnv?.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const membership = (uid, orgId, role, status = 'active') => ({
  uid, orgId, role, status, displayName: 'P', photoUrl: null,
  joinedAt: serverTimestamp(), invitedBy: null, approvedBy: null,
});
const organization = (ownerUid) => ({
  name: 'Club', nameLower: 'club', orgType: 'school', visibility: 'public',
  ownerUid, inviteCode: 'ABC234', parentOrgId: null, description: null,
  district: null, city: null, logoUrl: null, memberCount: 2,
  requiresApprovalToJoin: true, createdBy: ownerUid,
  createdAt: serverTimestamp(), deletedAt: null,
});

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => { await fn(ctx.firestore()); });
}

// The production shape: my club, me as owner, one person waiting to join,
// a handful of challenges between my club and another, and one invite.
async function seedWorld() {
  await seed(async (db) => {
    await setDoc(doc(db, 'orgs', ORG), organization(OWNER));
    await setDoc(doc(db, 'orgs', OTHER_ORG), organization('uid_stranger'));
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, ORG, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', JOINER), membership(JOINER, ORG, 'member', 'pending'));
    await setDoc(doc(db, 'orgs', OTHER_ORG, 'members', 'uid_stranger'),
      membership('uid_stranger', OTHER_ORG, 'owner'));
    for (let i = 0; i < 7; i++) {
      await setDoc(doc(db, 'challenges', `ch${i}`), {
        fromOrgId: i % 2 ? ORG : OTHER_ORG,
        toOrgId: i % 2 ? OTHER_ORG : ORG,
        status: i === 0 ? 'pending' : 'accepted',
        createdAt: serverTimestamp(),
      });
    }
    await setDoc(doc(db, 'tournamentInvites', 'inv1'), {
      fromOrgId: OTHER_ORG, toOrgId: ORG, tournamentId: 't1',
      status: 'pending', invitedBy: 'uid_stranger', createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'competitions', 'c1'), {
      orgId: ORG, name: 'Comp', status: 'in_progress', createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'competitions', 'c1', 'fixtures', 'f1'), {
      orgId: ORG, compId: 'c1', isDraft: false, status: 'scheduled',
      scorerUids: [OWNER], playerUids: [], entrantAId: 'a', entrantBId: 'b',
      entrantAName: 'A', entrantBName: 'B', round: 1, matchIndex: 0,
      scheduledAt: null, createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'competitions', 'c1', 'fixtures', 'f1',
      'scoringRequests', JOINER), {
      orgId: ORG, compId: 'c1', fixtureId: 'f1', uid: JOINER,
      status: 'pending', createdAt: serverTimestamp(),
    });
  });
}

describe('Notifications screen, as the club owner', () => {
  beforeEach(seedWorld);

  it('1. my scoring assignments (collectionGroup fixtures)', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDocs(query(collectionGroup(db, 'fixtures'),
      where('scorerUids', 'array-contains', OWNER),
      where('status', 'in', ['scheduled', 'live']))));
  });

  it('2. incoming challenges (OR query)', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDocs(query(collection(db, 'challenges'),
      or(where('fromOrgId', '==', ORG), where('toOrgId', '==', ORG)))));
  });

  it('3. join requests (members where status == pending)', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDocs(query(collection(db, 'orgs', ORG, 'members'),
      where('status', '==', 'pending'))));
  });

  it('4. requests to score (collectionGroup scoringRequests)', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDocs(query(collectionGroup(db, 'scoringRequests'),
      where('orgId', '==', ORG), where('status', '==', 'pending'))));
  });

  it('5. tournament invitations', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDocs(query(collection(db, 'tournamentInvites'),
      where('toOrgId', '==', ORG), where('status', '==', 'pending'))));
  });
});

// The founder's own device, in the window between the create-club batch
// landing in the LOCAL cache and the server acknowledging it. The app's
// membership listener sees the local write immediately (latency compensation)
// and fans out over the new club at once — but the server has no member
// document yet, so every org-scoped read is refused.
describe('the club-creation race: membership not yet committed server-side', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      // The org exists (say the batch partially landed / or nothing has),
      // but the caller's OWN member document does not.
      await setDoc(doc(db, 'orgs', ORG), organization(OWNER));
      await setDoc(doc(db, 'challenges', 'ch0'), {
        fromOrgId: OTHER_ORG, toOrgId: ORG, status: 'pending',
        createdAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), {
        fromOrgId: OTHER_ORG, toOrgId: ORG, tournamentId: 't1',
        status: 'pending', invitedBy: 'uid_stranger', createdAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'orgs', ORG, 'members', JOINER),
        membership(JOINER, ORG, 'member', 'pending'));
      await setDoc(doc(db, 'orgs', ORG, 'competitions', 'c1', 'fixtures', 'f1',
        'scoringRequests', JOINER), {
        orgId: ORG, compId: 'c1', fixtureId: 'f1', uid: JOINER,
        status: 'pending', createdAt: serverTimestamp(),
      });
    });
  });

  it('challenges are refused', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDocs(query(collection(db, 'challenges'),
      or(where('fromOrgId', '==', ORG), where('toOrgId', '==', ORG)))));
  });
  it('join requests are refused', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDocs(query(collection(db, 'orgs', ORG, 'members'),
      where('status', '==', 'pending'))));
  });
  it('requests to score are refused', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDocs(query(collectionGroup(db, 'scoringRequests'),
      where('orgId', '==', ORG), where('status', '==', 'pending'))));
  });
  it('tournament invitations are refused', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDocs(query(collection(db, 'tournamentInvites'),
      where('toOrgId', '==', ORG), where('status', '==', 'pending'))));
  });
});
