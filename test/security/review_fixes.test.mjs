// The holes closed by the 2026-09-13 code review, each pinned from the
// attacker's side and, where it matters, from the honest caller's side too.
//
//  - settlement records on a fixture are the server's (career/officiating
//    credit is reversed FROM them, so a client that wrote them could subtract
//    from anybody's record);
//  - the pen writes only scoring fields, and set-up writes only set-up fields;
//  - a registration's provenance (squad, team, group, who wrote it) is frozen;
//  - a team entry carries the team's own roster;
//  - nobody writes a membership row for somebody else, and members can leave;
//  - an invited club enters through its team's `clubId`, and its counter bump
//    names the club it acts for;
//  - approving a group writes each member's registration;
//  - an Arena move changes only what a move changes;
//  - a match event's `seq` is its document id;
//  - a sold auction lot cannot be put back in the pool;
//  - an accepted multi-sport challenge may create its scheduled container;
//  - an organizer's walkover stands over somebody else's pen.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion, deleteDoc, doc, increment, serverTimestamp, setDoc, updateDoc,
  writeBatch,
} from 'firebase/firestore';

let testEnv;
const ORG = 'org_review';
const GUEST = 'org_guest';
const COMP = 'comp1';
const FIX = 'fix1';
const SEASON = 'season1';

const OWNER = 'uid_owner';
const MEMBER = 'uid_member';
const SCORER = 'uid_scorer'; // on scorerUids, club judge_scorer
const ENTRANT = 'uid_entrant'; // plays; scores via isFixtureOfficial
const VICTIM = 'uid_victim'; // never did anything
const GUEST_ADMIN = 'uid_guest_admin';
const P1 = 'uid_p1';
const P2 = 'uid_p2';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-review',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
after(async () => { await testEnv?.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

const membership = (uid, orgId, role, status = 'active') => ({
  uid, orgId, role, status, displayName: 'P', photoUrl: null,
  joinedAt: serverTimestamp(), invitedBy: null, approvedBy: null,
});

const org = (ownerUid, visibility = 'public', extra = {}) => ({
  name: 'Club', nameLower: 'club', orgType: 'club', visibility, ownerUid,
  inviteCode: 'REV234', memberCount: 1, requiresApprovalToJoin: false,
  createdBy: ownerUid, createdAt: serverTimestamp(), deletedAt: null, ...extra,
});

const fixture = (overrides = {}) => ({
  orgId: ORG, compId: COMP,
  entrantAId: 'a', entrantBId: 'b', entrantAName: 'Alice', entrantBName: 'Bob',
  entrantAUid: ENTRANT, entrantBUid: null,
  status: 'live', round: 1, matchIndex: 0, roundLabel: 'Round 1',
  scheduledAt: null, venue: null,
  scorerUids: [SCORER], activeScorerUid: null, activeScorerDeviceId: null,
  penGrantedByUid: null, penGrantedAt: null, lastRestartSeq: null,
  participantOrgIds: null, officials: [],
  scoreState: { a: 0, b: 0 }, summary: '0-0', lastSeq: 3,
  winnerEntrantId: null, isDraw: false, rulesetVersion: 1,
  scoringPluginKey: 'badminton', sportId: 'badminton', scoringConfig: null,
  lineupA: [], lineupB: [], squadLockedA: false, squadLockedB: false,
  mvp: null, playerUids: [ENTRANT], tournamentId: null, resultType: 'normal',
  resultNote: null, isDraft: false, readiness: 'scheduled', resultState: 'none',
  sourceType: 'tournament', sourceId: COMP, createdAt: serverTimestamp(),
  ...overrides,
});

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'orgs', ORG), org(OWNER));
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, ORG, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', MEMBER), membership(MEMBER, ORG, 'member'));
    await setDoc(doc(db, 'orgs', ORG, 'members', SCORER), membership(SCORER, ORG, 'judge_scorer'));
    await setDoc(doc(db, 'orgs', ORG, 'members', ENTRANT), membership(ENTRANT, ORG, 'member'));
    await setDoc(doc(db, 'orgs', ORG, 'competitions', COMP), {
      orgId: ORG, name: 'Singles', sportId: 'badminton',
      status: 'registration_open', participationModel: 'open',
      confirmedCount: 0, waitlistCount: 0, maxEntrants: 16,
      waitlistEnabled: true, tournamentId: SEASON, createdBy: OWNER,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'orgs', ORG, 'tournaments', SEASON), {
      orgId: ORG, name: 'Season', status: 'entries_open', eventCount: 1,
      createdBy: OWNER, createdAt: serverTimestamp(),
    });
    if (fn) await fn(db);
  });
}

const fixPath = ['orgs', ORG, 'competitions', COMP, 'fixtures', FIX];
const fixRef = (uid) => doc(as(uid), ...fixPath);
const seedFixture = (overrides) =>
  seed((db) => setDoc(doc(db, ...fixPath), fixture(overrides)));

// ---------------------------------------------------------------------------
describe('settlement records are the server\'s', () => {
  const forged = {
    careerSettledAt: new Date(),
    careerSettlement: [{ uid: VICTIM, sportId: 'badminton', outcome: 'won', tally: { points: 100000 } }],
  };

  it('refuses an organizer writing a career settlement onto a live fixture', async () => {
    await seedFixture();
    await assertFails(updateDoc(fixRef(OWNER), forged));
    await assertFails(updateDoc(fixRef(OWNER), {
      officialsSettledAt: new Date(), officialsSettlement: [VICTIM],
    }));
    await assertFails(updateDoc(fixRef(OWNER), { ratingSettledAt: new Date() }));
  });

  it('refuses the pen smuggling one in with a scoring write', async () => {
    await seedFixture();
    await assertFails(updateDoc(fixRef(SCORER), {
      lastSeq: 4, scoreState: { a: 1, b: 0 }, summary: '1-0', status: 'live', ...forged,
    }));
  });

  it('refuses creating a fixture that already carries one', async () => {
    await seed();
    await assertFails(setDoc(doc(as(OWNER), ...fixPath), fixture({ lastSeq: 0, ...forged })));
  });

  it('still lets an organizer do ordinary fixture admin', async () => {
    await seedFixture({ status: 'scheduled', lastSeq: 0 });
    await assertSucceeds(updateDoc(fixRef(OWNER), { venue: 'Court 2', courtId: 'c2' }));
  });
});

// ---------------------------------------------------------------------------
describe('the pen writes scoring fields only', () => {
  it('lets the scorer advance the score', async () => {
    await seedFixture();
    await assertSucceeds(updateDoc(fixRef(SCORER), {
      lastSeq: 4, scoreState: { a: 1, b: 0 }, summary: '1-0', status: 'live',
      lastEventAt: serverTimestamp(),
    }));
  });

  it('refuses an entrant scoring their own match rewriting officials or player lists', async () => {
    await seedFixture();
    await assertFails(updateDoc(fixRef(ENTRANT), {
      lastSeq: 4, scoreState: { a: 1, b: 0 }, summary: '1-0', status: 'live',
      officials: [{ uid: VICTIM, name: 'x', role: 'main_umpire', grantedScoringAccess: true }],
    }));
    await assertFails(updateDoc(fixRef(ENTRANT), {
      lastSeq: 4, scoreState: { a: 1, b: 0 }, summary: '1-0', status: 'live',
      playerUids: [ENTRANT, VICTIM],
    }));
    await assertFails(updateDoc(fixRef(ENTRANT), {
      lastSeq: 4, scoreState: { a: 1, b: 0 }, summary: '1-0', status: 'live',
      isDraft: true,
    }));
  });

  it('refuses a scorer certifying their own result', async () => {
    await seedFixture();
    await assertFails(updateDoc(fixRef(SCORER), {
      lastSeq: 4, status: 'completed', resultState: 'finalized',
    }));
  });

  it('lets a claimant add only themselves to the scorers', async () => {
    await seedFixture();
    await assertSucceeds(updateDoc(fixRef(ENTRANT), {
      activeScorerUid: ENTRANT, scorerUids: arrayUnion(ENTRANT),
    }));
  });

  it('refuses a claimant adding a friend to the scorers', async () => {
    await seedFixture();
    await assertFails(updateDoc(fixRef(ENTRANT), {
      activeScorerUid: ENTRANT, scorerUids: [SCORER, ENTRANT, VICTIM],
    }));
  });

  it('lets an organizer award a walkover while somebody else holds the pen', async () => {
    await seedFixture({ activeScorerUid: SCORER });
    await assertSucceeds(updateDoc(fixRef(OWNER), {
      status: 'walkover', resultType: 'walkover', winnerEntrantId: 'a',
      resultNote: 'No show',
    }));
  });

  it('refuses an organizer moving the score itself under somebody else\'s pen', async () => {
    await seedFixture({ activeScorerUid: SCORER });
    await assertFails(updateDoc(fixRef(OWNER), {
      status: 'walkover', scoreState: { a: 21, b: 0 },
    }));
  });
});

// ---------------------------------------------------------------------------
describe('a match event\'s seq is its id', () => {
  it('refuses an event whose seq disagrees with its document id', async () => {
    await seedFixture();
    const ev = (seq) => ({
      seq, type: 'point', payload: {}, byUid: SCORER, at: serverTimestamp(),
      clientEventId: `c${seq}`,
    });
    await assertFails(setDoc(doc(as(SCORER), ...fixPath, 'events', '000000004'), ev(9)));
    await assertSucceeds(setDoc(doc(as(SCORER), ...fixPath, 'events', '000000004'), ev(4)));
  });
});

// ---------------------------------------------------------------------------
describe('registrations keep their provenance', () => {
  const regPath = (id) => ['orgs', ORG, 'competitions', COMP, 'registrations', id];

  it('refuses an organizer adding a stranger to an entry\'s squad', async () => {
    await seed((db) => setDoc(doc(db, ...regPath('team1')), {
      uid: 'team1', teamId: 'team1', memberUids: [P1, P2], status: 'confirmed',
      registeredByUid: OWNER, preselected: false, createdAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(as(OWNER), ...regPath('team1')), {
      memberUids: [P1, P2, VICTIM],
    }));
    await assertSucceeds(updateDoc(doc(as(OWNER), ...regPath('team1')), {
      status: 'waitlisted',
    }));
  });

  it('refuses an organizer turning their own pick into a self-registration', async () => {
    await seed((db) => setDoc(doc(db, ...regPath(VICTIM)), {
      uid: VICTIM, status: 'confirmed', preselected: true,
      createdAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(as(OWNER), ...regPath(VICTIM)), { preselected: false }));
  });

  it('refuses a team entry whose squad is not the team\'s roster', async () => {
    await seed((db) => setDoc(doc(db, 'teams', 'team1'), {
      name: 'Owners XI', sportId: 'badminton', type: 'permanent', status: 'active',
      clubId: ORG, createdByUid: OWNER, captainUid: OWNER, memberUids: [OWNER, P1],
    }));
    const entry = (memberUids) => {
      const db = as(OWNER);
      const batch = writeBatch(db);
      batch.set(doc(db, ...regPath('team1')), {
        uid: 'team1', teamId: 'team1', memberUids, status: 'confirmed',
        registeredByUid: OWNER, preselected: false, createdAt: serverTimestamp(),
      });
      batch.update(doc(db, 'orgs', ORG, 'competitions', COMP), { confirmedCount: increment(1) });
      return batch.commit();
    };
    await assertFails(entry([OWNER, P1, VICTIM]));
    await assertSucceeds(entry([OWNER, P1]));
  });
});

// ---------------------------------------------------------------------------
describe('memberships are the member\'s own', () => {
  it('refuses an admin writing an active membership for somebody else', async () => {
    await seed();
    await assertFails(setDoc(doc(as(OWNER), 'orgs', ORG, 'members', VICTIM),
      membership(VICTIM, ORG, 'member')));
    await assertFails(setDoc(doc(as(OWNER), 'orgs', ORG, 'members', VICTIM),
      membership(VICTIM, ORG, 'member', 'pending')));
  });

  it('lets a member leave, and refuses an owner leaving without stepping down', async () => {
    await seed();
    await assertSucceeds(deleteDoc(doc(as(MEMBER), 'orgs', ORG, 'members', MEMBER)));
    await assertFails(deleteDoc(doc(as(OWNER), 'orgs', ORG, 'members', OWNER)));
  });

  it('refuses a member removing somebody else', async () => {
    await seed();
    await assertFails(deleteDoc(doc(as(MEMBER), 'orgs', ORG, 'members', SCORER)));
  });
});

// ---------------------------------------------------------------------------
describe('an invited club enters its side', () => {
  const INV = `${ORG}_${SEASON}_${GUEST}`;

  const seedInvited = (status = 'accepted') => seed(async (db) => {
    await setDoc(doc(db, 'orgs', GUEST), org(GUEST_ADMIN));
    await setDoc(doc(db, 'orgs', GUEST, 'members', GUEST_ADMIN), membership(GUEST_ADMIN, GUEST, 'owner'));
    await setDoc(doc(db, 'tournamentInvites', INV), {
      fromOrgId: ORG, toOrgId: GUEST, tournamentId: SEASON, status,
      invitedBy: OWNER, createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, 'teams', 'gteam'), {
      name: 'Guest XI', sportId: 'badminton', type: 'permanent', status: 'active',
      clubId: GUEST, createdByUid: GUEST_ADMIN, captainUid: GUEST_ADMIN,
      memberUids: [GUEST_ADMIN, P1],
    });
  });

  const enter = () => {
    const db = as(GUEST_ADMIN);
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs', ORG, 'competitions', COMP, 'registrations', 'gteam'), {
      uid: 'gteam', teamId: 'gteam', memberUids: [GUEST_ADMIN, P1],
      status: 'confirmed', registeredByUid: GUEST_ADMIN, preselected: false,
      createdAt: serverTimestamp(),
    });
    batch.update(doc(db, 'orgs', ORG, 'competitions', COMP), {
      confirmedCount: increment(1), lastInvitedEntryOrgId: GUEST,
    });
    return batch.commit();
  };

  it('lets the accepted club\'s owner enter its team', async () => {
    await seedInvited('accepted');
    await assertSucceeds(enter());
  });

  it('refuses the entry while the invitation is unanswered', async () => {
    await seedInvited('pending');
    await assertFails(enter());
  });
});

// ---------------------------------------------------------------------------
describe('approving a group entry', () => {
  it('writes each accepted member\'s registration in the approval batch', async () => {
    await seed((db) => setDoc(doc(db, 'orgs', ORG, 'competitions', COMP, 'groupEntries', 'g1'), {
      leaderUid: P1, name: 'Group', status: 'pending_approval',
      memberUids: [P1, P2], acceptedUids: [P1, P2], declinedUids: [],
      createdAt: serverTimestamp(),
    }));
    const db = as(OWNER);
    const approve = (memberUid) => {
      const batch = writeBatch(db);
      batch.update(doc(db, 'orgs', ORG, 'competitions', COMP, 'groupEntries', 'g1'), {
        status: 'approved', decidedBy: OWNER,
      });
      batch.set(doc(db, 'orgs', ORG, 'competitions', COMP, 'registrations', memberUid), {
        uid: memberUid, status: 'confirmed', preselected: false, groupId: 'g1',
        createdAt: serverTimestamp(),
      });
      return batch.commit();
    };
    await assertFails(approve(VICTIM));
    await assertSucceeds(approve(P1));
  });
});

// ---------------------------------------------------------------------------
describe('an Arena move changes only what a move changes', () => {
  const seedGame = () => testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'arenaMatches', 'm1'), {
      players: [P1, P2], challengerUid: P1, gameId: 'chess', variantId: null,
      config: {}, status: 'active', turnUid: P1, moves: [],
      drawOfferBy: null, createdAt: new Date(), updatedAt: new Date(),
    });
  });
  const move = { ply: 0, uid: P1, side: 0, notation: 'e4', move: { key: 'e2e4' } };

  it('lets the player to move append a move and pass the turn', async () => {
    await seedGame();
    await assertSucceeds(updateDoc(doc(as(P1), 'arenaMatches', 'm1'), {
      moves: [move], turnUid: P2, lastMoveAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  it('refuses a move that puts the opponent\'s name on a draw offer', async () => {
    await seedGame();
    await assertFails(updateDoc(doc(as(P1), 'arenaMatches', 'm1'), {
      moves: [move], turnUid: P2, lastMoveAt: serverTimestamp(), drawOfferBy: P2,
    }));
  });

  it('refuses a move carrying a result while the game goes on, or any other field', async () => {
    await seedGame();
    await assertFails(updateDoc(doc(as(P1), 'arenaMatches', 'm1'), {
      moves: [move], turnUid: P2, lastMoveAt: serverTimestamp(),
      result: { winnerUid: P1 },
    }));
    await assertFails(updateDoc(doc(as(P1), 'arenaMatches', 'm1'), {
      moves: [move], turnUid: P2, lastMoveAt: serverTimestamp(), closedBy: 'timeout',
    }));
    await assertFails(updateDoc(doc(as(P1), 'arenaMatches', 'm1'), {
      moves: [move], turnUid: 'uid_stranger', lastMoveAt: serverTimestamp(),
    }));
  });
});

// ---------------------------------------------------------------------------
describe('auction lots', () => {
  it('refuses an organizer putting a sold player back in the pool', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'auctions', 'a1'), { status: 'revealed', visibility: 'unlisted', createdByUid: OWNER });
      await setDoc(doc(db, 'auctions', 'a1', 'participants', OWNER), {
        uid: OWNER, auctionId: 'a1', status: 'approved', roles: ['organizer'],
      });
      await setDoc(doc(db, 'auctions', 'a1', 'lots', P1), {
        playerUid: P1, auctionId: 'a1', status: 'sold', basePricePaise: 1000,
        bidCount: 2, soldToTeamId: P2, soldPricePaise: 5000,
      });
    });
    await assertFails(updateDoc(doc(as(OWNER), 'auctions', 'a1', 'lots', P1), { status: 'pool' }));
  });
});

describe('auction approvals', () => {
  const seedAuction = (lotExtra = {}) => testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'auctions', 'a2'), {
      status: 'registration', visibility: 'unlisted', createdByUid: OWNER,
      teamCount: 0, playerCount: 0, soldCount: 0,
    });
    await setDoc(doc(db, 'auctions', 'a2', 'participants', OWNER), {
      uid: OWNER, auctionId: 'a2', status: 'approved', roles: ['organizer'],
    });
    await setDoc(doc(db, 'auctions', 'a2', 'participants', P1), {
      uid: P1, auctionId: 'a2', status: 'pending', roles: ['bidder', 'player'],
    });
    if (Object.keys(lotExtra).length > 0) {
      await setDoc(doc(db, 'auctions', 'a2', 'lots', P2), {
        playerUid: P2, auctionId: 'a2', status: 'pool', basePricePaise: 1000,
        bidCount: 0, ...lotExtra,
      });
    }
  });

  it('approves a bidder-player, their side and their lot in one batch', async () => {
    await seedAuction();
    const db = as(OWNER);
    const batch = writeBatch(db);
    batch.update(doc(db, 'auctions', 'a2', 'participants', P1), { status: 'approved' });
    batch.set(doc(db, 'auctions', 'a2', 'teams', P1), {
      auctionId: 'a2', ownerUid: P1, name: 'P1 XI', pursePaise: 100000,
      committedPaise: 0, spentPaise: 0, wonCount: 0, liveBidCount: 0,
      createdAt: serverTimestamp(),
    });
    batch.set(doc(db, 'auctions', 'a2', 'lots', P1), {
      auctionId: 'a2', playerUid: P1, status: 'pool', basePricePaise: 1000,
      bidCount: 0, createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('refuses the organizer bumping the server-kept counts', async () => {
    await seedAuction();
    await assertFails(updateDoc(doc(as(OWNER), 'auctions', 'a2'), {
      teamCount: increment(1),
    }));
  });

  it('refuses taking a lot with sealed bids on it out of the pool', async () => {
    await seedAuction({ bidCount: 2 });
    await assertFails(updateDoc(doc(as(OWNER), 'auctions', 'a2', 'lots', P2), { status: 'withdrawn' }));
  });

  it('lets an unbid lot be withdrawn', async () => {
    await seedAuction({ bidCount: 0 });
    await assertSucceeds(updateDoc(doc(as(OWNER), 'auctions', 'a2', 'lots', P2), { status: 'withdrawn' }));
  });

  it('lets the player withdraw an unbid lot themselves', async () => {
    await seedAuction({ bidCount: 0 });
    await assertSucceeds(updateDoc(doc(as(P2), 'auctions', 'a2', 'lots', P2), { status: 'withdrawn' }));
  });
});

// ---------------------------------------------------------------------------
describe('an accepted multi-sport challenge', () => {
  it('may create its scheduled container, which a plain season may not', async () => {
    await seed((db) => setDoc(doc(db, 'orgs', GUEST), org(GUEST_ADMIN)));
    const container = (extra) => ({
      orgId: ORG, name: 'Guest v Review', status: 'scheduled', eventCount: 2,
      createdBy: OWNER, createdAt: serverTimestamp(), ...extra,
    });
    await assertFails(setDoc(doc(as(OWNER), 'orgs', ORG, 'tournaments', 't_plain'), container({})));
    await assertSucceeds(setDoc(doc(as(OWNER), 'orgs', ORG, 'tournaments', 't_chal'),
      container({ participantOrgIds: [GUEST, ORG] })));
  });
});
