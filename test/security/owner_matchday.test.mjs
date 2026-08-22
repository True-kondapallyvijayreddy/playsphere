// What a brand-new club owner can and cannot do, end to end.
//
// Written against a report that an owner could not assign umpires to their own
// matches, which turned out to be two separate things:
//
//  1. Most single-field organizer edits to a fixture were refused. Not by any
//     rule — by Firestore's 1,000-expression evaluation budget, which ran out
//     while falling through seven statements before the organizer branch was
//     reached. Every `assertSucceeds` on a fixture update below failed before
//     that branch was hoisted to the front of the block.
//
//  2. The `umpires` registry is global and self-service, so a new club has
//     nobody in it and its owner has no rules-permitted way to put anybody
//     there. The last group pins that boundary, because it is a product
//     decision living in a rules file and should fail loudly if it changes by
//     accident.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection, doc, getDocs, query, serverTimestamp, setDoc, updateDoc, where,
  writeBatch,
} from 'firebase/firestore';

let testEnv;
const OWNER = 'uid_owner';
const MEMBER = 'uid_member';
const ORG = 'org_new';
const COMP = 'comp1';
const FIX = 'fix1';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-matchday',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
after(async () => { await testEnv?.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const membership = (uid, orgId, role, status = 'active') => ({
  uid, orgId, role, status, displayName: 'P', photoUrl: null,
  joinedAt: serverTimestamp(), invitedBy: null, approvedBy: null,
});

const organization = (ownerUid) => ({
  name: 'Brand New Club', nameLower: 'brand new club', orgType: 'club',
  visibility: 'public', ownerUid, inviteCode: 'ABC234', parentOrgId: null,
  description: null, district: null, city: null, logoUrl: null,
  memberCount: 1, requiresApprovalToJoin: true, createdBy: ownerUid,
  createdAt: serverTimestamp(), deletedAt: null,
});

const competition = (orgId) => ({
  orgId, name: 'Club Championship', nameLower: 'club championship',
  sportId: 'cricket', sportName: 'Cricket', archetype: 'versus',
  entrantType: 'individual', format: 'knockout', status: 'draft',
  category: { label: 'Open', dimensions: ['open'] },
  scoringPluginKey: 'cricket', description: null, venue: null,
  startDate: null, endDate: null, registrationClosesAt: null,
  maxEntrants: 8, entrantCount: 0, fixtureCount: 0,
  participationModel: 'open', preselectedSlots: 0, waitlistEnabled: true,
  openToNonMembers: false, entryFeeRupees: 0, teamSize: null,
  rulesNote: null, confirmedCount: 0, waitlistCount: 0,
  verificationTier: 'casual', rulesetVersion: 1, pointsForWin: 3,
  pointsForDraw: 1, pointsForLoss: 0, tiebreakChain: null,
  participantOrgIds: null, createdBy: OWNER, createdAt: serverTimestamp(),
});

/** A fixture as `Fixture.toCreate` writes it. */
const fixture = (orgId, compId) => ({
  orgId, compId,
  entrantAId: 'a', entrantBId: 'b', entrantAName: 'Alice', entrantBName: 'Bob',
  entrantAUid: null, entrantBUid: null,
  status: 'scheduled', round: 1, matchIndex: 0, roundLabel: 'Round 1',
  scheduledAt: null, venue: null,
  scorerUids: [], activeScorerUid: null, activeScorerDeviceId: null,
  penGrantedByUid: null, penGrantedAt: null, lastRestartSeq: null,
  participantOrgIds: null, officials: [],
  scoreState: {}, summary: '', lastSeq: 0,
  winnerEntrantId: null, isDraw: false, rulesetVersion: 1,
  scoringPluginKey: 'cricket', sportId: 'cricket', scoringConfig: null,
  lineupA: [], lineupB: [], squadLockedA: false, squadLockedB: false,
  mvp: null, squadCallA: {}, squadCallB: {}, playerUids: [],
  tossWonByEntrantId: null, tossDecision: null,
  feedsWinnerToFixtureId: null, feedsWinnerToSlot: null,
  feedsLoserToFixtureId: null, feedsLoserToSlot: null,
  bracket: 'main', groupId: null, qualifierA: null, qualifierB: null,
  courtId: null, tournamentId: null, resultType: 'normal', resultNote: null,
  isDraft: false, readiness: 'scheduled', resultState: 'none',
  sourceType: null, sourceId: null, createdAt: serverTimestamp(),
});

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => { await fn(ctx.firestore()); });
}

async function seedClub() {
  await seed(async (db) => {
    await setDoc(doc(db, 'orgs', ORG), organization(OWNER));
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, ORG, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', MEMBER), membership(MEMBER, ORG, 'member'));
  });
}

const fixRef = (db) =>
  doc(db, 'orgs', ORG, 'competitions', COMP, 'fixtures', FIX);

describe('a new owner setting up their first match', () => {
  beforeEach(seedClub);

  it('creates the event', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'orgs', ORG, 'competitions', COMP), competition(ORG)),
    );
  });

  it('creates a fixture in it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', ORG, 'competitions', COMP), competition(ORG));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(fixRef(db), fixture(ORG, COMP)));
  });

  describe('with the fixture in place', () => {
    beforeEach(async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'orgs', ORG, 'competitions', COMP), competition(ORG));
        await setDoc(
          doc(db, 'orgs', ORG, 'competitions', COMP, 'fixtures', FIX),
          fixture(ORG, COMP),
        );
      });
    });

    it('reads the whole fixture list unfiltered, the way the clash check does',
      async () => {
        // `UmpireRepository.checkOfficialAvailability` reads every fixture of
        // the event with no `where` at all. A member's query has to pin
        // `isDraft`; an organizer's short-circuits past that clause, and this
        // is what proves it.
        const db = testEnv.authenticatedContext(OWNER).firestore();
        await assertSucceeds(getDocs(
          collection(db, 'orgs', ORG, 'competitions', COMP, 'fixtures'),
        ));
      });

    it('assigns an official and grants them the scoring right', async () => {
      // Exactly the write `UmpireRepository.assignOfficialToFixture` makes.
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(updateDoc(fixRef(db), {
        officials: [{ uid: MEMBER, name: 'Ravi', role: 'umpire',
                      grantedScoringAccess: true }],
        scorerUids: [MEMBER],
        readiness: 'officials_assigned',
      }));
    });

    it('assigns a SECOND umpire, which writes no readiness', async () => {
      // The one that was actually broken. `assignOfficialToFixture` only
      // writes `readiness` while the match is still `scheduled`, so the
      // second assignment is a two-field write — and a two-field organizer
      // write used to fall through every statement below the organizer one
      // and exhaust Firestore's 1,000-expression budget before reaching it.
      // The failure arrived as permission-denied with no rule having denied.
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(updateDoc(fixRef(db), {
        officials: [
          { uid: MEMBER, name: 'Ravi', grantedScoringAccess: true },
          { uid: 'uid_second', name: 'Anitha', grantedScoringAccess: true },
        ],
        scorerUids: [MEMBER, 'uid_second'],
      }));
    });

    it('marks the match ready', async () => {
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(updateDoc(fixRef(db), { readiness: 'ready' }));
    });

    it('takes the official back off again', async () => {
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(updateDoc(fixRef(db), {
        officials: [],
        scorerUids: [],
      }));
    });

    it('hands the pen to the official it just named', async () => {
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(updateDoc(fixRef(db), {
        activeScorerUid: MEMBER,
        activeScorerDeviceId: 'device-1',
        penGrantedByUid: OWNER,
        penGrantedAt: serverTimestamp(),
      }));
    });

    it('reschedules the match', async () => {
      const db = testEnv.authenticatedContext(OWNER).firestore();
      await assertSucceeds(updateDoc(fixRef(db), {
        scheduledAt: new Date('2026-09-01T10:00:00Z'),
        venue: 'Main ground',
      }));
    });
  });

  it('promotes a member to judge/scorer so they may actually score', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(updateDoc(
      doc(db, 'orgs', ORG, 'members', MEMBER),
      { role: 'judge_scorer' },
    ));
  });

  it('approves somebody waiting to join', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', ORG, 'members', 'uid_joiner'),
        membership('uid_joiner', ORG, 'member', 'pending'));
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(updateDoc(
      doc(db, 'orgs', ORG, 'members', 'uid_joiner'),
      { status: 'active', approvedBy: OWNER },
    ));
  });

  it('puts an official on a tournament panel by hand', async () => {
    // The tournament panel DOES let an organizer name anybody — which is the
    // asymmetry with the match-level registry below.
    await seed(async (db) => {
      await setDoc(doc(db, 'orgs', ORG, 'tournaments', 't1'), {
        orgId: ORG, name: 'Annual Meet', createdBy: OWNER,
        createdAt: serverTimestamp(),
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(
      doc(db, 'orgs', ORG, 'tournaments', 't1', 'officials', MEMBER),
      { name: 'Ravi', addedBy: OWNER, addedAt: serverTimestamp() },
    ));
  });
});

describe('the umpire registry is global and self-service', () => {
  beforeEach(seedClub);

  it('an owner may NOT register one of their members as an umpire', async () => {
    // This is the whole reported bug. The assign sheet offers only people who
    // appear in `umpires`, and `umpires/{uid}` is writable by {uid} alone —
    // so the owner of a brand-new club is shown an empty list and has no
    // action available that would fill it.
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(setDoc(doc(db, 'umpires', MEMBER), {
      uid: MEMBER, displayName: 'Ravi', photoUrl: null, phone: null,
      sports: ['cricket'], badgeLevel: 'community', matchesOfficiated: 0,
      isAvailable: true,
    }));
  });

  it('the member may register themselves', async () => {
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(setDoc(doc(db, 'umpires', MEMBER), {
      uid: MEMBER, displayName: 'Ravi', photoUrl: null, phone: null,
      sports: ['cricket'], badgeLevel: 'community', matchesOfficiated: 0,
      isAvailable: true,
    }));
  });

  it('and once they have, the owner can find them', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'umpires', MEMBER), {
        uid: MEMBER, displayName: 'Ravi', sports: ['cricket'],
        badgeLevel: 'community', matchesOfficiated: 0, isAvailable: true,
      });
    });
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDocs(query(
      collection(db, 'umpires'),
      where('sports', 'array-contains', 'cricket'),
      where('isAvailable', '==', true),
    )));
  });
});

describe('the founding batch itself', () => {
  it('creates the club and its owner row together', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs', ORG), organization(OWNER));
    batch.set(doc(db, 'orgs', ORG, 'members', OWNER),
      membership(OWNER, ORG, 'owner'));
    await assertSucceeds(batch.commit());
  });
});
