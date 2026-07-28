// Emulator-backed tests for firestore.rules.
//
// These exercise the real rules file against the Firestore emulator, which is
// the only way to catch the class of bug the Dart unit tests structurally
// cannot see: rules that are individually sensible but wrong in interaction
// with batched writes and collection-group queries.
//
// Run with:  npm test        (from test/security/)
//
// The Dart suite in ../ covers pure domain logic — scoring plugins, the
// permission matrix, fixture generation. Nothing there touches Firestore, so
// nothing there could have caught P0-1 or P0-2.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  serverTimestamp,
  where,
  writeBatch,
} from 'firebase/firestore';

let testEnv;

const OWNER = 'uid_owner';
const ADMIN = 'uid_admin';
const SCORER = 'uid_scorer';
const OUTSIDER = 'uid_outsider';

const PUBLIC_ORG = 'org_public';
const PRIVATE_ORG = 'org_unlisted';

/** A membership document as the app writes it. */
const membership = (uid, orgId, role, status = 'active') => ({
  uid,
  orgId,
  role,
  status,
  displayName: 'Test Person',
  photoUrl: null,
  joinedAt: serverTimestamp(),
  invitedBy: null,
  approvedBy: null,
});

/** An organization document as the app writes it. */
const organization = (ownerUid, visibility) => ({
  name: 'Test Organization',
  nameLower: 'test organization',
  orgType: 'school',
  visibility,
  ownerUid,
  inviteCode: 'ABC234',
  parentOrgId: null,
  description: null,
  district: null,
  city: null,
  logoUrl: null,
  memberCount: 1,
  requiresApprovalToJoin: true,
  createdBy: ownerUid,
  createdAt: serverTimestamp(),
  deletedAt: null,
});

/** A fixture document as the draw generator writes it. */
const fixture = (orgId, compId, scorerUids, status = 'live') => ({
  orgId,
  compId,
  entrantAId: 'entrant_a',
  entrantBId: 'entrant_b',
  entrantAName: 'Alice',
  entrantBName: 'Bhavya',
  status,
  round: 1,
  matchIndex: 0,
  roundLabel: 'Round 1',
  scheduledAt: null,
  venue: null,
  scorerUids,
  scoreState: {},
  summary: '',
  lastSeq: 0,
  winnerEntrantId: null,
  isDraw: false,
  rulesetVersion: 1,
  scoringPluginKey: 'set_based',
  feedsWinnerToFixtureId: null,
  createdAt: serverTimestamp(),
});

// Defaults to the project's real rules. Override to run the suite against a
// different revision — which is how these tests were shown to actually fail
// before the P0 fixes rather than being written to match them:
//   RULES_FILE=/tmp/old.rules npm test
const RULES_FILE = process.env.RULES_FILE ?? '../../firestore.rules';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test',
    firestore: {
      rules: readFileSync(RULES_FILE, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** Seeds data bypassing rules, for tests about *reading* it. */
async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore());
  });
}

// ---------------------------------------------------------------------------
// P0-1 — founding an organization
// ---------------------------------------------------------------------------
describe('P0-1: organization creation', () => {
  it('allows a founder to create an org and their owner membership in ONE batch', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);

    batch.set(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    batch.set(
      doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
      membership(OWNER, PUBLIC_ORG, 'owner'),
    );

    // Rules `get()` only sees committed state, so the owner-membership branch
    // must use getAfter() to see the org being created alongside it. With a
    // plain get() this whole batch is denied and onboarding is impossible.
    await assertSucceeds(batch.commit());
  });

  it('refuses an owner membership in an org owned by someone else', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const batch = writeBatch(db);

    batch.set(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    batch.set(
      doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
      membership(OUTSIDER, PUBLIC_ORG, 'owner'),
    );

    await assertFails(batch.commit());
  });

  it('refuses a self-minted owner membership in an existing org', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'owner'),
      ),
    );
  });

  it('still allows a stranger to self-join only as a pending member', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    });

    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'pending'),
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Joining a club — invite codes, auto-approval, re-applying
// ---------------------------------------------------------------------------
describe('joining a club', () => {
  const inviteCode = (orgId, requiresApproval) => ({
    code: 'ABC234',
    orgId,
    orgName: 'Test Organization',
    orgType: 'school',
    requiresApprovalToJoin: requiresApproval,
    city: 'Hyderabad',
    createdAt: serverTimestamp(),
  });

  it('lets a founder create the club and its invite code in one batch', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    batch.set(doc(db, 'inviteCodes', 'ABC234'), inviteCode(PUBLIC_ORG, true));
    batch.set(
      doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
      membership(OWNER, PUBLIC_ORG, 'owner'),
    );
    await assertSucceeds(batch.commit());
  });

  it('resolves a code for an UNLISTED club — the case that was broken', async () => {
    // Querying /orgs by inviteCode could never work here: the org read rule
    // requires membership the applicant does not yet have.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PRIVATE_ORG), organization(OWNER, 'unlisted'));
      await setDoc(doc(db, 'inviteCodes', 'ABC234'), inviteCode(PRIVATE_ORG, true));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(getDoc(doc(db, 'inviteCodes', 'ABC234')));
    assert.equal(snap.data().orgId, PRIVATE_ORG);
  });

  it('refuses listing every invite code', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'inviteCodes', 'ABC234'), inviteCode(PUBLIC_ORG, true));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDocs(collection(db, 'inviteCodes')));
  });

  it('grants membership immediately when the club does not require approval', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), {
        ...organization(OWNER, 'public'),
        requiresApprovalToJoin: false,
      });
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'active'),
      ),
    );
  });

  it('still refuses self-activation when the club DOES require approval', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'active'),
      ),
    );
  });

  it('refuses self-joining at a role above member even with approval off', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), {
        ...organization(OWNER, 'public'),
        requiresApprovalToJoin: false,
      });
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'admin', 'active'),
      ),
    );
  });

  it('lets someone declined by mistake apply again', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'removed'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        { status: 'pending', role: 'member' },
        { merge: true },
      ),
    );
  });

  it('does not let re-applying restore a role that was taken away', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'removed'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        { status: 'pending', role: 'admin' },
        { merge: true },
      ),
    );
  });

  it('does not let an ACTIVE member rewrite their own row to pending tricks', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'active'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    // Only a `removed` row may be re-applied; self-editing otherwise stays shut.
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        { role: 'admin' },
        { merge: true },
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Collection-group query over memberships — the landing screen's only query
// ---------------------------------------------------------------------------
describe('my memberships collection-group query', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(doc(db, 'orgs', PRIVATE_ORG), organization(OWNER, 'unlisted'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'members', OWNER),
        membership(OWNER, PRIVATE_ORG, 'admin'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
        membership(ADMIN, PUBLIC_ORG, 'admin'),
      );
    });
  });

  it('lets a user list their own memberships across every org', async () => {
    // Regression: this rule originally matched on the {memberUid} document
    // id. Firestore does not bind that wildcard when evaluating a
    // collection-group query, so it was null and the query died with
    // "Null value error" — the landing screen could never load.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(collectionGroup(db, 'members'), where('uid', '==', OWNER)),
      ),
    );
    assert.equal(snap.size, 2);
  });

  it('refuses an unconstrained collection-group read of every membership', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDocs(query(collectionGroup(db, 'members'))));
  });

  it('refuses reading somebody else\'s memberships', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      getDocs(query(collectionGroup(db, 'members'), where('uid', '==', OWNER))),
    );
  });
});

// ---------------------------------------------------------------------------
// P0-2 — collection-group queries over fixtures
// ---------------------------------------------------------------------------
describe('P0-2: fixtures collection-group queries', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(doc(db, 'orgs', PRIVATE_ORG), organization(OWNER, 'unlisted'));
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'members', ADMIN),
        membership(ADMIN, PRIVATE_ORG, 'admin'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'fx1'),
        fixture(PUBLIC_ORG, 'comp1', [SCORER]),
      );
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'competitions', 'comp2', 'fixtures', 'fx2'),
        fixture(PRIVATE_ORG, 'comp2', [SCORER]),
      );
    });
  });

  it('lets a signed-in user read live fixtures of a PUBLIC org via collectionGroup', async () => {
    // A rule at the nested fixtures path does not apply to a collection-group
    // read; without a /{path=**}/fixtures rule this is permission-denied.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('orgId', '==', PUBLIC_ORG),
          where('status', '==', 'live'),
        ),
      ),
    );
    assert.equal(snap.size, 1);
  });

  it('lets a spectator with no account read a public org\'s live fixtures', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('orgId', '==', PUBLIC_ORG),
          where('status', '==', 'live'),
        ),
      ),
    );
  });

  it('lets an assigned scorer find their own assignments across orgs', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('scorerUids', 'array-contains', SCORER),
          where('status', 'in', ['scheduled', 'live']),
        ),
      ),
    );
    // Both the public and the unlisted org's fixtures — they are assigned to
    // score both, which is the whole point of the screen.
    assert.equal(snap.size, 2);
  });

  it('refuses an outsider reading an UNLISTED org\'s fixtures', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('orgId', '==', PRIVATE_ORG),
          where('status', '==', 'live'),
        ),
      ),
    );
  });

  it('lets a member of an unlisted org read its fixtures', async () => {
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('orgId', '==', PRIVATE_ORG),
          where('status', '==', 'live'),
        ),
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Scoring writes — the guard the whole event-sourcing design rests on
// ---------------------------------------------------------------------------
describe('scoring writes', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'fx1'),
        fixture(PUBLIC_ORG, 'comp1', [SCORER]),
      );
    });
  });

  const eventPath = (seq) =>
    ['orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'fx1', 'events', seq];
  const fixturePath = ['orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'fx1'];

  const scoreBatch = (db, seq) => {
    const batch = writeBatch(db);
    batch.set(doc(db, ...eventPath(String(seq).padStart(9, '0'))), {
      seq,
      type: 'point',
      payload: { side: 'a' },
      byUid: SCORER,
      at: serverTimestamp(),
      clientEventId: `fx1:${seq}:point`,
      note: null,
    });
    batch.update(doc(db, ...fixturePath), {
      scoreState: { currentA: seq, currentB: 0 },
      lastSeq: seq,
      summary: `${seq}-0`,
      status: 'live',
      winnerEntrantId: null,
      isDraw: false,
    });
    return batch;
  };

  it('lets the assigned scorer append an event and advance the projection', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(scoreBatch(db, 1).commit());
  });

  it('refuses a member who is not an assigned scorer', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(scoreBatch(db, 1).commit());
  });

  it('refuses a projection that does not move the sequence forward', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(scoreBatch(db, 1).commit());
    // Replaying seq 1 is a stale client trying to overwrite a newer score.
    await assertFails(scoreBatch(db, 1).commit());
  });

  it('never allows a scoring event to be rewritten', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(scoreBatch(db, 1).commit());
    await assertFails(
      setDoc(doc(db, ...eventPath('000000001')), {
        seq: 1,
        type: 'point',
        payload: { side: 'b' },
        byUid: SCORER,
        at: serverTimestamp(),
        clientEventId: 'tampered',
        note: null,
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Date of birth is write-once — the rule every age category depends on
// ---------------------------------------------------------------------------
describe('user profiles', () => {
  const profile = (uid, dob) => ({
    uid,
    displayName: 'Test Person',
    email: 'test@example.com',
    dateOfBirth: dob,
    gender: 'female',
    photoUrl: null,
    phone: null,
    profileVisibility: 'community',
    profileComplete: true,
    isMinor: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  it('lets a user create their own profile with a past date of birth', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER), profile(OWNER, new Date('2005-04-11'))),
    );
  });

  it('refuses a date of birth in the future', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER), profile(OWNER, new Date('2099-01-01'))),
    );
  });

  it('refuses any later edit of the date of birth', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OWNER), profile(OWNER, new Date('2005-04-11')));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OWNER),
        profile(OWNER, new Date('2011-04-11')),
        { merge: true },
      ),
    );
  });

  it('refuses writing to somebody else\'s profile', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER), profile(OWNER, new Date('2005-04-11'))),
    );
  });
});
