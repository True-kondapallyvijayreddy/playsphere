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
  deleteDoc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  serverTimestamp,
  updateDoc,
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
const STORAGE_RULES_FILE =
  process.env.STORAGE_RULES_FILE ?? '../../storage.rules';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test',
    firestore: {
      rules: readFileSync(RULES_FILE, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    // Cloud Storage holds the actual bytes of every memory and every club
    // logo, and its rules are a completely separate ruleset with completely
    // separate blind spots — it cannot read Firestore at all. Nothing
    // exercised them before, which is how a world-writable logo path survived.
    storage: {
      rules: readFileSync(STORAGE_RULES_FILE, 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** A tiny but genuine JPEG header, so contentType and bytes agree. */
const jpegBytes = () =>
  new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

const imageMeta = { contentType: 'image/jpeg' };

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

  it('lets a scorer advance a winner into an EMPTY slot of the next round', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
        {
          ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled'),
          entrantAId: '',
          entrantAName: 'To be decided',
          entrantBId: '',
          entrantBName: 'To be decided',
        },
      );
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
        { entrantAId: 'entrant_a', entrantAName: 'Alice' },
        { merge: true },
      ),
    );
  });

  it('refuses replacing an entrant already placed in the next round', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
        { ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled') },
      );
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    // Both sides are already filled — a scorer must never be able to swap who
    // is playing.
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
        { entrantAId: 'someone_else', entrantAName: 'Impostor' },
        { merge: true },
      ),
    );
  });

  it('refuses advancing into a match that has already been scored', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
        {
          ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled'),
          entrantAId: '',
          entrantAName: 'To be decided',
          lastSeq: 4,
        },
      );
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
        { entrantAId: 'entrant_a', entrantAName: 'Alice' },
        { merge: true },
      ),
    );
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

// ---------------------------------------------------------------------------
// Minor safety — profile visibility MUST derive from the immutable
// dateOfBirth, never from the client-mirrored `isMinor` boolean.
// ---------------------------------------------------------------------------
describe('minor safety: profile visibility derives from dateOfBirth', () => {
  const MINOR_UID = 'uid_minor_profile';
  const ADULT_UID = 'uid_adult_profile';

  const publicProfile = (uid, dob, forgedIsMinor, visibility = 'public') => ({
    uid,
    displayName: 'Test Person',
    email: 'test@example.com',
    dateOfBirth: dob,
    gender: 'female',
    photoUrl: null,
    phone: null,
    profileVisibility: visibility,
    profileComplete: true,
    isMinor: forgedIsMinor,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  it('refuses a stranger reading a MINOR profile even when isMinor is forged to false', async () => {
    await seed(async (db) => {
      // ~16 years old as of "today" — a real minor — but the client-owned
      // isMinor field lies and claims the owner is an adult.
      await setDoc(
        doc(db, 'users', MINOR_UID),
        publicProfile(MINOR_UID, new Date('2010-01-01'), false),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'users', MINOR_UID)));
  });

  it('still lets a stranger read a genuinely ADULT public profile', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', ADULT_UID),
        publicProfile(ADULT_UID, new Date('1990-01-01'), false),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', ADULT_UID)));
  });

  it('lets the minor read their own profile regardless of visibility', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', MINOR_UID),
        publicProfile(MINOR_UID, new Date('2010-01-01'), true, 'private'),
      );
    });
    const db = testEnv.authenticatedContext(MINOR_UID).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', MINOR_UID)));
  });
});

// ---------------------------------------------------------------------------
// Guardian consent records (§2.7 MUST) — the only channel that may reveal a
// minor's profile to a scout, and only while an unrevoked record exists.
// ---------------------------------------------------------------------------
describe('guardian consent records', () => {
  const MINOR_UID = 'uid_minor_consent';
  const GUARDIAN = 'uid_guardian';
  const SCOUT = 'uid_scout';

  const scoutPath = (scoutUid) => ['users', MINOR_UID, 'guardianConsents', scoutUid];

  const minorProfile = (guardianUid) => ({
    uid: MINOR_UID,
    displayName: 'Young Player',
    email: 'minor@example.com',
    dateOfBirth: new Date('2012-01-01'),
    gender: 'male',
    photoUrl: null,
    phone: null,
    profileVisibility: 'private',
    profileComplete: true,
    isMinor: true,
    guardianUid: guardianUid ?? null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  const consent = (overrides = {}) => ({
    guardianUid: GUARDIAN,
    minorUid: MINOR_UID,
    scoutUid: SCOUT,
    consentedTo: ['profile_visibility'],
    revoked: false,
    revokedAt: null,
    grantedAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a self-declared guardian create a consent record for a scout', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(setDoc(doc(db, ...scoutPath(SCOUT)), consent()));
  });

  it('refuses a scout minting their own consent record', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
    });
    const db = testEnv.authenticatedContext(SCOUT).firestore();
    await assertFails(
      setDoc(doc(db, ...scoutPath(SCOUT)), consent({ guardianUid: SCOUT })),
    );
  });

  it('refuses the minor consenting for themselves', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
    });
    const db = testEnv.authenticatedContext(MINOR_UID).firestore();
    await assertFails(
      setDoc(doc(db, ...scoutPath(SCOUT)), consent({ guardianUid: MINOR_UID })),
    );
  });

  it('refuses a creator whose uid does not match the profile\'s linked guardian', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(GUARDIAN));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, ...scoutPath(SCOUT)), consent({ guardianUid: OUTSIDER })),
    );
  });

  it('a scout with a valid unrevoked consent can read the minor\'s profile', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
      await setDoc(doc(db, ...scoutPath(SCOUT)), consent());
    });
    const db = testEnv.authenticatedContext(SCOUT).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', MINOR_UID)));
  });

  it('refuses the same scout when no consent record exists at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
    });
    const db = testEnv.authenticatedContext(SCOUT).firestore();
    await assertFails(getDoc(doc(db, 'users', MINOR_UID)));
  });

  it('lets the guardian revoke their own consent, after which the scout loses access', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
      await setDoc(doc(db, ...scoutPath(SCOUT)), consent());
    });
    const guardianDb = testEnv.authenticatedContext(GUARDIAN).firestore();
    // Only the revocation is sent. Re-writing the whole record would carry a
    // fresh `grantedAt`, which the rules freeze on purpose — a consent whose
    // grant date can be moved is a consent whose expiry can be moved.
    await assertSucceeds(
      updateDoc(
        doc(guardianDb, ...scoutPath(SCOUT)),
        { revoked: true, revokedAt: serverTimestamp() },
      ),
    );
    const scoutDb = testEnv.authenticatedContext(SCOUT).firestore();
    await assertFails(getDoc(doc(scoutDb, 'users', MINOR_UID)));
  });

  it('refuses anyone other than the granting guardian revoking it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
      await setDoc(doc(db, ...scoutPath(SCOUT)), consent());
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, ...scoutPath(SCOUT)),
        { ...consent(), revoked: true, revokedAt: serverTimestamp() },
      ),
    );
  });

  it('refuses editing what was consented to after the record is granted', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
      await setDoc(doc(db, ...scoutPath(SCOUT)), consent());
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(
      setDoc(
        doc(db, ...scoutPath(SCOUT)),
        { ...consent(), consentedTo: ['profile_visibility', 'contact_info'] },
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Ratings & career stats — must no longer be world-writable.
// ---------------------------------------------------------------------------
describe('ratings & career_stats: server-settled only', () => {
  // These were client-written under a long list of guards — assigned scorer
  // only, on a fixture the target played in, every field typed and bounded,
  // gamesPlayed advancing by exactly one. That stopped a passing stranger.
  //
  // It could not stop a scorer of genuine matches nudging their own rating
  // upward a little at a time, because every individual write looked
  // legitimate. `onMatchSettled` derives both documents from the finished
  // fixture instead, so the client needs no write path and does not get one.
  const SPORT = 'badminton';
  const ratingPath = (uid) => `users/${uid}/ratings/${SPORT}`;
  const careerPath = (uid) => `users/${uid}/career_stats/${SPORT}`;

  const rating = {
    rating: 1520,
    deviation: 300,
    volatility: 0.06,
    gamesPlayed: 1,
  };

  it('a rating is readable by any signed-in user', async () => {
    // A rating nobody can see is not a rating.
    await seed(async (db) => {
      await setDoc(doc(db, ratingPath(OWNER)), rating);
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(db, ratingPath(OWNER))));
  });

  it('nobody may write their own rating', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(setDoc(doc(db, ratingPath(OWNER)), rating));
  });

  it('nobody may write anybody else\'s rating', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, ratingPath(OWNER)), rating));
  });

  it('a scorer may no longer settle a rating either', async () => {
    // The path that existed before. It was the narrowest client write in the
    // product and it is still gone, because narrow is not the same as
    // verifiable.
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(doc(db, ratingPath(OWNER)), {
        ...rating,
        settledBy: { orgId: PUBLIC_ORG, compId: 'c1', fixtureId: 'f1' },
      }),
    );
  });

  it('an existing rating cannot be edited or deleted', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ratingPath(OWNER)), rating);
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(updateDoc(doc(db, ratingPath(OWNER)), { rating: 2400 }));
    await assertFails(deleteDoc(doc(db, ratingPath(OWNER))));
  });

  it('career statistics are equally read-only to every client', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, careerPath(OWNER)), {
        uid: OWNER,
        sportId: SPORT,
        matchesPlayed: 4,
      });
    });
    const read = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(read, careerPath(OWNER))));

    const write = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(write, careerPath(OWNER)), {
        uid: OWNER,
        sportId: SPORT,
        matchesPlayed: 999,
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Inter-club challenges — accept/decline/reschedule requires club admin.
// ---------------------------------------------------------------------------
describe('inter-club challenges', () => {
  const FROM_ORG = 'org_challenge_from';
  const TO_ORG = 'org_challenge_to';

  const challengeDoc = (overrides = {}) => ({
    fromOrgId: FROM_ORG,
    toOrgId: TO_ORG,
    fromOrgName: 'From Club',
    toOrgName: 'To Club',
    sportId: 'cricket',
    status: 'pending',
    proposedSlots: [],
    venue: null,
    createdFixtureId: null,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', FROM_ORG), organization(OWNER, 'public'));
      await setDoc(doc(db, 'orgs', TO_ORG), organization(ADMIN, 'public'));
      await setDoc(
        doc(db, 'orgs', FROM_ORG, 'members', OWNER),
        membership(OWNER, FROM_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', TO_ORG, 'members', ADMIN),
        membership(ADMIN, TO_ORG, 'admin'),
      );
      await setDoc(
        doc(db, 'orgs', FROM_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, FROM_ORG, 'member'),
      );
    });
  });

  it('lets an admin of the FROM club issue a challenge', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, 'challenges', 'ch1'), challengeDoc()));
  });

  it('refuses a plain member of the FROM club issuing a challenge', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, 'challenges', 'ch1'), challengeDoc()));
  });

  it('refuses a total stranger issuing a challenge', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(setDoc(doc(db, 'challenges', 'ch1'), challengeDoc()));
  });

  it('lets an admin of the TO club accept the challenge', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'challenges', 'ch1'), { status: 'accepted' }),
    );
  });

  it('lets an admin of the FROM club reschedule the challenge', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'challenges', 'ch1'), { status: 'rescheduled' }),
    );
  });

  it('refuses a total stranger accepting/declining another club\'s challenge', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      updateDoc(doc(db, 'challenges', 'ch1'), { status: 'declined' }),
    );
  });

  // Withdrawal is the issuing club's counterpart to the receiving club's
  // decline, and the asymmetry between them is the whole point of these.
  describe('withdrawing', () => {
    it('lets an admin of the FROM club withdraw an unanswered challenge', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
      });
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, 'challenges', 'ch1'), { status: 'withdrawn' }),
      );
    });

    it('refuses the TO club withdrawing a challenge issued against it', async () => {
      // The receiving club declines; it does not get to rewrite history as
      // the other side having backed out.
      await seed(async (db) => {
        await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
      });
      const db = testEnv.authenticatedContext(ADMIN).firestore();
      await assertFails(
        updateDoc(doc(db, 'challenges', 'ch1'), { status: 'withdrawn' }),
      );
    });

    it('refuses withdrawing a challenge the other club already accepted', async () => {
      // There is a fixture in both clubs' schedules by now. Reverting the
      // challenge behind it would orphan that match.
      await seed(async (db) => {
        await setDoc(
          doc(db, 'challenges', 'ch1'),
          challengeDoc({ status: 'accepted' }),
        );
      });
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertFails(
        updateDoc(doc(db, 'challenges', 'ch1'), { status: 'withdrawn' }),
      );
    });

    it('refuses a plain member of the FROM club withdrawing', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
      });
      const db = testEnv.authenticatedContext(OUTSIDER).firestore();
      await assertFails(
        updateDoc(doc(db, 'challenges', 'ch1'), { status: 'withdrawn' }),
      );
    });
  });
});

// ---------------------------------------------------------------------------
// Scoring requests — "let me score this one", and who may grant it.
//
// The security property that matters: a request must never be able to grant
// itself. Everything below is arranged around trying to make it.
// ---------------------------------------------------------------------------
describe('scoring requests', () => {
  const COMP = 'comp_sr';
  const FIXTURE = 'fx_sr';

  const requestDoc = (uid, overrides = {}) => ({
    uid,
    orgId: PUBLIC_ORG,
    compId: COMP,
    fixtureId: FIXTURE,
    displayName: 'Test Person',
    matchLabel: 'Alice v Bhavya',
    status: 'pending',
    note: null,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  const requestRef = (db, uid) =>
    doc(
      db,
      'orgs', PUBLIC_ORG,
      'competitions', COMP,
      'fixtures', FIXTURE,
      'scoringRequests', uid,
    );

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'member'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP),
        { orgId: PUBLIC_ORG, name: 'Test Comp', createdBy: OWNER },
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FIXTURE),
        fixture(PUBLIC_ORG, COMP, [], 'scheduled'),
      );
    });
  });

  it('lets an active member ask to score a match of their own club', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(setDoc(requestRef(db, SCORER), requestDoc(SCORER)));
  });

  it('refuses a non-member asking', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(requestRef(db, OUTSIDER), requestDoc(OUTSIDER)));
  });

  it('refuses asking on somebody else\'s behalf', async () => {
    // Doc id is the requester's uid, so this is also an attempt to write
    // outside your own row.
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(setDoc(requestRef(db, OWNER), requestDoc(OWNER)));
  });

  it('refuses a request that arrives pre-approved', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(requestRef(db, SCORER), requestDoc(SCORER, { status: 'approved' })),
    );
  });

  it('refuses the requester approving their own pending request', async () => {
    // The whole point. A member who can flip their own row to `approved`
    // would not need an admin at all.
    await seed(async (db) => {
      await setDoc(requestRef(db, SCORER), requestDoc(SCORER));
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      updateDoc(requestRef(db, SCORER), {
        status: 'approved',
        decidedBy: SCORER,
      }),
    );
  });

  it('lets an organizer approve, and add the scorer, in one batch', async () => {
    await seed(async (db) => {
      await setDoc(requestRef(db, SCORER), requestDoc(SCORER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);
    batch.update(
      doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FIXTURE),
      { scorerUids: [SCORER] },
    );
    batch.update(requestRef(db, SCORER), {
      status: 'approved',
      decidedBy: OWNER,
    });
    await assertSucceeds(batch.commit());
  });

  it('refuses an organizer recording somebody else as the decider', async () => {
    // Who granted the pen has to be true, because it is the record a
    // disputed result is settled against.
    await seed(async (db) => {
      await setDoc(requestRef(db, SCORER), requestDoc(SCORER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(requestRef(db, SCORER), {
        status: 'approved',
        decidedBy: ADMIN,
      }),
    );
  });

  it('lets the requester ask again after being declined', async () => {
    await seed(async (db) => {
      await setDoc(
        requestRef(db, SCORER),
        requestDoc(SCORER, { status: 'declined', decidedBy: OWNER }),
      );
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(setDoc(requestRef(db, SCORER), requestDoc(SCORER)));
  });

  it('lets an organizer list every request waiting on their club', async () => {
    await seed(async (db) => {
      await setDoc(requestRef(db, SCORER), requestDoc(SCORER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'scoringRequests'),
          where('orgId', '==', PUBLIC_ORG),
          where('status', '==', 'pending'),
        ),
      ),
    );
    assert.equal(snap.size, 1);
  });

  it('refuses a plain member listing the club\'s requests', async () => {
    await seed(async (db) => {
      await setDoc(requestRef(db, SCORER), requestDoc(SCORER));
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      getDocs(
        query(
          collectionGroup(db, 'scoringRequests'),
          where('orgId', '==', PUBLIC_ORG),
          where('status', '==', 'pending'),
        ),
      ),
    );
  });

  it('lets the requester read their own request', async () => {
    await seed(async (db) => {
      await setDoc(requestRef(db, SCORER), requestDoc(SCORER));
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(getDoc(requestRef(db, SCORER)));
  });

  it('refuses deleting a decided request', async () => {
    await seed(async (db) => {
      await setDoc(
        requestRef(db, SCORER),
        requestDoc(SCORER, { status: 'declined', decidedBy: OWNER }),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(deleteDoc(requestRef(db, SCORER)));
  });
});

// ---------------------------------------------------------------------------
// lookingForPosts — the author field can never be reassigned by an editor.
// ---------------------------------------------------------------------------
describe('lookingForPosts: author cannot be reassigned', () => {
  const POST_ID = 'post1';
  const postDoc = (authorUid, overrides = {}) => ({
    authorUid,
    sportId: 'football',
    type: 'player',
    message: 'Looking for a striker',
    orgId: null,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets the author create their own post', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OWNER)));
  });

  it('lets the real author edit their own post', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OWNER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OWNER, { message: 'Updated' })),
    );
  });

  it('refuses a stranger stamping themselves in as the new author to take over the post', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OWNER));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OUTSIDER, { message: 'Hijacked' })),
    );
  });

  it('refuses a stranger editing the post even while leaving authorUid alone', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OWNER));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'lookingForPosts', POST_ID), postDoc(OWNER, { message: 'Vandalized' })),
    );
  });
});

// ---------------------------------------------------------------------------
// Fixtures — the organizer branch must not be able to silently overwrite the
// live/final score projection of a fixture.
// ---------------------------------------------------------------------------
describe('fixtures: organizer branch cannot silently overwrite the score', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
        membership(ADMIN, PUBLIC_ORG, 'admin'),
      );
    });
  });

  const fixturePath = (id) => ['orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', id];

  it('refuses an admin rewriting the score of a COMPLETED fixture', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('done')), {
        ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'completed'),
        lastSeq: 5,
        scoreState: { currentA: 21, currentB: 15 },
        summary: '21-15',
        winnerEntrantId: 'entrant_a',
        isDraw: false,
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      setDoc(
        doc(db, ...fixturePath('done')),
        { scoreState: { currentA: 0, currentB: 21 }, summary: '0-21', winnerEntrantId: 'entrant_b' },
        { merge: true },
      ),
    );
  });

  it('still lets an admin edit a non-score field of a COMPLETED fixture', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('done')), {
        ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'completed'),
        lastSeq: 5,
        scoreState: { currentA: 21, currentB: 15 },
        summary: '21-15',
        winnerEntrantId: 'entrant_a',
        isDraw: false,
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      setDoc(doc(db, ...fixturePath('done')), { venue: 'Ground 2' }, { merge: true }),
    );
  });

  it('refuses an admin rewinding lastSeq on a LIVE fixture', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('live')), {
        ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'live'),
        lastSeq: 3,
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      setDoc(doc(db, ...fixturePath('live')), { lastSeq: 1 }, { merge: true }),
    );
  });

  it('still lets an admin force a status change on a LIVE fixture without touching the score', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('live')), {
        ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'live'),
        lastSeq: 3,
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      setDoc(doc(db, ...fixturePath('live')), { status: 'abandoned' }, { merge: true }),
    );
  });
});

// ---------------------------------------------------------------------------
// Standings — writing a competition's points table requires the organizer
// tier, not merely being assigned to score one fixture in the org.
// ---------------------------------------------------------------------------
describe('standings: write requires organizer role, not just any scorer', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
        membership(ADMIN, PUBLIC_ORG, 'admin'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
    });
  });

  const standingsPath = ['orgs', PUBLIC_ORG, 'competitions', 'comp1', 'standings', 'entrant_a'];

  it('refuses a bare judge_scorer writing a standings row', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(setDoc(doc(db, ...standingsPath), { points: 9, played: 3 }));
  });

  it('lets an event organizer write a standings row', async () => {
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(setDoc(doc(db, ...standingsPath), { points: 9, played: 3 }));
  });
});

// ---------------------------------------------------------------------------
// Inter-club challenges — school v school, village v village.
//
// This is the flow CLAUDE.md calls the heart of the OS, and until now it had
// never worked: `acceptChallenge` wrote the fixture into the CHALLENGER's
// tenant, so the accepting club's admin was always denied, and the UI hid the
// rejection by rendering failed reads as empty lists.
//
// The match is now hosted by the club that accepted, and the visiting club's
// access comes from `participantOrgIds`. These tests pin both halves: that the
// accept batch commits, and that the participant grant is not a way in for
// anybody else.
// ---------------------------------------------------------------------------
describe('inter-club challenges', () => {
  const HOME = 'org_home';        // accepts, and therefore hosts
  const AWAY = 'org_away';        // issued the challenge
  const THIRD = 'org_bystander';  // uninvolved

  const HOME_ADMIN = 'uid_home_admin';
  const AWAY_ADMIN = 'uid_away_admin';
  const AWAY_SCORER = 'uid_away_scorer';
  const THIRD_ADMIN = 'uid_third_admin';

  const CHALLENGE = 'chal1';
  const COMP = 'comp_interclub';
  const FIX = 'fx_interclub';

  const participants = [AWAY, HOME];

  const interClubCompetition = () => ({
    orgId: HOME,
    name: 'Away Village v Home School',
    nameLower: 'away village v home school',
    sportId: 'kabaddi',
    sportName: 'Kabaddi',
    archetype: 'versus',
    entrantType: 'team',
    format: 'knockout',
    status: 'scheduled',
    category: { label: 'Open' },
    scoringPluginKey: 'kabaddi',
    description: null,
    venue: 'Home ground',
    startDate: null,
    endDate: null,
    registrationClosesAt: null,
    maxEntrants: 2,
    entrantCount: 2,
    fixtureCount: 1,
    verificationTier: 'casual',
    rulesetVersion: 1,
    pointsForWin: 3,
    pointsForDraw: 1,
    pointsForLoss: 0,
    tiebreakChain: null,
    participantOrgIds: participants,
    createdBy: HOME_ADMIN,
    createdAt: serverTimestamp(),
  });

  const interClubFixture = (scorerUids = [HOME_ADMIN], status = 'scheduled') => ({
    ...fixture(HOME, COMP, scorerUids, status),
    participantOrgIds: participants,
  });

  // Both clubs unlisted on purpose: if either were public, `orgIsReadable`
  // would grant the access and these tests would pass without the participant
  // rule doing any work at all.
  beforeEach(async () => {
    await seed(async (db) => {
      for (const [org, admin] of [[HOME, HOME_ADMIN], [AWAY, AWAY_ADMIN], [THIRD, THIRD_ADMIN]]) {
        await setDoc(doc(db, 'orgs', org), organization(admin, 'unlisted'));
        await setDoc(doc(db, 'orgs', org, 'members', admin), membership(admin, org, 'admin'));
      }
      await setDoc(
        doc(db, 'orgs', AWAY, 'members', AWAY_SCORER),
        membership(AWAY_SCORER, AWAY, 'judge_scorer'),
      );
      await setDoc(doc(db, 'challenges', CHALLENGE), {
        fromOrgId: AWAY,
        toOrgId: HOME,
        fromOrgName: 'Away Village',
        toOrgName: 'Home School',
        sportId: 'kabaddi',
        status: 'pending',
        proposedSlots: [],
        venue: 'Home ground',
        createdFixtureId: null,
        createdCompId: null,
        hostOrgId: null,
        agreedSlot: null,
        createdAt: serverTimestamp(),
      });
    });
  });

  it('lets the accepting club commit the whole accept batch', async () => {
    const db = testEnv.authenticatedContext(HOME_ADMIN).firestore();
    const batch = writeBatch(db);

    batch.set(doc(db, 'orgs', HOME, 'competitions', COMP), interClubCompetition());
    batch.set(
      doc(db, 'orgs', HOME, 'competitions', COMP, 'fixtures', FIX),
      interClubFixture(),
    );
    batch.update(doc(db, 'challenges', CHALLENGE), {
      status: 'accepted',
      createdFixtureId: FIX,
      createdCompId: COMP,
      hostOrgId: HOME,
    });

    // The regression this whole change exists for: this batch used to be
    // written against the CHALLENGER's org and was denied every time.
    await assertSucceeds(batch.commit());
  });

  it('refuses the challenging club creating the match in the host tenant', async () => {
    const db = testEnv.authenticatedContext(AWAY_ADMIN).firestore();
    await assertFails(
      setDoc(doc(db, 'orgs', HOME, 'competitions', COMP), interClubCompetition()),
    );
  });

  it('refuses a competition naming two orgs the creator does not own', async () => {
    // Without the ownership half of interClubShapeValid, a club could create a
    // match inside its own tenant naming two unrelated orgs — a read grant
    // minted out of thin air.
    const db = testEnv.authenticatedContext(THIRD_ADMIN).firestore();
    await assertFails(
      setDoc(doc(db, 'orgs', THIRD, 'competitions', COMP), {
        ...interClubCompetition(),
        orgId: THIRD,
        createdBy: THIRD_ADMIN,
        participantOrgIds: [HOME, AWAY],
      }),
    );
  });

  it('refuses status scheduled on a competition that is not inter-club', async () => {
    const db = testEnv.authenticatedContext(HOME_ADMIN).firestore();
    await assertFails(
      setDoc(doc(db, 'orgs', HOME, 'competitions', 'comp_plain'), {
        ...interClubCompetition(),
        participantOrgIds: null,
      }),
    );
  });

  describe('once the match exists', () => {
    beforeEach(async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'orgs', HOME, 'competitions', COMP), interClubCompetition());
        await setDoc(
          doc(db, 'orgs', HOME, 'competitions', COMP, 'fixtures', FIX),
          interClubFixture([HOME_ADMIN, AWAY_SCORER], 'live'),
        );
        await setDoc(
          doc(db, 'orgs', HOME, 'competitions', COMP, 'fixtures', FIX, 'events', '0000000001'),
          { seq: 1, byUid: HOME_ADMIN, at: serverTimestamp(), clientEventId: 'c1', type: 'raid' },
        );
      });
    });

    const compRef = (db) => doc(db, 'orgs', HOME, 'competitions', COMP);
    const fixRef = (db) => doc(db, 'orgs', HOME, 'competitions', COMP, 'fixtures', FIX);
    const eventRef = (db, seq) =>
      doc(db, 'orgs', HOME, 'competitions', COMP, 'fixtures', FIX, 'events', seq);

    it('lets the visiting club read the competition it is playing in', async () => {
      const db = testEnv.authenticatedContext(AWAY_ADMIN).firestore();
      await assertSucceeds(getDoc(compRef(db)));
    });

    it('lets the visiting club read the fixture', async () => {
      const db = testEnv.authenticatedContext(AWAY_ADMIN).firestore();
      await assertSucceeds(getDoc(fixRef(db)));
    });

    it('lets the visiting club read the event ledger', async () => {
      // Without this the away club can see the match but cannot rebuild the
      // scorecard, which is the same as not having it.
      const db = testEnv.authenticatedContext(AWAY_ADMIN).firestore();
      await assertSucceeds(getDoc(eventRef(db, '0000000001')));
    });

    it('refuses an uninvolved club reading the fixture', async () => {
      const db = testEnv.authenticatedContext(THIRD_ADMIN).firestore();
      await assertFails(getDoc(fixRef(db)));
    });

    it('refuses a signed-out stranger reading an unlisted inter-club fixture', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(getDoc(fixRef(db)));
    });

    it("lets the visiting club's assigned scorer append an event", async () => {
      const db = testEnv.authenticatedContext(AWAY_SCORER).firestore();
      await assertSucceeds(
        setDoc(eventRef(db, '0000000002'), {
          seq: 2,
          byUid: AWAY_SCORER,
          at: serverTimestamp(),
          clientEventId: 'c2',
          type: 'raid',
        }),
      );
    });

    it("refuses the visiting club's admin appending an event they are not assigned to", async () => {
      // AWAY_ADMIN is an admin of a participating club but is NOT on
      // scorerUids. The participant grant widens who may be assigned, never
      // who may score unassigned.
      const db = testEnv.authenticatedContext(AWAY_ADMIN).firestore();
      await assertFails(
        setDoc(eventRef(db, '0000000003'), {
          seq: 3,
          byUid: AWAY_ADMIN,
          at: serverTimestamp(),
          clientEventId: 'c3',
          type: 'raid',
        }),
      );
    });

    it("lets the visiting club's scorer advance the live score projection", async () => {
      const db = testEnv.authenticatedContext(AWAY_SCORER).firestore();
      await assertSucceeds(
        updateDoc(fixRef(db), { lastSeq: 1, summary: '4-2', status: 'live' }),
      );
    });

    it('refuses anyone rewriting participantOrgIds on the fixture', async () => {
      // The escalation this guards: stapling your own org onto someone else's
      // match to read it. Even the host admin cannot do it.
      const db = testEnv.authenticatedContext(HOME_ADMIN).firestore();
      await assertFails(
        updateDoc(fixRef(db), { participantOrgIds: [HOME, THIRD], lastSeq: 1 }),
      );
    });

    it('refuses anyone rewriting participantOrgIds on the competition', async () => {
      const db = testEnv.authenticatedContext(HOME_ADMIN).firestore();
      await assertFails(
        updateDoc(compRef(db), { participantOrgIds: [HOME, THIRD] }),
      );
    });

    it('refuses an uninvolved admin adding themselves as a participant', async () => {
      const db = testEnv.authenticatedContext(THIRD_ADMIN).firestore();
      await assertFails(
        updateDoc(compRef(db), { participantOrgIds: [HOME, THIRD] }),
      );
    });

    it('lets either club accept or decline the challenge doc, but not a bystander', async () => {
      const away = testEnv.authenticatedContext(AWAY_ADMIN).firestore();
      const third = testEnv.authenticatedContext(THIRD_ADMIN).firestore();
      await assertSucceeds(updateDoc(doc(away, 'challenges', CHALLENGE), { status: 'declined' }));
      await assertFails(updateDoc(doc(third, 'challenges', CHALLENGE), { status: 'accepted' }));
    });
  });
});

// ---------------------------------------------------------------------------
// Memories — the access-controlled reference to a Cloud Storage object.
//
// Storage rules cannot read Firestore, so an object is only as private as its
// path is unguessable and being listed here is the only way to learn that path.
// That makes these rules the real access control for match media: what they
// permit is what is discoverable.
// ---------------------------------------------------------------------------
describe('match memories', () => {
  const MEMBER = 'uid_member';
  const OTHER_MEMBER = 'uid_member2';
  const COMP = 'comp1';
  const FIX = 'fx1';
  const MEM = 'mem1';

  const memoryDoc = (uploaderUid, extra = {}) => ({
    orgId: PUBLIC_ORG,
    compId: COMP,
    fixtureId: FIX,
    uploaderUid,
    storagePath: `memories/${PUBLIC_ORG}/${FIX}/${uploaderUid}/${MEM}.jpg`,
    url: 'https://example.test/a.jpg',
    kind: 'photo',
    // Derived from the club, not chosen: PUBLIC_ORG is a public club.
    audience: 'public',
    caption: 'Winning raid',
    taggedUids: [MEMBER],
    width: 1600,
    height: 1200,
    sizeBytes: 240000,
    createdAt: serverTimestamp(),
    ...extra,
  });

  const memPath = ['orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FIX, 'memories', MEM];

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER), membership(OWNER, PUBLIC_ORG, 'owner'));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN), membership(ADMIN, PUBLIC_ORG, 'admin'));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', MEMBER), membership(MEMBER, PUBLIC_ORG, 'member'));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', OTHER_MEMBER), membership(OTHER_MEMBER, PUBLIC_ORG, 'member'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FIX),
        fixture(PUBLIC_ORG, COMP, [ADMIN]),
      );
    });
  });

  it('lets a plain member add a memory — the camera is not the scorebook', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(setDoc(doc(db, ...memPath), memoryDoc(MEMBER)));
  });

  it('refuses uploading under someone else’s uid', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(setDoc(doc(db, ...memPath), memoryDoc(OTHER_MEMBER)));
  });

  it('refuses an outsider adding a memory to a public org’s match', async () => {
    // Readable does not imply writable: a public club's matches are watchable
    // by anyone, but only members may attach media to them.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, ...memPath), memoryDoc(OUTSIDER)));
  });

  it('refuses a tag list over the cap', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    const tooMany = Array.from({ length: 31 }, (_, i) => `uid_${i}`);
    await assertFails(
      setDoc(doc(db, ...memPath), memoryDoc(MEMBER, { taggedUids: tooMany })),
    );
  });

  it('refuses a client-stamped createdAt', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      setDoc(doc(db, ...memPath), memoryDoc(MEMBER, { createdAt: new Date(2020, 0, 1) })),
    );
  });

  it('refuses a memory claiming to belong to a different fixture', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      setDoc(doc(db, ...memPath), memoryDoc(MEMBER, { fixtureId: 'fx_elsewhere' })),
    );
  });

  describe('once a memory exists', () => {
    beforeEach(async () => {
      await seed(async (db) => {
        await setDoc(doc(db, ...memPath), memoryDoc(MEMBER));
      });
    });

    it('is readable by anyone for a public org', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(getDoc(doc(db, ...memPath)));
    });

    it('lets the uploader edit the caption', async () => {
      const db = testEnv.authenticatedContext(MEMBER).firestore();
      await assertSucceeds(updateDoc(doc(db, ...memPath), { caption: 'Better words' }));
    });

    it('refuses another member editing the caption', async () => {
      const db = testEnv.authenticatedContext(OTHER_MEMBER).firestore();
      await assertFails(updateDoc(doc(db, ...memPath), { caption: 'Not mine' }));
    });

    it('refuses the uploader repointing the bytes', async () => {
      // The whole record would otherwise be able to lie: same caption, same
      // timestamp, different photo.
      const db = testEnv.authenticatedContext(MEMBER).firestore();
      await assertFails(
        updateDoc(doc(db, ...memPath), { url: 'https://example.test/swapped.jpg' }),
      );
    });

    it('lets the uploader delete their own memory', async () => {
      const db = testEnv.authenticatedContext(MEMBER).firestore();
      await assertSucceeds(deleteDoc(doc(db, ...memPath)));
    });

    it('lets an organizer moderate anyone’s memory', async () => {
      // The subject of an unwanted photo is rarely the person who posted it, so
      // removal cannot depend on the uploader cooperating.
      const db = testEnv.authenticatedContext(ADMIN).firestore();
      await assertSucceeds(deleteDoc(doc(db, ...memPath)));
    });

    it('refuses an unrelated member deleting it', async () => {
      const db = testEnv.authenticatedContext(OTHER_MEMBER).firestore();
      await assertFails(deleteDoc(doc(db, ...memPath)));
    });
  });
});

// ---------------------------------------------------------------------------
// Career stats — now that clubsPlayedFor is actually persisted.
// ---------------------------------------------------------------------------
describe('career stats clubsPlayedFor', () => {
  // The clubs timeline is part of the career document, which is now written
  // only by `onMatchSettled`. The client cannot append to it any more than it
  // can set a rating — the trigger derives it from the fixture's own orgId.
  it('a client cannot append to its own clubs timeline', async () => {
    const path = `users/${OWNER}/career_stats/badminton`;
    await seed(async (db) => {
      await setDoc(doc(db, path), {
        uid: OWNER,
        sportId: 'badminton',
        matchesPlayed: 1,
        clubsPlayedFor: [PUBLIC_ORG],
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, path), { clubsPlayedFor: [PUBLIC_ORG, PRIVATE_ORG] }),
    );
  });
});

// ---------------------------------------------------------------------------
// Collection-group query over memories — the photo grid on a career profile.
//
// A rule at the nested memories path does NOT apply to a
// collectionGroup('memories') query. Without a /{path=**}/memories block,
// MemoryRepository.watchPlayerMemories was permission-denied for everyone and
// every profile's Memories section was permanently empty.
// ---------------------------------------------------------------------------
describe('memories collection-group query', () => {
  const TAGGED = 'uid_tagged_player';
  const COMP = 'comp_mem';

  const memoryDoc = (orgId, fixtureId, audience, extra = {}) => ({
    orgId,
    compId: COMP,
    fixtureId,
    uploaderUid: OWNER,
    storagePath: `memories/${orgId}/${fixtureId}/${OWNER}/m.jpg`,
    url: 'https://example.test/a.jpg',
    kind: 'photo',
    audience,
    caption: null,
    taggedUids: [TAGGED],
    createdAt: serverTimestamp(),
    ...extra,
  });

  /// Exactly the query MemoryRepository.watchPlayerMemories builds: the
  /// audiences the caller is entitled to, stated up front, because a
  /// collection-group `list` is authorized against the query's constraints
  /// rather than against the documents it returns.
  const profileGrid = (db, audiences) =>
    getDocs(
      query(
        collectionGroup(db, 'memories'),
        where('taggedUids', 'array-contains', TAGGED),
        where('audience', 'in', audiences),
      ),
    );

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(doc(db, 'orgs', PRIVATE_ORG), organization(OWNER, 'unlisted'));
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'members', ADMIN),
        membership(ADMIN, PRIVATE_ORG, 'admin'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', 'fx_pub'),
        fixture(PUBLIC_ORG, COMP, [SCORER]),
      );
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'competitions', COMP, 'fixtures', 'fx_priv'),
        fixture(PRIVATE_ORG, COMP, [SCORER]),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', 'fx_pub', 'memories', 'm1'),
        memoryDoc(PUBLIC_ORG, 'fx_pub', 'public'),
      );
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'competitions', COMP, 'fixtures', 'fx_priv', 'memories', 'm2'),
        memoryDoc(PRIVATE_ORG, 'fx_priv', PRIVATE_ORG),
      );
    });
  });

  it('lets a member load every memory they are entitled to, across orgs', async () => {
    // The regression this whole block exists for: before the
    // /{path=**}/memories rule this was permission-denied for everyone and
    // every profile's Memories section was empty no matter what was in it.
    // The member of the unlisted club sees both — the public one because it
    // is public, their own club's because they belong to it.
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    const snap = await assertSucceeds(profileGrid(db, ['public', PRIVATE_ORG]));
    assert.equal(snap.size, 2);
  });

  it('lets a signed-out spectator see the public club\'s memories', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    const snap = await assertSucceeds(profileGrid(db, ['public']));
    assert.equal(snap.size, 1);
  });

  it('refuses an outsider asking for an UNLISTED club\'s memories', async () => {
    // Claiming an audience is not the same as holding it: the rule checks the
    // caller's real membership document for that club.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(profileGrid(db, ['public', PRIVATE_ORG]));
  });

  it('refuses an unconstrained sweep of every memory in the database', async () => {
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(getDocs(query(collectionGroup(db, 'memories'))));
  });

  // -------------------------------------------------------------------------
  // The CLUB GALLERY reads the same collection group with a different
  // constraint, and that difference broke it.
  //
  // `watchClubMemories` asks for one club's memories ordered by date, so it
  // constrains `orgId` and never mentions `audience`. A `list` is authorized
  // against the query rather than against the documents it returns, which
  // made `resource.data.audience` undefined — an evaluation error — in both
  // of the rule's original branches at once, with nothing left to rescue
  // them. Every club gallery was permission-denied ("Property audience is
  // undefined on object") regardless of how many photos the club had.
  // -------------------------------------------------------------------------
  const clubGallery = (db, orgId) =>
    getDocs(
      query(
        collectionGroup(db, 'memories'),
        where('orgId', '==', orgId),
        orderBy('createdAt', 'desc'),
        limit(120),
      ),
    );

  it('lets anyone open a PUBLIC club\'s gallery', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(clubGallery(db, PUBLIC_ORG));
    assert.equal(snap.size, 1);
  });

  it('lets a member open their UNLISTED club\'s gallery', async () => {
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    const snap = await assertSucceeds(clubGallery(db, PRIVATE_ORG));
    assert.equal(snap.size, 1);
  });

  it('refuses an outsider opening an UNLISTED club\'s gallery', async () => {
    // The orgId branch must not be a way around the membership check the
    // audience branches enforce — it grants exactly the same thing.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(clubGallery(db, PRIVATE_ORG));
  });

  it('refuses an uploader stamping an unlisted club\'s memory as public', async () => {
    // The audience is derived from the club document on the way in, so it is
    // not a field an uploader can use to promote a junior match's photos onto
    // a world-readable profile grid.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PRIVATE_ORG, 'member'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'competitions', COMP, 'fixtures', 'fx_priv', 'memories', 'm3'),
        memoryDoc(PRIVATE_ORG, 'fx_priv', 'public', { uploaderUid: OUTSIDER }),
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// profileVisibility: 'community' — the DEFAULT for every new account.
//
// The rules had no branch for it at all: only 'public' granted a cross-user
// read, so out of the box nobody could open anybody else's profile. There is
// no member directory, no opponent's record and no career page without this.
// ---------------------------------------------------------------------------
describe('profile visibility: community', () => {
  const SUBJECT = 'uid_community_subject';
  const CLUBMATE = 'uid_community_clubmate';

  const profileOf = (uid, orgIds, overrides = {}) => ({
    uid,
    displayName: 'Test Person',
    email: 'test@example.com',
    dateOfBirth: new Date('1995-04-11'),
    gender: 'female',
    photoUrl: null,
    phone: null,
    profileVisibility: 'community',
    profileComplete: true,
    isMinor: false,
    orgIds,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SUBJECT),
        membership(SUBJECT, PUBLIC_ORG, 'member'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CLUBMATE),
        membership(CLUBMATE, PUBLIC_ORG, 'member'),
      );
    });
  });

  it('lets a club-mate open a community profile', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', SUBJECT), profileOf(SUBJECT, [PUBLIC_ORG]));
    });
    const db = testEnv.authenticatedContext(CLUBMATE).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('refuses a stranger with no shared club', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', SUBJECT), profileOf(SUBJECT, [PUBLIC_ORG]));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('refuses somebody whose membership is still PENDING approval', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', SUBJECT), profileOf(SUBJECT, [PUBLIC_ORG]));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member', 'pending'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('refuses a club-mate when the mirror has not been written yet', async () => {
    // Fails closed: a profile with no `orgIds` is readable only by its owner,
    // which is the pre-fix behaviour and the safe direction.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', SUBJECT), profileOf(SUBJECT, []));
    });
    const db = testEnv.authenticatedContext(CLUBMATE).firestore();
    await assertFails(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('gives a padded mirror nothing: the CALLER still needs a real membership', async () => {
    // The mirror is written by the profile's owner, so the only thing an
    // inflated list can do is offer the profile to clubs the owner is not in
    // — and the rule still demands a genuine active membership document from
    // whoever is reading.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', SUBJECT),
        profileOf(SUBJECT, ['org_never_joined', 'org_also_fake']),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('never opens a MINOR\'s profile to a club-mate', async () => {
    // The adult floor is not a visibility preference. A junior's profile is
    // reachable only by its owner and by a guardian-consented scout,
    // whatever the setting says.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', SUBJECT),
        profileOf(SUBJECT, [PUBLIC_ORG], {
          dateOfBirth: new Date('2012-01-01'),
          isMinor: true,
        }),
      );
    });
    const db = testEnv.authenticatedContext(CLUBMATE).firestore();
    await assertFails(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('still refuses a club-mate when the owner chose private', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', SUBJECT),
        profileOf(SUBJECT, [PUBLIC_ORG], { profileVisibility: 'private' }),
      );
    });
    const db = testEnv.authenticatedContext(CLUBMATE).firestore();
    await assertFails(getDoc(doc(db, 'users', SUBJECT)));
  });

  it('lets the owner write their own club mirror, but not an unbounded one', async () => {
    const db = testEnv.authenticatedContext(SUBJECT).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', SUBJECT), profileOf(SUBJECT, [PUBLIC_ORG])),
    );
    const tooMany = Array.from({ length: 51 }, (_, i) => `org_${i}`);
    await assertFails(
      setDoc(
        doc(db, 'users', SUBJECT),
        profileOf(SUBJECT, tooMany),
        { merge: true },
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// The global rulebook. `allow write: if isSignedIn()` made the ICC's laws
// world-writable and world-deletable by any account in the country.
// ---------------------------------------------------------------------------
describe('sportRules: the global rulebook is not client-writable', () => {
  const rulePath = ['sportRules', 'cricket_no_ball'];

  const ruleDoc = (overrides = {}) => ({
    sportId: 'cricket',
    category: 'Bowling',
    title: 'No ball',
    description: 'The official law.',
    officialSource: 'ICC',
    keywords: ['no ball'],
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...rulePath), ruleDoc());
    });
  });

  it('stays world-readable, with or without an account', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, ...rulePath)));
  });

  it('refuses a signed-in stranger defacing a rule', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, ...rulePath), ruleDoc({ description: 'anything I like' })),
    );
  });

  it('refuses a signed-in stranger DELETING a rule', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(deleteDoc(doc(db, ...rulePath)));
  });

  it('refuses even a club owner — the rulebook is not any club\'s to edit', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, ...rulePath), ruleDoc({ title: 'Rewritten' })),
    );
  });

  it('admits a holder of the admin claim, which no app path can mint', async () => {
    // The documented escape hatch: an operator with an admin custom claim, or
    // the console/admin SDK. Nothing in the client can produce this token.
    const db = testEnv
      .authenticatedContext('uid_operator', { admin: true })
      .firestore();
    await assertSucceeds(
      setDoc(doc(db, ...rulePath), ruleDoc({ description: 'Corrected text.' })),
    );
  });
});

// ---------------------------------------------------------------------------
// Cloud Storage rules — a separate ruleset with separate blind spots.
//
// Storage rules cannot read Firestore, so authorization here comes from the
// path plus the caller's uid and nothing else. That is exactly why the club
// logo path was a hole: `orgs/{orgId}/logo/{fileName}` is fully guessable from
// an org id, and `write: if isSignedIn()` let any account in the world
// overwrite or delete a school's logo.
// ---------------------------------------------------------------------------
describe('storage: club logos', () => {
  const ORG_OWNER = 'uid_logo_owner';
  const STRANGER = 'uid_logo_stranger';
  const logoPath = (uid) => `orgs/${PUBLIC_ORG}/logo/${uid}/logo.jpg`;

  it('lets a signed-in user write a logo under their OWN uid segment', async () => {
    const storage = testEnv.authenticatedContext(ORG_OWNER).storage();
    await assertSucceeds(
      storage.ref(logoPath(ORG_OWNER)).put(jpegBytes(), imageMeta),
    );
  });

  it('refuses a stranger overwriting somebody else\'s logo object', async () => {
    // The exploit: the path is deterministic, so before the uid segment
    // existed this succeeded for any account and defaced the club.
    const storage = testEnv.authenticatedContext(STRANGER).storage();
    await assertFails(
      storage.ref(logoPath(ORG_OWNER)).put(jpegBytes(), imageMeta),
    );
  });

  it('refuses a stranger DELETING somebody else\'s logo object', async () => {
    const owner = testEnv.authenticatedContext(ORG_OWNER).storage();
    await assertSucceeds(
      owner.ref(logoPath(ORG_OWNER)).put(jpegBytes(), imageMeta),
    );

    const stranger = testEnv.authenticatedContext(STRANGER).storage();
    await assertFails(stranger.ref(logoPath(ORG_OWNER)).delete());
  });

  it('refuses a signed-out visitor writing a logo at all', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      storage.ref(logoPath(ORG_OWNER)).put(jpegBytes(), imageMeta),
    );
  });

  it('refuses the old uid-less path, which is now matched by nothing', async () => {
    const storage = testEnv.authenticatedContext(ORG_OWNER).storage();
    await assertFails(
      storage
        .ref(`orgs/${PUBLIC_ORG}/logo/logo.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });
});

describe('storage: profile photos and memories still work', () => {
  const ME = 'uid_storage_me';
  const SOMEBODY_ELSE = 'uid_storage_other';

  it('lets a player replace their own profile photo', async () => {
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertSucceeds(
      storage.ref(`users/${ME}/profile/avatar.jpg`).put(jpegBytes(), imageMeta),
    );
  });

  it('refuses replacing another player\'s face', async () => {
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertFails(
      storage
        .ref(`users/${SOMEBODY_ELSE}/profile/avatar.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });

  it('lets an uploader add a memory under their own uid segment', async () => {
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertSucceeds(
      storage
        .ref(`memories/${PUBLIC_ORG}/fx1/${ME}/mem1.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });

  it('refuses uploading a memory under somebody else\'s uid segment', async () => {
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertFails(
      storage
        .ref(`memories/${PUBLIC_ORG}/fx1/${SOMEBODY_ELSE}/mem1.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });
});

// ---------------------------------------------------------------------------
// Participation models — "the first thirteen who register are the team"
//
// The promise is about a COUNT, and a count is the one thing a client cannot
// be trusted with. These tests go at the rules directly, with no app in the
// way, because that is exactly the position a determined client is in.
// ---------------------------------------------------------------------------

const PLAYER = 'uid_player';
const PLAYER_TWO = 'uid_player_two';

/** A competition document as `Competition.toCreate` writes it. */
const competition = (orgId, overrides = {}) => ({
  orgId,
  name: 'Sunday Cricket',
  nameLower: 'sunday cricket',
  sportId: 'cricket',
  sportName: 'Cricket',
  archetype: 'versus',
  entrantType: 'individual',
  format: 'knockout',
  status: 'registration_open',
  category: { label: 'Open', dimensions: ['open'] },
  scoringPluginKey: 'cricket',
  description: null,
  venue: null,
  startDate: null,
  endDate: null,
  registrationClosesAt: null,
  maxEntrants: 13,
  entrantCount: 0,
  fixtureCount: 0,
  participationModel: 'open',
  preselectedSlots: 0,
  waitlistEnabled: true,
  openToNonMembers: false,
  entryFeeRupees: 0,
  teamSize: null,
  rulesNote: null,
  confirmedCount: 0,
  waitlistCount: 0,
  verificationTier: 'casual',
  rulesetVersion: 1,
  pointsForWin: 3,
  pointsForDraw: 1,
  pointsForLoss: 0,
  tiebreakChain: null,
  participantOrgIds: null,
  createdBy: OWNER,
  createdAt: serverTimestamp(),
  ...overrides,
});

/** A registration as `Registration.toCreate` writes it. */
const registration = (uid, status, overrides = {}) => ({
  uid,
  displayName: 'Test Player',
  photoUrl: null,
  teamName: null,
  status,
  waitlistPosition: null,
  preselected: false,
  eligibilityNote: null,
  createdAt: serverTimestamp(),
  ...overrides,
});

/** Seeds an org with an active member, plus a competition. */
async function seedEvent(overrides = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
      membership(OWNER, PUBLIC_ORG, 'owner'),
    );
    for (const uid of [PLAYER, PLAYER_TWO]) {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', uid),
        membership(uid, PUBLIC_ORG, 'member'),
      );
    }
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1'),
      competition(PUBLIC_ORG, overrides),
    );
  });
}

const regRef = (db, uid) =>
  doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'registrations', uid);
const compRef = (db) => doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1');

describe('participation: open registration confirms itself while a slot is free', () => {
  it('lets a member confirm themselves into an open event', async () => {
    await seedEvent({ participationModel: 'open', confirmedCount: 0 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertSucceeds(batch.commit());
  });

  it('refuses a self-confirmation once the field is full', async () => {
    await seedEvent({ participationModel: 'open', confirmedCount: 13 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 14 });
    await assertFails(batch.commit());
  });

  it('refuses a confirmation that does not move the counter at all', async () => {
    // Otherwise capacity is enforced against a number nobody increments, and
    // fourteen people each read "12 confirmed" and each write themselves in.
    await seedEvent({ participationModel: 'open', confirmedCount: 12 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(regRef(db, PLAYER), registration(PLAYER, 'confirmed')),
    );
  });

  it('refuses a counter bump of more than one', async () => {
    await seedEvent({ participationModel: 'open', confirmedCount: 0 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 5 });
    await assertFails(batch.commit());
  });

  it('refuses a member editing anything else on the competition', async () => {
    await seedEvent({ participationModel: 'open', confirmedCount: 0 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1, maxEntrants: 999 });
    await assertFails(batch.commit());
  });
});

describe('participation: the waitlist', () => {
  it('queues a member once the open slots are gone', async () => {
    await seedEvent({
      participationModel: 'open',
      confirmedCount: 13,
      waitlistEnabled: true,
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(
      regRef(db, PLAYER),
      registration(PLAYER, 'waitlisted', { waitlistPosition: 1 }),
    );
    batch.update(compRef(db), { waitlistCount: 1 });
    await assertSucceeds(batch.commit());
  });

  it('refuses a waitlist entry when the organizer did not enable one', async () => {
    await seedEvent({
      participationModel: 'open',
      confirmedCount: 13,
      waitlistEnabled: false,
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'waitlisted'));
    batch.update(compRef(db), { waitlistCount: 1 });
    await assertFails(batch.commit());
  });

  it('refuses waitlisting while slots are still open', async () => {
    // A reserve who is really in the team is a reserve nobody called up.
    await seedEvent({ participationModel: 'open', confirmedCount: 2 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'waitlisted'));
    batch.update(compRef(db), { waitlistCount: 1 });
    await assertFails(batch.commit());
  });

  it('promotes the first reserve into a slot a withdrawal has freed', async () => {
    await seedEvent({
      participationModel: 'open',
      confirmedCount: 12,
      waitlistCount: 1,
    });
    await seed(async (db) => {
      await setDoc(
        regRef(db, PLAYER_TWO),
        registration(PLAYER_TWO, 'waitlisted', { waitlistPosition: 1 }),
      );
    });

    // The withdrawal has already committed, which is why a slot is free — the
    // promotion is deliberately a SECOND transaction, because rules evaluate
    // against pre-transaction state and the event was full until it landed.
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const batch = writeBatch(db);
    batch.update(regRef(db, PLAYER_TWO), {
      status: 'confirmed',
      waitlistPosition: null,
      promotedFromWaitlistAt: serverTimestamp(),
    });
    batch.update(compRef(db), { confirmedCount: 13, waitlistCount: 0 });
    await assertSucceeds(batch.commit());
  });

  it('refuses a promotion into an event that is still full', async () => {
    await seedEvent({
      participationModel: 'open',
      confirmedCount: 13,
      waitlistCount: 1,
    });
    await seed(async (db) => {
      await setDoc(
        regRef(db, PLAYER_TWO),
        registration(PLAYER_TWO, 'waitlisted', { waitlistPosition: 1 }),
      );
    });

    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const batch = writeBatch(db);
    batch.update(regRef(db, PLAYER_TWO), { status: 'confirmed' });
    batch.update(compRef(db), { confirmedCount: 14, waitlistCount: 0 });
    await assertFails(batch.commit());
  });

  it('refuses a member promoting someone straight past the queue into a changed row', async () => {
    // The promotion branch is fenced to status/position/timestamp. It must not
    // become a way to edit another player's registration generally.
    await seedEvent({ participationModel: 'open', confirmedCount: 0 });
    await seed(async (db) => {
      await setDoc(
        regRef(db, PLAYER_TWO),
        registration(PLAYER_TWO, 'waitlisted', { waitlistPosition: 1 }),
      );
    });

    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      updateDoc(regRef(db, PLAYER_TWO), {
        status: 'confirmed',
        displayName: 'Renamed By Someone Else',
      }),
    );
  });
});

describe('participation: hybrid and approval', () => {
  it('refuses a self-confirmation into the organizer reserved block', async () => {
    // 13 capacity, 8 reserved -> only 5 are open. The sixth must not get in.
    await seedEvent({
      participationModel: 'hybrid',
      preselectedSlots: 8,
      confirmedCount: 5,
      waitlistEnabled: false,
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 6 });
    await assertFails(batch.commit());
  });

  it('lets the fifth open registrant into a hybrid event', async () => {
    await seedEvent({
      participationModel: 'hybrid',
      preselectedSlots: 8,
      confirmedCount: 4,
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 5 });
    await assertSucceeds(batch.commit());
  });

  it('refuses a self-confirmation into an approval event', async () => {
    await seedEvent({ participationModel: 'approval', confirmedCount: 0 });
    const db = testEnv.authenticatedContext(PLAYER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, PLAYER), registration(PLAYER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertFails(batch.commit());
  });

  it('still accepts a plain application to an approval event', async () => {
    await seedEvent({ participationModel: 'approval' });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      setDoc(regRef(db, PLAYER), registration(PLAYER, 'pending')),
    );
  });

  it('refuses a member marking their own entry as an organizer pick', async () => {
    await seedEvent({ participationModel: 'approval' });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(
        regRef(db, PLAYER),
        registration(PLAYER, 'confirmed', { preselected: true }),
      ),
    );
  });

  it('lets an organizer preselect a player directly', async () => {
    await seedEvent({ participationModel: 'hybrid', preselectedSlots: 8 });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(
        regRef(db, PLAYER),
        registration(PLAYER, 'confirmed', { preselected: true }),
      ),
    );
  });
});

describe('participation: events created before the model existed', () => {
  it('still accepts a pending application with no participation fields', async () => {
    // Every event already in the database lacks these fields. Reading a
    // missing field in a rule is an ERROR, which denies — so without the
    // `.get(field, default)` accessors this shipping change would have broken
    // registration for every existing event.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', PLAYER),
        membership(PLAYER, PUBLIC_ORG, 'member'),
      );
      const legacy = competition(PUBLIC_ORG);
      delete legacy.participationModel;
      delete legacy.preselectedSlots;
      delete legacy.waitlistEnabled;
      delete legacy.confirmedCount;
      delete legacy.waitlistCount;
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1'),
        legacy,
      );
    });

    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const legacyReg = registration(PLAYER, 'pending');
    delete legacyReg.preselected;
    delete legacyReg.waitlistPosition;
    await assertSucceeds(setDoc(regRef(db, PLAYER), legacyReg));
  });

  it('refuses a self-confirmation into a legacy event', async () => {
    // A legacy event defaults to `approval`, which is the behaviour it always
    // had. Anything else would retroactively admit an unvetted queue.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', PLAYER),
        membership(PLAYER, PUBLIC_ORG, 'member'),
      );
      const legacy = competition(PUBLIC_ORG);
      delete legacy.participationModel;
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1'),
        legacy,
      );
    });

    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(regRef(db, PLAYER), registration(PLAYER, 'confirmed')),
    );
  });
});

// ---------------------------------------------------------------------------
// Inter-club squads — ABC challenges XYZ, and XYZ picks its OWN players.
//
// A challenge fixture lives inside the HOSTING club's tenant, so every
// pre-existing write path was anchored to authority there. These tests pin
// the branch that lets the visiting club name its own side without letting
// either club name the other's.
// ---------------------------------------------------------------------------

const HOST_ORG = 'org_host';
const GUEST_ORG = 'org_guest';
const HOST_ADMIN = 'uid_host_admin';
const GUEST_ADMIN = 'uid_guest_admin';

const challengeFixtureDoc = (overrides = {}) => ({
  orgId: HOST_ORG,
  compId: 'comp_challenge',
  // For a challenge, the entrant ids ARE the clubs' ids. That is what makes
  // "which side is mine" answerable from the fixture alone.
  entrantAId: GUEST_ORG,
  entrantBId: HOST_ORG,
  entrantAName: 'Guest Club',
  entrantBName: 'Host Club',
  status: 'scheduled',
  round: 1,
  matchIndex: 0,
  roundLabel: 'Challenge',
  scheduledAt: null,
  venue: null,
  scorerUids: [HOST_ADMIN],
  participantOrgIds: [GUEST_ORG, HOST_ORG],
  officials: [],
  scoreState: {},
  summary: '',
  lastSeq: 0,
  winnerEntrantId: null,
  isDraw: false,
  rulesetVersion: 1,
  scoringPluginKey: 'cricket',
  sportId: 'cricket',
  scoringConfig: {},
  lineupA: [],
  lineupB: [],
  squadLockedA: false,
  squadLockedB: false,
  createdAt: serverTimestamp(),
  ...overrides,
});

async function seedChallenge(overrides = {}) {
  await seed(async (db) => {
    for (const [orgId, admin] of [
      [HOST_ORG, HOST_ADMIN],
      [GUEST_ORG, GUEST_ADMIN],
    ]) {
      await setDoc(doc(db, 'orgs', orgId), organization(admin, 'public'));
      await setDoc(
        doc(db, 'orgs', orgId, 'members', admin),
        membership(admin, orgId, 'owner'),
      );
    }
    await setDoc(
      doc(db, 'orgs', HOST_ORG, 'competitions', 'comp_challenge'),
      competition(HOST_ORG, {
        participantOrgIds: [GUEST_ORG, HOST_ORG],
        status: 'scheduled',
      }),
    );
    await setDoc(
      doc(
        db, 'orgs', HOST_ORG, 'competitions', 'comp_challenge',
        'fixtures', 'fx_challenge',
      ),
      challengeFixtureDoc(overrides),
    );
  });
}

const fixRef = (db) =>
  doc(
    db, 'orgs', HOST_ORG, 'competitions', 'comp_challenge',
    'fixtures', 'fx_challenge',
  );

const squad = (uid, name) => [{ id: uid, name, uid, isGuest: false }];

describe('inter-club: each club picks its own squad', () => {
  it('lets the VISITING club name side A', async () => {
    // This is the case that did not work at all before: the guest club has no
    // authority in the host's tenant, which is where the fixture lives.
    await seedChallenge();
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertSucceeds(
      updateDoc(fixRef(db), {
        lineupA: squad('u_guest', 'Guest Player'),
        playerUids: ['u_guest'],
      }),
    );
  });

  it('refuses the visiting club naming the HOST club players', async () => {
    await seedChallenge();
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertFails(
      updateDoc(fixRef(db), {
        lineupB: squad('u_host', 'Host Player'),
        playerUids: ['u_host'],
      }),
    );
  });

  it('refuses the visiting club touching the score under cover of a squad write', async () => {
    await seedChallenge();
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertFails(
      updateDoc(fixRef(db), {
        lineupA: squad('u_guest', 'Guest Player'),
        playerUids: ['u_guest'],
        lastSeq: 99,
        summary: 'Guest Club won',
      }),
    );
  });

  it('refuses an unrelated club touching either squad', async () => {
    await seedChallenge();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(fixRef(db), { lineupA: squad('u_x', 'Nobody') }),
    );
  });
});

describe('inter-club: locking a final squad', () => {
  it('lets a club lock its own side', async () => {
    await seedChallenge();
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertSucceeds(
      updateDoc(fixRef(db), {
        lineupA: squad('u_guest', 'Guest Player'),
        playerUids: ['u_guest'],
        squadLockedA: true,
      }),
    );
  });

  it('freezes a locked squad against the club that locked it', async () => {
    await seedChallenge({ squadLockedA: true });
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertFails(
      updateDoc(fixRef(db), { lineupA: squad('u_late', 'Late Change') }),
    );
  });

  it('freezes a locked squad against the HOSTING club too', async () => {
    // The host has broad authority over a fixture in its own tenant. A squad
    // the other club has declared final is the one thing that authority must
    // not reach — otherwise "lock your final squad" means nothing.
    await seedChallenge({ squadLockedA: true });
    const db = testEnv.authenticatedContext(HOST_ADMIN).firestore();
    await assertFails(
      updateDoc(fixRef(db), { lineupA: squad('u_swapped', 'Swapped In') }),
    );
  });

  it('lets the locking club reopen its own squad', async () => {
    await seedChallenge({ squadLockedA: true });
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertSucceeds(updateDoc(fixRef(db), { squadLockedA: false }));
  });

  it('refuses the host unlocking the visiting club squad', async () => {
    await seedChallenge({ squadLockedA: true });
    const db = testEnv.authenticatedContext(HOST_ADMIN).firestore();
    await assertFails(updateDoc(fixRef(db), { squadLockedA: false }));
  });

  it('refuses an unlock that smuggles a changed team past the opponent', async () => {
    await seedChallenge({
      squadLockedA: true,
      lineupA: squad('u_agreed', 'Agreed Player'),
    });
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertFails(
      updateDoc(fixRef(db), {
        squadLockedA: false,
        lineupA: squad('u_ringer', 'Ringer'),
      }),
    );
  });

  it('leaves an ordinary internal fixture unaffected', async () => {
    // Entrants there are houses, not clubs, and the hosting club's organizers
    // run both sides exactly as before.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1'),
        competition(PUBLIC_ORG),
      );
      await setDoc(
        doc(
          db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1',
          'fixtures', 'fx1',
        ),
        fixture(PUBLIC_ORG, 'comp1', [OWNER], 'scheduled'),
      );
    });

    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(
        doc(
          db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1',
          'fixtures', 'fx1',
        ),
        {
          lineupA: squad('u1', 'Blue Player'),
          lineupB: squad('u2', 'Red Player'),
          playerUids: ['u1', 'u2'],
        },
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Squad calls — "the first eleven of OUR members who register are playing".
//
// The per-side mirror of the participation model, and the half of flow step 6
// that was missing: a challenged club opening its own side to its own members
// instead of its admin naming eleven people by hand.
// ---------------------------------------------------------------------------

const GUEST_MEMBER = 'uid_guest_member';
const HOST_MEMBER = 'uid_host_member';

const squadCall = (over = {}) => ({
  open: true,
  capacity: 11,
  confirmed: 0,
  waitlisted: 0,
  waitlistEnabled: true,
  ...over,
});

async function seedSquadCall({ callA = squadCall(), callB = squadCall() } = {}) {
  await seed(async (db) => {
    for (const [orgId, admin, member] of [
      [HOST_ORG, HOST_ADMIN, HOST_MEMBER],
      [GUEST_ORG, GUEST_ADMIN, GUEST_MEMBER],
    ]) {
      await setDoc(doc(db, 'orgs', orgId), organization(admin, 'public'));
      await setDoc(
        doc(db, 'orgs', orgId, 'members', admin),
        membership(admin, orgId, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', orgId, 'members', member),
        membership(member, orgId, 'member'),
      );
    }
    await setDoc(
      doc(db, 'orgs', HOST_ORG, 'competitions', 'comp_challenge'),
      competition(HOST_ORG, {
        participantOrgIds: [GUEST_ORG, HOST_ORG],
        status: 'scheduled',
      }),
    );
    await setDoc(
      doc(
        db, 'orgs', HOST_ORG, 'competitions', 'comp_challenge',
        'fixtures', 'fx_challenge',
      ),
      challengeFixtureDoc({ squadCallA: callA, squadCallB: callB }),
    );
  });
}

const entryRef = (db, uid) =>
  doc(
    db, 'orgs', HOST_ORG, 'competitions', 'comp_challenge',
    'fixtures', 'fx_challenge', 'squadEntries', uid,
  );

const squadEntry = (uid, orgId, side, status, over = {}) => ({
  uid,
  displayName: 'Squad Member',
  photoUrl: null,
  side,
  orgId,
  status,
  waitlistPosition: null,
  addedByAdmin: false,
  createdAt: serverTimestamp(),
  ...over,
});

describe('squad call: a club opening its own side to its own members', () => {
  it('lets a guest-club member register for the guest club side', async () => {
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
    );
    batch.update(fixRef(db), { squadCallA: squadCall({ confirmed: 1 }) });
    await assertSucceeds(batch.commit());
  });

  it('refuses a member registering for the OTHER club side', async () => {
    // The whole point. A member of ABC cannot put themselves in XYZ's eleven,
    // however they craft the write — the side is checked against the club
    // they are actually active in.
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'b', 'confirmed'),
    );
    batch.update(fixRef(db), { squadCallB: squadCall({ confirmed: 1 }) });
    await assertFails(batch.commit());
  });

  it('refuses a member claiming to belong to a club they are not in', async () => {
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, HOST_ORG, 'b', 'confirmed'),
    );
    batch.update(fixRef(db), { squadCallB: squadCall({ confirmed: 1 }) });
    await assertFails(batch.commit());
  });

  it('refuses an outsider joining either side', async () => {
    await seedSquadCall();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        entryRef(db, OUTSIDER),
        squadEntry(OUTSIDER, GUEST_ORG, 'a', 'confirmed'),
      ),
    );
  });

  it('refuses registering when the club has not opened its side', async () => {
    await seedSquadCall({ callA: squadCall({ open: false }) });
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
    );
    batch.update(fixRef(db), {
      squadCallA: squadCall({ open: false, confirmed: 1 }),
    });
    await assertFails(batch.commit());
  });

  it('refuses confirming into a side that is already full', async () => {
    await seedSquadCall({ callA: squadCall({ confirmed: 11 }) });
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
    );
    batch.update(fixRef(db), { squadCallA: squadCall({ confirmed: 12 }) });
    await assertFails(batch.commit());
  });

  it('queues the twelfth member when the side is full', async () => {
    await seedSquadCall({ callA: squadCall({ confirmed: 11 }) });
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'waitlisted', {
        waitlistPosition: 1,
      }),
    );
    batch.update(fixRef(db), {
      squadCallA: squadCall({ confirmed: 11, waitlisted: 1 }),
    });
    await assertSucceeds(batch.commit());
  });

  it('refuses an entry that does not pay for its place', async () => {
    // Without the getAfter() linkage a member could write eleven confirmed
    // entries and never move the counter, and every one would pass.
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();
    await assertFails(
      setDoc(
        entryRef(db, GUEST_MEMBER),
        squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
      ),
    );
  });

  it('refuses a registrant changing the call itself', async () => {
    // Whether the side is open, and how many places it has, belongs to that
    // club's admins — not to whoever happens to be registering.
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
    );
    batch.update(fixRef(db), {
      squadCallA: squadCall({ confirmed: 1, capacity: 99 }),
    });
    await assertFails(batch.commit());
  });

  it('refuses a registrant touching the other side counters', async () => {
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();

    const batch = writeBatch(db);
    batch.set(
      entryRef(db, GUEST_MEMBER),
      squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
    );
    batch.update(fixRef(db), {
      squadCallA: squadCall({ confirmed: 1 }),
      squadCallB: squadCall({ confirmed: 5 }),
    });
    await assertFails(batch.commit());
  });

  it('lets a club admin add one of their own players directly', async () => {
    await seedSquadCall();
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertSucceeds(
      setDoc(
        entryRef(db, GUEST_MEMBER),
        squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed', {
          addedByAdmin: true,
        }),
      ),
    );
  });

  it('refuses the HOST admin adding a player to the guest club side', async () => {
    await seedSquadCall();
    const db = testEnv.authenticatedContext(HOST_ADMIN).firestore();
    await assertFails(
      setDoc(
        entryRef(db, HOST_MEMBER),
        squadEntry(HOST_MEMBER, GUEST_ORG, 'a', 'confirmed', {
          addedByAdmin: true,
        }),
      ),
    );
  });

  it('lets a member pull out of a squad they joined', async () => {
    await seedSquadCall({ callA: squadCall({ confirmed: 1 }) });
    await seed(async (db) => {
      await setDoc(
        entryRef(db, GUEST_MEMBER),
        squadEntry(GUEST_MEMBER, GUEST_ORG, 'a', 'confirmed'),
      );
    });

    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();
    const batch = writeBatch(db);
    batch.update(entryRef(db, GUEST_MEMBER), {
      status: 'withdrawn',
      waitlistPosition: null,
    });
    batch.update(fixRef(db), { squadCallA: squadCall({ confirmed: 0 }) });
    await assertSucceeds(batch.commit());
  });

  it('refuses a member withdrawing somebody else', async () => {
    await seedSquadCall({ callA: squadCall({ confirmed: 1 }) });
    await seed(async (db) => {
      await setDoc(
        entryRef(db, 'uid_someone_else'),
        squadEntry('uid_someone_else', GUEST_ORG, 'a', 'confirmed'),
      );
    });

    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();
    await assertFails(
      updateDoc(entryRef(db, 'uid_someone_else'), { status: 'withdrawn' }),
    );
  });

  it('promotes the first reserve into a place a withdrawal freed', async () => {
    await seedSquadCall({
      callA: squadCall({ confirmed: 10, waitlisted: 1 }),
    });
    await seed(async (db) => {
      await setDoc(
        entryRef(db, 'uid_reserve'),
        squadEntry('uid_reserve', GUEST_ORG, 'a', 'waitlisted', {
          waitlistPosition: 1,
        }),
      );
    });

    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();
    const batch = writeBatch(db);
    batch.update(entryRef(db, 'uid_reserve'), {
      status: 'confirmed',
      waitlistPosition: null,
      promotedFromWaitlistAt: serverTimestamp(),
    });
    batch.update(fixRef(db), {
      squadCallA: squadCall({ confirmed: 11, waitlisted: 0 }),
    });
    await assertSucceeds(batch.commit());
  });
});

// ---------------------------------------------------------------------------
// Club polls — members answer, without being able to post.
// ---------------------------------------------------------------------------

const announcement = (over = {}) => ({
  orgId: PUBLIC_ORG,
  authorUid: OWNER,
  authorName: 'Owner',
  title: 'Which ground on Sunday?',
  content: '',
  isPinned: false,
  createdAt: serverTimestamp(),
  poll: {
    options: ['Ground A', 'Ground B'],
    votes: {},
    closed: false,
  },
  ...over,
});

const annRef = (db) => doc(db, 'orgs', PUBLIC_ORG, 'announcements', 'a1');

async function seedPoll(over = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
      membership(OWNER, PUBLIC_ORG, 'owner'),
    );
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'members', PLAYER),
      membership(PLAYER, PUBLIC_ORG, 'member'),
    );
    await setDoc(annRef(db), announcement(over));
  });
}

describe('club polls', () => {
  it('lets an ordinary member cast a vote', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      updateDoc(annRef(db), { [`poll.votes.${PLAYER}`]: 1 }),
    );
  });

  it('refuses a member voting on somebody else behalf', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      updateDoc(annRef(db), { [`poll.votes.${OWNER}`]: 0 }),
    );
  });

  it('refuses a member rewriting the question', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(updateDoc(annRef(db), { title: 'Something else' }));
  });

  it('refuses a member rewriting the options', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      updateDoc(annRef(db), { 'poll.options': ['Only one answer now'] }),
    );
  });

  it('refuses a member closing the poll', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(updateDoc(annRef(db), { 'poll.closed': true }));
  });

  it('refuses votes once an admin has closed it', async () => {
    await seedPoll({ poll: { options: ['A', 'B'], votes: {}, closed: true } });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      updateDoc(annRef(db), { [`poll.votes.${PLAYER}`]: 0 }),
    );
  });

  it('refuses an outsider voting', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(annRef(db), { [`poll.votes.${OUTSIDER}`]: 0 }),
    );
  });

  it('still refuses a member posting an announcement', async () => {
    // Voting must not have widened who can post to the club feed.
    await seedPoll();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(doc(db, 'orgs', PUBLIC_ORG, 'announcements', 'a2'), announcement()),
    );
  });

  it('lets an admin close their own poll', async () => {
    await seedPoll();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(updateDoc(annRef(db), { 'poll.closed': true }));
  });
});

// ---------------------------------------------------------------------------
// Quick match — the club's own internal game, and one player against another.
//
// This is the only competition an ORDINARY MEMBER may create, so it is the
// only place in the ruleset where the create path is not an organizer's. The
// tests below are about where that widening stops.
//
// The competition and its single fixture are written in ONE batch, which is
// what forces the fixture rule to use getAfter() rather than get(): at the
// moment it is evaluated the parent does not exist committed yet.
// ---------------------------------------------------------------------------
describe('quick match: a member starting their own match', () => {
  const QM_COMP = 'comp_quick';
  const QM_FIX = 'fx_quick';
  const MEMBER_A = 'uid_qm_member_a';
  const MEMBER_B = 'uid_qm_member_b';

  const player = (uid, name) => ({
    id: uid,
    name,
    uid,
    jerseyNumber: null,
    isCaptain: false,
    isKeeper: false,
  });

  /** A single-match competition as `Competition.toCreate` writes it. */
  const quickComp = (creator, overrides = {}) =>
    competition(PUBLIC_ORG, {
      name: 'Aarav v Bhavya',
      nameLower: 'aarav v bhavya',
      sportId: 'badminton',
      sportName: 'Badminton',
      scoringPluginKey: 'set_based',
      format: 'single_match',
      status: 'in_progress',
      participationModel: 'approval',
      maxEntrants: null,
      entrantCount: 2,
      fixtureCount: 1,
      createdBy: creator,
      ...overrides,
    });

  /** Its one fixture, with both line-ups already named. */
  const quickFixture = (creator, playerUids, overrides = {}) => ({
    ...fixture(PUBLIC_ORG, QM_COMP, [creator], 'live'),
    entrantAId: 'side_a',
    entrantBId: 'side_b',
    scoringPluginKey: 'set_based',
    sportId: 'badminton',
    lineupA: [player(playerUids[0], 'Aarav')],
    lineupB: [player(playerUids[1], 'Bhavya')],
    playerUids,
    ...overrides,
  });

  /** Exactly what `createQuickMatch` commits: both documents, one batch. */
  const startMatch = (db, creator, playerUids, opts = {}) => {
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'orgs', PUBLIC_ORG, 'competitions', QM_COMP),
      quickComp(creator, opts.comp),
    );
    batch.set(
      doc(db, 'orgs', PUBLIC_ORG, 'competitions', QM_COMP, 'fixtures', QM_FIX),
      quickFixture(creator, playerUids, opts.fixture),
    );
    return batch.commit();
  };

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      for (const uid of [MEMBER_A, MEMBER_B]) {
        await setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'members', uid),
          membership(uid, PUBLIC_ORG, 'member'),
        );
      }
    });
  });

  it('lets a plain member start a match they are playing in', async () => {
    // The whole point of the feature. Before this branch existed, two club
    // members could not record a game between themselves without finding an
    // admin to create an event, open entries, close them and draw a bracket.
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertSucceeds(startMatch(db, MEMBER_A, [MEMBER_A, MEMBER_B]));
  });

  it('refuses a member manufacturing a match between two OTHER people', async () => {
    // The real limit on the member branch. A finished match settles ratings
    // and career statistics onto its players' profiles, so being able to
    // invent matches you are not in is being able to write on other people's
    // records.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(startMatch(db, OUTSIDER, [MEMBER_A, MEMBER_B]));
  });

  it('lets an ORGANIZER start a match between two other people', async () => {
    // An admin running the club's Sunday game is not playing in it. The
    // organizer branch is unchanged and still applies.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
        membership(ADMIN, PUBLIC_ORG, 'admin'),
      );
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(startMatch(db, ADMIN, [MEMBER_A, MEMBER_B]));
  });

  it('refuses a NON-MEMBER starting a match in a club they do not belong to', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(startMatch(db, OUTSIDER, [OUTSIDER, MEMBER_A]));
  });

  it('refuses a member opening a TOURNAMENT through the same path', async () => {
    // The format is what the member branch is scoped to. Without this check
    // the widening would be "any member may create any competition".
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertFails(
      startMatch(db, MEMBER_A, [MEMBER_A, MEMBER_B], {
        comp: { format: 'knockout', status: 'registration_open' },
      }),
    );
  });

  it('refuses a member charging an entry fee for one', async () => {
    // Taking money is an organizing act whatever the format says.
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertFails(
      startMatch(db, MEMBER_A, [MEMBER_A, MEMBER_B], {
        comp: { entryFeeRupees: 200 },
      }),
    );
  });

  it('refuses a member attributing the match to somebody else', async () => {
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertFails(startMatch(db, MEMBER_B, [MEMBER_A, MEMBER_B]));
  });

  it('refuses a member handing the pen to a third party', async () => {
    // A quick match has no organizer to assign a scorer, so the creator is
    // the scorer and nobody else. Otherwise this path would be a way to put
    // an unrelated person in control of a live scoreboard.
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertFails(
      startMatch(db, MEMBER_A, [MEMBER_A, MEMBER_B], {
        fixture: { scorerUids: [MEMBER_A, OUTSIDER] },
      }),
    );
  });

  it('refuses a fixture that claims single-match status its parent does not have', async () => {
    // The fixture rule re-reads the parent rather than trusting the fixture's
    // own fields, so a member cannot write a fixture into somebody's real
    // tournament by asserting the format on the fixture itself.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp_real'),
        competition(PUBLIC_ORG, { format: 'knockout', createdBy: OWNER }),
      );
    });
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp_real', 'fixtures', 'fx_x'),
        {
          ...quickFixture(MEMBER_A, [MEMBER_A, MEMBER_B]),
          compId: 'comp_real',
        },
      ),
    );
  });

  it('lets the creator score the match they started', async () => {
    // The path is only worth anything if the next tap is a score.
    const db = testEnv.authenticatedContext(MEMBER_A).firestore();
    await assertSucceeds(startMatch(db, MEMBER_A, [MEMBER_A, MEMBER_B]));
    await assertSucceeds(
      setDoc(
        doc(
          db, 'orgs', PUBLIC_ORG, 'competitions', QM_COMP,
          'fixtures', QM_FIX, 'events', '0000000001',
        ),
        {
          seq: 1,
          type: 'point',
          side: 'a',
          payload: {},
          byUid: MEMBER_A,
          clientEventId: 'evt-1',
          at: serverTimestamp(),
        },
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Player codes — `playerCodes/{PSOS-4K7M2}`.
//
// The code IS the document id, which is where uniqueness comes from: Firestore
// has no unique constraint, but a create on an existing id fails, so claiming
// is first-come by construction.
//
// The document is world-readable on purpose, and the tests below are about the
// two things that makes acceptable: it carries a name and a photo and nothing
// else, and it can never be reassigned once claimed.
// ---------------------------------------------------------------------------
describe('player codes', () => {
  const CODE = 'PSOS-4K7M2';
  const CLAIMER = 'uid_code_claimer';
  const RIVAL = 'uid_code_rival';

  const profile = (uid, overrides = {}) => ({
    uid,
    displayName: 'Aarav Reddy',
    email: `${uid}@example.test`,
    dateOfBirth: new Date('1996-04-02'),
    gender: 'male',
    photoUrl: null,
    phone: null,
    profileVisibility: 'community',
    profileComplete: true,
    geo: {},
    orgIds: [],
    playerCode: null,
    isMinor: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  const reservation = (uid, overrides = {}) => ({
    uid,
    displayName: 'Aarav Reddy',
    photoUrl: null,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  /** Exactly what `UserRepository.ensureCode` commits: both writes, one batch. */
  const claim = (db, uid, code = CODE, opts = {}) => {
    const batch = writeBatch(db);
    batch.set(doc(db, 'playerCodes', code), reservation(uid, opts.reservation));
    batch.update(doc(db, 'users', uid), { playerCode: opts.pointAt ?? code });
    return batch.commit();
  };

  beforeEach(async () => {
    await seed(async (db) => {
      for (const uid of [CLAIMER, RIVAL]) {
        await setDoc(doc(db, 'users', uid), profile(uid));
      }
    });
  });

  it('lets a signed-in user claim a code and point their profile at it', async () => {
    const db = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertSucceeds(claim(db, CLAIMER));
  });

  it('refuses a second claim on a code somebody already holds', async () => {
    // This is the uniqueness guarantee, and it is structural rather than
    // enforced: the id already exists, so the create fails. Without it two
    // players share a public identity and every match record follows the
    // wrong one.
    const first = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertSucceeds(claim(first, CLAIMER));

    const second = testEnv.authenticatedContext(RIVAL).firestore();
    await assertFails(claim(second, RIVAL));
  });

  it('refuses claiming a code on somebody else\'s behalf', async () => {
    const db = testEnv.authenticatedContext(RIVAL).firestore();
    await assertFails(
      setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER)),
    );
  });

  it('refuses a reservation whose profile does not point back at it', async () => {
    // The two writes have to agree, or the reservation names a code the
    // profile does not carry — a code burned for nobody.
    const db = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertFails(claim(db, CLAIMER, CODE, { pointAt: 'PSOS-99999' }));
  });

  it('refuses a bare reservation with no profile write at all', async () => {
    const db = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertFails(
      setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER)),
    );
  });

  it('refuses a signed-out claim', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER)),
    );
  });

  it('lets a total stranger resolve a code', async () => {
    // The entire point. A captain filling in a team sheet is adding somebody
    // from another club, whose profile they cannot read — if the lookup
    // required a shared club it would be a slower member list.
    await seed(async (db) => {
      await setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(getDoc(doc(db, 'playerCodes', CODE)));
    assert.equal(snap.data().uid, CLAIMER);
    // What the world may learn is a name and a photo. Anything more would
    // make an enumerable collection a privacy problem rather than a directory.
    assert.deepEqual(
      Object.keys(snap.data()).sort(),
      ['createdAt', 'displayName', 'photoUrl', 'uid'],
    );
  });

  it('lets a signed-out spectator resolve one too', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER));
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'playerCodes', CODE)));
  });

  it('refuses reassigning a claimed code to somebody else', async () => {
    // A reassignable code is two people able to trade public identities, and
    // every match either had played would follow the swap.
    await seed(async (db) => {
      await setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER));
    });
    const db = testEnv.authenticatedContext(RIVAL).firestore();
    await assertFails(
      updateDoc(doc(db, 'playerCodes', CODE), { uid: RIVAL }),
    );
  });

  it('refuses the holder editing or deleting their own reservation', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'playerCodes', CODE), reservation(CLAIMER));
    });
    const db = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertFails(
      updateDoc(doc(db, 'playerCodes', CODE), { displayName: 'Someone Else' }),
    );
    await assertFails(deleteDoc(doc(db, 'playerCodes', CODE)));
  });

  it('refuses a user changing the code on their own profile once set', async () => {
    // The reservation makes a code unique; this is what stops it moving.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', CLAIMER), profile(CLAIMER, { playerCode: CODE }));
    });
    const db = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', CLAIMER), { playerCode: 'PSOS-00000' }),
    );
  });

  it('still lets a user edit the rest of their profile afterwards', async () => {
    // Guards against the write-once rule being so blunt it freezes the whole
    // document — profile editing has to keep working.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', CLAIMER), profile(CLAIMER, { playerCode: CODE }));
    });
    const db = testEnv.authenticatedContext(CLAIMER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', CLAIMER), {
        displayName: 'Aarav R',
        playerCode: CODE,
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Venues and tournaments
// ---------------------------------------------------------------------------
//
// A venue's court list is what the scheduler allocates against, so write
// access has to match who runs competitions — a member who could add courts
// could manufacture a timetable that does not exist.
describe('venues', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
    });
  });

  const venue = (overrides = {}) => ({
    orgId: PUBLIC_ORG,
    name: 'Gachibowli Indoor Stadium',
    nameLower: 'gachibowli indoor stadium',
    address: null,
    city: 'Hyderabad',
    district: 'Rangareddy',
    latitude: null,
    longitude: null,
    courts: [
      { id: 'c1', name: 'Court 1', isIndoor: true, surface: null, isAvailable: true },
      { id: 'c2', name: 'Court 2', isIndoor: true, surface: null, isAvailable: true },
    ],
    openHour: 6,
    closeHour: 22,
    notes: null,
    isArchived: false,
    createdBy: OWNER,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('an organizer creates a venue for their club', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, `orgs/${PUBLIC_ORG}/venues/v_new`), venue()),
    );
  });

  it('a plain outsider cannot create one', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, `orgs/${PUBLIC_ORG}/venues/v_outsider`), venue()),
    );
  });

  it('a venue that closes before it opens is rejected', async () => {
    // A backwards window produces a slot grid with no slots, and therefore a
    // schedule that silently contains nothing.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, `orgs/${PUBLIC_ORG}/venues/v_backwards`),
        venue({ openHour: 20, closeHour: 8 }),
      ),
    );
  });

  it('anyone who can read the org can read its venues', async () => {
    // A spectator opening a public fixture needs to know which hall to walk to.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/venues/v_read`),
        venue(),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      getDoc(doc(db, `orgs/${PUBLIC_ORG}/venues/v_read`)),
    );
  });

  it('a venue can never be deleted, only archived', async () => {
    // Fixtures name it, and a career profile that says "played at" needs
    // somewhere to point.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/venues/v_perm`),
        venue(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      deleteDoc(doc(db, `orgs/${PUBLIC_ORG}/venues/v_perm`)),
    );
    await assertSucceeds(
      updateDoc(doc(db, `orgs/${PUBLIC_ORG}/venues/v_perm`), {
        isArchived: true,
      }),
    );
  });

  it('an organizer cannot move a venue to another org', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/venues/v_move`),
        venue(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, `orgs/${PUBLIC_ORG}/venues/v_move`), {
        orgId: PRIVATE_ORG,
      }),
    );
  });
});

describe('tournaments', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
    });
  });

  const tournament = (overrides = {}) => ({
    orgId: PUBLIC_ORG,
    name: 'Hyderabad District Championship',
    nameLower: 'hyderabad district championship',
    status: 'draft',
    grade: 'district',
    description: null,
    venueIds: [],
    startDate: new Date('2026-09-12'),
    endDate: new Date('2026-09-13'),
    entryDeadline: null,
    eventCount: 0,
    contactPhone: null,
    entryFeeRupees: 0,
    matchMinutesDefault: 30,
    changeoverMinutes: 5,
    restGapMinutes: 20,
    createdBy: OWNER,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('an organizer creates a tournament', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, `orgs/${PUBLIC_ORG}/tournaments/t_new`), tournament()),
    );
  });

  it('a tournament cannot be created already claiming to hold events', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, `orgs/${PUBLIC_ORG}/tournaments/t_liar`),
        tournament({ eventCount: 12 }),
      ),
    );
  });

  it('an outsider cannot create one', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, `orgs/${PUBLIC_ORG}/tournaments/t_out`), tournament()),
    );
  });

  it('a completed tournament cannot be reopened', async () => {
    // Reopening would silently rewrite results participants have already been
    // told are final.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t_done`),
        tournament({ status: 'completed' }),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, `orgs/${PUBLIC_ORG}/tournaments/t_done`), {
        status: 'in_progress',
      }),
    );
  });

  it('a tournament holding events cannot be deleted', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t_full`),
        tournament({ eventCount: 3 }),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      deleteDoc(doc(db, `orgs/${PUBLIC_ORG}/tournaments/t_full`)),
    );
  });

  it('an empty tournament can be deleted', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t_empty`),
        tournament(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      deleteDoc(doc(db, `orgs/${PUBLIC_ORG}/tournaments/t_empty`)),
    );
  });
});

// ---------------------------------------------------------------------------
// Ranking points
// ---------------------------------------------------------------------------
//
// The one collection with no client write path at all. A ranking table decides
// seeding, selection and funding, so a client that could write here could
// award itself a national title.
describe('ranking entries', () => {
  const entry = (uid, overrides = {}) => ({
    uid,
    entrantId: uid,
    displayName: 'Aarav Reddy',
    orgId: PUBLIC_ORG,
    tournamentId: 't1',
    tournamentName: 'District Championship',
    grade: 'district',
    compId: 'c1',
    eventName: 'Senior Singles',
    sportId: 'badminton',
    categoryLabel: 'Open',
    round: 'winner',
    points: 300,
    awardedAt: new Date(),
    expiresAt: new Date(Date.now() + 364 * 24 * 3600 * 1000),
    ...overrides,
  });

  it('anyone can read the ranking list, signed in or not', async () => {
    // A ranking list nobody can see is not a ranking list.
    await seed(async (db) => {
      await setDoc(doc(db, 'rankingEntries/e1'), entry(OWNER));
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'rankingEntries/e1')));
  });

  it('a player cannot award themselves points', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'rankingEntries/forged'), entry(OUTSIDER)),
    );
  });

  it('an org owner cannot award points either', async () => {
    // Not a permissions question — nobody writes here but the trigger.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'rankingEntries/forged2'), entry(OWNER)),
    );
  });

  it('an existing entry cannot be edited or deleted', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'rankingEntries/e2'), entry(OWNER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'rankingEntries/e2'), { points: 99999 }),
    );
    await assertFails(deleteDoc(doc(db, 'rankingEntries/e2')));
  });
});

// ---------------------------------------------------------------------------
// Disputes
// ---------------------------------------------------------------------------
//
// The event log is tamper-proof but not right — a scorer can press the wrong
// button. The one rule that makes a protest mean anything is that the person
// who raised it cannot be the person who decides it.
describe('disputes', () => {
  const COMP = 'comp_dispute';
  const FIX = 'fix_dispute';
  const MEMBER = 'uid_disputer';

  const path = `orgs/${PUBLIC_ORG}/competitions/${COMP}/fixtures/${FIX}/disputes`;

  const dispute = (uid, overrides = {}) => ({
    orgId: PUBLIC_ORG,
    compId: COMP,
    fixtureId: FIX,
    raisedByUid: uid,
    raisedByName: 'Aarav',
    entrantId: uid,
    reason: 'wrong_score',
    detail: 'Third set was 21-19, recorded as 21-18.',
    status: 'open',
    resolvedByUid: null,
    resolutionNote: null,
    raisedAt: serverTimestamp(),
    resolvedAt: null,
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', MEMBER),
        membership(MEMBER, PUBLIC_ORG, 'member'),
      );
    });
  });

  it('a member may raise a protest against their own name', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(setDoc(doc(db, path, 'd1'), dispute(MEMBER)));
  });

  it('a protest cannot be raised in somebody else\'s name', async () => {
    // An anonymous or forged protest is not one a referee can act on.
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(setDoc(doc(db, path, 'd2'), dispute(OWNER)));
  });

  it('a protest cannot be created already decided', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      setDoc(
        doc(db, path, 'd3'),
        dispute(MEMBER, { status: 'upheld', resolvedByUid: MEMBER }),
      ),
    );
  });

  it('a plain member cannot decide a protest', async () => {
    await seed(async (db) => {
      await setDoc(doc(db.app ? db : db, path, 'd4'), dispute(OWNER));
    });
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      updateDoc(doc(db, path, 'd4'), {
        status: 'rejected',
        resolvedByUid: MEMBER,
        resolutionNote: 'No.',
      }),
    );
  });

  it('an organizer cannot decide a protest they raised themselves', async () => {
    // The whole point of a referee: a decision the complainant made
    // themselves settles nothing.
    await seed(async (db) => {
      await setDoc(doc(db, path, 'd5'), dispute(OWNER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, path, 'd5'), {
        status: 'upheld',
        resolvedByUid: OWNER,
        resolutionNote: 'I was right.',
      }),
    );
  });

  it('an organizer decides somebody else\'s protest, with a reason', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, path, 'd6'), dispute(MEMBER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, path, 'd6'), {
        status: 'rejected',
        resolvedByUid: OWNER,
        resolutionNote: 'Scorecard matches the event log; result stands.',
      }),
    );
  });

  it('a decision without a reason is refused', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, path, 'd7'), dispute(MEMBER));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, path, 'd7'), {
        status: 'rejected',
        resolvedByUid: OWNER,
        resolutionNote: '',
      }),
    );
  });

  it('a protest can never be deleted, even once rejected', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, path, 'd8'), dispute(MEMBER, { status: 'rejected' }));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(deleteDoc(doc(db, path, 'd8')));
  });
});
