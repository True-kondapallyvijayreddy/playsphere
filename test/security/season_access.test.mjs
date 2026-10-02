// The season's management data, written by anybody but its organizers.
//
// The client hides every organizer control from members (see
// test/season_access_test.dart). This is the half that makes hiding them
// safe rather than cosmetic: a member who calls the API directly is refused.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

let testEnv;
const ORG = 'org_season';
const SEASON = 's1';
const OWNER = 'uid_owner';
const MANAGER = 'uid_manager';
const MEMBER = 'uid_member';
const SCORER = 'uid_scorer';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-season-access',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
after(async () => { await testEnv?.cleanup(); });

const membership = (uid, role) => ({
  uid, orgId: ORG, role, status: 'active', displayName: 'P', photoUrl: null,
  joinedAt: serverTimestamp(), invitedBy: null, approvedBy: null,
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'orgs', ORG), {
      name: 'Season Club', nameLower: 'season club', orgType: 'club',
      visibility: 'public', ownerUid: OWNER, inviteCode: 'SEA234',
      memberCount: 4, requiresApprovalToJoin: true, createdBy: OWNER,
      createdAt: serverTimestamp(), deletedAt: null,
    });
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', MANAGER), membership(MANAGER, 'event_manager'));
    await setDoc(doc(db, 'orgs', ORG, 'members', MEMBER), membership(MEMBER, 'member'));
    await setDoc(doc(db, 'orgs', ORG, 'members', SCORER), membership(SCORER, 'judge_scorer'));
    await setDoc(doc(db, 'orgs', ORG, 'tournaments', SEASON), {
      orgId: ORG, name: 'Summer Games', status: 'in_progress', eventCount: 1,
      venueIds: [], createdBy: OWNER, createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'venues', 'v1'), {
      orgId: ORG, name: 'Main Ground', openHour: 8, closeHour: 20,
      createdBy: OWNER, createdAt: serverTimestamp(),
    });
  });
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const official = (uid) => ({
  name: 'Umpire', role: 'main_umpire', sports: [], addedBy: uid,
  addedAt: serverTimestamp(),
});

describe('a plain member cannot run the season', () => {
  for (const [who, uid] of [['a member', MEMBER], ['a club scorer', SCORER]]) {
    it(`${who} cannot add an umpire to the panel`, async () => {
      await assertFails(setDoc(
        doc(as(uid), 'orgs', ORG, 'tournaments', SEASON, 'officials', 'x'),
        official(uid),
      ));
    });

    it(`${who} cannot edit the season`, async () => {
      await assertFails(updateDoc(
        doc(as(uid), 'orgs', ORG, 'tournaments', SEASON),
        { name: 'Renamed' },
      ));
    });

    it(`${who} cannot name who is in charge of a sport`, async () => {
      await assertFails(updateDoc(
        doc(as(uid), 'orgs', ORG, 'tournaments', SEASON),
        { 'sportLeads.cricket': [{ uid, name: 'Me' }] },
      ));
    });

    it(`${who} cannot plan a ground`, async () => {
      await assertFails(setDoc(
        doc(as(uid), 'orgs', ORG, 'tournaments', SEASON, 'venuePlans', 'v1'),
        { maxMatchesPerCourtPerDay: 4 },
      ));
    });

    it(`${who} cannot add or edit a venue`, async () => {
      await assertFails(updateDoc(
        doc(as(uid), 'orgs', ORG, 'venues', 'v1'),
        { name: 'Mine now', openHour: 8, closeHour: 20 },
      ));
    });
  }
});

describe('the organizers can', () => {
  for (const [who, uid] of [['the owner', OWNER], ['an event manager', MANAGER]]) {
    it(`${who} adds an umpire and names a sport lead`, async () => {
      await assertSucceeds(setDoc(
        doc(as(uid), 'orgs', ORG, 'tournaments', SEASON, 'officials', 'x'),
        official(uid),
      ));
      await assertSucceeds(updateDoc(
        doc(as(uid), 'orgs', ORG, 'tournaments', SEASON),
        { 'sportLeads.cricket': [{ uid, name: 'Lead' }] },
      ));
    });
  }
});
