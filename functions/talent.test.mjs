/**
 * The JavaScript half of the talent-discovery contract.
 *
 * `lib/domain/scout/talent_trend.dart` and `functions/talent.js` compute the
 * same rising score — one so the app can explain a row it is showing, one
 * because the ranking has to be built where a client cannot reach. The tables
 * below are the *same inputs and outputs* as the "cross-implementation
 * contract" group in `test/talent_trend_test.dart`. Change the formula on one
 * side only and one of the two suites goes red.
 *
 * Run: `node --test functions/talent.test.mjs`
 */

import assert from 'node:assert/strict';
import { test, describe } from 'node:test';

import {
  ageBandFor,
  audiencesFor,
  boardId,
  buildBoards,
  risingSignal,
  scopesFor,
  slug,
  teamFormSignal,
} from './talent.js';

const NOW = new Date('2026-08-09T00:00:00Z');
const daysAgo = (d) => new Date(NOW.getTime() - d * 86400000).toISOString();
const trail = (pairs) => pairs.map(([d, r]) => ({ r, t: daysAgo(d) }));

describe('risingSignal', () => {
  test('matches the Dart contract table', () => {
    const cases = [
      ['4 matches, +120', [[100, 1480], [60, 1520], [30, 1560], [5, 1600]], 60.0],
      ['3 matches, +60', [[100, 1500], [60, 1520], [30, 1540], [5, 1560]], 30.0],
      ['6 matches, +90', [
        [100, 1500], [70, 1515], [60, 1530],
        [40, 1545], [30, 1560], [20, 1575], [5, 1590],
      ], 60.0],
    ];
    for (const [label, raw, expected] of cases) {
      const s = risingSignal(trail(raw), 60, NOW);
      assert.ok(Math.abs(s.score - expected) < 1e-9, `${label}: got ${s.score}`);
    }
  });

  test('anchors on the last reading before the window', () => {
    const s = risingSignal(
      trail([[120, 1500], [80, 1540], [40, 1570], [10, 1600]]),
      60,
      NOW,
    );
    assert.equal(s.points, 100);
    assert.equal(s.matches, 3);
    assert.equal(s.truncated, false);
  });

  test('a trail starting inside the window is truncated and does not count '
    + 'its own baseline as a match', () => {
    const s = risingSignal(trail([[50, 1500], [20, 1560], [5, 1580]]), 60, NOW);
    assert.equal(s.truncated, true);
    assert.equal(s.points, 80);
    assert.equal(s.matches, 2);
  });

  test('two matches is below the floor however big the climb', () => {
    const s = risingSignal(trail([[100, 1400], [20, 1500], [5, 1600]]), 60, NOW);
    assert.equal(s.matches, 2);
    assert.equal(s.eligible, false);
  });

  test('a decline is never eligible', () => {
    const s = risingSignal(
      trail([[100, 1700], [60, 1650], [30, 1600], [5, 1550]]),
      60,
      NOW,
    );
    assert.ok(s.score < 0);
    assert.equal(s.eligible, false);
  });

  test('a high deviation is disclosed, not excluded', () => {
    const s = risingSignal(
      trail([[100, 1400], [50, 1450], [20, 1500], [5, 1540]]),
      200,
      NOW,
    );
    assert.equal(s.eligible, true);
    assert.equal(s.provisional, true);
  });

  test('malformed rows are dropped individually', () => {
    const s = risingSignal(
      [
        { r: 1500, t: daysAgo(100) },
        { r: 'nope', t: daysAgo(50) },
        'garbage',
        { r: 1600 },
        { r: 1520, t: daysAgo(40) },
        { r: 1540, t: daysAgo(20) },
        { r: 1560, t: daysAgo(5) },
      ],
      60,
      NOW,
    );
    assert.equal(s.points, 60);
    assert.equal(s.matches, 3);
  });

  test('an empty trail is not eligible rather than a zero-score row', () => {
    assert.equal(risingSignal([], 60, NOW).eligible, false);
    assert.equal(risingSignal(undefined, 60, NOW).eligible, false);
  });
});

describe('teamFormSignal', () => {
  test('matches the Dart contract table', () => {
    const improving = teamFormSignal({
      matchesInWindow: 8, winsInWindow: 6, lifetimeMatches: 40, lifetimeWins: 10,
    });
    assert.ok(Math.abs(improving.score - 0.8 * (0.75 + 0.5)) < 1e-9);

    const dominant = teamFormSignal({
      matchesInWindow: 12, winsInWindow: 10, lifetimeMatches: 32, lifetimeWins: 27,
    });
    const expected = (12 / 14) * (10 / 12 + (10 / 12 - 27 / 32));
    assert.ok(Math.abs(dominant.score - expected) < 1e-9);
  });

  test('a brand-new club gets no manufactured momentum', () => {
    const s = teamFormSignal({
      matchesInWindow: 5, winsInWindow: 4, lifetimeMatches: 5, lifetimeWins: 4,
    });
    assert.equal(s.momentum, 0);
    assert.ok(Math.abs(s.score - (5 / 7) * 0.8) < 1e-9);
  });

  test('two matches is below the floor', () => {
    assert.equal(
      teamFormSignal({
        matchesInWindow: 2, winsInWindow: 2, lifetimeMatches: 2, lifetimeWins: 2,
      }).eligible,
      false,
    );
  });
});

describe('slug and boardId', () => {
  test('mirror the Dart key format', () => {
    assert.equal(slug('Nalgonda'), 'nalgonda');
    assert.equal(slug('Rangareddy / Vikarabad'), 'rangareddy-vikarabad');
    assert.equal(slug('!!!'), '_any');
    assert.equal(slug(''), '_any');
    assert.equal(slug(null), '_any');
    assert.equal(
      boardId({
        sportId: 'kabaddi',
        state: 'telangana',
        district: 'nalgonda',
        ageGroup: 'u17',
        audience: 'scout',
      }),
      'kabaddi__telangana__nalgonda__u17__scout',
    );
  });
});

describe('ageBandFor', () => {
  test('places a birthday into the youngest band that admits it', () => {
    assert.equal(ageBandFor(new Date('2013-01-01Z'), NOW).name, 'u14');
    assert.equal(ageBandFor(new Date('2010-01-01Z'), NOW).name, 'u17');
    assert.equal(ageBandFor(new Date('1990-01-01Z'), NOW).name, 'senior');
  });

  test('a birthday not yet reached counts as the younger age', () => {
    // Turns 15 on 2026-12-01, so on 2026-08-09 they are still 14 → U-14.
    assert.equal(ageBandFor(new Date('2011-12-01Z'), NOW).name, 'u14');
  });
});

describe('audiencesFor — the minor-safety rule', () => {
  test('a public adult is on both boards', () => {
    assert.deepEqual(
      audiencesFor({ visibility: 'public', isMinor: false }),
      ['public', 'scout'],
    );
  });

  test('a public MINOR is on the scout board only, never the public one', () => {
    assert.deepEqual(
      audiencesFor({ visibility: 'public', isMinor: true }),
      ['scout'],
    );
  });

  test('anything short of public visibility is on no board at all', () => {
    for (const visibility of ['community', 'private', undefined, '']) {
      assert.deepEqual(audiencesFor({ visibility, isMinor: false }), []);
      assert.deepEqual(audiencesFor({ visibility, isMinor: true }), []);
    }
  });
});

describe('scopesFor', () => {
  test('a located player lands on district, state and national boards', () => {
    const scopes = scopesFor({
      state: 'telangana', district: 'nalgonda', ageBand: 'u17',
    });
    assert.equal(scopes.length, 6); // 3 geo × 2 age
    const ids = scopes.map((s) => `${s.state}/${s.district}/${s.ageGroup}`);
    assert.ok(ids.includes('_any/_any/_any'));
    assert.ok(ids.includes('telangana/_any/u17'));
    assert.ok(ids.includes('telangana/nalgonda/u17'));
  });

  test('a player with no geography is national-only', () => {
    const scopes = scopesFor({ state: '_any', district: '_any', ageBand: 'u14' });
    assert.equal(scopes.length, 2);
  });
});

describe('buildBoards', () => {
  const adult = {
    uid: 'adult', displayName: 'Ravi', visibility: 'public',
    dob: new Date('1996-01-01Z'), state: 'telangana', district: 'nalgonda',
    districtLabel: 'Nalgonda', sportId: 'kabaddi', deviation: 60,
    isMinor: false, photoUrl: null,
    trail: trail([[100, 1400], [60, 1440], [30, 1480], [5, 1520]]),
  };
  const minor = {
    ...adult, uid: 'minor', displayName: 'Asha',
    dob: new Date('2011-01-01Z'), isMinor: true,
    trail: trail([[100, 1400], [60, 1460], [30, 1520], [5, 1600]]),
  };
  const hidden = { ...adult, uid: 'hidden', visibility: 'community' };

  test('a minor never reaches a public board but does reach the scout one', () => {
    const docs = buildBoards({ players: [adult, minor, hidden], teams: [], now: NOW });
    const byId = new Map(docs.map((d) => [d.id, d.data]));

    const pub = byId.get('kabaddi__telangana__nalgonda___any__public');
    const scout = byId.get('kabaddi__telangana__nalgonda___any__scout');

    assert.deepEqual(pub.players.map((p) => p.uid), ['adult']);
    // Asha climbed further, so she is correctly ranked above Ravi — on the
    // gated board only.
    assert.deepEqual(scout.players.map((p) => p.uid), ['minor', 'adult']);
  });

  test('a community-visibility player appears on no board', () => {
    const docs = buildBoards({ players: [hidden], teams: [], now: NOW });
    assert.equal(docs.length, 0);
  });

  test('rows are ranked by score and numbered from 1', () => {
    const docs = buildBoards({ players: [adult, minor], teams: [], now: NOW });
    const scout = docs.find(
      (d) => d.id === 'kabaddi___any___any___any__scout',
    ).data;
    assert.equal(scout.players[0].rank, 1);
    assert.equal(scout.players[1].rank, 2);
    assert.ok(scout.players[0].score > scout.players[1].score);
    assert.equal(scout.playerPoolSize, 2);
  });

  test('an age-band board holds only that band', () => {
    const docs = buildBoards({ players: [adult, minor], teams: [], now: NOW });
    const byId = new Map(docs.map((d) => [d.id, d.data]));
    assert.deepEqual(
      byId.get('kabaddi___any___any__u17__scout').players.map((p) => p.uid),
      ['minor'],
    );
    assert.deepEqual(
      byId.get('kabaddi___any___any__senior__scout').players.map((p) => p.uid),
      ['adult'],
    );
  });

  test('warehouse trends override the trail when supplied', () => {
    // The trail says +120 over 3 matches; the warehouse says +300 over 10,
    // because it can see history the 24-entry trail cannot.
    const trends = new Map([
      ['adult__kabaddi', {
        points: 300, matches: 10, confidence: 10 / 13,
        score: 300 * (10 / 13), truncated: false, provisional: false,
        eligible: true,
      }],
    ]);
    const docs = buildBoards({ players: [adult], teams: [], now: NOW, trends });
    const row = docs.find((d) => d.id === 'kabaddi___any___any___any__public')
      .data.players[0];
    assert.equal(row.ratingDelta, 300);
    assert.equal(row.matchesInWindow, 10);
  });

  test('a player absent from the warehouse trends is not resurrected from '
    + 'their trail', () => {
    const docs = buildBoards({
      players: [adult], teams: [], now: NOW, trends: new Map(),
    });
    assert.equal(docs.length, 0);
  });

  test('teams land on both audiences and on the all-ages scope only', () => {
    const docs = buildBoards({
      players: [],
      now: NOW,
      teams: [{
        orgId: 'o1', orgName: 'Falcons', logoUrl: null,
        state: 'telangana', district: 'nalgonda', districtLabel: 'Nalgonda',
        sportId: 'cricket', matchesInWindow: 8, winsInWindow: 6,
        lifetimeMatches: 40, lifetimeWins: 10, tournamentWins: 2,
      }],
    });
    const ids = docs.map((d) => d.id);
    assert.ok(ids.includes('cricket__telangana__nalgonda___any__public'));
    assert.ok(ids.includes('cricket__telangana__nalgonda___any__scout'));
    assert.ok(!ids.some((id) => id.includes('__u17__')));

    const board = docs.find(
      (d) => d.id === 'cricket__telangana__nalgonda___any__public',
    ).data;
    assert.equal(board.teams[0].orgName, 'Falcons');
    assert.equal(board.teams[0].tournamentWins, 2);
    assert.equal(board.teams[0].rank, 1);
  });

  test('an ineligible team produces no board', () => {
    const docs = buildBoards({
      players: [],
      now: NOW,
      teams: [{
        orgId: 'o1', orgName: 'Two Games', state: '_any', district: '_any',
        sportId: 'cricket', matchesInWindow: 2, winsInWindow: 2,
        lifetimeMatches: 2, lifetimeWins: 2,
      }],
    });
    assert.equal(docs.length, 0);
  });
});
