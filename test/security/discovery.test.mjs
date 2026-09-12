// Emulator-backed tests for the two rules changes discovery needed:
//
//   1. A club's owners and admins may read the profile of somebody who has
//      asked to join them — and may not read it a moment longer than that.
//   2. `playerDirectory` — the opt-in, adults-only, findable-by-strangers
//      collection that a "who is near me" search reads instead of `users`.
//
// Both are read grants to people who previously had none, which is exactly
// the class of change that has to be proved at the rules rather than in the
// app: the app is a client-side mirror and a modified one skips it entirely.

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
  getDoc,
  getDocs,
  limit,
  query,
  collection,
  setDoc,
  serverTimestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

let testEnv;

const OWNER = 'uid_owner';
const ADMIN = 'uid_admin';
const SCORER = 'uid_scorer';      // active member, but no authority over members
const APPLICANT = 'uid_applicant';
const OUTSIDER = 'uid_outsider';
const MINOR = 'uid_minor';
const ORG = 'org_club';
const OTHER_ORG = 'org_other';

const ADULT_DOB = new Date('1995-04-11');
const MINOR_DOB = new Date('2014-01-01');

const membership = (uid, role, status = 'active') => ({
  uid,
  orgId: ORG,
  role,
  status,
  displayName: 'Test Person',
  photoUrl: null,
  joinedAt: serverTimestamp(),
  invitedBy: null,
  approvedBy: null,
});

const profile = (uid, overrides = {}) => ({
  uid,
  displayName: 'Test Person',
  email: 'test@example.com',
  dateOfBirth: ADULT_DOB,
  gender: 'female',
  photoUrl: null,
  phone: null,
  // The DEFAULT for every new account, and the whole reason this grant is
  // needed: a `public` applicant would already be readable.
  profileVisibility: 'community',
  profileComplete: true,
  isMinor: false,
  orgIds: [],
  pendingOrgIds: [],
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...overrides,
});

const listing = (uid, overrides = {}) => ({
  uid,
  displayName: 'Test Person',
  photoUrl: null,
  playerCode: 'PSOS-4K7M2',
  sportIds: ['cricket'],
  intents: ['club'],
  ageGroup: 'senior',
  gender: 'female',
  geo: { district: 'Warangal', state: 'Telangana' },
  district: 'Warangal',
  state: 'Telangana',
  note: 'Left-arm spinner, just moved here.',
  matchesPlayed: 12,
  updatedAt: serverTimestamp(),
  ...overrides,
});

const RULES_FILE = process.env.RULES_FILE ?? '../../firestore.rules';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-discovery-test',
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

const seed = (fn) =>
  testEnv.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    for (const orgId of [ORG, OTHER_ORG]) {
      await setDoc(doc(db, 'orgs', orgId), {
        name: 'Test Club',
        orgType: 'club',
        visibility: 'public',
        ownerUid: OWNER,
        requiresApprovalToJoin: true,
        memberCount: 1,
        deletedAt: null,
        createdBy: OWNER,
        createdAt: serverTimestamp(),
      });
    }
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', ADMIN), membership(ADMIN, 'admin'));
    await setDoc(doc(db, 'orgs', ORG, 'members', SCORER), membership(SCORER, 'scorer'));
  });
});

// ---------------------------------------------------------------------------
// Reading an applicant's profile
// ---------------------------------------------------------------------------
describe('a club reading the profile of somebody asking to join it', () => {
  /** APPLICANT has an outstanding, correctly-mirrored application to ORG. */
  const seedPendingApplication = (profileOverrides = {}) =>
    seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, { pendingOrgIds: [ORG], ...profileOverrides }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'pending'),
      );
    });

  it('lets the owner open it', async () => {
    await seedPendingApplication();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('lets an admin open it', async () => {
    await seedPendingApplication();
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('refuses an ordinary member of the same club', async () => {
    // Reviewing applications is what earns the read. Being in the club is not.
    await seedPendingApplication();
    const db = testEnv.authenticatedContext(SCORER).firestore();
    await assertFails(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('refuses the owner of a club they did NOT apply to', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, { pendingOrgIds: [ORG] }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'pending'),
      );
      // OUTSIDER owns a different club entirely.
      await setDoc(doc(db, 'orgs', OTHER_ORG, 'members', OUTSIDER), {
        ...membership(OUTSIDER, 'owner'),
        orgId: OTHER_ORG,
      });
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('stops the moment the application is APPROVED and the mirror is stale', async () => {
    // The grant expires on a fact the DECIDER controls, not on the applicant
    // remembering to prune a list only they can write. An approved member is
    // read through the ordinary community branch instead — which needs the
    // other mirror, `orgIds`, and this profile has not written it yet.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, { pendingOrgIds: [ORG], orgIds: [] }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'active'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('stops the moment the application is DECLINED and the mirror is stale', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, { pendingOrgIds: [ORG] }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'removed'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('gives a fabricated mirror entry nothing without a real pending row', async () => {
    // The list is written by the applicant, so the only thing naming a club
    // they never applied to can do is offer their own profile to that club's
    // admins — and the rule still demands a genuine `pending` membership.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, { pendingOrgIds: [ORG] }),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('never opens a MINOR applicant, however the club is placed', async () => {
    // The adult floor is not a visibility preference and this grant does not
    // lift it. What a club sees of a junior applicant is the introduction
    // they chose to send, on the membership row.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', MINOR),
        profile(MINOR, {
          dateOfBirth: MINOR_DOB,
          isMinor: true,
          pendingOrgIds: [ORG],
        }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', MINOR),
        membership(MINOR, 'member', 'pending'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDoc(doc(db, 'users', MINOR)));
  });

  it('reaches an application that is third in the list', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, {
          pendingOrgIds: ['org_a', 'org_b', ORG],
        }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'pending'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('does not reach one pushed past the third slot', async () => {
    // Documented, not accidental: each entry costs document accesses against
    // a hard per-read budget. The client keeps the freshest first.
    await seed(async (db) => {
      await setDoc(
        doc(db, 'users', APPLICANT),
        profile(APPLICANT, {
          pendingOrgIds: ['org_a', 'org_b', 'org_c', ORG],
        }),
      );
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'pending'),
      );
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(getDoc(doc(db, 'users', APPLICANT)));
  });

  it('lets the applicant write their own mirror, but not an unbounded one', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', APPLICANT), profile(APPLICANT, { pendingOrgIds: [ORG] })),
    );
    await assertFails(
      updateDoc(doc(db, 'users', APPLICANT), {
        pendingOrgIds: Array.from({ length: 11 }, (_, i) => `org_${i}`),
      }),
    );
  });

  it('refuses to let anyone else write somebody\'s pending mirror', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', APPLICANT), profile(APPLICANT));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', APPLICANT), { pendingOrgIds: [ORG] }),
    );
  });
});

// ---------------------------------------------------------------------------
// The introduction that travels with the application
// ---------------------------------------------------------------------------
describe('the application an applicant sends with a join request', () => {
  const application = (overrides = {}) => ({
    note: 'I played U-19 cricket in Warangal and have just moved here.',
    ageYears: 30,
    gender: 'female',
    locationLabel: 'Warangal, Telangana',
    playerCode: 'PSOS-4K7M2',
    sports: [{ sportId: 'cricket', matchesPlayed: 12 }],
    submittedAt: new Date(),
    ...overrides,
  });

  it('lets the applicant attach one to their own join request', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        ...membership(APPLICANT, 'member', 'pending'),
        application: application(),
      }),
    );
  });

  it('refuses a note longer than the bound', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertFails(
      setDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        ...membership(APPLICANT, 'member', 'pending'),
        application: application({ note: 'x'.repeat(401) }),
      }),
    );
  });

  it('lets an admin decide the application without touching its words', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        ...membership(APPLICANT, 'member', 'pending'),
        application: application(),
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        status: 'active',
        approvedBy: ADMIN,
      }),
    );
  });

  it('refuses an admin rewriting what the applicant said', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        ...membership(APPLICANT, 'member', 'pending'),
        application: application(),
      });
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        application: application({ note: 'Words the applicant never wrote.' }),
      }),
    );
  });

  it('refuses an admin inventing one on a row that had none', async () => {
    await seed(async (db) => {
      await setDoc(
        doc(db, 'orgs', ORG, 'members', APPLICANT),
        membership(APPLICANT, 'member', 'pending'),
      );
    });
    const db = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      updateDoc(doc(db, 'orgs', ORG, 'members', APPLICANT), {
        application: application(),
      }),
    );
  });
});

// ---------------------------------------------------------------------------
// The player directory
// ---------------------------------------------------------------------------
describe('playerDirectory', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', APPLICANT), profile(APPLICANT));
      await setDoc(
        doc(db, 'users', MINOR),
        profile(MINOR, { dateOfBirth: MINOR_DOB, isMinor: true }),
      );
      await setDoc(doc(db, 'users', OUTSIDER), profile(OUTSIDER));
    });
  });

  it('lets an adult list themselves', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'playerDirectory', APPLICANT), listing(APPLICANT)),
    );
  });

  it('lets them edit the listing they already published', async () => {
    // `allow create, update` is one rule, and an edit is the commoner action:
    // somebody who moves, or takes up a new sport, comes back to this.
    await seed(async (db) => {
      await setDoc(doc(db, 'playerDirectory', APPLICANT), listing(APPLICANT));
    });
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'playerDirectory', APPLICANT),
        listing(APPLICANT, { sportIds: ['cricket', 'badminton'] }),
      ),
    );
  });

  it('refuses a MINOR listing themselves', async () => {
    // The point of the whole collection design. A searchable,
    // location-bearing directory of children is not shipped by accident.
    const db = testEnv.authenticatedContext(MINOR).firestore();
    await assertFails(
      setDoc(doc(db, 'playerDirectory', MINOR), listing(MINOR)),
    );
  });

  it('refuses listing somebody else', async () => {
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(db, 'playerDirectory', APPLICANT), listing(APPLICANT)),
    );
  });

  it('refuses a listing whose uid does not match its id', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertFails(
      setDoc(
        doc(db, 'playerDirectory', APPLICANT),
        listing(APPLICANT, { uid: OUTSIDER }),
      ),
    );
  });

  it('refuses an over-long note', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertFails(
      setDoc(
        doc(db, 'playerDirectory', APPLICANT),
        listing(APPLICANT, { note: 'x'.repeat(281) }),
      ),
    );
  });

  it('refuses a hand-edited match count', async () => {
    const db = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertFails(
      setDoc(
        doc(db, 'playerDirectory', APPLICANT),
        listing(APPLICANT, { matchesPlayed: 1000000 }),
      ),
    );
  });

  it('lets any signed-in person search the directory', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'playerDirectory', APPLICANT), listing(APPLICANT));
    });
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'playerDirectory'),
          where('district', '==', 'Warangal'),
          limit(50),
        ),
      ),
    );
  });

  it('refuses a signed-out reader', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'playerDirectory', APPLICANT), listing(APPLICANT));
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'playerDirectory', APPLICANT)));
  });

  it('lets somebody take themselves off, and nobody else take them off', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'playerDirectory', APPLICANT), listing(APPLICANT));
    });
    const stranger = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(deleteDoc(doc(stranger, 'playerDirectory', APPLICANT)));

    const mine = testEnv.authenticatedContext(APPLICANT).firestore();
    await assertSucceeds(deleteDoc(doc(mine, 'playerDirectory', APPLICANT)));
  });
});
