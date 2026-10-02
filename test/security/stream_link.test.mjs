// Who may set a match's broadcast link — branch (h) of the fixture rules.
//
// The link is what every spectator of the match is sent to, so it belongs to
// the people running the match: organizers, this match's scorers and umpires,
// and the season's umpire panel. Not somebody watching, not an entrant, and
// not a member who holds the club-wide scorer rank but is not on this match.
// Mirrors `Fixture.canSetStreamBy`.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteField, doc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

let testEnv;
const ORG = 'org_stream';
const COMP = 'comp1';
const FIX = 'fix1';
const SEASON = 'season1';

const OWNER = 'uid_owner';
const EVENT_MANAGER = 'uid_event_manager';
const CLUB_SCORER = 'uid_club_scorer'; // judge_scorer rank, not on this match
const MEMBER = 'uid_member';
const OUTSIDER = 'uid_outsider';
const MATCH_SCORER = 'uid_match_scorer'; // in scorerUids, no club rank
const UMPIRE = 'uid_umpire'; // in officials, no club rank
const PANEL = 'uid_panel'; // on the season's officials roster only
const ENTRANT = 'uid_entrant'; // plays in the match

const LINK = 'https://youtu.be/dQw4w9WgXcQ';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'playsphere-test-stream',
    firestore: {
      rules: readFileSync(process.env.RULES_FILE ?? '../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
after(async () => { await testEnv?.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const membership = (uid, role) => ({
  uid, orgId: ORG, role, status: 'active', displayName: 'P', photoUrl: null,
  joinedAt: serverTimestamp(), invitedBy: null, approvedBy: null,
});

const fixture = (overrides = {}) => ({
  orgId: ORG, compId: COMP,
  entrantAId: 'a', entrantBId: 'b', entrantAName: 'Alice', entrantBName: 'Bob',
  entrantAUid: ENTRANT, entrantBUid: null,
  status: 'scheduled', round: 1, matchIndex: 0, roundLabel: 'Round 1',
  scheduledAt: null, venue: null,
  scorerUids: [MATCH_SCORER], activeScorerUid: null, activeScorerDeviceId: null,
  penGrantedByUid: null, penGrantedAt: null, lastRestartSeq: null,
  participantOrgIds: null,
  officials: [{ uid: UMPIRE, name: 'Ump', role: 'main_umpire', grantedScoringAccess: true }],
  scoreState: {}, summary: '', lastSeq: 0,
  winnerEntrantId: null, isDraw: false, rulesetVersion: 1,
  scoringPluginKey: 'badminton', sportId: 'badminton', scoringConfig: null,
  lineupA: [], lineupB: [], squadLockedA: false, squadLockedB: false,
  mvp: null, squadCallA: {}, squadCallB: {}, playerUids: [],
  tossWonByEntrantId: null, tossDecision: null,
  feedsWinnerToFixtureId: null, feedsWinnerToSlot: null,
  feedsLoserToFixtureId: null, feedsLoserToSlot: null,
  bracket: 'main', groupId: null, qualifierA: null, qualifierB: null,
  courtId: null, tournamentId: SEASON, resultType: 'normal', resultNote: null,
  isDraft: false, readiness: 'scheduled', resultState: 'none',
  sourceType: null, sourceId: null, createdAt: serverTimestamp(),
  ...overrides,
});

async function seed(fixtureOverrides) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'orgs', ORG), {
      name: 'Stream Club', nameLower: 'stream club', orgType: 'club',
      visibility: 'public', ownerUid: OWNER, inviteCode: 'STR234',
      memberCount: 4, requiresApprovalToJoin: true, createdBy: OWNER,
      createdAt: serverTimestamp(), deletedAt: null,
    });
    await setDoc(doc(db, 'orgs', ORG, 'members', OWNER), membership(OWNER, 'owner'));
    await setDoc(doc(db, 'orgs', ORG, 'members', EVENT_MANAGER), membership(EVENT_MANAGER, 'event_manager'));
    await setDoc(doc(db, 'orgs', ORG, 'members', CLUB_SCORER), membership(CLUB_SCORER, 'judge_scorer'));
    await setDoc(doc(db, 'orgs', ORG, 'members', MEMBER), membership(MEMBER, 'member'));
    await setDoc(doc(db, 'orgs', ORG, 'competitions', COMP), {
      orgId: ORG, name: 'Singles', sportId: 'badminton', status: 'in_progress',
      tournamentId: SEASON,
    });
    await setDoc(doc(db, 'orgs', ORG, 'tournaments', SEASON, 'officials', PANEL), {
      name: 'Panel Umpire', role: 'main_umpire', sports: [], addedBy: OWNER,
      addedAt: serverTimestamp(),
    });
    await setDoc(
      doc(db, 'orgs', ORG, 'competitions', COMP, 'fixtures', FIX),
      fixture(fixtureOverrides),
    );
  });
}

const fixRef = (uid) =>
  doc(testEnv.authenticatedContext(uid).firestore(),
    'orgs', ORG, 'competitions', COMP, 'fixtures', FIX);

describe('setting a stream link', () => {
  beforeEach(() => seed());

  for (const [who, uid] of [
    ['the club owner', OWNER],
    ['an event manager', EVENT_MANAGER],
    ['a scorer assigned to this match', MATCH_SCORER],
    ['an umpire assigned to this match', UMPIRE],
    ["a member of the season's umpire panel", PANEL],
  ]) {
    it(`is allowed for ${who}`, async () => {
      await assertSucceeds(updateDoc(fixRef(uid), { streamUrl: LINK }));
    });
  }

  for (const [who, uid] of [
    ['a plain club member watching', MEMBER],
    ['a signed-in outsider watching', OUTSIDER],
    ['a club scorer who is not on this match', CLUB_SCORER],
    ['an entrant playing in the match', ENTRANT],
  ]) {
    it(`is refused for ${who}`, async () => {
      await assertFails(updateDoc(fixRef(uid), { streamUrl: LINK }));
    });
  }

  it('is refused signed out', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(updateDoc(
      doc(db, 'orgs', ORG, 'competitions', COMP, 'fixtures', FIX),
      { streamUrl: LINK },
    ));
  });

  it('cannot carry any other field alongside it', async () => {
    await assertFails(updateDoc(fixRef(UMPIRE), { streamUrl: LINK, summary: '21-0' }));
  });

  it('refuses a value that is not a short string', async () => {
    await assertFails(updateDoc(fixRef(UMPIRE), { streamUrl: 'x'.repeat(501) }));
    await assertFails(updateDoc(fixRef(UMPIRE), { streamUrl: 42 }));
  });
});

describe('removing a stream link', () => {
  beforeEach(() => seed({ streamUrl: LINK }));

  it('is allowed for an assigned umpire', async () => {
    await assertSucceeds(updateDoc(fixRef(UMPIRE), { streamUrl: deleteField() }));
  });

  it('is refused for a member watching', async () => {
    await assertFails(updateDoc(fixRef(MEMBER), { streamUrl: deleteField() }));
  });
});

describe('a panel member of a match outside any season', () => {
  beforeEach(() => seed({ tournamentId: null }));

  it('has no say over its stream', async () => {
    await assertFails(updateDoc(fixRef(PANEL), { streamUrl: LINK }));
  });
});
