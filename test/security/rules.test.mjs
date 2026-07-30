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
describe('ratings & career_stats: write-lockdown', () => {
  const PLAYER = 'uid_rating_player';
  const OTHER_PLAYER = 'uid_rating_other_player';

  const ratingDoc = (overrides = {}) => ({
    rating: 1500,
    deviation: 350,
    volatility: 0.06,
    gamesPlayed: 0,
    ...overrides,
  });

  it('lets a signed-in user write their own first rating doc', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', PLAYER, 'ratings', 'cricket'), ratingDoc({ gamesPlayed: 1 })),
    );
  });

  it('lets a match settler write a DIFFERENT player\'s first rating doc (the documented client-settlement flow)', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        ratingDoc({ gamesPlayed: 1 }),
      ),
    );
  });

  it('refuses a rating write carrying an unrecognized extra field', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        { ...ratingDoc({ gamesPlayed: 1 }), note: 'hacked' },
      ),
    );
  });

  it('refuses an absurd out-of-range rating value', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        ratingDoc({ rating: 999999, gamesPlayed: 1 }),
      ),
    );
  });

  it('refuses gamesPlayed jumping by more than one in a single write', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'), ratingDoc({ gamesPlayed: 1 }));
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'), ratingDoc({ gamesPlayed: 50 })),
    );
  });

  it('refuses a single write catapulting the rating by an implausible amount', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        ratingDoc({ rating: 1500, gamesPlayed: 1 }),
      );
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        ratingDoc({ rating: 3000, gamesPlayed: 2 }),
      ),
    );
  });

  it('lets a follow-up write advance gamesPlayed by exactly one with a bounded rating delta', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        ratingDoc({ rating: 1500, gamesPlayed: 1 }),
      );
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'ratings', 'cricket'),
        ratingDoc({ rating: 1516, gamesPlayed: 2 }),
      ),
    );
  });

  const careerDoc = (uid, sportId, overrides = {}) => ({
    uid,
    sportId,
    matchesPlayed: 1,
    lastPlayedAt: new Date(),
    tally: { runsScored: 42 },
    ...overrides,
  });

  it('lets a match settler write a career_stats doc whose identity fields match its own path', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', OTHER_PLAYER, 'career_stats', 'cricket'), careerDoc(OTHER_PLAYER, 'cricket')),
    );
  });

  it('refuses a career_stats write whose uid field does not match the document\'s owner', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      // uid spoofed to the writer instead of the doc's own owner.
      setDoc(doc(db, 'users', OTHER_PLAYER, 'career_stats', 'cricket'), careerDoc(PLAYER, 'cricket')),
    );
  });

  it('refuses a future-dated lastPlayedAt', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'career_stats', 'cricket'),
        careerDoc(OTHER_PLAYER, 'cricket', { lastPlayedAt: new Date('2099-01-01') }),
      ),
    );
  });

  it('refuses an extra field being smuggled into career_stats', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OTHER_PLAYER, 'career_stats', 'cricket'),
        { ...careerDoc(OTHER_PLAYER, 'cricket'), verified: true },
      ),
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
