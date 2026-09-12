/**
 * The server half of the contract in `test/overall_glicko_test.dart`.
 *
 * Every number asserted here is asserted there too, against the Dart engine.
 * That is the whole point: the two implementations exist for different reasons
 * (see the file doc on `overall_glicko.js`) and nothing but these two tables
 * stops them drifting apart. If you change a constant on one side, this file
 * and its Dart twin should both fail.
 */

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  baseSportId,
  confidenceFor,
  denormalise,
  evidenceWeight,
  overallGlicko,
  recencyFor,
} from './overall_glicko.js';

const NOW = new Date('2026-08-27T00:00:00Z');
const YESTERDAY = new Date('2026-08-26T00:00:00Z');

/** Mirrors the `established` helper in the Dart test. */
function established(ratingKey, rating, { matches = 40, deviation = 60 } = {}) {
  return {
    ratingKey,
    rating,
    deviation,
    gamesPlayed: matches,
    lastPlayedAt: YESTERDAY,
  };
}

test('four established sports blend to 1717 — the worked example', () => {
  const r = overallGlicko(
    [
      established('cricket', 1842),
      established('badminton', 1618),
      established('football', 1497),
      established('volleyball', 1325),
    ],
    NOW,
  );

  assert.equal(Math.round(r.overall), 1717);
  assert.equal(r.provisional, false);
  assert.deepEqual(
    r.components.map((c) => c.sportId),
    ['cricket', 'badminton', 'football', 'volleyball'],
  );
});

test('an established one-sport player keeps their own rating', () => {
  const r = overallGlicko([established('cricket', 1842)], NOW);
  assert.ok(Math.abs(r.overall - 1842) < 3, `got ${r.overall}`);
  assert.equal(r.provisional, false);
});

test('dabbling in a second sport costs far less than a mean would', () => {
  const one = overallGlicko([established('cricket', 1842)], NOW);
  const two = overallGlicko(
    [
      established('cricket', 1842),
      established('volleyball', 1325, { matches: 4, deviation: 180 }),
    ],
    NOW,
  );

  const mean = (1842 + 1325) / 2;
  assert.ok(two.overall > mean + 100, `got ${two.overall}`);
  assert.ok(one.overall - two.overall < 120);
  assert.equal(two.components[0].sportId, 'cricket');
});

test('two matches are shrunk hard toward 1500 and flagged', () => {
  const r = overallGlicko(
    [
      {
        ratingKey: 'cricket',
        rating: 1750,
        deviation: 290,
        gamesPlayed: 2,
        lastPlayedAt: NOW,
      },
    ],
    NOW,
  );

  assert.equal(r.provisional, true);
  assert.ok(r.overall < 1600 && r.overall > 1500, `got ${r.overall}`);
});

test('an unplayed sport does not vote, and no rated match is null', () => {
  const r = overallGlicko(
    [
      established('cricket', 1842),
      { ratingKey: 'football', rating: 1500, deviation: 350, gamesPlayed: 0 },
    ],
    NOW,
  );
  assert.equal(r.components.length, 1);
  assert.equal(r.components[0].sportId, 'cricket');

  assert.equal(overallGlicko([], NOW), null);
  assert.equal(
    overallGlicko(
      [{ ratingKey: 'cricket', rating: 1500, deviation: 350, gamesPlayed: 0 }],
      NOW,
    ),
    null,
  );
});

test('recency decays a sport nobody has played for a year', () => {
  const yearAgo = new Date(NOW.getTime() - 365 * 86400000);
  const r = overallGlicko(
    [
      {
        ratingKey: 'cricket',
        rating: 1842,
        deviation: 60,
        gamesPlayed: 40,
        lastPlayedAt: yearAgo,
      },
    ],
    NOW,
  );

  assert.ok(Math.abs(r.components[0].recency - 0.25) < 0.01);
  assert.ok(r.overall < 1842 && r.overall > 1500);
});

test('a missing timestamp is a data gap, not an absence', () => {
  const r = overallGlicko(
    [{ ratingKey: 'cricket', rating: 1842, deviation: 60, gamesPlayed: 40 }],
    NOW,
  );
  assert.equal(r.components[0].recency, 1);
});

test('chess time controls collapse to one sport', () => {
  assert.equal(baseSportId('chess:blitz'), 'chess');
  assert.equal(baseSportId('chess:classical'), 'chess');

  const r = overallGlicko(
    [established('chess:blitz', 1900), established('chess:classical', 1700)],
    NOW,
  );
  assert.equal(r.components.length, 1);
  assert.equal(r.components[0].sportId, 'chess');
});

test('an underscore in a real sport id is NOT a separator', () => {
  // `table_tennis`, `kho_kho`, `athletics_sprint` and `athletics_field` are
  // whole sport ids. Splitting on `_` would truncate table tennis to `table`
  // and merge the two athletics disciplines into one pool.
  assert.equal(baseSportId('table_tennis'), 'table_tennis');
  assert.equal(baseSportId('kho_kho'), 'kho_kho');
  assert.equal(baseSportId('athletics_sprint'), 'athletics_sprint');
  assert.equal(baseSportId('athletics_field'), 'athletics_field');

  const r = overallGlicko(
    [
      established('athletics_sprint', 1700),
      established('athletics_field', 1600),
    ],
    NOW,
  );
  assert.equal(r.components.length, 2);
});

test('order is stable for identical inputs', () => {
  const rows = () => [
    established('badminton', 1600),
    established('cricket', 1600),
    established('football', 1600),
  ];
  const a = overallGlicko(rows(), NOW);
  const b = overallGlicko(rows().reverse(), NOW);

  assert.deepEqual(
    a.components.map((c) => c.sportId),
    b.components.map((c) => c.sportId),
  );
  assert.ok(Math.abs(a.overall - b.overall) < 0.0001);
});

test('the constants themselves', () => {
  // Pinned individually so a failure names which one moved rather than only
  // reporting that a blended number came out wrong.
  assert.equal(confidenceFor(350), 0);
  assert.ok(Math.abs(confidenceFor(60) - 0.8285714) < 1e-6);
  assert.equal(confidenceFor(0), 1);
  assert.equal(recencyFor(null, NOW), 1);
  assert.ok(Math.abs(recencyFor(new Date(NOW.getTime() - 180 * 86400000), NOW) - 0.5) < 1e-9);
  assert.equal(evidenceWeight(0), 0);
  assert.ok(evidenceWeight(30) > 0.97);
});

test('the denormalised badge is small, rounded and honest about what it drops', () => {
  const r = overallGlicko(
    [
      established('cricket', 1842),
      established('badminton', 1618),
      established('football', 1497),
      established('volleyball', 1325),
    ],
    NOW,
  );
  const badge = denormalise(r, NOW);

  assert.equal(badge.overall, 1717);
  assert.equal(badge.provisional, false);
  // Three sports travel; the fourth is counted but not carried, so a card can
  // say "+1 more" instead of implying these are all of them.
  assert.deepEqual(badge.sports, {
    cricket: 1842,
    badminton: 1618,
    football: 1497,
  });
  assert.equal(badge.sportCount, 4);
  assert.equal(badge.computedAt, NOW);
});
