// Three registration doors from the 19 Sep season test run:
//
//  1. A player who withdrew may enter again (TC-14).
//  2. In a season opened to other clubs, the host's own members and teams
//     are confirmed as they enter; outsiders still wait for approval (TC-22).
//  3. A house event's team cap is on houses, not on the people in them (TC-15).

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc, serverTimestamp, setDoc, writeBatch,
} from 'firebase/firestore';

let testEnv;

const HOST = 'org_host';
const GUEST = 'org_guest';
const SEASON = 'season1';
const COMP = 'comp1';

const HOST_OWNER = 'uid_host_owner';
const MEMBER = 'uid_member';
const OUTSIDER = 'uid_outsider';
const GUEST_OWNER = 'uid_guest_owner';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-entry-fixes',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
after(async () => { await testEnv?.cleanup(); });

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

const membership = (uid, orgId, role) => ({
  uid, orgId, role, status: 'active', displayName: 'P', photoUrl: null,
  joinedAt: serverTimestamp(), invitedBy: null, approvedBy: null,
});

const org = (orgId, ownerUid, code) => ({
  name: orgId, nameLower: orgId, orgType: 'club', visibility: 'public',
  ownerUid, inviteCode: code, memberCount: 2, requiresApprovalToJoin: true,
  createdBy: ownerUid, createdAt: serverTimestamp(), deletedAt: null,
});

const competition = (overrides = {}) => ({
  orgId: HOST, name: 'Badminton', sportId: 'badminton',
  sportName: 'Badminton', status: 'registration_open',
  tournamentId: SEASON, entrantType: 'individual', teamEntryMode: 'individual',
  participationModel: 'open', format: 'knockout', category: 'open',
  confirmedCount: 0, waitlistCount: 0, maxEntrants: 16,
  waitlistEnabled: false, entryFeeRupees: 0, openToNonMembers: false,
  preselectedSlots: 0, createdBy: HOST_OWNER, createdAt: serverTimestamp(),
  ...overrides,
});

const registration = (uid, status, overrides = {}) => ({
  uid, displayName: 'P', photoUrl: null, teamName: null, status,
  waitlistPosition: null, preselected: false, eligibilityNote: null,
  createdAt: serverTimestamp(),
  ...overrides,
});

const team = (clubId, createdByUid) => ({
  name: 'Side', sportId: 'cricket', type: 'event', status: 'active',
  createdByUid, clubId, captainUid: createdByUid, managerUid: null,
  memberUids: [createdByUid], competitionId: COMP, baseTeamId: null,
  photoUrl: null, homeArea: null, joinCode: null, createdAt: serverTimestamp(),
});

async function seed(compOverrides = {}, extra = async () => {}) {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'orgs', HOST), org(HOST, HOST_OWNER, 'HST234'));
    await setDoc(doc(db, 'orgs', HOST, 'members', HOST_OWNER),
      membership(HOST_OWNER, HOST, 'owner'));
    await setDoc(doc(db, 'orgs', HOST, 'members', MEMBER),
      membership(MEMBER, HOST, 'member'));
    await setDoc(doc(db, 'orgs', GUEST), org(GUEST, GUEST_OWNER, 'GST234'));
    await setDoc(doc(db, 'orgs', GUEST, 'members', GUEST_OWNER),
      membership(GUEST_OWNER, GUEST, 'owner'));
    await setDoc(doc(db, 'orgs', HOST, 'tournaments', SEASON), {
      orgId: HOST, name: 'Season', status: 'entries_open', eventCount: 1,
      venueIds: [], createdBy: HOST_OWNER, createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', HOST, 'competitions', COMP),
      competition(compOverrides));
    await extra(db);
  });
}

const regRef = (db, id) =>
  doc(db, 'orgs', HOST, 'competitions', COMP, 'registrations', id);
const compRef = (db) => doc(db, 'orgs', HOST, 'competitions', COMP);

const enter = (uid, status, count, id = uid, data = null) => {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.set(regRef(db, id), data ?? registration(uid, status));
  if (status === 'confirmed') batch.update(compRef(db), { confirmedCount: count });
  return batch.commit();
};

beforeEach(async () => { await testEnv.clearFirestore(); });

// -------------------------------------------------------------------------
describe('re-entering after withdrawing', () => {
  it('lets the player enter again', async () => {
    await seed({}, (db) => setDoc(regRef(db, MEMBER),
      registration(MEMBER, 'withdrawn')));
    await assertSucceeds(enter(MEMBER, 'confirmed', 1));
  });

  it('does not reopen a rejected entry', async () => {
    await seed({}, (db) => setDoc(regRef(db, MEMBER),
      registration(MEMBER, 'rejected')));
    await assertFails(enter(MEMBER, 'confirmed', 1));
  });

  it('still makes the re-entry pay for its slot', async () => {
    await seed({}, (db) => setDoc(regRef(db, MEMBER),
      registration(MEMBER, 'withdrawn')));
    const db = as(MEMBER);
    await assertFails(setDoc(regRef(db, MEMBER), registration(MEMBER, 'confirmed')));
  });

  it('is refused for somebody else', async () => {
    await seed({}, (db) => setDoc(regRef(db, MEMBER),
      registration(MEMBER, 'withdrawn')));
    const db = as(HOST_OWNER);
    const batch = writeBatch(db);
    batch.set(regRef(db, MEMBER), registration(HOST_OWNER, 'confirmed'));
    batch.update(compRef(db), { confirmedCount: 1 });
    await assertFails(batch.commit());
  });
});

// -------------------------------------------------------------------------
describe('a season opened to other clubs', () => {
  const opened = { participationModel: 'approval', openToNonMembers: true };

  it("confirms the host's own member as they enter", async () => {
    await seed(opened);
    await assertSucceeds(enter(MEMBER, 'confirmed', 1));
  });

  it('still makes an outsider apply', async () => {
    await seed(opened);
    await assertFails(enter(OUTSIDER, 'confirmed', 1));
    await assertSucceeds(enter(OUTSIDER, 'pending', 0));
  });

  it('does not extend to a stand-alone approval event', async () => {
    await seed({ ...opened, tournamentId: null });
    await assertFails(enter(MEMBER, 'confirmed', 1));
  });

  it("confirms the host club's own team", async () => {
    const teamId = 'team_host';
    await seed({ ...opened, entrantType: 'team', teamEntryMode: 'preformed_team' },
      (db) => setDoc(doc(db, 'teams', teamId), team(HOST, HOST_OWNER)));
    await assertSucceeds(enter(HOST_OWNER, 'confirmed', 1, teamId,
      registration(teamId, 'confirmed', {
        teamId, memberUids: [HOST_OWNER], registeredByUid: HOST_OWNER,
      })));
  });

  it("does not confirm another club's team", async () => {
    const teamId = 'team_guest';
    await seed({ ...opened, entrantType: 'team', teamEntryMode: 'preformed_team' },
      (db) => setDoc(doc(db, 'teams', teamId), team(GUEST, GUEST_OWNER)));
    await assertFails(enter(GUEST_OWNER, 'confirmed', 1, teamId,
      registration(teamId, 'confirmed', {
        teamId, memberUids: [GUEST_OWNER], registeredByUid: GUEST_OWNER,
      })));
  });
});

// -------------------------------------------------------------------------
describe('a house event', () => {
  it('does not count people against the team cap', async () => {
    await seed({
      entrantType: 'team', teamEntryMode: 'house_batch',
      maxEntrants: 4, confirmedCount: 4,
    });
    await assertSucceeds(enter(MEMBER, 'confirmed', 5));
  });

  it('leaves the cap in force for an individual event', async () => {
    await seed({ maxEntrants: 4, confirmedCount: 4 });
    await assertFails(enter(MEMBER, 'confirmed', 5));
  });
});
