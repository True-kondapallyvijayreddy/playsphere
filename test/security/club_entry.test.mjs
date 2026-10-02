// The invited club's route in: picking a side, entering it, and the host
// approving it.
//
// Four rules changed together to make that flow work, and each of them is a
// door that must open exactly as far as intended:
//
//  1. A club's manager may raise a team they are NOT on, for their own club.
//     Everyone else still has to be on the roster they create.
//  2. The host's organizers may approve a TEAM entry, whose document id is the
//     team's rather than any person's.
//  3. `seasonNominations` is written by the club's organizers and nobody else.
//  4. Whoever FILED an entry may read it back, which is what lets the app stop
//     showing them a Register button for a draw they already entered.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, serverTimestamp, setDoc, updateDoc, deleteDoc,
} from 'firebase/firestore';

let testEnv;

const HOST = 'org_host';       // the club running the season
const GUEST = 'org_guest';     // the club that was invited
const SEASON = 'season1';
const COMP = 'comp1';          // a team draw, by approval

const HOST_OWNER = 'uid_host_owner';
const GUEST_OWNER = 'uid_guest_owner';   // manager; does not play
const PLAYER_A = 'uid_player_a';
const PLAYER_B = 'uid_player_b';
const OUTSIDER = 'uid_outsider';

const TEAM = 'team_guest_a';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-club-entry',
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
  ownerUid, inviteCode: code, memberCount: 3, requiresApprovalToJoin: true,
  createdBy: ownerUid, createdAt: serverTimestamp(), deletedAt: null,
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'orgs', HOST), org(HOST, HOST_OWNER, 'HST234'));
    await setDoc(doc(db, 'orgs', HOST, 'members', HOST_OWNER),
      membership(HOST_OWNER, HOST, 'owner'));

    await setDoc(doc(db, 'orgs', GUEST), org(GUEST, GUEST_OWNER, 'GST234'));
    await setDoc(doc(db, 'orgs', GUEST, 'members', GUEST_OWNER),
      membership(GUEST_OWNER, GUEST, 'owner'));
    await setDoc(doc(db, 'orgs', GUEST, 'members', PLAYER_A),
      membership(PLAYER_A, GUEST, 'member'));
    await setDoc(doc(db, 'orgs', GUEST, 'members', PLAYER_B),
      membership(PLAYER_B, GUEST, 'member'));

    await setDoc(doc(db, 'orgs', HOST, 'tournaments', SEASON), {
      orgId: HOST, name: 'Invitational', status: 'in_progress', eventCount: 1,
      venueIds: [], createdBy: HOST_OWNER, createdAt: serverTimestamp(),
    });

    // A team draw that admits entries by approval — so an entry arrives
    // `pending` and somebody has to decide it, which is the case in point.
    await setDoc(doc(db, 'orgs', HOST, 'competitions', COMP), {
      orgId: HOST, name: 'Open Cricket', sportId: 'cricket',
      sportName: 'Cricket', status: 'registration_open',
      tournamentId: SEASON, entrantType: 'team', teamEntryMode: 'preformed_team',
      participationModel: 'approval', format: 'knockout', category: 'open',
      confirmedCount: 0, waitlistCount: 0, maxEntrants: 16,
      waitlistEnabled: false, entryFeeRupees: 0, openToNonMembers: false,
      preselectedSlots: 0, createdBy: HOST_OWNER, createdAt: serverTimestamp(),
    });

    // The invitation the guest club accepted.
    await setDoc(doc(db, 'tournamentInvites', `${SEASON}_${GUEST}`), {
      tournamentId: SEASON, fromOrgId: HOST, toOrgId: GUEST,
      fromOrgName: 'Host', toOrgName: 'Guest', tournamentName: 'Invitational',
      status: 'accepted', createdAt: serverTimestamp(),
    });
  });
});

const team = (overrides = {}) => ({
  name: 'Guest A', sportId: 'cricket', type: 'event', status: 'active',
  createdByUid: GUEST_OWNER, clubId: GUEST,
  captainUid: PLAYER_A, managerUid: null,
  memberUids: [PLAYER_A, PLAYER_B],
  competitionId: COMP, baseTeamId: null, photoUrl: null, homeArea: null,
  joinCode: null, createdAt: serverTimestamp(),
  ...overrides,
});

// -------------------------------------------------------------------------
describe('a club manager raises a side they do not play in', () => {
  it('is allowed for their own club', async () => {
    await assertSucceeds(
      setDoc(doc(as(GUEST_OWNER), 'teams', TEAM), team()),
    );
  });

  it('is still refused to a plain member', async () => {
    // PLAYER_A runs nothing. A roster they are not on is a list of other
    // people they have no standing to assemble.
    await assertFails(
      setDoc(doc(as(PLAYER_A), 'teams', TEAM), team({
        createdByUid: PLAYER_A,
        memberUids: [PLAYER_B],
      })),
    );
  });

  it('is refused for a club the creator does not run', async () => {
    await assertFails(
      setDoc(doc(as(OUTSIDER), 'teams', TEAM), team({
        createdByUid: OUTSIDER,
      })),
    );
  });

  it('still lets an ordinary person create a team they ARE on', async () => {
    await assertSucceeds(
      setDoc(doc(as(PLAYER_A), 'teams', 'team_friends'), team({
        createdByUid: PLAYER_A,
        clubId: null,
        type: 'independent',
        competitionId: null,
        memberUids: [PLAYER_A, PLAYER_B],
      })),
    );
  });
});

// -------------------------------------------------------------------------
describe('the host approves the team entry', () => {
  const entry = (status) => ({
    uid: TEAM, displayName: 'Guest A', photoUrl: null, status,
    teamName: 'Guest A', teamId: TEAM, memberUids: [PLAYER_A, PLAYER_B],
    registeredByUid: GUEST_OWNER, waitlistPosition: null, preselected: false,
    houseName: null, partnerUid: null, partnerName: null,
    isSoloDoubles: false, groupId: null, eligibilityNote: null,
    decidedBy: null, createdAt: serverTimestamp(),
  });

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'teams', TEAM), team());
      await setDoc(
        doc(db, 'orgs', HOST, 'competitions', COMP, 'registrations', TEAM),
        entry('pending'),
      );
    });
  });

  it("lets the season's owner confirm it", async () => {
    // The complaint was that this was impossible. The document id is the
    // TEAM's, which is what `decideRegistration` must be handed — passing the
    // captain's uid writes to a document that does not exist.
    await assertSucceeds(
      updateDoc(
        doc(as(HOST_OWNER), 'orgs', HOST, 'competitions', COMP,
          'registrations', TEAM),
        {
          status: 'confirmed',
          decidedBy: HOST_OWNER,
          decidedAt: serverTimestamp(),
          waitlistPosition: null,
        },
      ),
    );
  });

  it('lets the host reject it', async () => {
    await assertSucceeds(
      updateDoc(
        doc(as(HOST_OWNER), 'orgs', HOST, 'competitions', COMP,
          'registrations', TEAM),
        { status: 'rejected', decidedBy: HOST_OWNER, waitlistPosition: null },
      ),
    );
  });

  it('does not let the entering club confirm its own side', async () => {
    // Approval is the host's call. A guest who could confirm themselves has
    // an entry, not an application.
    await assertFails(
      updateDoc(
        doc(as(GUEST_OWNER), 'orgs', HOST, 'competitions', COMP,
          'registrations', TEAM),
        { status: 'confirmed', decidedBy: GUEST_OWNER },
      ),
    );
  });

  it('refuses an approval that also rewrites the squad', async () => {
    // `memberUids` is the entry's provenance — whose ratings a finished match
    // may move. Deciding an entry must not be a way to change who is in it.
    await assertFails(
      updateDoc(
        doc(as(HOST_OWNER), 'orgs', HOST, 'competitions', COMP,
          'registrations', TEAM),
        { status: 'confirmed', memberUids: [PLAYER_A, OUTSIDER] },
      ),
    );
  });

  it('lets the person who filed it read it back', async () => {
    // GUEST_OWNER is not in `memberUids` and is not the `uid` — the team is.
    // Without the `registeredByUid` clause the one person who registered the
    // side could not see that it was registered.
    await assertSucceeds(
      getDoc(doc(as(GUEST_OWNER), 'orgs', HOST, 'competitions', COMP,
        'registrations', TEAM)),
    );
  });
});

// -------------------------------------------------------------------------
describe('nominating a member for a draw the club cannot enter them into', () => {
  const nomination = (uid, by) => ({
    orgId: GUEST, hostOrgId: HOST, tournamentId: SEASON, compId: COMP,
    uid, nominatedByUid: by, compName: 'Open Cricket',
    tournamentName: 'Invitational', clubName: 'Guest',
    createdAt: serverTimestamp(),
  });
  const id = (uid) => `${HOST}_${SEASON}_${COMP}_${uid}`;

  it('is written by the club that is doing the picking', async () => {
    await assertSucceeds(
      setDoc(
        doc(as(GUEST_OWNER), 'orgs', GUEST, 'seasonNominations', id(PLAYER_A)),
        nomination(PLAYER_A, GUEST_OWNER),
      ),
    );
  });

  it('is refused to a member picking themselves', async () => {
    await assertFails(
      setDoc(
        doc(as(PLAYER_A), 'orgs', GUEST, 'seasonNominations', id(PLAYER_A)),
        nomination(PLAYER_A, PLAYER_A),
      ),
    );
  });

  it('cannot name somebody who is not in the club', async () => {
    await assertFails(
      setDoc(
        doc(as(GUEST_OWNER), 'orgs', GUEST, 'seasonNominations', id(OUTSIDER)),
        nomination(OUTSIDER, GUEST_OWNER),
      ),
    );
  });

  it('refuses an id that does not match the row', async () => {
    // The deterministic id is what stops one person being nominated twice
    // and notified twice.
    await assertFails(
      setDoc(
        doc(as(GUEST_OWNER), 'orgs', GUEST, 'seasonNominations', 'anything'),
        nomination(PLAYER_A, GUEST_OWNER),
      ),
    );
  });

  it('lets the player decline by deleting their own row', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'orgs', GUEST, 'seasonNominations', id(PLAYER_A)),
        nomination(PLAYER_A, GUEST_OWNER),
      );
    });
    await assertSucceeds(
      deleteDoc(
        doc(as(PLAYER_A), 'orgs', GUEST, 'seasonNominations', id(PLAYER_A)),
      ),
    );
  });

  it('is not readable outside the club', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'orgs', GUEST, 'seasonNominations', id(PLAYER_A)),
        nomination(PLAYER_A, GUEST_OWNER),
      );
    });
    await assertFails(
      getDoc(
        doc(as(OUTSIDER), 'orgs', GUEST, 'seasonNominations', id(PLAYER_A)),
      ),
    );
  });
});
