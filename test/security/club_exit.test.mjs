// Leaving a club, and an owner handing it over on the way out.
//
// `OrgRepository.handOverClub` is two writes: a batch that makes the successor
// owner and steps the leaver down to admin, then the leaver deleting their own
// row. These pin that the rules allow exactly that order and still refuse the
// shortcut — an owner deleting themselves — that would leave a club with
// nobody who can ever appoint an owner.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let testEnv;

const OWNER = 'uid_owner';
const ADMIN = 'uid_admin';
const PLAYER = 'uid_player';
const TREASURER = 'uid_treasurer';
const ORG = 'org_exit';

const membership = (uid, role, portfolios = [], status = 'active') => ({
  uid,
  orgId: ORG,
  role,
  status,
  displayName: 'Test Person',
  photoUrl: null,
  joinedAt: serverTimestamp(),
  invitedBy: null,
  approvedBy: null,
  portfolios,
});

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-club-exit-test',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});

after(async () => { await testEnv?.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'orgs', ORG), {
      name: 'Exit Club', nameLower: 'exit club', orgType: 'club',
      visibility: 'public', ownerUid: OWNER, requiresApprovalToJoin: true,
      isDeleted: false, createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', ADMIN), membership(ADMIN, 'admin'));
    await setDoc(doc(db, 'orgs', ORG, 'members', PLAYER), membership(PLAYER, 'member'));
    await setDoc(
      doc(db, 'orgs', ORG, 'members', TREASURER),
      membership(TREASURER, 'member', ['finance']),
    );
  });
});

const dbAs = (uid) => testEnv.authenticatedContext(uid).firestore();
const member = (db, uid) => doc(db, 'orgs', ORG, 'members', uid);

describe('leaving', () => {
  it('a member may leave', async () => {
    await assertSucceeds(deleteDoc(member(dbAs(PLAYER), PLAYER)));
  });

  it('an admin may leave', async () => {
    await assertSucceeds(deleteDoc(member(dbAs(ADMIN), ADMIN)));
  });

  it('an owner may not simply delete themselves', async () => {
    await assertFails(deleteDoc(member(dbAs(OWNER), OWNER)));
  });
});

describe('handing the club over', () => {
  it('owner makes a member owner and steps down in one batch, then leaves', async () => {
    const db = dbAs(OWNER);
    const batch = writeBatch(db);
    batch.update(member(db, PLAYER), { role: 'owner', portfolios: [] });
    batch.update(member(db, OWNER), { role: 'admin' });
    await assertSucceeds(batch.commit());
    await assertSucceeds(deleteDoc(member(db, OWNER)));
  });

  it('the successor can then run the club', async () => {
    const db = dbAs(OWNER);
    const batch = writeBatch(db);
    batch.update(member(db, PLAYER), { role: 'owner', portfolios: [] });
    batch.update(member(db, OWNER), { role: 'admin' });
    await assertSucceeds(batch.commit());
    await assertSucceeds(
      updateDoc(member(dbAs(PLAYER), ADMIN), { role: 'event_manager' }),
    );
  });

  it('a successor holding briefs has them cleared as they become owner', async () => {
    const db = dbAs(OWNER);
    const batch = writeBatch(db);
    batch.update(member(db, TREASURER), { role: 'owner', portfolios: [] });
    batch.update(member(db, OWNER), { role: 'admin' });
    await assertSucceeds(batch.commit());
  });

  it('an owner row may not keep stored briefs', async () => {
    const db = dbAs(OWNER);
    const batch = writeBatch(db);
    batch.update(member(db, TREASURER), { role: 'owner' });
    batch.update(member(db, OWNER), { role: 'admin' });
    await assertFails(batch.commit());
  });

  it('an admin cannot hand the club to anybody', async () => {
    const db = dbAs(ADMIN);
    await assertFails(updateDoc(member(db, PLAYER), { role: 'owner', portfolios: [] }));
  });

  it('a member cannot take the club by promoting themselves', async () => {
    const db = dbAs(PLAYER);
    await assertFails(updateDoc(member(db, PLAYER), { role: 'owner' }));
  });
});
