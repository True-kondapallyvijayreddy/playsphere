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
  increment,
  limit,
  orderBy,
  query,
  runTransaction,
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
const fixture = (orgId, compId, scorerUids, status = 'live', isDraft = false) => ({
  orgId,
  compId,
  // Every fixture the app writes carries this — `Fixture.toCreate()` always
  // emits it — so the tests write it too. A draft is an unpublished draw the
  // organizer is still moving around.
  isDraft,
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
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
    // Cloud Storage holds the actual bytes of every memory and every club
    // logo, and its rules are a completely separate ruleset with completely
    // separate blind spots — it cannot read Firestore at all. Nothing
    // exercised them before, which is how a world-writable logo path survived.
    storage: {
      rules: readFileSync(STORAGE_RULES_FILE, 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.STORAGE_EMULATOR_PORT ?? 9199),
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

  it('refuses immediate membership of an UNLISTED club, approval setting or not', async () => {
    // "Opted out of approving joiners" is a front-door setting, and an unlisted
    // club has no front door. Nothing in this rule ever asked for the invite
    // code, so anyone who learned the orgId — from a fixture, a shared link,
    // another member's profile — could write themselves an active membership
    // and read the roster, announcements and files behind it.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PRIVATE_ORG), {
        ...organization(OWNER, 'unlisted'),
        requiresApprovalToJoin: false,
      });
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PRIVATE_ORG, 'member', 'active'),
      ),
    );
    // Asking is still fine — an unlisted club decides for itself.
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PRIVATE_ORG, 'member', 'pending'),
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
// Following a club — a reader's relationship, not a lightweight membership
// ---------------------------------------------------------------------------
describe('following a club', () => {
  const follow = (orgId, uid) => ({
    uid,
    orgId,
    followedAt: serverTimestamp(),
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG),
        organization(OWNER, 'unlisted'),
      );
    });
  });

  it('lets anyone signed in follow a public club', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER),
        follow(PUBLIC_ORG, OUTSIDER),
      ),
    );
  });

  it('refuses following a club that has not published itself', async () => {
    // Following a private club would be a request to see something the club
    // has not published, and this is not the mechanism for asking — that is
    // membership, which has an approval queue.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'followers', OUTSIDER),
        follow(PRIVATE_ORG, OUTSIDER),
      ),
    );
  });

  it('refuses following on somebody else\'s behalf', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'followers', OWNER),
        follow(PUBLIC_ORG, OWNER),
      ),
    );
    // ...nor by keeping their own document id and claiming another uid.
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER),
        follow(PUBLIC_ORG, OWNER),
      ),
    );
  });

  it('refuses a client-stamped follow date', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER), {
        uid: OUTSIDER,
        orgId: PUBLIC_ORG,
        followedAt: new Date('2020-01-01'),
      }),
    );
  });

  it('lets a follower unfollow, and nobody else', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER),
        { uid: OUTSIDER, orgId: PUBLIC_ORG, followedAt: serverTimestamp() },
      );
    });
    const stranger = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      deleteDoc(doc(stranger, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER)),
    );
    const own = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      deleteDoc(doc(own, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER)),
    );
  });

  it('lets a user list their own follows across every club', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'followers', OUTSIDER),
        { uid: OUTSIDER, orgId: PUBLIC_ORG, followedAt: serverTimestamp() },
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(collectionGroup(db, 'followers'), where('uid', '==', OUTSIDER)),
      ),
    );
    assert.equal(snap.size, 1);
  });

  it('refuses reading whom somebody else follows', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      getDocs(
        query(collectionGroup(db, 'followers'), where('uid', '==', OWNER)),
      ),
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
// A draft draw is internal until it is published
// ---------------------------------------------------------------------------
//
// `isDraft` marks a PLACEHOLDER draw — the bracket `generateDraftSchedule`
// lays out against synthetic entrants before registration has produced anybody
// real. It drove a banner in the UI but appeared nowhere in firestore.rules,
// so for a PUBLIC org those placeholders were world-readable the moment they
// were written: members saw "Team A vs Team B" for an undrawn event, with
// nothing to distinguish it from a real schedule.
//
// Rules reject a list rather than filtering it, so these tests pin down BOTH
// halves of the contract — the manager's unfiltered query must still work, and
// the member's must carry `where('isDraft', '==', false)`, which is exactly
// what `CompetitionRepository.watchFixtures` sends.
describe('placeholder (draft) fixtures are visible only to organizers', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      // One real match and one placeholder, in the same competition — the
      // state an organizer is in halfway through laying out a season.
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'published'),
        fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled', false),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'draft'),
        fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled', true),
      );
    });
  });

  const fixturesOf = (db) =>
    collection(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures');

  it('refuses an outsider reading a single draft fixture', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      getDoc(doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'draft')),
    );
  });

  it('still lets that outsider read the published one', async () => {
    // The gate must be about the draft flag and nothing else — a public org's
    // real schedule stays readable without an account, which is the whole
    // spectator story.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'published')),
    );
  });

  it('refuses an unfiltered list from someone who cannot manage the competition', async () => {
    // The load-bearing negative, and the one an earlier version of this fix
    // silently failed: rules do not filter a list, so a query that does not
    // pin `isDraft` must be refused outright rather than quietly trimmed.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDocs(query(fixturesOf(db))));
  });

  it('lets that same person list the published fixtures when the query pins isDraft', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(
      getDocs(query(fixturesOf(db), where('isDraft', '==', false))),
    );
    assert.equal(snap.size, 1);
    assert.equal(snap.docs[0].id, 'published');
  });

  it('lets an organizer list everything, drafts included', async () => {
    // The other half: if this ever fails, the organizer has lost sight of the
    // draw they are in the middle of editing, which is a worse bug than the
    // leak this block closes.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const snap = await assertSucceeds(getDocs(query(fixturesOf(db))));
    assert.equal(snap.size, 2);
  });

  it('lets an organizer read one draft fixture directly', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'draft')),
    );
  });

  it('DENIES a fixture missing isDraft entirely — the backfill is required', async () => {
    // Documents the cost of the strict comparison honestly rather than
    // papering over it. `resource.data.isDraft == false` cannot be satisfied
    // by a document that has no such field, so a match written before the
    // flag existed is invisible to non-organizers until it is backfilled.
    //
    // The defaulting form `.get('isDraft', false)` would let these through —
    // and would also reopen the leak this whole block exists to close, since
    // it reads as `false == false` for every unconstrained list. Backfilling
    // is the resolution: `backfillParticipants` in functions/participants.js
    // writes `isDraft: false` on every fixture that predates the field.
    await seed(async (db) => {
      const legacy = fixture(PUBLIC_ORG, 'comp1', [SCORER], 'completed');
      delete legacy.isDraft;
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'legacy'),
        legacy,
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      getDoc(doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'legacy')),
    );
  });

  it('reads that same fixture once the backfill has written isDraft: false', async () => {
    // The other half: the backfill genuinely resolves it, so the deny above
    // is a migration step and not a permanent hole in the back catalogue.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'backfilled'),
        fixture(PUBLIC_ORG, 'comp1', [SCORER], 'completed', false),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'backfilled')),
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

  // An individual draw — badminton singles, chess, a tennis bracket — never
  // fills a line-up, so the account behind a side lives on the fixture as
  // `entrantAUid`/`entrantBUid` and is the ONLY record that a promoted player
  // is in the next round. Advancement therefore has to carry it, and has to
  // extend `playerUids` alongside it, or the semi-finalist's own match list
  // and every career screen stop at the quarter-final.
  it('lets a scorer carry the account and playerUids with an advancing winner',
    async () => {
      await seed(async (db) => {
        await setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
          {
            ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled'),
            entrantAId: '',
            entrantAName: 'To be decided',
            entrantAUid: null,
            entrantBId: 'entrant_b',
            entrantBUid: 'uid_bhavya',
            playerUids: ['uid_bhavya'],
          },
        );
      });
      const db = testEnv.authenticatedContext(SCORER).firestore();
      await assertSucceeds(
        setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
          {
            entrantAId: 'entrant_a',
            entrantAName: 'Alice',
            entrantAUid: 'uid_alice',
            playerUids: ['uid_bhavya', 'uid_alice'],
          },
          { merge: true },
        ),
      );
    });

  // The additions-only guard. This statement is reachable by a scorer of
  // either contesting club, and `playerUids` is what the settlement rules
  // consult before writing ratings onto a profile — so promoting a player in
  // must never be usable to drop the opposite half of the bracket out.
  it('refuses an advancement that drops a player already in playerUids',
    async () => {
      await seed(async (db) => {
        await setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
          {
            ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'scheduled'),
            entrantAId: '',
            entrantAName: 'To be decided',
            entrantBId: 'entrant_b',
            entrantBUid: 'uid_bhavya',
            playerUids: ['uid_bhavya'],
          },
        );
      });
      const db = testEnv.authenticatedContext(SCORER).firestore();
      await assertFails(
        setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'final'),
          {
            entrantAId: 'entrant_a',
            entrantAName: 'Alice',
            entrantAUid: 'uid_alice',
            // Bhavya erased on the way past.
            playerUids: ['uid_alice'],
          },
          { merge: true },
        ),
      );
    });

  // Scoring a match must never redirect who the result accrues to. The
  // line-up freeze has always covered team sports; this is the same attack on
  // the shape that has no line-up to freeze.
  it('refuses a scoring write that reassigns the account behind a side',
    async () => {
      const db = testEnv.authenticatedContext(SCORER).firestore();
      const batch = scoreBatch(db, 1);
      batch.set(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'fix1'),
        { entrantAUid: 'uid_impostor' },
        { merge: true },
      );
      await assertFails(batch.commit());
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

  // `docs/Heart_of_the_playsphere.md` §23: a scorer submits a result, an
  // official verifies it. The scoring statement in the rules freezes named
  // fields rather than allow-listing them, so every field added to a fixture
  // becomes writable by a scorer unless something says otherwise — which is
  // exactly how a scorer would quietly acquire the power to certify their own
  // match.
  describe('result verification is not the scorer\'s to grant', () => {
    it('refuses a scorer marking their own result finalized', async () => {
      const db = testEnv.authenticatedContext(SCORER).firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, ...eventPath('000000001')), {
        seq: 1,
        type: 'point',
        payload: { side: 'a' },
        byUid: SCORER,
        at: serverTimestamp(),
        clientEventId: 'fx1:1:point',
        note: null,
      });
      batch.update(doc(db, ...fixturePath), {
        scoreState: { currentA: 1, currentB: 0 },
        lastSeq: 1,
        summary: '1-0',
        status: 'completed',
        resultState: 'finalized',
      });
      await assertFails(batch.commit());
    });

    it('lets a scorer submit a result for approval', async () => {
      // The legitimate half: ending the match and handing it to an official.
      const db = testEnv.authenticatedContext(SCORER).firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, ...eventPath('000000001')), {
        seq: 1,
        type: 'point',
        payload: { side: 'a' },
        byUid: SCORER,
        at: serverTimestamp(),
        clientEventId: 'fx1:1:point',
        note: null,
      });
      batch.update(doc(db, ...fixturePath), {
        scoreState: { currentA: 1, currentB: 0 },
        lastSeq: 1,
        summary: '1-0',
        status: 'completed',
        resultState: 'awaiting_approval',
      });
      await assertSucceeds(batch.commit());
    });

    it('refuses a scorer relabelling which competition the match came from',
      async () => {
        // §12. Moving a match's source moves its result onto a different
        // leaderboard, which is a way to manufacture standings out of games
        // that were never part of that competition.
        const db = testEnv.authenticatedContext(SCORER).firestore();
        const batch = writeBatch(db);
        batch.set(doc(db, ...eventPath('000000001')), {
          seq: 1,
          type: 'point',
          payload: { side: 'a' },
          byUid: SCORER,
          at: serverTimestamp(),
          clientEventId: 'fx1:1:point',
          note: null,
        });
        batch.update(doc(db, ...fixturePath), {
          scoreState: { currentA: 1, currentB: 0 },
          lastSeq: 1,
          summary: '1-0',
          status: 'live',
          sourceType: 'season',
          sourceId: 'someone_elses_season',
        });
        await assertFails(batch.commit());
      });

    it('lets an organizer finalize a result', async () => {
      // The other half of §23: verification exists, and somebody can do it.
      await seed(async (db) => {
        // The surrounding beforeEach seeds a scorer and a plain member but no
        // organizer, so this block adds one. Without the membership document
        // `canManageCompetitions` is false and the test fails for the wrong
        // reason — an absent role rather than a refused write.
        await setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
          membership(OWNER, PUBLIC_ORG, 'owner'),
        );
        await setDoc(
          doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1', 'fixtures', 'fx1'),
          {
            ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'completed'),
            resultState: 'awaiting_approval',
          },
        );
      });
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, ...fixturePath), { resultState: 'finalized' }),
      );
    });
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

  it('accepts the explicit nulls and free plan AppUser.toCreate sends', async () => {
    // The control for the refusals below: they must fail on the field they
    // name, not because an ordinary signup stopped working.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER), {
        ...profile(OWNER, new Date('1990-04-11')),
        plan: 'free',
        custodianUid: null,
        claimedAt: null,
      }),
    );
  });

  it('refuses a new profile that names a custodian', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER), {
        ...profile(OWNER, new Date('1990-04-11')),
        custodianUid: OUTSIDER,
      }),
    );
  });

  it('refuses a user adding a custodian to their own profile later', async () => {
    // Seeded WITHOUT the field, the shape of every account created before
    // custody existed — unchangedIfPresent let exactly this through.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OWNER), profile(OWNER, new Date('1990-04-11')));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', OWNER), { custodianUid: OUTSIDER }),
    );
  });

  it('refuses a new profile that starts on a paid plan', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER), {
        ...profile(OWNER, new Date('1990-04-11')),
        plan: 'premium',
        planValidUntil: new Date(Date.now() + 300 * 24 * 60 * 60 * 1000),
        planPaymentId: 'pay_invented',
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Guardian-managed child profiles — a guardian operates a child's profile
// (see functions/family.js) until the child claims it themselves, at which
// point write access moves to the child and read access stays with the
// guardian permanently.
// ---------------------------------------------------------------------------
describe('guardian-managed child profiles', () => {
  const FAMILY_GUARDIAN = 'uid_family_guardian';
  const MANAGED_CHILD = 'uid_managed_child';

  const managedChild = (claimedAt = null, overrides = {}) => ({
    uid: MANAGED_CHILD,
    displayName: 'Managed Child',
    email: '',
    dateOfBirth: new Date('2015-01-01'),
    gender: 'male',
    photoUrl: null,
    phone: null,
    profileVisibility: 'private',
    profileComplete: true,
    isMinor: true,
    orgIds: [],
    playerCode: null,
    custodianUid: FAMILY_GUARDIAN,
    claimedAt,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a custodian edit their own unclaimed child\'s profile', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MANAGED_CHILD), managedChild());
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', MANAGED_CHILD), {
        displayName: 'Renamed Child',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a custodian setting claimedAt themselves', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MANAGED_CHILD), managedChild());
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', MANAGED_CHILD), { claimedAt: serverTimestamp() }),
    );
  });

  it('refuses a custodian reassigning custodianUid', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MANAGED_CHILD), managedChild());
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', MANAGED_CHILD), { custodianUid: OUTSIDER }),
    );
  });

  it('lets the child\'s own session claim the profile exactly once', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MANAGED_CHILD), managedChild());
    });
    const db = testEnv.authenticatedContext(MANAGED_CHILD).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', MANAGED_CHILD), { claimedAt: serverTimestamp() }),
    );
  });

  it('refuses claiming a second time', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', MANAGED_CHILD),
        managedChild(new Date('2026-01-01')),
      );
    });
    const db = testEnv.authenticatedContext(MANAGED_CHILD).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', MANAGED_CHILD), { claimedAt: serverTimestamp() }),
    );
  });

  it('ends the custodian\'s write access the moment the profile is claimed', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', MANAGED_CHILD),
        managedChild(new Date('2026-01-01')),
      );
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', MANAGED_CHILD), { displayName: 'Still trying' }),
    );
  });

  it('keeps the custodian\'s read access even after the profile is claimed', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', MANAGED_CHILD),
        managedChild(new Date('2026-01-01')),
      );
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', MANAGED_CHILD)));
  });

  it('refuses a stranger any read or write of an unclaimed child\'s private profile', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MANAGED_CHILD), managedChild());
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'users', MANAGED_CHILD)));
    await assertFails(
      updateDoc(doc(db, 'users', MANAGED_CHILD), { displayName: 'Hijacked' }),
    );
  });
});

// ---------------------------------------------------------------------------
// Claim codes — the one-time handoff from a guardian's device to a child's.
// Nothing here is readable back by any client; only `redeemClaimCode`
// (functions/family.js, Admin SDK) ever consumes one.
// ---------------------------------------------------------------------------
describe('claim codes', () => {
  const FAMILY_GUARDIAN = 'uid_claim_guardian';
  const MANAGED_CHILD = 'uid_claim_child';
  // The shape ClaimCode.generate() produces and the create rule demands.
  const CODE = 'K7M2Q4XPZ9AB';

  const claimCode = (overrides = {}) => ({
    code: CODE,
    childUid: MANAGED_CHILD,
    guardianUid: FAMILY_GUARDIAN,
    createdAt: serverTimestamp(),
    expiresAt: new Date(Date.now() + 20 * 60 * 1000),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MANAGED_CHILD), {
        uid: MANAGED_CHILD,
        displayName: 'Claim Child',
        email: '',
        dateOfBirth: new Date('2015-01-01'),
        gender: 'male',
        photoUrl: null,
        phone: null,
        profileVisibility: 'private',
        profileComplete: true,
        isMinor: true,
        orgIds: [],
        playerCode: null,
        custodianUid: FAMILY_GUARDIAN,
        claimedAt: null,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    });
  });

  it('lets a custodian generate a code for their own unclaimed child', async () => {
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertSucceeds(setDoc(doc(db, 'claimCodes', CODE), claimCode()));
  });

  it('refuses anyone who is not the child\'s custodian', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'claimCodes', CODE),
        claimCode({ guardianUid: OUTSIDER }),
      ),
    );
  });

  it('refuses an expiry beyond the 30-minute ceiling', async () => {
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertFails(
      setDoc(
        doc(db, 'claimCodes', CODE),
        claimCode({ expiresAt: new Date(Date.now() + 40 * 60 * 1000) }),
      ),
    );
  });

  it('is not readable by anyone, custodian included', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'claimCodes', CODE), claimCode());
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertFails(getDoc(doc(db, 'claimCodes', CODE)));
  });

  it('cannot be updated or deleted by any client', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'claimCodes', CODE), claimCode());
    });
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    await assertFails(
      updateDoc(doc(db, 'claimCodes', CODE), { usedAt: serverTimestamp() }),
    );
    await assertFails(deleteDoc(doc(db, 'claimCodes', CODE)));
  });

  it('refuses a guessable code — six digits, or any shape but twelve alphabet characters', async () => {
    const db = testEnv.authenticatedContext(FAMILY_GUARDIAN).firestore();
    // Six digits (the old format), too short, lowercase, and a U — which the
    // alphabet leaves out.
    for (const weak of ['482913', 'K7M2Q4XPZ9', 'k7m2q4xpz9ab', 'K7M2Q4XPZ9AU']) {
      await assertFails(
        setDoc(doc(db, 'claimCodes', weak), claimCode({ code: weak })),
      );
    }
  });
});

// ---------------------------------------------------------------------------
// Plan grants — a plan on a user or club document is only ever written next to
// the ledger row that pays for it.
//
// planGrantIsBounded used to check the shape of a grant and nothing else, so
// any account could write itself Premium (or its club the Club plan) with an
// invented planPaymentId, and turning the launch offer off in billing.dart and
// razorpay.js would not have closed it. What cannot be exercised here is the
// offer switched OFF, since that is a constant in the rules file; run the suite
// with RULES_FILE pointing at a copy where `introOfferActive()` returns false
// and every "activates" case below must fail.
// ---------------------------------------------------------------------------
describe('plan grants: a ledger row in the same batch, launch offer only', () => {
  const NEW_ORG = 'org_new_on_club_plan';
  const yearOut = () => new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);

  const person = (uid) => ({
    uid,
    displayName: 'Plan Person',
    email: 'plan@example.com',
    dateOfBirth: new Date('1990-01-01'),
    gender: 'female',
    photoUrl: null,
    phone: null,
    profileVisibility: 'community',
    profileComplete: true,
    isMinor: false,
    plan: 'free',
    custodianUid: null,
    claimedAt: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  // As `PlanPayment.toCreate` writes it under FreeCheckout.
  const ledgerRow = (payerUid, kind, subjectId, plan) => ({
    payerUid,
    kind,
    subjectId,
    plan,
    amountPaise: 0,
    listPricePaise: 99900,
    currency: 'INR',
    validUntil: yearOut(),
    gateway: 'none',
    gatewayRef: null,
    status: 'paid',
    createdAt: serverTimestamp(),
  });

  const grant = (plan, paymentId) => ({
    plan,
    planActivatedAt: serverTimestamp(),
    planValidUntil: yearOut(),
    planPaymentId: paymentId,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OWNER), person(OWNER));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
    });
  });

  it('activates Premium at ₹0 with its ledger row in the same batch', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'payments', 'pay_premium'),
      ledgerRow(OWNER, 'member_plan', OWNER, 'premium'),
    );
    batch.update(doc(db, 'users', OWNER), grant('premium', 'pay_premium'));
    await assertSucceeds(batch.commit());
  });

  it('refuses Premium with no ledger row behind it', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', OWNER), grant('premium', 'pay_invented')),
    );
  });

  it('refuses replaying a ledger row that already exists', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'payments', 'pay_old'),
        ledgerRow(OWNER, 'member_plan', OWNER, 'premium'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', OWNER), grant('premium', 'pay_old')),
    );
  });

  it('refuses Premium on an account that carries no plan field at all', async () => {
    // The shape that made `planFieldsUnchanged` vacuously true: with the field
    // absent, `unchangedIfPresent('plan')` answered "unchanged" for a write
    // that ADDED a plan, so the grant never reached the ledger check. Every
    // free club is stored this way, and so is any account made before plans
    // existed.
    await seed(async (db) => {
      const stored = person(OWNER);
      delete stored.plan;
      await setDoc(doc(db, 'users', OWNER), stored);
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', OWNER), grant('premium', 'pay_invented')),
    );
  });

  it('refuses a ledger row for a different plan, kind or subject', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();

    const wrongPlan = writeBatch(db);
    wrongPlan.set(
      doc(db, 'payments', 'pay_wrong_plan'),
      ledgerRow(OWNER, 'member_plan', OWNER, 'free'),
    );
    wrongPlan.update(doc(db, 'users', OWNER), grant('premium', 'pay_wrong_plan'));
    await assertFails(wrongPlan.commit());

    const wrongKind = writeBatch(db);
    wrongKind.set(
      doc(db, 'payments', 'pay_wrong_kind'),
      ledgerRow(OWNER, 'org_plan', OWNER, 'premium'),
    );
    wrongKind.update(doc(db, 'users', OWNER), grant('premium', 'pay_wrong_kind'));
    await assertFails(wrongKind.commit());

    const wrongSubject = writeBatch(db);
    wrongSubject.set(
      doc(db, 'payments', 'pay_wrong_subject'),
      ledgerRow(OWNER, 'member_plan', OUTSIDER, 'premium'),
    );
    wrongSubject.update(
      doc(db, 'users', OWNER),
      grant('premium', 'pay_wrong_subject'),
    );
    await assertFails(wrongSubject.commit());
  });

  it('activates the Club plan on an existing club with its ledger row', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'payments', 'pay_club_plan'),
      ledgerRow(OWNER, 'org_plan', PUBLIC_ORG, 'club'),
    );
    batch.update(doc(db, 'orgs', PUBLIC_ORG), grant('club', 'pay_club_plan'));
    await assertSucceeds(batch.commit());
  });

  it('refuses the Club plan with no ledger row behind it', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', PUBLIC_ORG), grant('club', 'pay_invented')),
    );
  });

  it('founds a club on the Club plan in one batch with its ledger row', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs', NEW_ORG), {
      ...organization(OUTSIDER, 'public'),
      ...grant('club', 'pay_new_club'),
    });
    batch.set(
      doc(db, 'orgs', NEW_ORG, 'members', OUTSIDER),
      membership(OUTSIDER, NEW_ORG, 'owner'),
    );
    batch.set(
      doc(db, 'payments', 'pay_new_club'),
      ledgerRow(OUTSIDER, 'org_plan', NEW_ORG, 'club'),
    );
    await assertSucceeds(batch.commit());
  });

  it('refuses founding a club on the Club plan with no ledger row', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs', NEW_ORG), {
      ...organization(OUTSIDER, 'public'),
      ...grant('club', 'pay_invented'),
    });
    batch.set(
      doc(db, 'orgs', NEW_ORG, 'members', OUTSIDER),
      membership(OUTSIDER, NEW_ORG, 'owner'),
    );
    await assertFails(batch.commit());
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

  const minorProfile = ({ guardianUid = null, custodianUid = null } = {}) => ({
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
    guardianUid,
    custodianUid,
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

  it("lets the profile's LINKED guardian create a consent record for a scout", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile({ guardianUid: GUARDIAN }));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(setDoc(doc(db, ...scoutPath(SCOUT)), consent()));
  });

  it('lets the managed child\'s CUSTODIAN create a consent record for a scout', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile({ custodianUid: GUARDIAN }));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(setDoc(doc(db, ...scoutPath(SCOUT)), consent()));
  });

  it('REFUSES a self-declared stranger when the profile names neither custodian nor guardian', async () => {
    // The vulnerability that was here: a managed child carries a `custodianUid`
    // and no `guardianUid`, and the old rule's guardian check was vacuous when
    // `guardianUid` was absent — so ANY account could mint a consent naming
    // itself guardian and then read the minor's private profile. The consent
    // writer must now BE the child's real custodian or linked guardian.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile());
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(setDoc(doc(db, ...scoutPath(SCOUT)), consent()));
  });

  it('refuses a scout minting their own consent record', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile({ guardianUid: SCOUT }));
    });
    const db = testEnv.authenticatedContext(SCOUT).firestore();
    await assertFails(
      setDoc(doc(db, ...scoutPath(SCOUT)), consent({ guardianUid: SCOUT })),
    );
  });

  it('refuses the minor consenting for themselves', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile({ custodianUid: MINOR_UID }));
    });
    const db = testEnv.authenticatedContext(MINOR_UID).firestore();
    await assertFails(
      setDoc(doc(db, ...scoutPath(SCOUT)), consent({ guardianUid: MINOR_UID })),
    );
  });

  it('refuses a creator whose uid does not match the profile\'s linked guardian', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile({ guardianUid: GUARDIAN }));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, ...scoutPath(SCOUT)), consent({ guardianUid: OUTSIDER })),
    );
  });

  it('a scout with a valid unrevoked consent can read the minor\'s profile', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile());
      await setDoc(doc(db, ...scoutPath(SCOUT)), consent());
    });
    const db = testEnv.authenticatedContext(SCOUT).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', MINOR_UID)));
  });

  it('refuses the same scout when no consent record exists at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile());
    });
    const db = testEnv.authenticatedContext(SCOUT).firestore();
    await assertFails(getDoc(doc(db, 'users', MINOR_UID)));
  });

  it('lets the guardian revoke their own consent, after which the scout loses access', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile());
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
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile());
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
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile());
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
// The Overall PlaySphere Glicko, denormalised onto users/{uid}.
//
// The subcollection above is `write: if false`, which is the easy half. This
// field is the interesting one: it lives on a document its owner edits all the
// time — name, photo, district, visibility — so it cannot be protected by
// closing the path. `frozen('glicko')` inside `userUpdateInvariantsHold` is
// what stands between "a rating settled by a match" and "a number somebody
// typed onto their own profile", and the travelling copy is precisely the one
// that shows up on rosters and entry lists where nobody checks it.
// ---------------------------------------------------------------------------
describe('users.glicko: the travelling standing is server-written', () => {
  const RATED = 'uid_rated_player';

  const glicko = {
    overall: 1717,
    provisional: false,
    sports: { cricket: 1842, badminton: 1618 },
    sportCount: 4,
    computedAt: serverTimestamp(),
  };

  const profile = (uid, overrides = {}) => ({
    uid,
    displayName: 'Aarav Reddy',
    email: `${uid}@example.test`,
    dateOfBirth: new Date('1996-04-02'),
    gender: 'male',
    photoUrl: null,
    phone: null,
    profileVisibility: 'public',
    profileComplete: true,
    geo: {},
    orgIds: [],
    playerCode: null,
    isMinor: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', RATED), profile(RATED, { glicko }));
    });
  });

  it('is readable wherever the profile is', async () => {
    // The whole point of denormalising it: a roster reading the user document
    // gets the standing with it, for no extra read.
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await getDoc(doc(db, 'users', RATED));
    assert.equal(snap.data().glicko.overall, 1717);
  });

  it('nobody may raise their own standing', async () => {
    const db = testEnv.authenticatedContext(RATED).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', RATED), {
        glicko: { ...glicko, overall: 2400 },
      }),
    );
  });

  it('nobody may quietly drop the provisional flag', async () => {
    // Subtler than inflating the number and worth its own case: the flag is
    // the only thing telling a selector that a headline figure came off two
    // matches, and clearing it makes a guess look settled.
    const db = testEnv.authenticatedContext(RATED).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', RATED), {
        glicko: { ...glicko, provisional: false, overall: glicko.overall },
      }),
    );
  });

  it('an account without one cannot invent one', async () => {
    // `frozen` rather than `unchangedIfPresent` exists for this case: every
    // account created before the composite shipped has no field to compare
    // against.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OUTSIDER), profile(OUTSIDER));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(updateDoc(doc(db, 'users', OUTSIDER), { glicko }));
  });

  it('nobody signs up already rated', async () => {
    const NEW = 'uid_brand_new_player';
    const db = testEnv.authenticatedContext(NEW).firestore();
    await assertFails(
      setDoc(doc(db, 'users', NEW), profile(NEW, { glicko })),
    );
    // The same write without the field is an ordinary sign-up.
    await assertSucceeds(setDoc(doc(db, 'users', NEW), profile(NEW)));
  });

  it('an ordinary profile edit still goes through beside it', async () => {
    // The regression this rule could most easily cause: freezing a field that
    // every profile update carries would break editing a display name.
    const db = testEnv.authenticatedContext(RATED).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'users', RATED), {
        displayName: 'Aarav R',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('nobody may write a standing onto somebody else', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', RATED), {
        glicko: { ...glicko, overall: 1200 },
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
    message: null,
    entryFeeRupees: 0,
    // Written empty at creation so the rules can hold them unchanged on
    // every update except the counter itself.
    counterSlots: [],
    counterVenue: null,
    counterMessage: null,
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

  // A counter-offer is the receiving club's third answer — "yes, but not
  // then". It is the only field on a challenge that one club writes and the
  // other is expected to trust, which makes forging it the interesting
  // attack: a challenging club that could write its own counter could show
  // the opponent as having proposed terms it never offered.
  describe('countering', () => {
    const counter = {
      status: 'countered',
      counterSlots: [],
      counterVenue: 'City Sports Arena',
      counterMessage: 'Ground is booked that day — how about the 26th?',
    };

    it('lets an admin of the TO club counter an open challenge', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
      });
      const db = testEnv.authenticatedContext(ADMIN).firestore();
      await assertSucceeds(updateDoc(doc(db, 'challenges', 'ch1'), counter));
    });

    it('refuses the FROM club countering its own challenge', async () => {
      // The forgery this rule exists to stop: the issuing club writing the
      // opponent's reply into a document it also controls.
      await seed(async (db) => {
        await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
      });
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertFails(updateDoc(doc(db, 'challenges', 'ch1'), counter));
    });

    it('refuses countering a challenge already accepted', async () => {
      // Same orphaning the withdrawal branch prevents: there is a fixture and
      // probably a booked ground behind an accepted challenge.
      await seed(async (db) => {
        await setDoc(
          doc(db, 'challenges', 'ch1'),
          challengeDoc({ status: 'accepted' }),
        );
      });
      const db = testEnv.authenticatedContext(ADMIN).firestore();
      await assertFails(updateDoc(doc(db, 'challenges', 'ch1'), counter));
    });

    it('refuses a stranger countering', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'challenges', 'ch1'), challengeDoc());
      });
      const db = testEnv.authenticatedContext(SCORER).firestore();
      await assertFails(updateDoc(doc(db, 'challenges', 'ch1'), counter));
    });

    it('refuses a challenge created with a counter-offer already filled in',
      async () => {
        const db = testEnv.authenticatedContext(OWNER).firestore();
        await assertFails(
          setDoc(
            doc(db, 'challenges', 'ch_forged'),
            challengeDoc({ counterMessage: 'We agree to your terms' }),
          ),
        );
      });

    it('refuses either club rewriting the counter while accepting', async () => {
      // Accepting must take the counter as it stands. A club that could
      // amend it in the same write could agree to terms of its own invention.
      await seed(async (db) => {
        await setDoc(
          doc(db, 'challenges', 'ch1'),
          challengeDoc({ status: 'countered', counterVenue: 'City Arena' }),
        );
      });
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertFails(
        updateDoc(doc(db, 'challenges', 'ch1'), {
          status: 'accepted',
          counterVenue: 'Our Own Ground',
        }),
      );
    });

    it('refuses rewriting the message or the entry fee after the fact',
      async () => {
        // What was offered is a matter of record between two clubs, and the
        // fee is money.
        await seed(async (db) => {
          await setDoc(
            doc(db, 'challenges', 'ch1'),
            challengeDoc({ entryFeeRupees: 2000 }),
          );
        });
        const db = testEnv.authenticatedContext(OWNER).firestore();
        await assertFails(
          updateDoc(doc(db, 'challenges', 'ch1'), { entryFeeRupees: 0 }),
        );
        await assertFails(
          updateDoc(doc(db, 'challenges', 'ch1'), { message: 'rewritten' }),
        );
      });
  });
});

// ---------------------------------------------------------------------------
// Cross-club tournament invitations.
//
// Same two-tenant shape as a challenge, and the properties that matter are the
// same: only the HOST's organizers may invite in the host's name, only the
// INVITED club may answer, and neither club may impersonate the other's half
// of the exchange.
// ---------------------------------------------------------------------------
describe('cross-club tournament invitations', () => {
  const HOST_ORG = 'org_invite_host';
  const GUEST_ORG = 'org_invite_guest';

  const inviteDoc = (overrides = {}) => ({
    tournamentId: 'tour_1',
    tournamentName: 'District Championship',
    fromOrgId: HOST_ORG,
    fromOrgName: 'Host Club',
    toOrgId: GUEST_ORG,
    toOrgName: 'Guest Club',
    status: 'pending',
    message: null,
    startDate: null,
    endDate: null,
    invitedBy: OWNER,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', HOST_ORG), organization(OWNER, 'public'));
      await setDoc(doc(db, 'orgs', GUEST_ORG), organization(ADMIN, 'public'));
      await setDoc(
        doc(db, 'orgs', HOST_ORG, 'members', OWNER),
        membership(OWNER, HOST_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', GUEST_ORG, 'members', ADMIN),
        membership(ADMIN, GUEST_ORG, 'admin'),
      );
      await setDoc(
        doc(db, 'orgs', HOST_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, HOST_ORG, 'member'),
      );
    });
  });

  it('lets an organizer of the host club invite another club', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc()),
    );
  });

  it('refuses a plain member of the host club inviting in its name', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'tournamentInvites', 'inv1'),
        inviteDoc({ invitedBy: OUTSIDER }),
      ),
    );
  });

  it('refuses a stranger inviting on a club\'s behalf', async () => {
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'tournamentInvites', 'inv1'),
        inviteDoc({ invitedBy: SCORER }),
      ),
    );
  });

  it('refuses an invitation that claims to be from somebody else', async () => {
    // `invitedBy` must be the caller. Without it the audit trail on who
    // committed the club to inviting eleven schools is whatever was typed.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'tournamentInvites', 'inv1'),
        inviteDoc({ invitedBy: ADMIN }),
      ),
    );
  });

  it('refuses a club inviting itself', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'tournamentInvites', 'inv1'),
        inviteDoc({ toOrgId: HOST_ORG, toOrgName: 'Host Club' }),
      ),
    );
  });

  it('lets an organizer of the invited club accept', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc());
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'tournamentInvites', 'inv1'), { status: 'accepted' }),
    );
  });

  it('refuses the HOST answering on the invited club\'s behalf', async () => {
    // The whole value of the feature is that the host can read back a real
    // answer. A host that can write 'accepted' itself is reading its own echo.
    await seed(async (db) => {
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc());
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'tournamentInvites', 'inv1'), { status: 'accepted' }),
    );
  });

  it('lets the host withdraw an unanswered invitation', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc());
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'tournamentInvites', 'inv1'), { status: 'withdrawn' }),
    );
  });

  it('refuses withdrawing an invitation the club already accepted', async () => {
    // They have put the date in their calendar on the strength of it.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'tournamentInvites', 'inv1'),
        inviteDoc({ status: 'accepted' }),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'tournamentInvites', 'inv1'), { status: 'withdrawn' }),
    );
  });

  it('refuses re-pointing an invitation at a different tournament', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc());
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'tournamentInvites', 'inv1'), {
        status: 'accepted',
        tournamentId: 'tour_2',
      }),
    );
  });

  it('refuses a stranger reading two clubs\' invitation', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(getDoc(doc(db, 'tournamentInvites', 'inv1')));
  });

  it('lets the invited club read the invitation addressed to it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'tournamentInvites', 'inv1'), inviteDoc());
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(getDoc(doc(db, 'tournamentInvites', 'inv1')));
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

  // -------------------------------------------------------------------------
  // Branch (b3): taking an official's ruling back OFF.
  //
  // Every ruling used to be a one-way door, and these are why. Branch (a)
  // refuses a withdrawal on a `completed` fixture, because a retirement IS
  // completed and undoing one necessarily moves `winnerEntrantId` and
  // `lastSeq`. Branch (b) refuses it on every ruling, because it only opens on
  // a `scheduled` or `live` fixture. So an organizer who awarded a walkover to
  // the wrong side had the local write applied, watched it work, and saw the
  // server put the walkover back a few seconds later.
  // -------------------------------------------------------------------------

  const ruled = (extra) => ({
    ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'walkover'),
    lastSeq: 0,
    resultType: 'walkover',
    winnerEntrantId: 'entrant_a',
    resultNote: 'Opponent did not arrive by the cut-off',
    ...extra,
  });

  // The write `ScoringService.clearFixtureOutcome` actually makes.
  const withdrawal = (status, seq) => ({
    status,
    resultType: 'normal',
    resultNote: null,
    winnerEntrantId: null,
    isDraw: false,
    lastSeq: seq,
  });

  it('lets an organizer withdraw a walkover and resume the match', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('wo')), ruled({ lastSeq: 4 }));
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      setDoc(doc(db, ...fixturePath('wo')), withdrawal('live', 5), { merge: true }),
    );
  });

  it('lets an organizer withdraw a retirement, which branch (a) cannot', async () => {
    // The specific transition the old rules made impossible: a `completed`
    // fixture whose `winnerEntrantId` and `lastSeq` both have to move.
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('ret')), ruled({
        status: 'completed',
        resultType: 'retired',
        lastSeq: 9,
      }));
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      setDoc(doc(db, ...fixturePath('ret')), withdrawal('live', 10), { merge: true }),
    );
  });

  // The scorer arm of (b3), which is the one the branch's own conditions
  // actually gate. An organizer reaching branch (a) as well is deliberate and
  // long-standing — they may edit a fixture that is not `completed` however
  // they like — so the constraints below are pinned where they are the only
  // thing standing between the caller and the write.
  const retiredByScorer = () => ruled({
    status: 'completed',
    resultType: 'retired',
    lastSeq: 4,
    activeScorerUid: SCORER,
  });

  it('lets the umpire who called a retirement take it back', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(doc(db, ...fixturePath('r1')), retiredByScorer());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(
      setDoc(doc(db, ...fixturePath('r1')), withdrawal('live', 5), { merge: true }),
    );
  });

  it('refuses a withdrawal that also rewrites the score', async () => {
    // The whole safety of the branch. Withdrawing a ruling is not scoring:
    // every point already recorded stays exactly as it is, and without this the
    // statement would be a door around the pen and around the event log —
    // "call an arbitrary score edit a withdrawal".
    //
    // Written as a withdrawal that leaves the match COMPLETED, because that is
    // the shape only (b3) could ever admit. A withdrawal that also takes the
    // match back to `live` is a different thing with its own statement — see
    // (b4) below, where wiping the score IS the point.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(doc(db, ...fixturePath('r2')), retiredByScorer());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(
        doc(db, ...fixturePath('r2')),
        {
          ...withdrawal('completed', 5),
          winnerEntrantId: 'entrant_b',
          scoreState: { currentA: 0, currentB: 21 },
        },
        { merge: true },
      ),
    );
  });

  it('refuses a withdrawal that does not advance lastSeq by exactly one', async () => {
    // The sequence number IS the withdrawal's event in the log — the record of
    // who took the ruling off and when. A write that skips it leaves no trace.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(doc(db, ...fixturePath('r3')), retiredByScorer());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(doc(db, ...fixturePath('r3')), withdrawal('live', 4), { merge: true }),
    );
  });

  it('refuses a scorer leaving a different ruling behind', async () => {
    // (b3) admits exactly one transition: a ruling coming OFF. Swapping a
    // retirement for a disqualification is not that, and going through this
    // statement would let a scorer set a ruling they may only withdraw.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(doc(db, ...fixturePath('r4')), retiredByScorer());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(
        doc(db, ...fixturePath('r4')),
        { ...withdrawal('completed', 5), resultType: 'disqualified' },
        { merge: true },
      ),
    );
  });

  it('refuses an outsider withdrawing a ruling', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('wo4')), ruled({ lastSeq: 4 }));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, ...fixturePath('wo4')), withdrawal('live', 5), { merge: true }),
    );
  });

  // -------------------------------------------------------------------------
  // Reopening a finished match: the engine's own "the last point was wrong",
  // and the restart in the same sheet. Both take a `completed` fixture back to
  // `live` and both advance the log by one.
  // -------------------------------------------------------------------------
  const finished = (extra) => ({
    ...fixture(PUBLIC_ORG, 'comp1', [SCORER], 'completed'),
    lastSeq: 30,
    scoreState: { currentA: 21, currentB: 15 },
    summary: '21-15',
    winnerEntrantId: 'entrant_a',
    activeScorerUid: SCORER,
    ...extra,
  });

  const reopen = (seq) => ({
    status: 'live',
    lastSeq: seq,
    scoreState: { currentA: 20, currentB: 15 },
    summary: '20-15',
    winnerEntrantId: null,
    isDraw: false,
  });

  it('lets the scorer reopen a match they finished by mistake', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(doc(db, ...fixturePath('fin1')), finished());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertSucceeds(
      setDoc(doc(db, ...fixturePath('fin1')), reopen(31), { merge: true }),
    );
  });

  it('lets an organizer restart a finished match from nothing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('fin2')), finished({
        activeScorerUid: ADMIN,
      }));
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, ...fixturePath('fin2')),
        {
          ...reopen(31),
          scoreState: {},
          summary: '',
          lastRestartSeq: 31,
          completedAt: null,
          mvp: null,
          resultType: 'normal',
          resultNote: null,
        },
        { merge: true },
      ),
    );
  });

  it('refuses reopening a match without logging the reopen', async () => {
    // No sequence number means no event, and a finished match that goes back
    // to live with nothing in the log saying so is a result that changed with
    // no record of who changed it.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', SCORER),
        membership(SCORER, PUBLIC_ORG, 'judge_scorer'),
      );
      await setDoc(doc(db, ...fixturePath('fin3')), finished());
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(doc(db, ...fixturePath('fin3')), reopen(30), { merge: true }),
    );
  });

  it('refuses a stranger reopening a finished match', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('fin4')), finished());
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, ...fixturePath('fin4')), reopen(31), { merge: true }),
    );
  });

  it('refuses a scorer un-abandoning a match the organizer abandoned', async () => {
    // The asymmetry is deliberate. An umpire may take back the two rulings
    // they were allowed to declare — a retirement and a disqualification — and
    // nothing else. Un-abandoning somebody else's abandonment is not theirs.
    await seed(async (db) => {
      await setDoc(doc(db, ...fixturePath('ab')), ruled({
        status: 'abandoned',
        resultType: 'abandoned',
        winnerEntrantId: null,
        lastSeq: 4,
        activeScorerUid: SCORER,
      }));
    });
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(
      setDoc(doc(db, ...fixturePath('ab')), withdrawal('live', 5), { merge: true }),
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
// Collection-group query over career_stats — talent discovery's entry point.
//
// Exactly the class of bug this file's header warns about: the nested rule
// under /users/{userId} looked sufficient and was not. Without the
// /{path=**}/career_stats block, ScoutRepository.searchCandidates would be
// permission-denied for every sport, on every account, silently.
// ---------------------------------------------------------------------------
describe('career_stats collection-group query (talent discovery)', () => {
  it('lets a signed-in user query across every account\'s career_stats', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OWNER, 'career_stats', 'cricket'), {
        uid: OWNER,
        sportId: 'cricket',
        matchesPlayed: 5,
        lastPlayedAt: new Date(),
      });
      await setDoc(doc(db, 'users', OUTSIDER, 'career_stats', 'cricket'), {
        uid: OUTSIDER,
        sportId: 'cricket',
        matchesPlayed: 3,
        lastPlayedAt: new Date(),
      });
    });
    const db = testEnv.authenticatedContext('uid_scout_reader').firestore();
    const snap = await getDocs(
      query(collectionGroup(db, 'career_stats'), where('sportId', '==', 'cricket')),
    );
    assert.equal(snap.size, 2);
  });

  it('refuses an unauthenticated reader', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', OWNER, 'career_stats', 'cricket'), {
        uid: OWNER,
        sportId: 'cricket',
        matchesPlayed: 5,
        lastPlayedAt: new Date(),
      });
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      getDocs(query(collectionGroup(db, 'career_stats'), where('sportId', '==', 'cricket'))),
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

  // -------------------------------------------------------------------------
  // The SEASON MEMORY BOOK reads the same collection group again, constrained
  // by (orgId, tournamentId) rather than (orgId) alone or (taggedUids,
  // audience). It needs no rule of its own: `tournamentId` is not referenced
  // anywhere in the rule, so it costs nothing to filter on, and `orgId` being
  // pinned is exactly what the existing club-gallery branch already checks.
  // -------------------------------------------------------------------------
  const seasonMemoryBook = (db, orgId, tournamentId) =>
    getDocs(
      query(
        collectionGroup(db, 'memories'),
        where('orgId', '==', orgId),
        where('tournamentId', '==', tournamentId),
        orderBy('createdAt', 'desc'),
        limit(200),
      ),
    );

  it('lets a member open their UNLISTED club\'s season memory book', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'competitions', COMP, 'fixtures', 'fx_priv', 'memories', 'm2'),
        memoryDoc(PRIVATE_ORG, 'fx_priv', PRIVATE_ORG, { tournamentId: 't1' }),
      );
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    const snap = await assertSucceeds(seasonMemoryBook(db, PRIVATE_ORG, 't1'));
    assert.equal(snap.size, 1);
  });

  it('a season book only shows its own season, not a sibling one', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PRIVATE_ORG, 'competitions', COMP, 'fixtures', 'fx_priv', 'memories', 'm2'),
        memoryDoc(PRIVATE_ORG, 'fx_priv', PRIVATE_ORG, { tournamentId: 't1' }),
      );
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    const snap = await assertSucceeds(seasonMemoryBook(db, PRIVATE_ORG, 't_other'));
    assert.equal(snap.size, 0);
  });

  it('refuses an outsider opening an UNLISTED club\'s season memory book', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(seasonMemoryBook(db, PRIVATE_ORG, 't1'));
  });

  it('lets anyone open a PUBLIC club\'s season memory book', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', 'fx_pub', 'memories', 'm1'),
        memoryDoc(PUBLIC_ORG, 'fx_pub', 'public', { tournamentId: 't1' }),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const snap = await assertSucceeds(seasonMemoryBook(db, PUBLIC_ORG, 't1'));
    assert.equal(snap.size, 1);
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

  // The path shape is `MediaUploader`'s, uploader-uid segment and all — see
  // the comment on the `users/{uid}/profile/{uploaderUid}/{fileName}` block in
  // storage.rules. Written a segment shorter, as these tests were, it matches
  // no block at all and the deny-all at the bottom catches it; a rule that
  // only passes against a path the app never writes proves nothing.
  it('lets a player replace their own profile photo', async () => {
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertSucceeds(
      storage
        .ref(`users/${ME}/profile/${ME}/1700000000000.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });

  it('refuses replacing another player\'s face', async () => {
    // The uploader segment is somebody else's, which is the only fact this
    // file can check — see the block comment in storage.rules.
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertFails(
      storage
        .ref(`users/${SOMEBODY_ELSE}/profile/${SOMEBODY_ELSE}/1700000000000.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });

  it('lets an upload land under another profile from your own uid segment', async () => {
    // This is how a guardian sets the photo on a managed child's profile.
    // Storage rules cannot read Firestore and so cannot see custody, so the
    // object is owned by whoever uploaded it and the write that makes it
    // anybody's photo — `users/{childUid}.photoUrl` — is governed by
    // firestore.rules, where custody IS knowable. An object nobody linked is
    // an object nobody sees.
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertSucceeds(
      storage
        .ref(`users/${SOMEBODY_ELSE}/profile/${ME}/1700000000000.jpg`)
        .put(jpegBytes(), imageMeta),
    );
  });

  it('refuses the old flat path the rules no longer describe', async () => {
    const storage = testEnv.authenticatedContext(ME).storage();
    await assertFails(
      storage.ref(`users/${ME}/profile/avatar.jpg`).put(jpegBytes(), imageMeta),
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

// `OUTSIDER` (declared above, ~line 45) is never added as a member of
// `PUBLIC_ORG` by `seedEvent` — exactly the person `openToNonMembers` is
// meant to let in. These tests are the write-path half of that toggle: the
// discovery board already let this person find the event, this is where
// they try to actually take a place in it.
describe('participation: openToNonMembers lets an outsider register', () => {
  it('refuses a stranger when the toggle is off', async () => {
    await seedEvent({
      participationModel: 'approval',
      openToNonMembers: false,
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(regRef(db, OUTSIDER), registration(OUTSIDER, 'pending')),
    );
  });

  it('accepts a stranger as a pending application once the toggle is on', async () => {
    // `openToNonMembers` forces `participationModel: 'approval'` on the Dart
    // side (see `CreateSeasonScreen`) — a non-member's entry is always a
    // request for a human to confirm, never a self-confirm.
    await seedEvent({
      participationModel: 'approval',
      openToNonMembers: true,
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(regRef(db, OUTSIDER), registration(OUTSIDER, 'pending')),
    );
  });

  it('still refuses a stranger self-confirming, toggle or not', async () => {
    await seedEvent({
      participationModel: 'approval',
      openToNonMembers: true,
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(regRef(db, OUTSIDER), registration(OUTSIDER, 'confirmed')),
    );
  });

  it('lets a stranger self-confirm into a genuinely open, non-member event, and moves the counter', async () => {
    // Not every `openToNonMembers` event is approval-gated — a standalone
    // competition (`CreateCompetitionScreen`) lets an organizer pick 'open'
    // participation independently of the toggle. Both halves of the paired
    // write — the registration doc AND the competition's confirmedCount —
    // have to clear the rules for the same outsider in the same commit.
    await seedEvent({
      participationModel: 'open',
      openToNonMembers: true,
      confirmedCount: 0,
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, OUTSIDER), registration(OUTSIDER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertSucceeds(batch.commit());
  });

  it('refuses the same open+non-member self-confirmation once the toggle is off', async () => {
    await seedEvent({
      participationModel: 'open',
      openToNonMembers: false,
      confirmedCount: 0,
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();

    const batch = writeBatch(db);
    batch.set(regRef(db, OUTSIDER), registration(OUTSIDER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertFails(batch.commit());
  });

  it('lets a stranger withdraw their own entry and frees the slot they held', async () => {
    await seedEvent({
      participationModel: 'open',
      openToNonMembers: true,
      confirmedCount: 1,
    });
    await seed(async (db) => {
      await setDoc(
        regRef(db, OUTSIDER),
        registration(OUTSIDER, 'confirmed'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();

    const batch = writeBatch(db);
    batch.update(regRef(db, OUTSIDER), { status: 'withdrawn' });
    batch.update(compRef(db), { confirmedCount: 0 });
    await assertSucceeds(batch.commit());
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
// Match calls — who may call one OFF.
//
// A match call is an announcement carrying a `match` map. Unlike a plain
// notice, it is one named person asking the club to keep a Saturday free, and
// cancelling it deletes the call and its whole discussion. So editing and
// cancelling belong to its author alone — not to every admin in the club.
// The UI enforces the same rule in `_OrganizerActions`; this is the half that
// survives somebody talking to Firestore directly.
// ---------------------------------------------------------------------------

const matchCall = (authorUid) =>
  announcement({
    authorUid,
    title: 'Sunday game',
    poll: { options: ['In', 'Maybe', 'Out'], votes: {}, closed: false },
    match: {
      sportId: 'cricket',
      matchDate: serverTimestamp(),
      venue: 'Gymkhana',
      maxPlayers: 22,
      invitedUids: [],
    },
  });

async function seedMatchCall(authorUid) {
  await seed(async (db) => {
    await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
      membership(OWNER, PUBLIC_ORG, 'owner'),
    );
    // A SECOND person who can run competitions. The whole point of these
    // tests is that holding the capability is not enough.
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
      membership(ADMIN, PUBLIC_ORG, 'admin'),
    );
    await setDoc(
      doc(db, 'orgs', PUBLIC_ORG, 'members', PLAYER),
      membership(PLAYER, PUBLIC_ORG, 'member'),
    );
    await setDoc(annRef(db), matchCall(authorUid));
  });
}

describe('calling a match off', () => {
  it('lets the author cancel their own call', async () => {
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(deleteDoc(annRef(db)));
  });

  it('lets the author edit their own call', async () => {
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(updateDoc(annRef(db), { 'match.venue': 'Gymkhana B' }));
  });

  it('refuses another admin cancelling it', async () => {
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(deleteDoc(annRef(db)));
  });

  it('refuses another admin editing it', async () => {
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(updateDoc(annRef(db), { 'match.venue': 'Somewhere else' }));
  });

  it('refuses another admin moving the kick-off', async () => {
    // The nastiest version of the same write: the call survives, so nobody
    // is notified, and everybody turns up at the wrong time.
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(updateDoc(annRef(db), { title: 'Saturday game' }));
  });

  it('still lets any member answer somebody else call', async () => {
    // Narrowing who may CANCEL must not narrow who may vote — that is the
    // whole card for everyone who is not the author.
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      updateDoc(annRef(db), { [`poll.votes.${PLAYER}`]: 0 }),
    );
  });

  it('lets another admin answer it too, but not cancel it', async () => {
    await seedMatchCall(OWNER);
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      updateDoc(annRef(db), { [`poll.votes.${ADMIN}`]: 0 }),
    );
    await assertFails(deleteDoc(annRef(db)));
  });

  it('leaves a plain notice as any organizer to moderate', async () => {
    // The narrowing is for match calls only. Taking down a bad notice is
    // still an admin job — it is a club notice board.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
        membership(ADMIN, PUBLIC_ORG, 'admin'),
      );
      await setDoc(annRef(db), announcement({ authorUid: ADMIN }));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(deleteDoc(annRef(db)));
  });

  it('refuses an outsider cancelling anything', async () => {
    await seedMatchCall(ADMIN);
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(deleteDoc(annRef(db)));
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

describe('tournaments: venue plans', () => {
  const PLANNER_ORG = PUBLIC_ORG;

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PLANNER_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PLANNER_ORG, 'members', OWNER),
        membership(OWNER, PLANNER_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PLANNER_ORG, 'members', PLAYER),
        membership(PLAYER, PLANNER_ORG, 'member'),
      );
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PLANNER_ORG}/tournaments/t1`),
        {
          orgId: PLANNER_ORG,
          name: 'Summer Games 2026',
          status: 'draft',
          eventCount: 0,
          createdBy: OWNER,
          createdAt: serverTimestamp(),
        },
      );
    });
  });

  const plan = (overrides = {}) => ({
    venueName: 'Narsingi Cricket Ground',
    sportIds: ['cricket'],
    courtIds: [],
    sessions: [{ startMinute: 480, endMinute: 1200, label: 'All day' }],
    blackouts: [],
    matchMinutes: 180,
    turnaroundMinutes: 30,
    maxMatchesPerCourtPerDay: 3,
    firstDay: null,
    lastDay: null,
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  const planRef = (db, venueId = 'v1') =>
    doc(db, 'orgs', PLANNER_ORG, 'tournaments', 't1', 'venuePlans', venueId);

  it('an organizer plans when a ground is available', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(planRef(db), plan()));
  });

  it('refuses an ordinary member planning the venues', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(setDoc(planRef(db), plan()));
  });

  it('refuses an outsider entirely', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(planRef(db), plan()));
  });

  // A negative or absurd ceiling is not a preference, it is a corrupt
  // document — and the scheduler reads it as a hard rule.
  it('refuses a negative daily maximum', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(planRef(db), plan({ maxMatchesPerCourtPerDay: -1 })),
    );
  });

  it('refuses a daily maximum no ground could ever meet', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(planRef(db), plan({ maxMatchesPerCourtPerDay: 5000 })),
    );
  });

  it('any member can read the plan — a hole in the timetable needs a reason', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PLANNER_ORG}/tournaments/t1/venuePlans/v1`),
        plan(),
      );
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(getDoc(planRef(db)));
  });

  it('an organizer clears a plan back to the venue defaults', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PLANNER_ORG}/tournaments/t1/venuePlans/v1`),
        plan(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(deleteDoc(planRef(db)));
  });

  it('refuses an ordinary member clearing a plan', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PLANNER_ORG}/tournaments/t1/venuePlans/v1`),
        plan(),
      );
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(deleteDoc(planRef(db)));
  });
});

describe('tournaments: officiating panel', () => {
  const UMPIRE = 'uid_umpire';

  beforeEach(async () => {
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
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t1`),
        {
          orgId: PUBLIC_ORG,
          name: 'Hyderabad District Championship',
          status: 'draft',
          eventCount: 0,
          createdBy: OWNER,
          createdAt: serverTimestamp(),
        },
      );
    });
  });

  const official = (overrides = {}) => ({
    name: 'Ravi Kumar',
    role: 'main_umpire',
    sports: ['cricket'],
    clubId: null,
    scoringRightsGranted: true,
    addedBy: OWNER,
    addedAt: serverTimestamp(),
    ...overrides,
  });

  const officialRef = (db, uid = UMPIRE) =>
    doc(db, 'orgs', PUBLIC_ORG, 'tournaments', 't1', 'officials', uid);

  it('an organizer adds someone to the panel ahead of the tournament', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(officialRef(db), official()));
  });

  it('refuses an ordinary member adding someone to the panel', async () => {
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(setDoc(officialRef(db), official()));
  });

  it('refuses an outsider entirely', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(officialRef(db), official()));
  });

  it('refuses a write that credits someone else for adding them', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(officialRef(db), official({ addedBy: PLAYER })),
    );
  });

  it('lets the organizer revoke scoring rights without removing them from the panel', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t1/officials/${UMPIRE}`),
        official(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(officialRef(db), { scoringRightsGranted: false }),
    );
  });

  it('refuses backdating who added an existing panel member', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t1/officials/${UMPIRE}`),
        official(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(officialRef(db), { addedBy: PLAYER }),
    );
  });

  it('an organizer removes someone from the panel', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t1/officials/${UMPIRE}`),
        official(),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(deleteDoc(officialRef(db)));
  });

  it('any org member can read the panel', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `orgs/${PUBLIC_ORG}/tournaments/t1/officials/${UMPIRE}`),
        official(),
      );
    });
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(getDoc(officialRef(db)));
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

// ---------------------------------------------------------------------------
// Raising a protest: the fixture flag that goes with it
// ---------------------------------------------------------------------------
//
// The protest DOCUMENT rules above were correct all along, and passing. What
// nothing exercised was the write the app actually makes:
// `CompetitionRepository.raiseDispute` commits the protest and the fixture's
// `status: 'disputed'` flag in ONE batch, because a bracket, a points table
// and a spectator card all read that flag from the document they already hold.
//
// No fixture-update branch admitted that second write for anyone but an
// organizer, so the whole batch was rejected and the protest died with it —
// "Protest this result", shown to every viewer, returned a permission error to
// exactly the competitor it exists for. These tests are the batch.
describe('raising a protest flags the fixture', () => {
  const COMP = 'comp_protest';
  const FIX = 'fix_protest';
  const MEMBER = 'uid_protester';

  const fixPath = (db) =>
    doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FIX);
  const disputePath = (db, id) =>
    doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FIX,
      'disputes', id);

  const protest = (uid, overrides = {}) => ({
    orgId: PUBLIC_ORG,
    compId: COMP,
    fixtureId: FIX,
    raisedByUid: uid,
    raisedByName: 'Aarav',
    entrantId: uid,
    reason: 'wrong_score',
    detail: 'Third set was 21-19.',
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
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP),
        { orgId: PUBLIC_ORG, name: 'Club Championship', status: 'in_progress' },
      );
      await setDoc(
        fixPath(db),
        { ...fixture(PUBLIC_ORG, COMP, [SCORER], 'completed'), lastSeq: 12 },
      );
    });
  });

  it('an ordinary member may protest a finished result', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    const batch = writeBatch(db);
    batch.set(disputePath(db, 'p1'), protest(MEMBER));
    batch.update(fixPath(db), {
      status: 'disputed',
      openDisputeId: 'p1',
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('refuses the flag without a protest to justify it', async () => {
    // Otherwise any member could mark any finished match disputed for sport.
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      updateDoc(fixPath(db), {
        status: 'disputed',
        openDisputeId: 'p_nonexistent',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a flag naming somebody else\'s protest', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    const batch = writeBatch(db);
    batch.set(disputePath(db, 'p2'), protest(OWNER));
    batch.update(fixPath(db), {
      status: 'disputed',
      openDisputeId: 'p2',
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('refuses a protest that smuggles a score change with it', async () => {
    // The branch is scoped to `status`/`updatedAt`/`openDisputeId`. Protesting
    // must not be a way to rewrite the thing being protested.
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    const batch = writeBatch(db);
    batch.set(disputePath(db, 'p3'), protest(MEMBER));
    batch.update(fixPath(db), {
      status: 'disputed',
      openDisputeId: 'p3',
      winnerEntrantId: 'entrant_a',
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('refuses a protest from somebody with no membership at all', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const batch = writeBatch(db);
    batch.set(disputePath(db, 'p4'), protest(OUTSIDER));
    batch.update(fixPath(db), {
      status: 'disputed',
      openDisputeId: 'p4',
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  // A completed match's RESULT is the score AND the names against it.
  //
  // The score fields were frozen long before the line-ups were, which left a
  // gap worth naming: an organizer could leave every number untouched and swap
  // a name in `lineupA`, handing one player's innings to somebody who was not
  // at the ground. Immutable figures with mutable attribution are not an
  // immutable result.
  //
  // The pair of tests below also pins something structural. The organizer
  // branch is the LAST `allow update` on a long OR chain, and Firestore
  // budgets 1,000 expressions per request — so a legitimate organizer write to
  // a completed fixture has to be shown to still land, not merely assumed.
  it('refuses an organizer rewriting who played a finished match', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(fixPath(db), {
        lineupA: [{ id: 'ringer', name: 'Someone Else' }],
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('still lets an organizer move a finished match\'s venue', async () => {
    // The freeze is on the result, not on the document. An organizer
    // correcting where a match was played is not rewriting who won it — and
    // this is the positive case that proves the branch is still REACHABLE
    // within the expression budget.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(fixPath(db), {
        venue: 'Corrected Ground',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('an organizer resolves it and clears the pointer', async () => {
    await seed(async (db) => {
      await setDoc(disputePath(db, 'p5'), protest(MEMBER));
      await updateDoc(fixPath(db), {
        status: 'disputed',
        openDisputeId: 'p5',
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);
    batch.update(disputePath(db, 'p5'), {
      status: 'rejected',
      resolvedByUid: OWNER,
      resolutionNote: 'Scorecard matches the event log.',
      resolvedAt: serverTimestamp(),
    });
    batch.update(fixPath(db), {
      status: 'completed',
      openDisputeId: null,
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });
});

// ---------------------------------------------------------------------------
// The owner's row
// ---------------------------------------------------------------------------
describe('an admin cannot unmake the owner', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN),
        membership(ADMIN, PUBLIC_ORG, 'admin'),
      );
    });
  });

  it('refuses an admin demoting the owner to member', async () => {
    // The escalation guard only ever looked at the INCOMING role, so this —
    // the write that actually mattered — passed every clause. It left the club
    // with nobody holding `canManageOrg`, and since `ownerUid` on the org is
    // immutable, no client could repair it.
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER), {
        role: 'member',
      }),
    );
  });

  it('refuses an admin suspending the owner', async () => {
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER), {
        status: 'suspended',
        role: 'member',
      }),
    );
  });

  it('the owner may still hand the role to somebody else', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', ADMIN), {
        role: 'owner',
      }),
    );
  });

  it('an admin may still manage an ordinary member', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', 'uid_plain'),
        membership('uid_plain', PUBLIC_ORG, 'member'),
      );
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', 'uid_plain'), {
        role: 'judge_scorer',
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Registration counters cannot simply be zeroed
// ---------------------------------------------------------------------------
describe('withdrawal counter drop is bounded', () => {
  const COMP = 'comp_counters';
  const MEMBER = 'uid_counter_member';

  const compRef = (db) =>
    doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP);

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', MEMBER),
        membership(MEMBER, PUBLIC_ORG, 'member'),
      );
      await setDoc(compRef(db), {
        orgId: PUBLIC_ORG,
        name: 'Sunday Cricket',
        status: 'registration_open',
        participationModel: 'open',
        maxEntrants: 13,
        waitlistEnabled: true,
        confirmedCount: 13,
        waitlistCount: 4,
      });
    });
  });

  it('refuses a member zeroing the confirmed count', async () => {
    // This was legal: "any decrease, not below zero, only these two fields".
    // No registration changed, nobody withdrew, and a full event silently
    // reopened to whoever refreshed next. A counter that can be zeroed is not
    // a capacity check.
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(updateDoc(compRef(db), { confirmedCount: 0 }));
  });

  it('refuses a member dropping the count by more than one', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(updateDoc(compRef(db), { confirmedCount: 9 }));
  });

  it('refuses dropping both counters in one write', async () => {
    // One withdrawal frees one place on one counter.
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      updateDoc(compRef(db), { confirmedCount: 12, waitlistCount: 3 }),
    );
  });

  it('allows a single withdrawal off the confirmed field', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(updateDoc(compRef(db), { confirmedCount: 12 }));
  });

  it('allows a single withdrawal off the waitlist', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(updateDoc(compRef(db), { waitlistCount: 3 }));
  });
});

// ---------------------------------------------------------------------------
// A visiting club opening its own side
// ---------------------------------------------------------------------------
describe('a contesting club may open its own squad call', () => {
  it('lets the guest club admin open registration for the guest side', async () => {
    // `squadCallA` was missing from `squadFieldsFor`, so the only branch that
    // could carry it was `isSquadCounterMove` — which explicitly refuses a
    // change to `open` or `capacity`, because that branch is for REGISTRANTS.
    // The club the feature exists for could not use it.
    await seedSquadCall({ callA: squadCall({ open: false }) });
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertSucceeds(
      updateDoc(fixRef(db), {
        squadCallA: squadCall({ open: true, capacity: 11 }),
      }),
    );
  });

  it('refuses the guest club opening the HOST club\'s side', async () => {
    await seedSquadCall({ callB: squadCall({ open: false }) });
    const db = testEnv.authenticatedContext(GUEST_ADMIN).firestore();
    await assertFails(
      updateDoc(fixRef(db), {
        squadCallB: squadCall({ open: true, capacity: 11 }),
      }),
    );
  });

  it('refuses an ordinary guest member opening their club\'s side', async () => {
    // Opening a call is an organizing act; joining one is not.
    await seedSquadCall({ callA: squadCall({ open: false }) });
    const db = testEnv.authenticatedContext(GUEST_MEMBER).firestore();
    await assertFails(
      updateDoc(fixRef(db), {
        squadCallA: squadCall({ open: true, capacity: 11 }),
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Give — the equipment-donation network.
//
// One shared shape across all three collections: a donor/org can only ever
// assert the FIRST fact in a pipeline. Everything downstream is gated by the
// same `admin` custom claim as `sportRules` above — nothing in the client
// can mint that token, so these tests use the same
// `authenticatedContext(uid, { admin: true })` escape hatch.
// ---------------------------------------------------------------------------
describe('give: collection centers are curated, not self-listed', () => {
  const centerPath = ['giveCollectionCenters', 'center_hyd'];
  const center = (overrides = {}) => ({
    name: 'Hyderabad Collection Centre',
    city: 'Hyderabad',
    cityKey: 'hyderabad',
    address: null,
    contactPhone: null,
    latitude: null,
    longitude: null,
    acceptedCategories: [],
    isActive: true,
    notes: null,
    ...overrides,
  });

  it('is world-readable, with or without an account', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, ...centerPath), center());
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, ...centerPath)));
  });

  it('refuses a signed-in stranger planting a fake center', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, ...centerPath), center()));
  });

  it('refuses even a club owner — this is not any club\'s to list', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(setDoc(doc(db, ...centerPath), center()));
  });

  it('admits the admin claim', async () => {
    const db = testEnv
      .authenticatedContext('uid_operator', { admin: true })
      .firestore();
    await assertSucceeds(setDoc(doc(db, ...centerPath), center()));
  });
});

describe('give: donations — a donor may only ever submit, never advance', () => {
  const donation = (overrides = {}) => ({
    donorUid: OWNER,
    donorName: 'Test Donor',
    donorPhone: null,
    type: 'equipment',
    items: [{ category: 'shoes', quantity: 2, note: null }],
    city: 'Hyderabad',
    cityKey: 'hyderabad',
    collectionCenterId: null,
    amountPaise: 0,
    status: 'submitted',
    // Firestore refuses serverTimestamp() inside an array element — see
    // GiveStatusEvent.toMap() for why this is a client-clock Date instead.
    history: [{ status: 'submitted', at: new Date() }],
    assignedNeedId: null,
    notes: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a signed-in donor submit their own donation', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'giveDonations', 'don_1'), donation()),
    );
  });

  it('refuses a donation submitted in someone else\'s name', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'giveDonations', 'don_1'),
        donation({ donorUid: OUTSIDER }),
      ),
    );
  });

  it('refuses a donor pre-setting a later stage', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'giveDonations', 'don_1'),
        donation({ status: 'distributed' }),
      ),
    );
  });

  it('refuses an equipment donation claiming a nonzero amount', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'giveDonations', 'don_1'),
        donation({ amountPaise: 50000 }),
      ),
    );
  });

  it('lets the donor read their own donation, refuses a stranger', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'giveDonations', 'don_1'), donation());
    });
    const owner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDoc(doc(owner, 'giveDonations', 'don_1')));

    const stranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(stranger, 'giveDonations', 'don_1')));
  });

  it('refuses the donor advancing their own donation\'s stage', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'giveDonations', 'don_1'), donation());
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'giveDonations', 'don_1'), { status: 'collected' }),
    );
  });

  it('lets staff (admin claim) advance a donation\'s stage', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'giveDonations', 'don_1'), donation());
    });
    const db = testEnv
      .authenticatedContext('uid_operator', { admin: true })
      .firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'giveDonations', 'don_1'), { status: 'collected' }),
    );
  });
});

describe('give: needs — self-reported for a player, club-authority for a team/club', () => {
  const need = (overrides = {}) => ({
    beneficiaryType: 'club',
    orgId: PUBLIC_ORG,
    orgName: 'Test Organization',
    playerUid: null,
    playerName: null,
    title: 'Cricket shoes for the village club',
    description: null,
    city: 'Nalgonda',
    cityKey: 'nalgonda',
    playersCount: 12,
    items: [{ category: 'shoes', quantity: 12, note: null }],
    fulfilled: [],
    status: 'open',
    verified: false,
    createdByUid: OWNER,
    createdAt: serverTimestamp(),
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
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member'),
      );
    });
  });

  it('lets a club owner raise a need for their own club', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, 'giveNeeds', 'need_1'), need()));
  });

  it('refuses an ordinary member raising a need in the club\'s name', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'giveNeeds', 'need_1'),
        need({ createdByUid: OUTSIDER }),
      ),
    );
  });

  it('refuses a stranger to the club raising a need in its name', async () => {
    const db = testEnv.authenticatedContext('uid_stranger_to_club').firestore();
    await assertFails(
      setDoc(
        doc(db, 'giveNeeds', 'need_1'),
        need({ createdByUid: 'uid_stranger_to_club' }),
      ),
    );
  });

  it('lets a player self-report their own need', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'giveNeeds', 'need_2'),
        need({
          beneficiaryType: 'player',
          orgId: null,
          orgName: null,
          playerUid: OUTSIDER,
          playerName: 'Test Player',
          createdByUid: OUTSIDER,
        }),
      ),
    );
  });

  it('refuses nominating someone else\'s player need', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'giveNeeds', 'need_2'),
        need({
          beneficiaryType: 'player',
          orgId: null,
          orgName: null,
          playerUid: OWNER,
          playerName: 'Someone Else',
          createdByUid: OUTSIDER,
        }),
      ),
    );
  });

  it('is world-readable unverified, but only staff may verify it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'giveNeeds', 'need_1'), need());
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'giveNeeds', 'need_1')));

    const asOwner = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(asOwner, 'giveNeeds', 'need_1'), { verified: true }),
    );

    const asStaff = testEnv
      .authenticatedContext('uid_operator', { admin: true })
      .firestore();
    await assertSucceeds(
      updateDoc(doc(asStaff, 'giveNeeds', 'need_1'), { verified: true }),
    );
  });
});

describe('give: impact stats — Cloud Function only, no client escape hatch', () => {
  it('is world-readable', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'give', 'impactStats'), {
        donationsCount: 5,
        itemsCollected: 5,
        itemsDistributed: 0,
        needsFulfilled: 0,
        citiesActive: 1,
        updatedAt: serverTimestamp(),
      });
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'give', 'impactStats')));
  });

  it('refuses every client write, even the admin claim — only the Admin SDK may write here', async () => {
    const db = testEnv
      .authenticatedContext('uid_operator', { admin: true })
      .firestore();
    await assertFails(
      setDoc(doc(db, 'give', 'impactStats'), { donationsCount: 1 }),
    );
  });
});

// ---------------------------------------------------------------------------
// Sponsor an Athlete / Sponsor a Team.
// ---------------------------------------------------------------------------
describe('sponsorship listings: adult self-publish, guardian-only for a minor', () => {
  const ADULT = 'uid_sponsor_adult_athlete';
  const MINOR_UID = 'uid_sponsor_minor_athlete';
  const GUARDIAN = 'uid_sponsor_guardian';

  const adultProfile = (uid) => ({
    uid,
    displayName: 'Adult Athlete',
    email: 'adult@example.com',
    dateOfBirth: new Date('1998-01-01'),
    gender: 'female',
    photoUrl: null,
    phone: null,
    profileVisibility: 'public',
    profileComplete: true,
    isMinor: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  const minorProfile = (guardianUid) => ({
    uid: MINOR_UID,
    displayName: 'Young Athlete',
    email: 'minor-athlete@example.com',
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

  const athleteListing = (overrides = {}) => ({
    targetType: 'athlete',
    subjectUid: null,
    subjectDisplayName: 'A. Athlete',
    orgId: null,
    orgName: null,
    sport: 'Athletics',
    geo: { district: 'Warangal' },
    headline: 'State U-16 100m champion',
    story: 'Trains before school every day.',
    achievementSummary: [],
    ratingPercentile: null,
    verificationTier: null,
    asks: [],
    status: 'open',
    sponsorsCount: 0,
    createdByUid: null,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  const teamListing = (overrides = {}) => ({
    targetType: 'team',
    subjectUid: null,
    subjectDisplayName: null,
    orgId: PUBLIC_ORG,
    orgName: 'Test Organization',
    sport: 'Cricket',
    geo: { district: 'Nalgonda' },
    headline: '27 wins in 32 matches this season',
    story: '',
    achievementSummary: [],
    ratingPercentile: null,
    verificationTier: null,
    asks: [],
    status: 'open',
    sponsorsCount: 0,
    createdByUid: null,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets an adult publish their own athlete listing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', ADULT), adultProfile(ADULT));
    });
    const db = testEnv.authenticatedContext(ADULT).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_adult'),
        athleteListing({ subjectUid: ADULT, createdByUid: ADULT }),
      ),
    );
  });

  it('refuses an adult publishing a listing naming someone else as the subject', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', ADULT), adultProfile(ADULT));
      await setDoc(doc(db, 'users', OUTSIDER), adultProfile(OUTSIDER));
    });
    const db = testEnv.authenticatedContext(ADULT).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_adult'),
        athleteListing({ subjectUid: OUTSIDER, createdByUid: ADULT }),
      ),
    );
  });

  it('refuses a minor publishing their own listing, even naming themselves', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
    });
    const db = testEnv.authenticatedContext(MINOR_UID).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_minor'),
        athleteListing({ subjectUid: MINOR_UID, createdByUid: MINOR_UID }),
      ),
    );
  });

  it('lets the minor\'s linked guardian publish a listing on their behalf', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(GUARDIAN));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_minor'),
        athleteListing({ subjectUid: MINOR_UID, createdByUid: GUARDIAN }),
      ),
    );
  });

  it('refuses an unrelated adult publishing a minor\'s listing', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(GUARDIAN));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_minor'),
        athleteListing({ subjectUid: MINOR_UID, createdByUid: OUTSIDER }),
      ),
    );
  });

  it('refuses publishing a minor\'s listing before any guardian is linked at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', MINOR_UID), minorProfile(null));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_minor'),
        athleteListing({ subjectUid: MINOR_UID, createdByUid: GUARDIAN }),
      ),
    );
  });

  it('lets a club owner publish a listing for their own team', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_team'),
        teamListing({ createdByUid: OWNER }),
      ),
    );
  });

  it('refuses an ordinary member publishing a team listing in the club\'s name', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'member'),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorshipListings', 'listing_team'),
        teamListing({ createdByUid: OUTSIDER }),
      ),
    );
  });

  it('is world-readable', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', ADULT), adultProfile(ADULT));
      await setDoc(
        doc(db, 'sponsorshipListings', 'listing_adult'),
        athleteListing({ subjectUid: ADULT, createdByUid: ADULT }),
      );
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'sponsorshipListings', 'listing_adult')));
  });

  it('lets the owner edit the story, but not sponsorsCount or status', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', ADULT), adultProfile(ADULT));
      await setDoc(
        doc(db, 'sponsorshipListings', 'listing_adult'),
        athleteListing({ subjectUid: ADULT, createdByUid: ADULT }),
      );
    });
    const db = testEnv.authenticatedContext(ADULT).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'sponsorshipListings', 'listing_adult'), {
        story: 'Updated story.',
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'sponsorshipListings', 'listing_adult'), {
        sponsorsCount: 5,
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'sponsorshipListings', 'listing_adult'), {
        status: 'closed',
      }),
    );
  });

  it('refuses a non-owner editing the listing at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', ADULT), adultProfile(ADULT));
      await setDoc(
        doc(db, 'sponsorshipListings', 'listing_adult'),
        athleteListing({ subjectUid: ADULT, createdByUid: ADULT }),
      );
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(doc(db, 'sponsorshipListings', 'listing_adult'), {
        story: 'Hijacked.',
      }),
    );
  });
});

describe('sponsorship pledges: two parties, two moves', () => {
  const SPONSOR = 'uid_sponsor_backer';
  const LISTING_OWNER = 'uid_sponsor_listing_owner';

  const pledge = (overrides = {}) => ({
    listingId: 'listing_1',
    sponsorUid: SPONSOR,
    sponsorDisplayName: 'A Backer',
    message: 'Happy to help with kit.',
    offeredCategories: ['equipment'],
    amountPaise: null,
    anonymous: false,
    status: 'pending',
    createdAt: serverTimestamp(),
    respondedAt: null,
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', LISTING_OWNER), {
        uid: LISTING_OWNER,
        displayName: 'Owner',
        email: 'owner@example.com',
        dateOfBirth: new Date('1990-01-01'),
        gender: 'male',
        photoUrl: null,
        phone: null,
        profileVisibility: 'public',
        profileComplete: true,
        isMinor: false,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'sponsorshipListings', 'listing_1'), {
        targetType: 'athlete',
        subjectUid: LISTING_OWNER,
        subjectDisplayName: 'Owner Athlete',
        orgId: null,
        orgName: null,
        sport: 'Athletics',
        geo: { district: 'Warangal' },
        headline: 'Rising sprinter',
        story: '',
        achievementSummary: [],
        ratingPercentile: null,
        verificationTier: null,
        asks: [],
        status: 'open',
        sponsorsCount: 0,
        createdByUid: LISTING_OWNER,
        createdAt: serverTimestamp(),
      });
    });
  });

  it('lets a signed-in sponsor offer against an existing listing', async () => {
    const db = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertSucceeds(setDoc(doc(db, 'sponsorPledges', 'pledge_1'), pledge()));
  });

  it('refuses a pledge claiming to be from somebody else', async () => {
    const db = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorPledges', 'pledge_1'),
        pledge({ sponsorUid: OUTSIDER }),
      ),
    );
  });

  it('refuses a pledge that pre-sets its own status past pending', async () => {
    const db = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorPledges', 'pledge_1'),
        pledge({ status: 'accepted' }),
      ),
    );
  });

  it('refuses a pledge against a listing that does not exist', async () => {
    const db = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertFails(
      setDoc(
        doc(db, 'sponsorPledges', 'pledge_ghost'),
        pledge({ listingId: 'no_such_listing' }),
      ),
    );
  });

  it('lets the sponsor and the listing owner read the pledge, refuses a stranger', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'sponsorPledges', 'pledge_1'), pledge());
    });

    const asSponsor = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertSucceeds(getDoc(doc(asSponsor, 'sponsorPledges', 'pledge_1')));

    const asOwner = testEnv.authenticatedContext(LISTING_OWNER).firestore();
    await assertSucceeds(getDoc(doc(asOwner, 'sponsorPledges', 'pledge_1')));

    const asStranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(asStranger, 'sponsorPledges', 'pledge_1')));
  });

  it('lets the listing owner accept a pending pledge, refuses the sponsor self-accepting', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'sponsorPledges', 'pledge_1'), pledge());
    });

    const asSponsor = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertFails(
      updateDoc(doc(asSponsor, 'sponsorPledges', 'pledge_1'), {
        status: 'accepted',
        respondedAt: serverTimestamp(),
      }),
    );

    const asOwner = testEnv.authenticatedContext(LISTING_OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'sponsorPledges', 'pledge_1'), {
        status: 'accepted',
        respondedAt: serverTimestamp(),
      }),
    );
  });

  it('lets the sponsor withdraw their own pending pledge, refuses the owner withdrawing it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'sponsorPledges', 'pledge_1'), pledge());
    });

    const asOwner = testEnv.authenticatedContext(LISTING_OWNER).firestore();
    await assertFails(
      updateDoc(doc(asOwner, 'sponsorPledges', 'pledge_1'), {
        status: 'withdrawn',
        respondedAt: serverTimestamp(),
      }),
    );

    const asSponsor = testEnv.authenticatedContext(SPONSOR).firestore();
    await assertSucceeds(
      updateDoc(doc(asSponsor, 'sponsorPledges', 'pledge_1'), {
        status: 'withdrawn',
        respondedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses moving a pledge that is no longer pending', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'sponsorPledges', 'pledge_1'),
        pledge({ status: 'accepted', respondedAt: serverTimestamp() }),
      );
    });
    const asOwner = testEnv.authenticatedContext(LISTING_OWNER).firestore();
    await assertFails(
      updateDoc(doc(asOwner, 'sponsorPledges', 'pledge_1'), {
        status: 'declined',
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Club Commerce — every club's own store.
// ---------------------------------------------------------------------------
describe('club commerce: products are owner-only to price, orders are launch-offer bounded', () => {
  const product = (overrides = {}) => ({
    orgId: PUBLIC_ORG,
    orgName: 'Test Organization',
    name: 'Home Jersey',
    description: '',
    category: 'jersey',
    listPricePaise: 89900,
    imageUrl: null,
    sizes: ['S', 'M', 'L'],
    isActive: true,
    createdByUid: OWNER,
    createdAt: serverTimestamp(),
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
        doc(db, 'orgs', PUBLIC_ORG, 'members', OUTSIDER),
        membership(OUTSIDER, PUBLIC_ORG, 'event_manager'),
      );
    });
  });

  it('lets the club owner list a product', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, 'clubProducts', 'prod_1'), product()));
  });

  it('refuses an event_manager (not owner) listing a product', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'clubProducts', 'prod_1'),
        product({ createdByUid: OUTSIDER }),
      ),
    );
  });

  it('is world-readable, even signed out', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'clubProducts', 'prod_1'), product());
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'clubProducts', 'prod_1')));
  });

  it('lets the owner reprice, refuses a non-owner editing at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'clubProducts', 'prod_1'), product());
    });
    const asOwner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'clubProducts', 'prod_1'), { listPricePaise: 99900 }),
    );
    const asOutsider = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(doc(asOutsider, 'clubProducts', 'prod_1'), { isActive: false }),
    );
  });

  const order = (overrides = {}) => ({
    orgId: PUBLIC_ORG,
    orgName: 'Test Organization',
    productId: 'prod_1',
    productName: 'Home Jersey',
    size: 'M',
    quantity: 1,
    buyerUid: OUTSIDER,
    buyerName: 'Test Buyer',
    unitListPricePaise: 89900,
    amountPaidPaise: 0,
    status: 'placed',
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a signed-in buyer place a launch-offer (₹0) order', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(setDoc(doc(db, 'clubOrders', 'order_1'), order()));
  });

  it('refuses an order claiming a nonzero amount was collected', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'clubOrders', 'order_1'),
        order({ amountPaidPaise: 89900 }),
      ),
    );
  });

  it('refuses an order placed in somebody else\'s name', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'clubOrders', 'order_1'), order({ buyerUid: OWNER })),
    );
  });

  it('lets the buyer and the club owner read the order, refuses a stranger', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'clubOrders', 'order_1'), order());
    });
    const asBuyer = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(asBuyer, 'clubOrders', 'order_1')));

    const asOwner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDoc(doc(asOwner, 'clubOrders', 'order_1')));

    const asStranger = testEnv.authenticatedContext('uid_commerce_stranger').firestore();
    await assertFails(getDoc(doc(asStranger, 'clubOrders', 'order_1')));
  });

  it('lets the club owner advance an order, refuses the buyer fulfilling their own', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'clubOrders', 'order_1'), order());
    });
    const asBuyer = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(doc(asBuyer, 'clubOrders', 'order_1'), { status: 'fulfilled' }),
    );

    const asOwner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'clubOrders', 'order_1'), { status: 'confirmed' }),
    );
  });

  it('lets the shared payments ledger accept a club_store row at ₹0', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'payments', 'pay_club_1'), {
        payerUid: OUTSIDER,
        kind: 'club_store',
        subjectId: 'order_1',
        plan: 'prod_1',
        amountPaise: 0,
        listPricePaise: 89900,
        validUntil: null,
        gateway: 'none',
        gatewayRef: null,
        currency: 'INR',
        createdAt: serverTimestamp(),
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Advertising — the self-serve console.
// ---------------------------------------------------------------------------
describe('ad campaigns: self-serve submission, staff-only review', () => {
  const ADVERTISER = 'uid_advertiser';
  const STAFF = 'uid_ad_staff';

  const campaign = (overrides = {}) => ({
    advertiserUid: ADVERTISER,
    advertiserName: 'Local Sports Store',
    headline: 'New season, new boots',
    body: 'Boots and balls for every side.',
    emoji: '⚽',
    ctaLabel: 'Shop now',
    sportIds: ['football'],
    destination: '/shop?sport=football',
    slots: ['home'],
    status: 'pending',
    budgetPaise: 500000,
    impressions: 0,
    clicks: 0,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a signed-in advertiser submit a pending campaign', async () => {
    const db = testEnv.authenticatedContext(ADVERTISER).firestore();
    await assertSucceeds(setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign()));
  });

  it('refuses a campaign submitted in somebody else\'s name', async () => {
    const db = testEnv.authenticatedContext(ADVERTISER).firestore();
    await assertFails(
      setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign({ advertiserUid: OUTSIDER })),
    );
  });

  it('refuses a campaign pre-approving itself, or pre-setting counters', async () => {
    const db = testEnv.authenticatedContext(ADVERTISER).firestore();
    await assertFails(
      setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign({ status: 'approved' })),
    );
    await assertFails(
      setDoc(doc(db, 'adCampaigns', 'camp_2'), campaign({ impressions: 1 })),
    );
  });

  it('refuses an external destination', async () => {
    const db = testEnv.authenticatedContext(ADVERTISER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'adCampaigns', 'camp_1'),
        campaign({ destination: 'https://example.com' }),
      ),
    );
  });

  it('is readable by its own advertiser and by staff while pending, but not by a stranger', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign());
    });
    const asAdvertiser = testEnv.authenticatedContext(ADVERTISER).firestore();
    await assertSucceeds(getDoc(doc(asAdvertiser, 'adCampaigns', 'camp_1')));

    const asStaff = testEnv.authenticatedContext(STAFF, { admin: true }).firestore();
    await assertSucceeds(getDoc(doc(asStaff, 'adCampaigns', 'camp_1')));

    const asStranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(asStranger, 'adCampaigns', 'camp_1')));
  });

  it('becomes world-readable once approved', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign({ status: 'approved' }));
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'adCampaigns', 'camp_1')));
  });

  it('refuses the advertiser approving their own campaign, lets staff do it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign());
    });
    const asAdvertiser = testEnv.authenticatedContext(ADVERTISER).firestore();
    await assertFails(
      updateDoc(doc(asAdvertiser, 'adCampaigns', 'camp_1'), { status: 'approved' }),
    );

    const asStaff = testEnv.authenticatedContext(STAFF, { admin: true }).firestore();
    await assertSucceeds(
      updateDoc(doc(asStaff, 'adCampaigns', 'camp_1'), { status: 'approved' }),
    );
  });

  it('lets any signed-in viewer bump impressions or clicks by exactly one, nothing else', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'adCampaigns', 'camp_1'), campaign({ status: 'approved' }));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'adCampaigns', 'camp_1'), { impressions: 1 }),
    );
    await assertSucceeds(
      updateDoc(doc(db, 'adCampaigns', 'camp_1'), { clicks: 1 }),
    );
    // Not by two at once, and not alongside another field.
    await assertFails(
      updateDoc(doc(db, 'adCampaigns', 'camp_1'), { impressions: 3 }),
    );
    await assertFails(
      updateDoc(doc(db, 'adCampaigns', 'camp_1'), { impressions: 2, headline: 'Hijacked' }),
    );
  });
});

// ---------------------------------------------------------------------------
// Talent discovery boards.
//
// The whole minor-safety story for §6 rests on these rules. `functions/talent.js`
// decides who is listed on which board, but that decision is only worth
// something if the gated board is actually gated — a `__scout` document served
// to anyone would make the public/scout split decorative.
// ---------------------------------------------------------------------------
describe('talent boards: public is open, scout boards need the claim', () => {
  const PUBLIC_BOARD = 'kabaddi__telangana__nalgonda___any__public';
  const SCOUT_BOARD = 'kabaddi__telangana__nalgonda___any__scout';

  const board = (audience) => ({
    sportId: 'kabaddi',
    state: 'telangana',
    district: 'nalgonda',
    ageGroup: '_any',
    audience,
    windowDays: 90,
    playerPoolSize: 1,
    teamPoolSize: 0,
    players: [
      {
        uid: 'uid_climber',
        displayName: 'Asha',
        rank: 1,
        score: 62.5,
        ratingDelta: 100,
        matchesInWindow: 5,
        ageGroupLabel: audience === 'scout' ? 'U-17' : 'Senior',
      },
    ],
    teams: [],
    computedAt: serverTimestamp(),
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'talentBoards', PUBLIC_BOARD), board('public'));
      await setDoc(doc(db, 'talentBoards', SCOUT_BOARD), board('scout'));
    });
  });

  it('serves a public board to anyone, signed in or not', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'talentBoards', PUBLIC_BOARD)));

    const signedIn = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(signedIn, 'talentBoards', PUBLIC_BOARD)));
  });

  it('refuses a scout board to an ordinary signed-in account', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'talentBoards', SCOUT_BOARD)));
  });

  it('refuses a scout board to an anonymous reader', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'talentBoards', SCOUT_BOARD)));
  });

  it('serves a scout board to the scout claim', async () => {
    const db = testEnv
      .authenticatedContext('uid_scout', { scout: true })
      .firestore();
    await assertSucceeds(getDoc(doc(db, 'talentBoards', SCOUT_BOARD)));
  });

  it('serves a scout board to platform staff, so support can see what a '
    + 'scout sees', async () => {
    const db = testEnv
      .authenticatedContext('uid_operator', { admin: true })
      .firestore();
    await assertSucceeds(getDoc(doc(db, 'talentBoards', SCOUT_BOARD)));
  });

  it('a claim of any other value does not open the gate', async () => {
    for (const claims of [{ scout: false }, { scout: 'yes' }, { scoutish: true }]) {
      const db = testEnv.authenticatedContext('uid_liar', claims).firestore();
      await assertFails(getDoc(doc(db, 'talentBoards', SCOUT_BOARD)));
    }
  });

  it('refuses every client write, even from a scout or an admin — boards are '
    + 'Admin SDK only', async () => {
    for (const claims of [{ scout: true }, { admin: true }, {}]) {
      const db = testEnv.authenticatedContext('uid_writer', claims).firestore();
      await assertFails(
        setDoc(doc(db, 'talentBoards', PUBLIC_BOARD), board('public')),
      );
      await assertFails(
        updateDoc(doc(db, 'talentBoards', PUBLIC_BOARD), { players: [] }),
      );
      await assertFails(deleteDoc(doc(db, 'talentBoards', PUBLIC_BOARD)));
    }
  });

  it('a board id with neither suffix is denied by default, not served', async () => {
    // Guards the id-matching approach itself: a malformed or future id must
    // fall through to a deny rather than matching the public branch loosely.
    await seed(async (db) => {
      await setDoc(doc(db, 'talentBoards', 'kabaddi___any___any___any'), board('public'));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      getDoc(doc(db, 'talentBoards', 'kabaddi___any___any___any')),
    );
  });

  it('listing the collection is denied even for a scout — a board is read by '
    + 'id, never enumerated', async () => {
    const db = testEnv
      .authenticatedContext('uid_scout', { scout: true })
      .firestore();
    await assertFails(getDocs(collection(db, 'talentBoards')));
  });
});

// ---------------------------------------------------------------------------
// Per-sport stat leaderboards — `functions/leaderboard.js`.
//
// Simpler than talent boards: there is no gated variant, because eligibility
// (public visibility, not a minor) is decided entirely server-side before a
// row is ever written — see the rules file's own comment. So this only has
// to confirm the doc is public and that a client can never write one.
// ---------------------------------------------------------------------------
describe('leaderboards: public read, admin-sdk-only write', () => {
  const BOARD_ID = 'cricket:runsScored';

  const board = () => ({
    sportId: 'cricket',
    statKey: 'runsScored',
    entries: [
      { uid: 'uid_topscorer', displayName: 'Meera', photoUrl: null, value: 812, rank: 1 },
    ],
    updatedAt: serverTimestamp(),
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'leaderboards', BOARD_ID), board());
    });
  });

  it('serves a board to anyone, signed in or not', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'leaderboards', BOARD_ID)));

    const signedIn = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(signedIn, 'leaderboards', BOARD_ID)));
  });

  it('allows listing the collection — a board id is not a secret the way a '
    + 'scout board id is', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDocs(collection(db, 'leaderboards')));
  });

  it('refuses every client write, even from an admin — boards are Admin SDK '
    + 'only', async () => {
    for (const claims of [{ admin: true }, {}]) {
      const db = testEnv.authenticatedContext('uid_writer', claims).firestore();
      await assertFails(setDoc(doc(db, 'leaderboards', BOARD_ID), board()));
      await assertFails(
        updateDoc(doc(db, 'leaderboards', BOARD_ID), { entries: [] }),
      );
      await assertFails(deleteDoc(doc(db, 'leaderboards', BOARD_ID)));
    }
  });
});

// ---------------------------------------------------------------------------
// Grounds marketplace.
//
// A ground is a business, not a club — see Refs.grounds' doc comment — so the
// trust shape is "one owner, checked by uid" throughout, the same pattern
// `groundOwnerUid` gives `groundMenuItems`/`foodOrders` below.
// ---------------------------------------------------------------------------
describe('grounds: owner-only listing, world-readable, isVerified/bookingCount locked', () => {
  const GROUND = 'ground_1';
  const GROUND_OWNER = 'uid_ground_owner';

  const ground = (overrides = {}) => ({
    ownerUid: GROUND_OWNER,
    name: 'Sunrise Turf',
    city: 'Hyderabad',
    cityKey: 'hyderabad',
    address: null,
    district: null,
    latitude: null,
    longitude: null,
    geohash: null,
    sportIds: ['cricket'],
    hourlyRatePaise: 100000,
    openHour: 6,
    closeHour: 22,
    facilities: [],
    surface: null,
    isIndoor: false,
    capacity: null,
    contactPhone: null,
    photoUrl: null,
    notes: null,
    isActive: true,
    isVerified: false,
    bookingCount: 0,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a signed-in person list a ground naming themselves owner', async () => {
    const db = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, 'grounds', GROUND), ground()));
  });

  it('refuses listing a ground already verified, or owned by someone else', async () => {
    const db = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'grounds', GROUND), ground({ isVerified: true })),
    );
    await assertFails(
      setDoc(
        doc(db, 'grounds', GROUND),
        ground({ ownerUid: 'uid_someone_else' }),
      ),
    );
  });

  it('is world-readable, even signed out', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND), ground());
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'grounds', GROUND)));
  });

  it('lets the owner reprice, refuses a stranger editing at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND), ground());
    });
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'grounds', GROUND), { hourlyRatePaise: 120000 }),
    );
    const asStranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(doc(asStranger, 'grounds', GROUND), { hourlyRatePaise: 1 }),
    );
  });

  it('refuses the owner setting their own isVerified or bookingCount', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND), ground());
    });
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertFails(
      updateDoc(doc(asOwner, 'grounds', GROUND), { isVerified: true }),
    );
    await assertFails(
      updateDoc(doc(asOwner, 'grounds', GROUND), { bookingCount: 999 }),
    );
  });

  it('never allows a delete — isActive: false is the only way a listing '
    + 'goes away', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND), ground());
    });
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertFails(deleteDoc(doc(asOwner, 'grounds', GROUND)));
  });
});

describe('ground bookings: price derived server-side, hourHolds are the real '
  + 'exclusivity guard', () => {
  const GROUND = 'ground_2';
  const GROUND_OWNER = 'uid_ground_owner_2';
  const BOOKER = 'uid_booker';

  const booking = (overrides = {}) => ({
    groundId: GROUND,
    groundName: 'Sunrise Turf',
    dayKey: '2026-08-10',
    startHour: 18,
    endHour: 20,
    startsAt: serverTimestamp(),
    bookedByUid: BOOKER,
    bookedByName: 'Test Booker',
    bookedForOrgId: null,
    competitionId: null,
    sportId: 'cricket',
    amountPaise: 200000, // 2 hours at the ground's 100,000-paise hourly rate
    paymentId: null,
    notes: null,
    status: 'confirmed',
    createdAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND), {
        ownerUid: GROUND_OWNER,
        name: 'Sunrise Turf',
        city: 'Hyderabad',
        cityKey: 'hyderabad',
        hourlyRatePaise: 100000,
        openHour: 6,
        closeHour: 22,
        sportIds: ['cricket'],
        facilities: [],
        isActive: true,
        isVerified: false,
        bookingCount: 0,
        createdAt: serverTimestamp(),
      });
    });
  });

  it('accepts a booking priced at exactly hourlyRate × hours', async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking()),
    );
  });

  it("refuses a booking that understates the ground's own rate", async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'grounds', GROUND, 'bookings', 'bk_1'),
        booking({ amountPaise: 1 }),
      ),
    );
  });

  it('refuses a booking longer than 12 hours', async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'grounds', GROUND, 'bookings', 'bk_1'),
        booking({ startHour: 6, endHour: 19, amountPaise: 1300000 }),
      ),
    );
  });

  it("refuses booking in somebody else's name", async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'grounds', GROUND, 'bookings', 'bk_1'),
        booking({ bookedByUid: OUTSIDER }),
      ),
    );
  });

  it('lets the booker or the ground owner cancel, refuses a stranger', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
    });
    const asStranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      updateDoc(doc(asStranger, 'grounds', GROUND, 'bookings', 'bk_1'), {
        status: 'cancelled',
      }),
    );
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'grounds', GROUND, 'bookings', 'bk_1'), {
        status: 'cancelled',
        cancelledAt: serverTimestamp(),
      }),
    );
  });

  it("refuses moving a confirmed booking's hours instead of its status", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
    });
    const asBooker = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      updateDoc(doc(asBooker, 'grounds', GROUND, 'bookings', 'bk_1'), {
        startHour: 10,
        endHour: 12,
      }),
    );
  });

  // -------------------------------------------------------------------
  // hourHolds — the fix for the double-booking race. See firestore.rules
  // and GroundRepository.book for the full story: a query-based check
  // inside a transaction cannot prevent two clients racing for the same
  // hour, and this per-hour, deterministically-id'd document is what
  // actually can.
  // -------------------------------------------------------------------

  const hold = (overrides = {}) => ({
    bookingId: 'bk_1',
    bookedByUid: BOOKER,
    dayKey: '2026-08-10',
    hour: 18,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a booking create its own hour holds in the same batch', async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
    batch.set(
      doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
      hold({ hour: 18 }),
    );
    batch.set(
      doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_19'),
      hold({ hour: 19 }),
    );
    await assertSucceeds(batch.commit());
  });

  // -------------------------------------------------------------------
  // The whole write GroundRepository.book actually performs.
  //
  // Every test above checks one document of it in isolation, and each of
  // them passed while booking was completely broken in the app: the
  // transaction also bumps the GROUND's `bookingCount`, and the only
  // `allow update` on a ground required `ownerUid == uid()`. So every
  // booking by anybody other than the ground's own owner — which is every
  // real booking — died on that one line with permission-denied, surfacing
  // as "Something went wrong".
  //
  // This test is the shape of the real transaction, run as a stranger,
  // because that is the only shape that could have caught it.
  // -------------------------------------------------------------------
  it('lets a stranger complete a whole booking: doc, holds and the '
    + "ground's own bookingCount", async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
    batch.set(
      doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
      hold({ hour: 18 }),
    );
    batch.set(
      doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_19'),
      hold({ hour: 19 }),
    );
    batch.update(doc(db, 'grounds', GROUND), {
      bookingCount: increment(1),
    });
    await assertSucceeds(batch.commit());
  });

  it('refuses a stranger touching anything on the ground except the '
    + 'counter', async () => {
    // The counter bump is the one write a non-owner may make to a ground.
    // Opening it must not have opened the listing itself — the price, the
    // hours and the verified badge are still the owner's alone.
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      updateDoc(doc(db, 'grounds', GROUND), {
        bookingCount: increment(1),
        hourlyRatePaise: 1,
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'grounds', GROUND), { isVerified: true }),
    );
  });

  it('refuses a stranger inflating the counter by more than one', async () => {
    // One booking, one increment. A ground's booking count is the closest
    // thing it has to a reputation, and a stranger who could add 500 to it
    // could sell that.
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      updateDoc(doc(db, 'grounds', GROUND), { bookingCount: increment(50) }),
    );
    await assertFails(
      updateDoc(doc(db, 'grounds', GROUND), { bookingCount: 999 }),
    );
  });

  it('refuses an hour hold with no matching booking in the same batch', async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      setDoc(doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'), hold()),
    );
  });

  it("refuses an hour hold outside the booking's own [startHour, endHour)", async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
    // bk_1 covers 18–20; 21 is not in range.
    batch.set(
      doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_21'),
      hold({ hour: 21 }),
    );
    await assertFails(batch.commit());
  });

  it("refuses an hour hold claimed under somebody else's booking", async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'grounds', GROUND, 'bookings', 'bk_owned_by_someone_else'),
        booking({ bookedByUid: OUTSIDER }),
      );
    });
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
        hold({ bookingId: 'bk_owned_by_someone_else' }),
      ),
    );
  });

  it("refuses a hold id that does not match its own dayKey/hour", async () => {
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
    batch.set(
      // Payload says hour 18; the document id claims 19.
      doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_19'),
      hold({ hour: 18 }),
    );
    await assertFails(batch.commit());
  });

  it('refuses overwriting an hour hold that already exists — the actual '
    + 'exclusivity guarantee behind the fix', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
        hold({ bookingId: 'bk_first' }),
      );
    });
    // A second booking trying to take the same hour hits `allow update: if
    // false` the instant the document already exists. This is the rule that
    // makes the race GroundRepository.book guards against actually
    // unwinnable — a client racing to `tx.set` this id after another
    // transaction already committed it finds this exact denial on retry.
    const db = testEnv.authenticatedContext('uid_second_booker').firestore();
    await assertFails(
      setDoc(
        doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
        hold({ bookingId: 'bk_second', bookedByUid: 'uid_second_booker' }),
      ),
    );
  });

  it('IS readable by a signed-in caller — the exclusivity check reads it', async () => {
    // Deliberately readable. `GroundRepository.book` runs a transaction that
    // must `get()` each hold to see whether the slot is taken, and a
    // transaction's reads are gated by these rules — so `read: if false` made
    // every booking fail on that first read. A hold carries only a booking id,
    // a day and an hour; the calendar people browse is `bookings`, not this.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
        hold(),
      );
    });
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertSucceeds(
      getDoc(doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18')),
    );
  });

  it('completes the REAL transaction: get the holds, then write them, the '
    + 'booking and the counter', async () => {
    // The shape the app actually uses — a `runTransaction` whose reads are
    // subject to the rules, unlike the `writeBatch` every other test here
    // uses. This is the only shape that could have caught the dead-booking
    // bug: the batch tests passed while `read: if false` blocked the get().
    // The ground is already seeded by this block's beforeEach.
    const db = testEnv.authenticatedContext(BOOKER).firestore();
    await assertSucceeds(runTransaction(db, async (tx) => {
      const h18 = doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18');
      const h19 = doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_19');
      await tx.get(h18);
      await tx.get(h19);
      tx.set(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
      tx.set(h18, hold({ hour: 18 }));
      tx.set(h19, hold({ hour: 19 }));
      tx.update(doc(db, 'grounds', GROUND), { bookingCount: increment(1) });
    }));
  });

  it('lets the booker release their own hold, and the ground owner release '
    + 'it too', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND, 'bookings', 'bk_1'), booking());
      await setDoc(
        doc(db, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
        hold(),
      );
    });
    const asStranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      deleteDoc(
        doc(asStranger, 'grounds', GROUND, 'hourHolds', '2026-08-10_18'),
      ),
    );
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(
      deleteDoc(doc(asOwner, 'grounds', GROUND, 'hourHolds', '2026-08-10_18')),
    );
  });
});

// ---------------------------------------------------------------------------
// Food & delivery at the ground.
// ---------------------------------------------------------------------------
describe('ground food: menu is owner-only to price, orders are launch-offer '
  + 'bounded', () => {
  const GROUND = 'ground_food_1';
  const GROUND_OWNER = 'uid_food_ground_owner';
  const BUYER = 'uid_food_buyer';

  const menuItem = (overrides = {}) => ({
    groundId: GROUND,
    groundName: 'Sunrise Turf',
    name: 'Water bottle',
    description: '',
    category: 'drinks',
    priceInPaise: 2000,
    isActive: true,
    createdByUid: GROUND_OWNER,
    createdAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'grounds', GROUND), {
        ownerUid: GROUND_OWNER,
        name: 'Sunrise Turf',
        city: 'Hyderabad',
        cityKey: 'hyderabad',
        hourlyRatePaise: 100000,
        openHour: 6,
        closeHour: 22,
        sportIds: [],
        facilities: [],
        isActive: true,
        isVerified: false,
        bookingCount: 0,
        createdAt: serverTimestamp(),
      });
    });
  });

  it('lets the ground owner list a menu item', async () => {
    const db = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'groundMenuItems', 'item_1'), menuItem()),
    );
  });

  it("refuses a non-owner listing an item on someone else's ground", async () => {
    const db = testEnv.authenticatedContext(BUYER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'groundMenuItems', 'item_1'),
        menuItem({ createdByUid: BUYER }),
      ),
    );
  });

  it('is world-readable, even signed out', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groundMenuItems', 'item_1'), menuItem());
    });
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'groundMenuItems', 'item_1')));
  });

  it('lets the owner reprice, refuses a stranger editing at all', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'groundMenuItems', 'item_1'), menuItem());
    });
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'groundMenuItems', 'item_1'), {
        priceInPaise: 2500,
      }),
    );
    const asStranger = testEnv.authenticatedContext(BUYER).firestore();
    await assertFails(
      updateDoc(doc(asStranger, 'groundMenuItems', 'item_1'), {
        priceInPaise: 1,
      }),
    );
  });

  it('refuses a negative price', async () => {
    const db = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'groundMenuItems', 'item_1'),
        menuItem({ priceInPaise: -100 }),
      ),
    );
  });

  const order = (overrides = {}) => ({
    groundId: GROUND,
    groundName: 'Sunrise Turf',
    lines: [
      { menuItemId: 'item_1', name: 'Water bottle', quantity: 2, unitPricePaise: 2000 },
    ],
    buyerUid: BUYER,
    buyerName: 'Test Buyer',
    deliveryPartner: 'manual',
    partnerRef: null,
    amountPaidPaise: 0,
    status: 'placed',
    createdAt: serverTimestamp(),
    ...overrides,
  });

  it('lets a signed-in buyer place a launch-offer (₹0) order', async () => {
    const db = testEnv.authenticatedContext(BUYER).firestore();
    await assertSucceeds(setDoc(doc(db, 'foodOrders', 'order_1'), order()));
  });

  it('refuses an order claiming a nonzero amount was collected', async () => {
    const db = testEnv.authenticatedContext(BUYER).firestore();
    await assertFails(
      setDoc(doc(db, 'foodOrders', 'order_1'), order({ amountPaidPaise: 4000 })),
    );
  });

  it("refuses an empty order, and one placed in somebody else's name", async () => {
    const db = testEnv.authenticatedContext(BUYER).firestore();
    await assertFails(
      setDoc(doc(db, 'foodOrders', 'order_1'), order({ lines: [] })),
    );
    await assertFails(
      setDoc(doc(db, 'foodOrders', 'order_1'), order({ buyerUid: OUTSIDER })),
    );
  });

  it('lets the buyer and the ground owner read the order, refuses a '
    + 'stranger', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'foodOrders', 'order_1'), order());
    });
    const asBuyer = testEnv.authenticatedContext(BUYER).firestore();
    await assertSucceeds(getDoc(doc(asBuyer, 'foodOrders', 'order_1')));
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(getDoc(doc(asOwner, 'foodOrders', 'order_1')));
    const asStranger =
      testEnv.authenticatedContext('uid_food_stranger').firestore();
    await assertFails(getDoc(doc(asStranger, 'foodOrders', 'order_1')));
  });

  it('lets the ground owner advance an order, refuses the buyer fulfilling '
    + 'their own', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'foodOrders', 'order_1'), order());
    });
    const asBuyer = testEnv.authenticatedContext(BUYER).firestore();
    await assertFails(
      updateDoc(doc(asBuyer, 'foodOrders', 'order_1'), { status: 'preparing' }),
    );
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(asOwner, 'foodOrders', 'order_1'), { status: 'preparing' }),
    );
  });

  it("refuses the owner smuggling a paid amount in through a status update", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'foodOrders', 'order_1'), order());
    });
    const asOwner = testEnv.authenticatedContext(GROUND_OWNER).firestore();
    await assertFails(
      updateDoc(doc(asOwner, 'foodOrders', 'order_1'), {
        status: 'preparing',
        amountPaidPaise: 4000,
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// Government dashboard rollups — `functions/gov.js`. Admin-claim gated read,
// no client write path at all — see the rule's own comment for why.
// ---------------------------------------------------------------------------
describe('gov aggregates: admin-claim read, no client write ever', () => {
  const ROW = 'telangana__nalgonda';

  const row = (overrides = {}) => ({
    state: 'telangana',
    district: 'nalgonda',
    clubCount: 12,
    memberCount: 480,
    competitionCount: 30,
    completedMatchCount: 210,
    source: 'firestore-scan',
    computedAt: serverTimestamp(),
    ...overrides,
  });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'gov_aggregates', ROW), row());
    });
  });

  it('refuses a read from an ordinary signed-in account', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'gov_aggregates', ROW)));
  });

  it('refuses a read from a signed-out visitor', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'gov_aggregates', ROW)));
  });

  it('serves the row to the admin claim', async () => {
    const db = testEnv
      .authenticatedContext('uid_gov_admin', { admin: true })
      .firestore();
    await assertSucceeds(getDoc(doc(db, 'gov_aggregates', ROW)));
  });

  it('refuses every client write, even from an admin — Admin SDK only', async () => {
    const db = testEnv
      .authenticatedContext('uid_gov_admin', { admin: true })
      .firestore();
    await assertFails(setDoc(doc(db, 'gov_aggregates', ROW), row()));
    await assertFails(
      updateDoc(doc(db, 'gov_aggregates', ROW), { clubCount: 999 }),
    );
    await assertFails(deleteDoc(doc(db, 'gov_aggregates', ROW)));
  });
});

// ---------------------------------------------------------------------------
// Teams — top-level, club-optional (Rule 4)
// ---------------------------------------------------------------------------
//
// The rules carry three jobs the client cannot be trusted with: the
// type/clubId pairing, the freeze on the fields that decide authority
// (`createdByUid`, `clubId`, `sportId`), and the no-delete guarantee that
// keeps match history walkable.
describe('teams', () => {
  const TEAM = 'team_strikers';
  const CAPTAIN = 'uid_captain';
  const PLAYER = 'uid_player';

  /** A team document as TeamRepository.createTeam writes it. */
  const team = (over = {}) => ({
    name: 'Hyderabad Strikers',
    sportId: 'cricket',
    type: 'independent',
    createdByUid: CAPTAIN,
    clubId: null,
    captainUid: CAPTAIN,
    managerUid: null,
    memberUids: [CAPTAIN, PLAYER],
    status: 'active',
    competitionId: null,
    baseTeamId: null,
    photoUrl: null,
    homeArea: 'Gachibowli',
    createdAt: serverTimestamp(),
    ...over,
  });

  const seedTeam = (over = {}) =>
    seed(async (db) => {
      await setDoc(doc(db, 'teams', TEAM), team(over));
    });

  it('lets a signed-in person found a club-less team', async () => {
    // Rule 4 in one assertion: no club, no org membership, still a team.
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertSucceeds(setDoc(doc(db, 'teams', TEAM), team()));
  });

  it('refuses a team created in somebody else name', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(doc(db, 'teams', TEAM), team()));
  });

  it('refuses a founder who leaves themselves off the roster', async () => {
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(
      setDoc(doc(db, 'teams', TEAM), team({ memberUids: [PLAYER] })),
    );
  });

  it('refuses an independent team that names a club', async () => {
    // The pairing matters for authority, not tidiness: the admin branch only
    // fires when clubId is set, so a mistyped team is a team with a confused
    // owner.
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(
      setDoc(doc(db, 'teams', TEAM), team({ clubId: PUBLIC_ORG })),
    );
  });

  it('refuses a permanent team with no club', async () => {
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(
      setDoc(doc(db, 'teams', TEAM), team({ type: 'permanent' })),
    );
  });

  it('refuses claiming a club the creator cannot manage', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'teams', TEAM),
        team({
          type: 'permanent',
          clubId: PUBLIC_ORG,
          createdByUid: OUTSIDER,
          captainUid: OUTSIDER,
          memberUids: [OUTSIDER],
        }),
      ),
    );
  });

  it('refuses an event team that does not name its competition', async () => {
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(setDoc(doc(db, 'teams', TEAM), team({ type: 'event' })));
  });

  it('lets the captain rename the team', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'teams', TEAM), { name: 'Strikers XI' }),
    );
  });

  it('refuses an outsider renaming the team', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(updateDoc(doc(db, 'teams', TEAM), { name: 'Mine now' }));
  });

  it('refuses a roster member editing the team they merely play for', async () => {
    // Being on the roster is not authority. Only creator/captain/manager, or
    // an admin of a club the team already names.
    await seedTeam();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(updateDoc(doc(db, 'teams', TEAM), { name: 'Mine now' }));
  });

  it('freezes createdByUid against an owner takeover', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'teams', TEAM), { createdByUid: OUTSIDER }),
    );
  });

  it('freezes clubId, so a team cannot be walked into a club', async () => {
    // Moving a team between clubs would carry its whole match history with
    // it, which is not something one field write may do.
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'teams', TEAM), {
        clubId: PUBLIC_ORG,
        type: 'permanent',
      }),
    );
  });

  it('freezes sportId', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'teams', TEAM), { sportId: 'football' }),
    );
  });

  it('lets a player remove themselves without the captain', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'teams', TEAM), { memberUids: [CAPTAIN] }),
    );
  });

  it('refuses a departure that also adds somebody', async () => {
    // The subset check is what stops self-leave being a general roster edit.
    await seedTeam();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      updateDoc(doc(db, 'teams', TEAM), { memberUids: [CAPTAIN, OUTSIDER] }),
    );
  });

  it('refuses removing somebody else under cover of leaving', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(updateDoc(doc(db, 'teams', TEAM), { memberUids: [] }));
  });

  it('refuses a departing player installing a captain on the way out', async () => {
    // Probes `isSelfLeave` specifically, so the caller must be somebody with
    // no other authority — a captain doing this is exercising the ordinary
    // management branch, which is allowed and is covered separately below.
    await seedTeam();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(
      updateDoc(doc(db, 'teams', TEAM), {
        memberUids: [CAPTAIN],
        captainUid: OUTSIDER,
      }),
    );
  });

  it('clears the captaincy when the captain is the one leaving', async () => {
    // The one role change a departure may make, and it may only be a clear.
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'teams', TEAM), {
        memberUids: [PLAYER],
        captainUid: null,
      }),
    );
  });

  it('lets the captain manage the roster and name a successor', async () => {
    // Deliberate, not an oversight: running the squad is what a captain is
    // for. This is the ordinary management branch, not `isSelfLeave`.
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'teams', TEAM), {
        memberUids: [CAPTAIN],
        captainUid: PLAYER,
      }),
    );
  });

  it('never allows a delete, however senior the caller', async () => {
    // Rule 31/16: fixtures, entrants and career statistics point here.
    await seedTeam();
    const db = testEnv.authenticatedContext(CAPTAIN).firestore();
    await assertFails(deleteDoc(doc(db, 'teams', TEAM)));
  });

  it('requires an account to read a roster', async () => {
    await seedTeam();
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'teams', TEAM)));
  });

  it('serves a team to any signed-in person', async () => {
    await seedTeam();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(db, 'teams', TEAM)));
  });
});

// ---------------------------------------------------------------------------
// The career query — "every match this player has appeared in, anywhere".
//
// `CareerRepository.watchPlayerFixtures` runs
// `collectionGroup('fixtures').where('playerUids', arrayContains: uid)` with no
// other constraint, and it is the only source for the Matches list on a career
// profile, the sport page and the head-to-head table. Every fixtures test above
// pins `orgId` or `scorerUids`, so this shape had never been exercised.
// ---------------------------------------------------------------------------
describe('career: a player reading their own matches across every club', () => {
  const PLAYER = 'uid_player';
  const OTHER_PUBLIC_ORG = 'org_public_2';

  /** `count` public-org fixtures the player played in and did NOT score. */
  async function seedCareer(count) {
    await seed(async (db) => {
      for (const orgId of [PUBLIC_ORG, OTHER_PUBLIC_ORG]) {
        await setDoc(doc(db, 'orgs', orgId), organization(OWNER, 'public'));
      }
      for (let i = 0; i < count; i++) {
        const orgId = i % 2 === 0 ? PUBLIC_ORG : OTHER_PUBLIC_ORG;
        await setDoc(
          doc(db, 'orgs', orgId, 'competitions', `comp${i}`, 'fixtures', `fx${i}`),
          {
            ...fixture(orgId, `comp${i}`, [SCORER], 'completed'),
            playerUids: [PLAYER],
          },
        );
      }
    });
  }

  const careerQuery = (db) =>
    query(
      collectionGroup(db, 'fixtures'),
      where('playerUids', 'array-contains', PLAYER),
      limit(300),
    );

  it('reads a handful of matches', async () => {
    await seedCareer(3);
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const snap = await assertSucceeds(getDocs(careerQuery(db)));
    assert.equal(snap.size, 3);
  });

  it('reads a real career — more matches than a rule may make lookups', async () => {
    // The reason this is the interesting number: the rule resolved each
    // fixture's club with a `get()`, and a query may make at most ten document
    // lookups in total. A career of fifteen matches therefore failed outright,
    // while the three above passed — which is why the Matches list said
    // "Could not load matches" on an account whose statistics rendered fine.
    await seedCareer(15);
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const snap = await assertSucceeds(getDocs(careerQuery(db)));
    assert.equal(snap.size, 15);
  });

  it('still refuses a VISITOR listing somebody else\'s career', async () => {
    // The known limit recorded on the rule. A visitor is in neither array, and
    // the org branch cannot be evaluated because a career query cannot pin
    // `orgId` — so there is nothing left to authorize the list. Asserted
    // rather than left untested so that closing it (an `audience` field on the
    // fixture, as memories already carry) turns this red instead of going
    // unnoticed.
    await seedCareer(15);
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDocs(careerQuery(db)));
  });
});

// ---------------------------------------------------------------------------
// The owner who cannot score their own club's match
// ---------------------------------------------------------------------------
//
// Reported as "even though I am the owner and I am scoring, the app says I am
// not the one scoring". It is not a pen conflict and not a device problem —
// nobody else holds the pen at all.
//
// `ScoringScreen` opens the pad for anyone with `manageCompetitions`, and
// `generateDraw` deliberately writes an EMPTY `scorerUids` (its own doc
// comment says so, and promises "an unassigned match is not an unscorable one
// — an organizer may score any match in their own club"). So the ordinary
// club case is: owner walks up to a match nobody was assigned to, opens the
// pad, taps.
//
// The fixture update passes — branch (a) admits an organizer. The EVENT
// create is the one that fails, and because a scoring write is a batch
// containing both, the whole thing rolls back: the score moves on the
// scorer's screen from the local cache, then jumps back a second later.
describe('an organizer scoring an unassigned match in their own club', () => {
  const COMP = 'comp1';
  const FX = 'fx_unassigned';

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP), {
        orgId: PUBLIC_ORG,
        name: 'Club Championship',
        sportId: 'badminton',
        format: 'knockout',
        status: 'in_progress',
        createdAt: serverTimestamp(),
      });
      // Exactly what the draw generator writes: nobody assigned to score.
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FX),
        fixture(PUBLIC_ORG, COMP, []),
      );
    });
  });

  /** The batch `ScoringService.submit` actually issues. */
  const scoringBatch = (db) => {
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FX,
        'events', '0000000001'),
      {
        seq: 1,
        type: 'point',
        payload: { side: 'a' },
        byUid: OWNER,
        clientEventId: 'abc123',
        at: serverTimestamp(),
      },
    );
    batch.update(
      doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FX),
      {
        scoreState: { currentA: 1 },
        lastSeq: 1,
        summary: '1-0',
        status: 'live',
        winnerEntrantId: null,
        isDraw: false,
      },
    );
    return batch;
  };

  it('lets the owner score a match nobody was assigned to', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(scoringBatch(db).commit());
  });

  it('lets the owner record the very first event, the one that races the pen claim',
    async () => {
      // The pad repairs `scorerUids` with a fire-and-forget TRANSACTION
      // (`UmpireRepository.claimPen`). A transaction needs the network, and a
      // ground is where there is none — so the first taps routinely arrive
      // before the repair lands, or instead of it. Scoring must not depend on
      // that race being won.
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(scoringBatch(db).commit());
    });

  it('still refuses an outsider with no role in the club', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(scoringBatch(db).commit());
  });

  it('still refuses the owner while somebody else holds the pen', async () => {
    // The single-scorer rule is the point of the pen and must survive this
    // fix: an organizer who wants control takes it deliberately, which leaves
    // a record, rather than by opening a screen and typing over the umpire.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', COMP, 'fixtures', FX),
        { ...fixture(PUBLIC_ORG, COMP, [SCORER]), activeScorerUid: SCORER },
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(scoringBatch(db).commit());
  });
});

// ---------------------------------------------------------------------------
// A guardian handling participation for an unclaimed child — the other half
// of `isCustodianOfUnclaimed`. Creating and editing the profile itself is
// covered above ("guardian-managed child profiles"); these are the actual
// participation writes a guardian needs before the child ever has a device:
// asking to join a team, entering an individual event, RSVPing into a
// club's squad for a match. All three follow the same shape as an ordinary
// self-service write, just keyed on the child's uid while authenticated as
// the guardian — see `isSelfOrCustodian` in firestore.rules.
// ---------------------------------------------------------------------------

function managedChildFixture(uid, guardianUid, claimedAt = null) {
  return {
    uid,
    displayName: 'Managed Participant',
    email: '',
    dateOfBirth: new Date('2015-01-01'),
    gender: 'male',
    photoUrl: null,
    phone: null,
    profileVisibility: 'private',
    profileComplete: true,
    isMinor: true,
    orgIds: [],
    playerCode: null,
    custodianUid: guardianUid,
    claimedAt,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

describe('guardian participation: joining a team on behalf of an unclaimed child', () => {
  const GUARDIAN = 'uid_join_guardian';
  const CHILD = 'uid_join_child';
  const CAPTAIN = 'uid_join_captain';
  const TEAM = 'team_family_join';

  const seedTeamAndChild = (claimedAt = null) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', CHILD), managedChildFixture(CHILD, GUARDIAN, claimedAt));
      await setDoc(doc(db, 'teams', TEAM), {
        name: 'Family Team',
        sportId: 'cricket',
        type: 'independent',
        createdByUid: CAPTAIN,
        clubId: null,
        captainUid: CAPTAIN,
        managerUid: null,
        memberUids: [CAPTAIN],
        status: 'active',
        competitionId: null,
        baseTeamId: null,
        photoUrl: null,
        homeArea: null,
        createdAt: serverTimestamp(),
      });
    });

  const reqRef = (db) => doc(db, 'teams', TEAM, 'joinRequests', CHILD);
  const joinRequest = () => ({
    uid: CHILD,
    displayName: 'Managed Participant',
    message: '',
    createdAt: serverTimestamp(),
  });

  it("lets a guardian ask to join a team on their unclaimed child's behalf", async () => {
    await seedTeamAndChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(setDoc(reqRef(db), joinRequest()));
  });

  it('lets the guardian read and withdraw that request', async () => {
    await seedTeamAndChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(setDoc(reqRef(db), joinRequest()));
    await assertSucceeds(getDoc(reqRef(db)));
    await assertSucceeds(deleteDoc(reqRef(db)));
  });

  it("refuses the request once the child has claimed their own profile", async () => {
    await seedTeamAndChild(new Date('2026-01-01'));
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(setDoc(reqRef(db), joinRequest()));
  });

  it("still refuses a stranger asking on the child's behalf", async () => {
    await seedTeamAndChild();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(setDoc(reqRef(db), joinRequest()));
  });
});

describe('guardian participation: entering an unclaimed child in an individual event', () => {
  const GUARDIAN = 'uid_reg_guardian';
  const CHILD = 'uid_reg_child';

  const seedEventAndChild = (claimedAt = null) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', CHILD), managedChildFixture(CHILD, GUARDIAN, claimedAt));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', OWNER),
        membership(OWNER, PUBLIC_ORG, 'owner'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'member'),
      );
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'competitions', 'comp1'),
        competition(PUBLIC_ORG, { participationModel: 'open', confirmedCount: 0 }),
      );
    });

  // KNOWN GAP, not yet closed: confirming into a capacity-limited event moves
  // the competition's own counter in the same atomic batch
  // (`isRegistrationCounterBump`), and that document's `allow update` still
  // gates on `isActive(orgId)` for the CALLER — the guardian, who has no
  // reason to be a member of the child's club themselves. The competition
  // doc has no way to learn which registration doc the write is paired
  // with (`regId` isn't in scope at that path), so this can't be closed in
  // rules alone without either a data-model change or a server-side
  // callable that performs the whole atomic write with Admin privileges,
  // the same way `createManagedChildProfile` does. Read/withdraw already
  // work (see below) — only the capacity-checked confirm is blocked.
  it('still refuses a guardian confirming a capacity-limited slot for now', async () => {
    await seedEventAndChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    const batch = writeBatch(db);
    batch.set(regRef(db, CHILD), registration(CHILD, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertFails(batch.commit());
  });

  it('refuses once the child has claimed their own profile', async () => {
    await seedEventAndChild(new Date('2026-01-01'));
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    const batch = writeBatch(db);
    batch.set(regRef(db, CHILD), registration(CHILD, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertFails(batch.commit());
  });

  it("still refuses a stranger entering someone else's child", async () => {
    await seedEventAndChild();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const batch = writeBatch(db);
    batch.set(regRef(db, CHILD), registration(CHILD, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertFails(batch.commit());
  });

  it('lets the guardian withdraw the child afterwards', async () => {
    await seedEventAndChild();
    await seed(async (db) => {
      await setDoc(regRef(db, CHILD), registration(CHILD, 'confirmed'));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(updateDoc(regRef(db, CHILD), { status: 'withdrawn' }));
  });
});

describe('guardian participation: RSVPing an unclaimed child into a squad call', () => {
  const GUARDIAN = 'uid_squad_guardian';
  const CHILD = 'uid_squad_child';

  async function seedSquadCallWithChild(claimedAt = null) {
    await seedSquadCall();
    await seed(async (db) => {
      await setDoc(doc(db, 'users', CHILD), managedChildFixture(CHILD, GUARDIAN, claimedAt));
      await setDoc(
        doc(db, 'orgs', GUEST_ORG, 'members', CHILD),
        membership(CHILD, GUEST_ORG, 'member'),
      );
    });
  }

  // KNOWN GAP, not yet closed — same shape as the individual-event one
  // above: the fixture's own squadCallA/B counter move
  // (`isSquadCounterMove`) still gates on `isActive(entrantId)` for the
  // CALLER, and the fixture doc has no way to learn which squadEntries doc
  // the write is paired with. Read/withdraw already work; only the
  // capacity-checked confirm is blocked, pending the same kind of
  // server-side callable noted above.
  it("still refuses a guardian confirming a capacity-limited squad slot for now", async () => {
    await seedSquadCallWithChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    const batch = writeBatch(db);
    batch.set(entryRef(db, CHILD), squadEntry(CHILD, GUEST_ORG, 'a', 'confirmed'));
    batch.update(fixRef(db), { squadCallA: squadCall({ confirmed: 1 }) });
    await assertFails(batch.commit());
  });

  it('refuses once the child has claimed their own profile', async () => {
    await seedSquadCallWithChild(new Date('2026-01-01'));
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    const batch = writeBatch(db);
    batch.set(entryRef(db, CHILD), squadEntry(CHILD, GUEST_ORG, 'a', 'confirmed'));
    batch.update(fixRef(db), { squadCallA: squadCall({ confirmed: 1 }) });
    await assertFails(batch.commit());
  });

  it("still refuses a stranger RSVPing someone else's child", async () => {
    await seedSquadCallWithChild();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    const batch = writeBatch(db);
    batch.set(entryRef(db, CHILD), squadEntry(CHILD, GUEST_ORG, 'a', 'confirmed'));
    batch.update(fixRef(db), { squadCallA: squadCall({ confirmed: 1 }) });
    await assertFails(batch.commit());
  });

  it('lets the guardian withdraw the child afterwards', async () => {
    await seedSquadCallWithChild();
    await seed(async (db) => {
      await setDoc(entryRef(db, CHILD), squadEntry(CHILD, GUEST_ORG, 'a', 'confirmed'));
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(updateDoc(entryRef(db, CHILD), { status: 'withdrawn' }));
  });
});

// ---------------------------------------------------------------------------
// A guardian joining/following a CLUB on behalf of an unclaimed child — the
// same isSelfOrCustodian carve-out as team joinRequests, applied to
// orgs/{orgId}/members and orgs/{orgId}/followers. Deliberately NOT applied
// to the owner-membership creation path: founding a club stays a thing only
// an adult signed in as themselves may do.
// ---------------------------------------------------------------------------

describe('guardian participation: joining and following a club on behalf of an unclaimed child', () => {
  const GUARDIAN = 'uid_club_guardian';
  const CHILD = 'uid_club_child';

  const seedOrgAndChild = (claimedAt = null, requiresApproval = true) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', CHILD), managedChildFixture(CHILD, GUARDIAN, claimedAt));
      await setDoc(doc(db, 'orgs', PUBLIC_ORG), {
        ...organization(OWNER, 'public'),
        requiresApprovalToJoin: requiresApproval,
      });
    });

  it("lets a guardian ask to join a club on their unclaimed child's behalf", async () => {
    await seedOrgAndChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'member', 'pending'),
      ),
    );
  });

  it('grants the child immediate membership when the club skips approval', async () => {
    await seedOrgAndChild(null, false);
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'member', 'active'),
      ),
    );
  });

  it("refuses joining as an owner on the child's behalf", async () => {
    // The carve-out: a guardian may enroll a child as a member, never found
    // or co-own a club through them.
    await seedOrgAndChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'owner', 'active'),
      ),
    );
  });

  it('refuses once the child has claimed their own profile', async () => {
    await seedOrgAndChild(new Date('2026-01-01'));
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'member', 'pending'),
      ),
    );
  });

  it("still refuses a stranger enrolling someone else's child", async () => {
    await seedOrgAndChild();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'member', 'pending'),
      ),
    );
  });

  it('lets the guardian read the membership row once created', async () => {
    await seedOrgAndChild();
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD),
        membership(CHILD, PUBLIC_ORG, 'member', 'pending'),
      );
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(getDoc(doc(db, 'orgs', PUBLIC_ORG, 'members', CHILD)));
  });

  it("lets a guardian follow a public club on their child's behalf", async () => {
    await seedOrgAndChild();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'orgs', PUBLIC_ORG, 'followers', CHILD), {
        uid: CHILD,
        orgId: PUBLIC_ORG,
        followedAt: serverTimestamp(),
      }),
    );
  });

  it('lets the guardian unfollow again', async () => {
    await seedOrgAndChild();
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', PUBLIC_ORG, 'followers', CHILD), {
        uid: CHILD,
        orgId: PUBLIC_ORG,
        followedAt: serverTimestamp(),
      });
    });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(deleteDoc(doc(db, 'orgs', PUBLIC_ORG, 'followers', CHILD)));
  });
});

// ---------------------------------------------------------------------------
// Switching INTO a child's profile — the read side.
//
// The block above covers a guardian making a participation write keyed on the
// child's uid, which `isSelfOrCustodian` authorizes by reading the child's own
// document. This block covers the queries a switched-in profile actually runs
// on every screen, and they are a different problem: a collection-group query
// matches on an ARRAY (`playerUids`, `memberUids`) or on a field, and gives
// the rule no uid to look up. Those go through the custody mirror on the
// GUARDIAN's document instead — `wardUids()` in firestore.rules, maintained by
// functions/family.js.
//
// Every case here failed with a bare permission error before the mirror
// existed, which is what made "open the child's profile" unusable: the shell
// itself reads memberships and notifications on every screen.
// ---------------------------------------------------------------------------
describe('profile switching: reading a managed child\'s own data', () => {
  const GUARDIAN = 'uid_switch_guardian';
  const CHILD = 'uid_switch_child';
  const STRANGER = 'uid_switch_stranger';
  const ORG = 'org_switch';
  const COMP = 'comp_switch';
  const FX = 'fx_switch';

  // The mirror the rules read. Written only by createManagedChildProfile and
  // pruned only by onChildProfileClaimed; a client that could write it would
  // be able to name anybody as its ward, which the last test here checks.
  const seedHousehold = ({ claimedAt = null, mirror = [CHILD] } = {}) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', GUARDIAN), {
        ...managedChildFixture(GUARDIAN, null),
        displayName: 'Guardian',
        dateOfBirth: new Date('1985-01-01'),
        isMinor: false,
        custodianUid: null,
        managedChildUids: mirror,
      });
      await setDoc(
        doc(db, 'users', CHILD),
        managedChildFixture(CHILD, GUARDIAN, claimedAt),
      );
      await setDoc(doc(db, 'orgs', ORG), {
        name: 'Switch Club',
        orgType: 'club',
        visibility: 'private',
        createdBy: STRANGER,
        createdAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'orgs', ORG, 'members', CHILD), {
        uid: CHILD,
        orgId: ORG,
        role: 'member',
        status: 'active',
        joinedAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'orgs', ORG, 'followers', CHILD), {
        uid: CHILD,
        orgId: ORG,
        followedAt: serverTimestamp(),
      });
      await setDoc(
        doc(db, 'orgs', ORG, 'competitions', COMP, 'fixtures', FX),
        { ...fixture(ORG, COMP, []), playerUids: [CHILD] },
      );
      await setDoc(doc(db, 'users', CHILD, 'notifications', 'n1'), {
        uid: CHILD,
        kind: 'match_start',
        title: 'Your match starts soon',
        read: false,
        createdAt: serverTimestamp(),
      });
    });

  it("lets a guardian query their child's club memberships", async () => {
    await seedHousehold();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      getDocs(query(collectionGroup(db, 'members'), where('uid', '==', CHILD))),
    );
  });

  it("lets a guardian query the clubs their child follows", async () => {
    await seedHousehold();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      getDocs(query(collectionGroup(db, 'followers'), where('uid', '==', CHILD))),
    );
  });

  it("lets a guardian read their child's match history", async () => {
    await seedHousehold();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('playerUids', 'array-contains', CHILD),
        ),
      ),
    );
  });

  it("lets a guardian read their child's notification inbox", async () => {
    await seedHousehold();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      getDocs(collection(db, 'users', CHILD, 'notifications')),
    );
  });

  it('refuses all of it once the child claims their own profile', async () => {
    // The mirror is pruned by the trigger, so the honest test of the claimed
    // case is a pruned mirror — this is the state onChildProfileClaimed
    // leaves behind, and the reads must stop there and not merely narrow.
    await seedHousehold({ claimedAt: new Date('2026-01-01'), mirror: [] });
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertFails(
      getDocs(query(collectionGroup(db, 'members'), where('uid', '==', CHILD))),
    );
    await assertFails(
      getDocs(
        query(
          collectionGroup(db, 'fixtures'),
          where('playerUids', 'array-contains', CHILD),
        ),
      ),
    );
  });

  it('refuses a stranger the same queries', async () => {
    await seedHousehold();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      getDocs(query(collectionGroup(db, 'members'), where('uid', '==', CHILD))),
    );
    await assertFails(
      getDocs(collection(db, 'users', CHILD, 'notifications')),
    );
  });

  it('refuses a client naming its own wards', async () => {
    // The whole mirror rests on this: an account that could append to its own
    // managedChildUids would grant itself read access to any uid it typed.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', STRANGER), {
        ...managedChildFixture(STRANGER, null),
        displayName: 'Stranger',
        dateOfBirth: new Date('1990-01-01'),
        isMinor: false,
        custodianUid: null,
        managedChildUids: [],
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', STRANGER), { managedChildUids: [CHILD] }),
    );
  });

  it('refuses a client inventing a ward list its profile never had', async () => {
    // The shape every ordinary account actually has: `AppUser` never writes
    // managedChildUids, so the field is ABSENT rather than empty — and absent
    // is what `unchangedIfPresent` waved straight through. The test above
    // seeded an empty list and so could never have caught it.
    await seed(async (db) => {
      await setDoc(doc(db, 'users', STRANGER), {
        ...managedChildFixture(STRANGER, null),
        displayName: 'Stranger',
        dateOfBirth: new Date('1990-01-01'),
        isMinor: false,
      });
    });
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', STRANGER), { managedChildUids: [CHILD] }),
    );
  });

  it('refuses a brand-new profile that arrives carrying a ward list', async () => {
    // The same escalation one write earlier, which the update invariants
    // cannot see at all.
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', STRANGER), {
        ...managedChildFixture(STRANGER, null),
        displayName: 'Stranger',
        dateOfBirth: new Date('1990-01-01'),
        isMinor: false,
        managedChildUids: [CHILD],
      }),
    );
  });

  it('still lets an ordinary profile be created without one', async () => {
    // The control for both refusals above.
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', STRANGER), {
        ...managedChildFixture(STRANGER, null),
        displayName: 'Stranger',
        dateOfBirth: new Date('1990-01-01'),
        isMinor: false,
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// The My Children query itself.
//
// `users/{userId}` is split into `get` and `list` for one reason, and this is
// it: a list rule cannot build a get()/exists() PATH out of the row being
// tested, so the minor/guardian-consent branch — reachable for every managed
// child, since a managed child is by definition a minor — took the whole query
// down with "Null value error" instead of evaluating false and falling through
// to the custodian branch. A guardian got a flat permission error on the one
// screen the feature is reached from.
// ---------------------------------------------------------------------------
describe('a guardian listing the children they manage', () => {
  const GUARDIAN = 'uid_mychildren_guardian';
  const KIDS = ['uid_mychildren_a', 'uid_mychildren_b', 'uid_mychildren_c'];

  const seedChildren = () =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', GUARDIAN), {
        ...managedChildFixture(GUARDIAN, null),
        displayName: 'Guardian',
        dateOfBirth: new Date('1990-01-01'),
        isMinor: false,
        custodianUid: null,
      });
      for (const uid of KIDS) {
        await setDoc(doc(db, 'users', uid), {
          ...managedChildFixture(uid, GUARDIAN),
          // The shape createManagedChildProfile actually writes: private,
          // and a minor. Both matter — private skips the public/community
          // branches, and being a minor is what reaches the consent branch.
          profileVisibility: 'private',
          dateOfBirth: new Date('2018-08-25'),
        });
      }
    });

  it('returns them, ordered, exactly as the app queries', async () => {
    await seedChildren();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'users'),
          where('custodianUid', '==', GUARDIAN),
          orderBy('createdAt', 'desc'),
        ),
      ),
    );
  });

  it('still opens one child on its own', async () => {
    await seedChildren();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', KIDS[0])));
  });

  it('refuses a stranger the same query', async () => {
    await seedChildren();
    const db = testEnv.authenticatedContext('uid_mychildren_nobody').firestore();
    await assertFails(
      getDocs(
        query(
          collection(db, 'users'),
          where('custodianUid', '==', GUARDIAN),
          orderBy('createdAt', 'desc'),
        ),
      ),
    );
  });

  it('refuses a stranger fishing for a minor by listing the collection', async () => {
    // The consent branch is gone from `list`, so this must not become a way
    // to enumerate children a guardian has not shared.
    await seedChildren();
    const db = testEnv.authenticatedContext('uid_mychildren_nobody').firestore();
    await assertFails(getDocs(query(collection(db, 'users'), limit(10))));
  });
});

// ---------------------------------------------------------------------------
// "What have I entered?" — the cross-club read behind the home screen's
// Registered seasons and Registered tournaments tiles
// ---------------------------------------------------------------------------
describe('a person listing their own entries across every club', () => {
  const PLAYER = 'uid_entries_player';
  const GUARDIAN = 'uid_entries_guardian';
  const CHILD = 'uid_entries_child';
  const STRANGER = 'uid_entries_stranger';
  const TEAM = 'team_entries_a';

  const seedEntries = () =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', GUARDIAN), {
        ...managedChildFixture(GUARDIAN, null),
        isMinor: false,
        custodianUid: null,
        managedChildUids: [CHILD],
      });
      await setDoc(doc(db, 'users', CHILD), managedChildFixture(CHILD, GUARDIAN));

      // An entry each: filed personally, filed for a ward, and filed by a
      // team that names the player.
      for (const [compId, data] of [
        ['comp_solo', { uid: PLAYER, displayName: 'Player', status: 'confirmed' }],
        ['comp_ward', { uid: CHILD, displayName: 'Child', status: 'confirmed' }],
        [
          'comp_team',
          {
            uid: TEAM,
            displayName: 'Nizampet A',
            status: 'confirmed',
            teamId: TEAM,
            memberUids: [PLAYER],
          },
        ],
      ]) {
        await setDoc(
          doc(db, 'orgs', PRIVATE_ORG, 'competitions', compId, 'registrations', data.uid),
          { ...data, createdAt: serverTimestamp() },
        );
      }
    });

  it('returns the entries they filed themselves', async () => {
    await seedEntries();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(collectionGroup(db, 'registrations'), where('uid', '==', PLAYER)),
      ),
    );
    assert.equal(snap.size, 1);
  });

  it('returns the entries a team filed with them named in it', async () => {
    // A player whose club entered them in the league has entered the league.
    // The document id there is the TEAM's, which is why this is a second
    // query and not a wider version of the first.
    await seedEntries();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(
          collectionGroup(db, 'registrations'),
          where('memberUids', 'array-contains', PLAYER),
        ),
      ),
    );
    assert.equal(snap.size, 1);
  });

  it("lets a guardian read an unclaimed child's entries", async () => {
    // The parent's home screen answers for the household, and switching into
    // each child's profile to find out what they are in is the trip that
    // screen exists to save.
    await seedEntries();
    const db = testEnv.authenticatedContext(GUARDIAN).firestore();
    const snap = await assertSucceeds(
      getDocs(
        query(collectionGroup(db, 'registrations'), where('uid', '==', CHILD)),
      ),
    );
    assert.equal(snap.size, 1);
  });

  it('refuses an unconstrained read of every entry ever made', async () => {
    await seedEntries();
    const db = testEnv.authenticatedContext(PLAYER).firestore();
    await assertFails(getDocs(query(collectionGroup(db, 'registrations'))));
  });

  it("refuses a stranger somebody else's entries", async () => {
    // A club's own members can read who has entered their club's event, at
    // the nested path. A cross-club query has no club to be a member of, so
    // the only defensible reader is somebody the entry is about.
    await seedEntries();
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(
      getDocs(
        query(collectionGroup(db, 'registrations'), where('uid', '==', PLAYER)),
      ),
    );
  });
});

// ---------------------------------------------------------------------------
// Governance & join fixes — review follow-up.
//
// Each of these reproduced a real hole or breakage before its fix and passes
// after it. They use the shared `organization`/`membership` helpers at the top
// of this file, and the global beforeEach clears Firestore between them.
// ---------------------------------------------------------------------------
describe('governance & join fixes (review follow-up)', () => {
  const CLUB = 'org_gov';
  const OWNER2 = 'uid_owner2';
  const JOINER = 'uid_joiner';

  const openClub = () => ({
    ...organization(OWNER, 'public'),
    requiresApprovalToJoin: false,
  });

  const seedOwned = (extraMembers = async () => {}) =>
    seed(async (db) => {
      await setDoc(doc(db, 'orgs', CLUB), organization(OWNER, 'public'));
      await setDoc(
        doc(db, 'orgs', CLUB, 'members', OWNER),
        membership(OWNER, CLUB, 'owner'),
      );
      await extraMembers(db);
    });

  // #2 — joining a no-approval club writes the member row AND bumps the roster
  // count in one batch. The count write is by a non-member, which every other
  // org-update branch refuses, so the whole join failed before this.
  it('lets a new member join an open club and bump the roster count in one batch', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', CLUB), openClub());
      await setDoc(
        doc(db, 'orgs', CLUB, 'members', OWNER),
        membership(OWNER, CLUB, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs', CLUB, 'members', JOINER), {
      ...membership(JOINER, CLUB, 'member'),
      joinedAt: serverTimestamp(),
    });
    batch.update(doc(db, 'orgs', CLUB), { memberCount: increment(1) });
    await assertSucceeds(batch.commit());
  });

  it('refuses a bare memberCount bump with no membership behind it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', CLUB), openClub());
      await setDoc(
        doc(db, 'orgs', CLUB, 'members', OWNER),
        membership(OWNER, CLUB, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', CLUB), { memberCount: increment(1) }),
    );
  });

  // #3 — an owner may step THEMSELVES down to admin.
  it('lets an owner resign to admin', async () => {
    await seedOwned(async (db) => {
      await setDoc(
        doc(db, 'orgs', CLUB, 'members', OWNER2),
        membership(OWNER2, CLUB, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'orgs', CLUB, 'members', OWNER), { role: 'admin' }),
    );
  });

  // #5 — one owner cannot unilaterally unseat a co-owner; that is the vote's job.
  it('refuses an owner demoting a co-owner directly', async () => {
    await seedOwned(async (db) => {
      await setDoc(
        doc(db, 'orgs', CLUB, 'members', OWNER2),
        membership(OWNER2, CLUB, 'owner'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', CLUB, 'members', OWNER2), { role: 'member' }),
    );
  });

  // #6 — only an owner may retire (soft-delete) the club.
  it('refuses an admin soft-deleting the club, allows the owner', async () => {
    await seedOwned(async (db) => {
      await setDoc(
        doc(db, 'orgs', CLUB, 'members', ADMIN),
        membership(ADMIN, CLUB, 'admin'),
      );
    });
    const adminDb = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      updateDoc(doc(adminDb, 'orgs', CLUB), { deletedAt: serverTimestamp() }),
    );
    const ownerDb = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      updateDoc(doc(ownerDb, 'orgs', CLUB), { deletedAt: serverTimestamp() }),
    );
  });

  // #7 — a withdrawn invitation cannot be resurrected into an acceptance.
  it('refuses accepting a tournament invite the host has withdrawn', async () => {
    const GUEST = 'org_guest_gov';
    const GADMIN = 'uid_gadmin_gov';
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', GUEST), organization('uid_gowner_gov', 'public'));
      await setDoc(
        doc(db, 'orgs', GUEST, 'members', GADMIN),
        membership(GADMIN, GUEST, 'admin'),
      );
      await setDoc(doc(db, 'tournamentInvites', 'inv_gov'), {
        fromOrgId: 'org_host_gov',
        toOrgId: GUEST,
        tournamentId: 't1',
        status: 'withdrawn',
        invitedBy: 'uid_hadmin_gov',
        createdAt: serverTimestamp(),
      });
    });
    const db = testEnv.authenticatedContext(GADMIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'tournamentInvites', 'inv_gov'), {
        status: 'accepted',
        respondedAt: serverTimestamp(),
      }),
    );
  });
});
