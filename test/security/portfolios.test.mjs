// Emulator-backed tests for department portfolios in firestore.rules.
//
// The Dart suite (../club_portfolio_test.dart) proves the permission matrix is
// the right shape. It cannot prove anything about security, because the matrix
// is only a client-side mirror — a modified app skips it entirely. These tests
// go at the rules, which are the actual authority, and target the one thing
// that would make portfolios worse than useless: a path by which somebody
// grants themselves a brief they were never given.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  serverTimestamp,
  updateDoc,
} from 'firebase/firestore';

let testEnv;

const OWNER = 'uid_owner';
const ADMIN = 'uid_admin';          // admin, no portfolios
const GROUNDSKEEPER = 'uid_grounds'; // admin, holds `grounds`
const TREASURER = 'uid_treasurer';   // plain member, holds `finance`
const PLAYER = 'uid_player';         // plain member, nothing
const ORG = 'org_club';

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

const RULES_FILE = process.env.RULES_FILE ?? '../../firestore.rules';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-portfolios-test',
    firestore: {
      rules: readFileSync(RULES_FILE, 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'orgs', ORG), {
      name: 'Test Club',
      nameLower: 'test club',
      orgType: 'club',
      visibility: 'public',
      ownerUid: OWNER,
      requiresApprovalToJoin: true,
      isDeleted: false,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', ADMIN), membership(ADMIN, 'admin'));
    await setDoc(
      doc(db, 'orgs', ORG, 'members', GROUNDSKEEPER),
      membership(GROUNDSKEEPER, 'admin', ['grounds']),
    );
    await setDoc(
      doc(db, 'orgs', ORG, 'members', TREASURER),
      membership(TREASURER, 'member', ['finance']),
    );
    await setDoc(doc(db, 'orgs', ORG, 'members', PLAYER), membership(PLAYER, 'member'));
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const memberRef = (db, uid) => doc(db, 'orgs', ORG, 'members', uid);

describe('granting a department brief', () => {
  it('the owner may put anybody in charge of anything', async () => {
    const db = as(OWNER);
    await assertSucceeds(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['finance', 'medical'] }),
    );
  });

  it('an admin holding no brief may hand out none', async () => {
    const db = as(ADMIN);
    await assertFails(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['finance'] }),
    );
  });

  it('an admin may pass on the brief they hold', async () => {
    const db = as(GROUNDSKEEPER);
    await assertSucceeds(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['grounds'] }),
    );
  });

  it('...but not one they do not', async () => {
    const db = as(GROUNDSKEEPER);
    await assertFails(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['grounds', 'finance'] }),
    );
  });

  it('nobody may grant themselves a brief', async () => {
    // The self-edit branch is scoped to `grouping` alone; this is the test
    // that keeps it that way.
    const db = as(ADMIN);
    await assertFails(
      updateDoc(memberRef(db, ADMIN), { portfolios: ['finance'] }),
    );
  });

  it('a plain member may not grant themselves or anybody else', async () => {
    const db = as(PLAYER);
    await assertFails(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['finance'] }),
    );
    await assertFails(
      updateDoc(memberRef(db, TREASURER), { portfolios: [] }),
    );
  });

  it('the treasurer cannot appoint, holding no authority over people', async () => {
    const db = as(TREASURER);
    await assertFails(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['finance'] }),
    );
  });

  it('a brief this ruleset has never heard of is refused', async () => {
    const db = as(OWNER);
    await assertFails(
      updateDoc(memberRef(db, PLAYER), { portfolios: ['superuser'] }),
    );
  });
});

describe('taking a brief back', () => {
  it('the owner may take any brief back', async () => {
    const db = as(OWNER);
    await assertSucceeds(
      updateDoc(memberRef(db, TREASURER), { portfolios: [] }),
    );
  });

  it('an admin may not strip a brief they do not hold themselves', async () => {
    // Otherwise an admin could quietly sideline a treasurer the owner
    // appointed over their head.
    const db = as(GROUNDSKEEPER);
    await assertFails(
      updateDoc(memberRef(db, TREASURER), { portfolios: [] }),
    );
  });
});

describe("an owner's row carries no stored brief", () => {
  it('an owner cannot be written with portfolios', async () => {
    const db = as(OWNER);
    // Owners hold every department by rank. Storing grants would leave them
    // behind when the rank went away.
    await assertFails(
      updateDoc(memberRef(db, ADMIN), { role: 'owner', portfolios: ['finance'] }),
    );
  });

  it('promoting to owner with an empty brief list is fine', async () => {
    const db = as(OWNER);
    await assertSucceeds(
      updateDoc(memberRef(db, ADMIN), { role: 'owner', portfolios: [] }),
    );
  });
});

describe('joining never carries a brief', () => {
  it('somebody joining a club cannot arrive holding one', async () => {
    const db = as('uid_newcomer');
    await assertFails(
      setDoc(doc(db, 'orgs', ORG, 'members', 'uid_newcomer'), {
        uid: 'uid_newcomer',
        orgId: ORG,
        role: 'member',
        status: 'pending',
        displayName: 'Newcomer',
        photoUrl: null,
        joinedAt: serverTimestamp(),
        invitedBy: null,
        approvedBy: null,
        portfolios: ['finance'],
      }),
    );
  });

  it('joining with no brief still works', async () => {
    const db = as('uid_newcomer');
    await assertSucceeds(
      setDoc(doc(db, 'orgs', ORG, 'members', 'uid_newcomer'), {
        uid: 'uid_newcomer',
        orgId: ORG,
        role: 'member',
        status: 'pending',
        displayName: 'Newcomer',
        photoUrl: null,
        joinedAt: serverTimestamp(),
        invitedBy: null,
        approvedBy: null,
        portfolios: [],
      }),
    );
  });
});

describe('the grounds brief actually reaches the ground', () => {
  it('the groundskeeper may move the club home ground', async () => {
    const db = as(GROUNDSKEEPER);
    await assertSucceeds(
      updateDoc(doc(db, 'orgs', ORG), {
        homeGroundId: 'g_maidan',
        homeGroundName: 'Village Maidan',
      }),
    );
  });

  it('...and nothing else on the org document', async () => {
    // A brief over the ground is not a brief over the club.
    const db = as(GROUNDSKEEPER);
    await assertFails(
      updateDoc(doc(db, 'orgs', ORG), {
        homeGroundName: 'Village Maidan',
        name: 'Renamed Club',
      }),
    );
  });

  it('a plain member holding no brief may not', async () => {
    const db = as(PLAYER);
    await assertFails(
      updateDoc(doc(db, 'orgs', ORG), { homeGroundName: 'Village Maidan' }),
    );
  });
});

describe('the equipment brief reaches the kit shortfall', () => {
  const need = (uid) => ({
    orgId: ORG,
    createdByUid: uid,
    verified: false,
    status: 'open',
    fulfilled: [],
    items: [{ name: 'Pads', quantity: 6 }],
    beneficiaryType: 'club',
    title: 'Six pairs of pads',
  });

  it('the kit manager may raise a club need without being an organizer', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'orgs', ORG, 'members', PLAYER),
        membership(PLAYER, 'member', ['equipment']),
      );
    });
    const db = as(PLAYER);
    await assertSucceeds(setDoc(doc(db, 'giveNeeds', 'n1'), need(PLAYER)));
  });

  it('a member with no brief may not raise one for the club', async () => {
    const db = as(PLAYER);
    await assertFails(setDoc(doc(db, 'giveNeeds', 'n2'), need(PLAYER)));
  });
});

describe('the finance brief actually reaches the money', () => {
  const product = (uid) => ({
    orgId: ORG,
    orgName: 'Test Club',
    createdByUid: uid,
    isActive: true,
    name: 'Club shirt',
    listPricePaise: 90000,
  });

  it('the treasurer may list a product without being an admin', async () => {
    const db = as(TREASURER);
    await assertSucceeds(
      setDoc(doc(db, 'clubProducts', 'p_shirt'), product(TREASURER)),
    );
  });

  it('an admin without the finance brief may not', async () => {
    const db = as(ADMIN);
    await assertFails(
      setDoc(doc(db, 'clubProducts', 'p_shirt2'), product(ADMIN)),
    );
  });

  it('the owner may, holding every brief by rank', async () => {
    const db = as(OWNER);
    await assertSucceeds(
      setDoc(doc(db, 'clubProducts', 'p_shirt3'), product(OWNER)),
    );
  });

  it('the treasurer reads the club orders; a bare admin does not', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'clubOrders', 'o1'), {
        orgId: ORG,
        buyerUid: PLAYER,
        status: 'placed',
        quantity: 1,
        unitListPricePaise: 90000,
        amountPaidPaise: 0,
      });
    });
    await assertSucceeds(getDoc(doc(as(TREASURER), 'clubOrders', 'o1')));
    await assertFails(getDoc(doc(as(ADMIN), 'clubOrders', 'o1')));
  });
});
