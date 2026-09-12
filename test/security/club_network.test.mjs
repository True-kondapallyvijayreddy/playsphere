// Emulator-backed tests for the club owners' network.
//
// This ruleset is unusual in the file and is worth its own suite: it is the
// first place two TENANTS write to each other, it authorises by decomposing a
// document ID rather than by reading a document, and it decides a paywall
// from whether a row exists at the moment a batch is evaluated. None of the
// three can be checked by reading the rules; each is one assertion here.
//
// The inbox test in particular is not decoration. The first version of this
// feature kept every conversation in one top-level collection and let the
// rule read `resource.data.orgIds` — which passes review, passes a `get`, and
// fails every `list`, because Firestore checks a query against a resource
// synthesised from its constraints rather than against the documents it would
// return. That is the shape the whole inbox now hangs off.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let testEnv;

// Ids that sort the way `ClubThread.idFor` sorts them: 'club_a' < 'club_b'.
const CLUB_A = 'club_a';
const CLUB_B = 'club_b';
const CLUB_C = 'club_c';
const THREAD = `${CLUB_A}__${CLUB_B}`;

const OWNER_A = 'uid_owner_a';
const OWNER_B = 'uid_owner_b';
const ADMIN_A = 'uid_admin_a';
const OUTSIDER = 'uid_outsider';

const DAY = 1000 * 60 * 60 * 24;

const membership = (uid, orgId, role) => ({
  uid,
  orgId,
  role,
  status: 'active',
  displayName: 'Test Person',
  photoUrl: null,
  joinedAt: serverTimestamp(),
  invitedBy: null,
  approvedBy: null,
});

/** An org document, on the club plan or lapsed off it. */
const organization = (ownerUid, { paid = true } = {}) => ({
  name: 'Test Club',
  orgType: 'club',
  visibility: 'public',
  ownerUid,
  ownerUids: [],
  inviteCode: 'ABC234',
  memberCount: 1,
  requiresApprovalToJoin: true,
  plan: paid ? 'club' : 'free',
  planActivatedAt: paid ? new Date(Date.now() - 180 * DAY) : null,
  // A club whose year ran out yesterday — not one that never paid. The lapse
  // is the interesting case, because that club still has conversations.
  planValidUntil: paid ? new Date(Date.now() + 180 * DAY) : new Date(Date.now() - DAY),
  createdBy: ownerUid,
  createdAt: serverTimestamp(),
  deletedAt: null,
});

/** One club's inbox row, as `ClubNetworkRepository.sendMessage` writes it. */
const inboxRow = (myOrgId, otherOrgId, senderOrgId, { markRead = false } = {}) => ({
  orgIds: [CLUB_A, CLUB_B].includes(myOrgId) && [CLUB_A, CLUB_B].includes(otherOrgId)
    ? [CLUB_A, CLUB_B]
    : [myOrgId, otherOrgId].sort(),
  otherOrgId,
  otherOrgName: 'The Other Club',
  otherOrgLogoUrl: null,
  lastMessage: 'Fixture on Saturday?',
  lastMessageAt: serverTimestamp(),
  lastSenderOrgId: senderOrgId,
  ...(markRead ? { lastReadAt: serverTimestamp() } : {}),
});

const message = (senderOrgId, senderUid) => ({
  senderOrgId,
  senderUid,
  senderName: 'Ramesh',
  text: 'Are you free on Saturday?',
  createdAt: serverTimestamp(),
});

const RULES_FILE = process.env.RULES_FILE ?? '../../firestore.rules';

before(async () => {
  testEnv = await initializeTestEnvironment({
    // Its own project id, like every other suite here. `node --test` runs
    // these files CONCURRENTLY and each one clears its database between
    // tests, so two suites sharing a project id delete each other's fixtures
    // mid-assertion — which looks exactly like a rules regression in whichever
    // file happened to lose the race.
    projectId: 'playsphere-clubnet-test',
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
});

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore());
  });
}

/** Two clubs with owners, plus an admin of A who is deliberately not one. */
async function seedClubs({ aPaid = true, bPaid = true } = {}) {
  await seed(async (db) => {
    await setDoc(doc(db, 'orgs', CLUB_A), organization(OWNER_A, { paid: aPaid }));
    await setDoc(doc(db, 'orgs', CLUB_B), organization(OWNER_B, { paid: bPaid }));
    await setDoc(doc(db, 'orgs', CLUB_C), organization(OUTSIDER));
    await setDoc(doc(db, 'orgs', CLUB_A, 'members', OWNER_A),
      membership(OWNER_A, CLUB_A, 'owner'));
    await setDoc(doc(db, 'orgs', CLUB_A, 'members', ADMIN_A),
      membership(ADMIN_A, CLUB_A, 'admin'));
    await setDoc(doc(db, 'orgs', CLUB_B, 'members', OWNER_B),
      membership(OWNER_B, CLUB_B, 'owner'));
    await setDoc(doc(db, 'orgs', CLUB_C, 'members', OUTSIDER),
      membership(OUTSIDER, CLUB_C, 'owner'));
  });
}

/** An existing conversation, opened by club B. */
async function seedConversation() {
  await seed(async (db) => {
    const row = (mine, theirs) => ({
      orgIds: [CLUB_A, CLUB_B],
      otherOrgId: theirs,
      otherOrgName: 'The Other Club',
      otherOrgLogoUrl: null,
      lastMessage: 'Hello',
      lastMessageAt: new Date(),
      lastSenderOrgId: CLUB_B,
    });
    await setDoc(doc(db, 'orgs', CLUB_A, 'clubThreads', THREAD), row(CLUB_A, CLUB_B));
    await setDoc(doc(db, 'orgs', CLUB_B, 'clubThreads', THREAD), {
      ...row(CLUB_B, CLUB_A),
      lastReadAt: new Date(),
    });
    await setDoc(doc(db, 'clubThreads', THREAD, 'messages', 'm1'),
      { ...message(CLUB_B, OWNER_B), createdAt: new Date() });
  });
}

/** One send: both inbox rows and the message, in the batch the app uses. */
function sendBatch(db, {
  senderOrgId,
  senderUid,
  recipientOrgId,
  threadId = THREAD,
}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'orgs', senderOrgId, 'clubThreads', threadId),
    inboxRow(senderOrgId, recipientOrgId, senderOrgId, { markRead: true }),
    { merge: true });
  batch.set(doc(db, 'orgs', recipientOrgId, 'clubThreads', threadId),
    inboxRow(recipientOrgId, senderOrgId, senderOrgId),
    { merge: true });
  batch.set(doc(db, 'clubThreads', threadId, 'messages', `m_${Date.now()}`),
    message(senderOrgId, senderUid));
  return batch.commit();
}

describe('club network: who may open a conversation', () => {
  it('lets a paid club owner write to another club for the first time', async () => {
    await seedClubs();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertSucceeds(sendBatch(db, {
      senderOrgId: CLUB_A, senderUid: OWNER_A, recipientOrgId: CLUB_B,
    }));
  });

  it('refuses an ADMIN of the club — the network is owners only', async () => {
    // Committing a club to another club's season is the same class of
    // decision as accepting a challenge. The client hides the surface from
    // admins; this is the half that holds.
    await seedClubs();
    const db = testEnv.authenticatedContext(ADMIN_A).firestore();
    await assertFails(sendBatch(db, {
      senderOrgId: CLUB_A, senderUid: ADMIN_A, recipientOrgId: CLUB_B,
    }));
  });

  it('refuses a stranger sending AS a club they do not own', async () => {
    await seedClubs();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(sendBatch(db, {
      senderOrgId: CLUB_A, senderUid: OUTSIDER, recipientOrgId: CLUB_B,
    }));
  });

  it('refuses a message signed with somebody else’s uid', async () => {
    await seedClubs();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(setDoc(
      doc(db, 'clubThreads', THREAD, 'messages', 'm1'),
      message(CLUB_A, OWNER_B),
    ));
  });

  it('refuses a thread id that does not name the sender', async () => {
    // The whole authorisation scheme rests on the id being the pair. A client
    // that could pick its own id could address a conversation to clubs that
    // are not in it.
    await seedClubs();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(setDoc(
      doc(db, 'clubThreads', `${CLUB_B}__${CLUB_C}`, 'messages', 'm1'),
      message(CLUB_A, OWNER_A),
    ));
  });

  it('refuses an unsorted pair, which would be a second id for one conversation', async () => {
    await seedClubs();
    const db = testEnv.authenticatedContext(OWNER_B).firestore();
    await assertFails(sendBatch(db, {
      senderOrgId: CLUB_B,
      senderUid: OWNER_B,
      recipientOrgId: CLUB_A,
      threadId: `${CLUB_B}__${CLUB_A}`,
    }));
  });
});

describe('club network: the plan gate', () => {
  it('refuses a LAPSED club opening a new conversation', async () => {
    await seedClubs({ aPaid: false });
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(sendBatch(db, {
      senderOrgId: CLUB_A, senderUid: OWNER_A, recipientOrgId: CLUB_B,
    }));
  });

  it('lets a LAPSED club reply in a conversation that already exists', async () => {
    // A paywall that lets a club receive a fixture offer and then refuses to
    // let it answer is a broken inbox, not a paywall.
    await seedClubs({ aPaid: false });
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertSucceeds(sendBatch(db, {
      senderOrgId: CLUB_A, senderUid: OWNER_A, recipientOrgId: CLUB_B,
    }));
  });

  it('lets a lapsed club still read everything it is in', async () => {
    await seedClubs({ aPaid: false });
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertSucceeds(getDocs(collection(db, 'clubThreads', THREAD, 'messages')));
  });
});

describe('club network: the inbox', () => {
  it('serves the inbox query the app actually runs', async () => {
    // The reason the rows hang off the club rather than off a top-level
    // collection. A `list` is authorised from the PATH here; there is no
    // document for the rule to read, and Firestore would not give it one.
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertSucceeds(getDocs(query(
      collection(db, 'orgs', CLUB_A, 'clubThreads'),
      orderBy('lastMessageAt', 'desc'),
    )));
  });

  it('refuses another club’s inbox', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(getDocs(collection(db, 'orgs', CLUB_B, 'clubThreads')));
    await assertFails(getDoc(doc(db, 'orgs', CLUB_B, 'clubThreads', THREAD)));
  });

  it('refuses an admin of the club — the inbox is the owner’s', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(ADMIN_A).firestore();
    await assertFails(getDocs(collection(db, 'orgs', CLUB_A, 'clubThreads')));
  });
});

describe('club network: reading the conversation', () => {
  it('lets both sides read the messages', async () => {
    await seedClubs();
    await seedConversation();
    for (const uid of [OWNER_A, OWNER_B]) {
      const db = testEnv.authenticatedContext(uid).firestore();
      await assertSucceeds(getDocs(collection(db, 'clubThreads', THREAD, 'messages')));
    }
  });

  it('refuses a third club entirely', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDocs(collection(db, 'clubThreads', THREAD, 'messages')));
  });

  it('refuses an admin of a participating club', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(ADMIN_A).firestore();
    await assertFails(getDocs(collection(db, 'clubThreads', THREAD, 'messages')));
  });
});

describe('club network: the read marker', () => {
  it('lets a club mark its own row read', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertSucceeds(setDoc(
      doc(db, 'orgs', CLUB_A, 'clubThreads', THREAD),
      { lastReadAt: serverTimestamp() },
      { merge: true },
    ));
  });

  it('refuses a sender stamping the recipient’s marker on delivery', async () => {
    // The quietest possible way to make a message disappear: deliver a
    // fixture offer that never shows as unread.
    await seedClubs();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(setDoc(
      doc(db, 'orgs', CLUB_B, 'clubThreads', THREAD),
      inboxRow(CLUB_B, CLUB_A, CLUB_A, { markRead: true }),
      { merge: true },
    ));
  });

  it('refuses moving a row to a different pair of clubs', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(updateDoc(
      doc(db, 'orgs', CLUB_A, 'clubThreads', THREAD),
      { orgIds: [CLUB_A, CLUB_C] },
    ));
  });
});

describe('club network: the record is append-only', () => {
  it('refuses editing a message, including your own', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_B).firestore();
    await assertFails(updateDoc(
      doc(db, 'clubThreads', THREAD, 'messages', 'm1'),
      { text: 'What I meant to say' },
    ));
  });

  it('refuses deleting a message', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(deleteDoc(doc(db, 'clubThreads', THREAD, 'messages', 'm1')));
  });

  it('refuses deleting an inbox row', async () => {
    await seedClubs();
    await seedConversation();
    const db = testEnv.authenticatedContext(OWNER_A).firestore();
    await assertFails(deleteDoc(doc(db, 'orgs', CLUB_A, 'clubThreads', THREAD)));
  });
});
