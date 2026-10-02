/**
 * The pure halves of the 2026-09-13 review fixes.
 *
 * Run: `node --test functions/review_fixes.test.mjs`
 */

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { decidedSides, slotUpdate } from './advancement.js';
import { lotOutcome } from './auctions.js';
import { proofFlags } from './grounds.js';
import { pendingTypes, summarize } from './notification_digest.js';
import { teamEntryVouchesFor } from './participant_trust.js';
import { computeRatingUpdates, reversedRating, MAX_SWING } from './rating_settlement.js';
import {
  settlementMayBeDue,
  trustedCareerRecord,
  trustedOfficialsRecord,
} from './settlement.js';

// ---------------------------------------------------------------------------
describe('auction lotOutcome — the money at the reveal', () => {
  const bid = (id, amountPaise, ms) => ({
    id, amountPaise, amountSetAt: { toMillis: () => ms }, teamName: id,
  });

  test('nobody bid: the lot is unsold', () => {
    assert.deepEqual(lotOutcome([]), { unsold: true });
  });

  test('the winner\'s commitment stays and becomes spend; losers are released', () => {
    const out = lotOutcome([bid('t1', 5000, 2), bid('t2', 7000, 3)]);
    assert.equal(out.winner.id, 't2');
    assert.equal(out.price, 7000);
    assert.deepEqual(out.teams.get('t2'), { committed: 0, spent: 7000, won: 1, liveBids: -1 });
    assert.deepEqual(out.teams.get('t1'), { committed: -5000, spent: 0, won: 0, liveBids: -1 });
  });

  test('a side that spent its whole purse stays committed to it for the next round', () => {
    // purse 10000; one live bid of 10000 won. committed 10000 -> 10000 (no
    // release), spent 0 -> 10000, so availablePaise = purse - committed = 0.
    const out = lotOutcome([bid('t1', 10000, 1)]);
    const committedAfter = 10000 + out.teams.get('t1').committed;
    assert.equal(10000 - committedAfter, 0);
  });

  test('ties go to the earlier commitment, then the team id', () => {
    assert.equal(lotOutcome([bid('b', 5000, 1), bid('a', 5000, 2)]).winner.id, 'b');
    assert.equal(lotOutcome([bid('b', 5000, 1), bid('a', 5000, 1)]).winner.id, 'a');
  });
});

// ---------------------------------------------------------------------------
describe('teamEntryVouchesFor', () => {
  const base = {
    entryId: 'team1',
    entry: { teamId: 'team1', memberUids: ['u1', 'victim'] },
    team: { clubId: 'club1', createdByUid: 'captain', memberUids: ['captain', 'u1', 'victim'] },
  };

  test('an active member of the team\'s club, on its roster, is vouched for', () => {
    assert.equal(teamEntryVouchesFor({ ...base, uid: 'u1', clubMemberStatus: 'active' }), true);
  });

  test('a name typed onto the entry but not the team roster is not', () => {
    assert.equal(teamEntryVouchesFor({
      ...base, uid: 'stranger', clubMemberStatus: 'active',
      entry: { teamId: 'team1', memberUids: ['stranger'] },
    }), false);
  });

  test('a roster name with no relationship of their own is not', () => {
    assert.equal(teamEntryVouchesFor({ ...base, uid: 'victim', clubMemberStatus: null }), false);
    assert.equal(teamEntryVouchesFor({ ...base, uid: 'victim', clubMemberStatus: 'pending' }), false);
  });

  test('the team\'s founder is vouched for without a club', () => {
    assert.equal(teamEntryVouchesFor({
      ...base,
      uid: 'captain',
      entry: { teamId: 'team1', memberUids: ['captain'] },
      team: { clubId: null, createdByUid: 'captain', memberUids: ['captain'] },
      clubMemberStatus: null,
    }), true);
  });

  test('an individual registration pretending to be a team entry is not', () => {
    assert.equal(teamEntryVouchesFor({
      ...base, uid: 'u1', clubMemberStatus: 'active', entryId: 'u1',
    }), false);
  });
});

// ---------------------------------------------------------------------------
describe('settlement', () => {
  const fixture = {
    status: 'live',
    sportId: 'cricket',
    lineupA: [{ id: 'p1', uid: 'p1' }],
    lineupB: [],
    entrantBUid: 'p2',
    officials: [{ uid: 'ump1' }],
  };

  test('a recorded career settlement only reaches players named on the match', () => {
    const recorded = [
      { uid: 'p1', sportId: 'cricket', outcome: 'won', tally: { runs: 40 } },
      { uid: 'victim', sportId: 'cricket', outcome: 'won', tally: { runs: 100000 } },
      { uid: 'p2', sportId: 'kabaddi', outcome: 'lost', tally: {} },
      { uid: 'p2', sportId: 'cricket', outcome: 'lost', tally: { runs: 'NaN' } },
    ];
    assert.deepEqual(
      trustedCareerRecord(recorded, fixture, null).map((c) => c.uid),
      ['p1'],
    );
  });

  test('a recorded officiating settlement only reaches officials named on the match', () => {
    assert.deepEqual(trustedOfficialsRecord(['ump1', 'victim'], fixture, null), ['ump1']);
  });

  test('settlement is due on a status change, not on a ball', () => {
    const live = { status: 'live', scoreState: { a: 1 } };
    assert.equal(settlementMayBeDue(live, { ...live, scoreState: { a: 2 } }), false);
    assert.equal(settlementMayBeDue(live, { status: 'completed' }), true);
    assert.equal(
      settlementMayBeDue(
        { status: 'completed', careerSettledAt: 1, officialsSettledAt: 1 },
        { status: 'completed', careerSettledAt: 1, officialsSettledAt: 1, summary: 'x' },
      ),
      false,
    );
    // A missed settlement is retried on the next write.
    assert.equal(
      settlementMayBeDue({ status: 'completed' }, { status: 'completed', summary: 'x' }),
      true,
    );
  });
});

// ---------------------------------------------------------------------------
describe('rating settlement', () => {
  const player = (rating, settled = []) => ({
    rating, deviation: 200, volatility: 0.06, gamesPlayed: 5, settled, trail: [],
  });

  test('moves both sides, capped, and records before and after', () => {
    const current = new Map([['a', player(1500)], ['b', player(1500)]]);
    const out = computeRatingUpdates({
      current, sideA: ['a'], sideB: ['b'], aWon: true, isDraw: false,
      weights: new Map(), fixtureId: 'f1', settledAt: new Date(0), trailLength: 24,
    });
    const a = out.find((u) => u.uid === 'a');
    const b = out.find((u) => u.uid === 'b');
    assert.ok(a.after.rating > 1500 && a.after.rating <= 1500 + MAX_SWING);
    assert.ok(b.after.rating < 1500);
    assert.equal(a.before.rating, 1500);
    assert.deepEqual(a.settledFixtures, ['f1']);
    assert.equal(a.trail[0].f, 'f1');
  });

  test('does not pay a player twice for one match', () => {
    const current = new Map([['a', player(1500, ['f1'])], ['b', player(1500)]]);
    const out = computeRatingUpdates({
      current, sideA: ['a'], sideB: ['b'], aWon: true, isDraw: false,
      weights: new Map(), fixtureId: 'f1', settledAt: new Date(0), trailLength: 24,
    });
    assert.deepEqual(out.map((u) => u.uid), ['b']);
  });

  test('reversing the latest settlement restores the rating exactly', () => {
    const record = {
      uid: 'a',
      before: { rating: 1500, deviation: 200, volatility: 0.06, gamesPlayed: 5 },
      after: { rating: 1520, deviation: 190, volatility: 0.06, gamesPlayed: 6 },
    };
    const doc = {
      rating: 1520, deviation: 190, volatility: 0.06, gamesPlayed: 6,
      settledFixtures: ['f0', 'f1'], trail: [{ r: 1500, f: 'f0' }, { r: 1520, f: 'f1' }],
    };
    const back = reversedRating(doc, record, 'f1');
    assert.equal(back.rating, 1500);
    assert.equal(back.gamesPlayed, 5);
    assert.deepEqual(back.settledFixtures, ['f0']);
    assert.deepEqual(back.trail, [{ r: 1500, f: 'f0' }]);
  });

  test('reversing an older settlement takes its delta back from where the rating now is', () => {
    const record = {
      uid: 'a',
      before: { rating: 1500, deviation: 200, volatility: 0.06, gamesPlayed: 5 },
      after: { rating: 1520, deviation: 190, volatility: 0.06, gamesPlayed: 6 },
    };
    const doc = {
      rating: 1540, deviation: 180, volatility: 0.06, gamesPlayed: 7,
      settledFixtures: ['f1', 'f2'], trail: [],
    };
    const back = reversedRating(doc, record, 'f1');
    assert.equal(back.rating, 1520);
    assert.equal(back.gamesPlayed, 6);
    assert.deepEqual(back.settledFixtures, ['f2']);
  });
});

// ---------------------------------------------------------------------------
describe('knockout advancement', () => {
  const source = {
    status: 'completed', isDraw: false, winnerEntrantId: 'e1',
    entrantAId: 'e1', entrantAName: 'Asha', entrantAUid: 'u1',
    entrantBId: 'e2', entrantBName: 'Bina', entrantBUid: 'u2',
  };
  const target = (overrides = {}) => ({
    status: 'scheduled', lastSeq: 0, entrantAId: '', entrantBId: 'e9',
    entrantBUid: 'u9', playerUids: ['u9'], ...overrides,
  });

  test('a decided match hands on its winner and its loser', () => {
    const sides = decidedSides(source);
    assert.equal(sides.winner.id, 'e1');
    assert.equal(sides.loser.id, 'e2');
    assert.equal(decidedSides({ ...source, isDraw: true }), null);
    assert.equal(decidedSides({ ...source, status: 'live' }), null);
  });

  test('fills an empty slot and adds the player to the fixture', () => {
    const update = slotUpdate({ target: target(), slot: 'a', entrant: decidedSides(source).winner, source });
    assert.equal(update.entrantAId, 'e1');
    assert.deepEqual(update.playerUids.sort(), ['u1', 'u9']);
  });

  test('re-points a slot the same match filled before, and drops the old player', () => {
    const update = slotUpdate({
      target: target({ entrantAId: 'e2', entrantAUid: 'u2', playerUids: ['u2', 'u9'] }),
      slot: 'a', entrant: decidedSides(source).winner, source,
    });
    assert.equal(update.entrantAId, 'e1');
    assert.deepEqual(update.playerUids.sort(), ['u1', 'u9']);
  });

  test('leaves a slot alone once the match has started, or another feeder filled it', () => {
    assert.equal(slotUpdate({ target: target({ lastSeq: 3 }), slot: 'a', entrant: decidedSides(source).winner, source }), null);
    assert.equal(slotUpdate({ target: target({ entrantAId: 'e7' }), slot: 'a', entrant: decidedSides(source).winner, source }), null);
  });
});

// ---------------------------------------------------------------------------
describe('ground proof flags', () => {
  const ground = { latitude: 17.4, longitude: 78.4 };

  test('flags a mocked fix and a pin far from where the photos were taken', () => {
    const flags = proofFlags(ground, [
      { latitude: 17.4, longitude: 78.4, isMocked: true },
      { latitude: 17.41, longitude: 78.4 },
    ]);
    assert.ok(flags.includes('mockedLocation'));
    assert.ok(flags.includes('pinFarFromCapture'));
  });

  test('says nothing about honest captures at the pin', () => {
    assert.deepEqual(proofFlags(ground, [{ latitude: 17.4, longitude: 78.4 }]), []);
  });
});

// ---------------------------------------------------------------------------
describe('digest types', () => {
  test('reads the nested map and the literal dotted fields the old writer left', () => {
    const types = pendingTypes({
      types: { challenge_received: 2 },
      'types.club_message': 3,
      pendingCount: 5,
    });
    assert.deepEqual(types, { challenge_received: 2, club_message: 3 });
    assert.equal(summarize(types), '2 challenges and 3 club messages');
  });
});
