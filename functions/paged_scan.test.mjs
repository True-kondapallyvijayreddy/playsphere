/**
 * Tests for the cursor pager, and the guard that keeps the scans paged.
 *
 * The last test is the one that matters over time. Seven scheduled jobs read
 * whole collection groups into a single 1 GiB instance, every one of them
 * already configured at the memory and timeout ceiling, so there was nothing
 * left to raise when they stopped fitting. Paging them all is a one-off fix;
 * the guard is what stops the eighth arriving.
 */

import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

import { PAGE_SIZE, collectPaged, forEachPaged } from './paged_scan.js';

/**
 * A Query stand-in that serves `docs` in pages, the way Firestore does.
 *
 * Records the cursors it was asked for so a test can assert the traversal
 * actually paged rather than happening to fit in one page.
 */
function fakeQuery(docs, { calls = [] } = {}) {
  const make = (ordered, limit, after) => ({
    orderBy: () => make(true, limit, after),
    limit: (n) => make(ordered, n, after),
    startAfter: (cursor) => make(ordered, limit, cursor),
    get: async () => {
      assert.ok(ordered, 'the pager must order by __name__ before limiting');
      calls.push(after?.id ?? null);
      const from = after ? docs.findIndex((d) => d.id === after.id) + 1 : 0;
      const slice = docs.slice(from, from + (limit ?? docs.length));
      return { docs: slice, size: slice.length, empty: slice.length === 0 };
    },
  });
  return make(false, null, null);
}

const docsOf = (n) =>
  Array.from({ length: n }, (_, i) => ({ id: `d${String(i).padStart(6, '0')}` }));

test('visits every document in one short page', async () => {
  const seen = [];
  const count = await forEachPaged(fakeQuery(docsOf(3)), (d) => seen.push(d.id));
  assert.equal(count, 3);
  assert.deepEqual(seen.length, 3);
});

test('an empty collection is not an error', async () => {
  const count = await forEachPaged(fakeQuery([]), () => {
    assert.fail('callback ran for an empty collection');
  });
  assert.equal(count, 0);
});

test('pages through a collection larger than one page', async () => {
  const calls = [];
  const total = PAGE_SIZE * 2 + 7;
  const seen = new Set();
  const count = await forEachPaged(
    fakeQuery(docsOf(total), { calls }),
    (d) => seen.add(d.id),
  );

  assert.equal(count, total, 'every document must be visited exactly once');
  assert.equal(seen.size, total, 'no document may be visited twice');
  // Three pages: two full, one short. The first asks for no cursor.
  assert.equal(calls.length, 3);
  assert.equal(calls[0], null);
  assert.notEqual(calls[1], null);
});

test('an exactly-full last page still terminates', async () => {
  // The boundary a `size < PAGE_SIZE` break gets wrong if it is checked before
  // the work rather than after: the final full page has to be processed, and
  // then the NEXT read comes back empty and ends the loop.
  const calls = [];
  const count = await forEachPaged(
    fakeQuery(docsOf(PAGE_SIZE * 2), { calls }),
    () => {},
  );
  assert.equal(count, PAGE_SIZE * 2);
  assert.equal(calls.length, 3, 'two full pages, then an empty read');
});

test('the callback is awaited, so an accumulator cannot interleave', async () => {
  // Every caller is an aggregation step. Firing these concurrently across a
  // page is how a tally ends up with a lost update.
  const order = [];
  await forEachPaged(fakeQuery(docsOf(5)), async (d) => {
    order.push(`start:${d.id}`);
    await new Promise((r) => setTimeout(r, 1));
    order.push(`end:${d.id}`);
  });
  for (let i = 0; i < order.length; i += 2) {
    assert.ok(order[i].startsWith('start:'));
    assert.ok(order[i + 1].startsWith('end:'));
    assert.equal(order[i].slice(6), order[i + 1].slice(4));
  }
});

test('collectPaged returns the whole set', async () => {
  const out = await collectPaged(fakeQuery(docsOf(PAGE_SIZE + 3)));
  assert.equal(out.length, PAGE_SIZE + 3);
});

test('a cursor that will not advance is stopped and logged, not looped', async () => {
  // The bug case: a query whose cursor has no effect. Without the page cap
  // this burns the whole invocation on one collection and the job never
  // reaches anything else.
  const stuck = {
    orderBy: () => stuck,
    limit: () => stuck,
    startAfter: () => stuck,
    // Always a full page, always the same documents.
    get: async () => ({
      docs: docsOf(PAGE_SIZE),
      size: PAGE_SIZE,
      empty: false,
    }),
  };
  const count = await forEachPaged(stuck, () => {});
  // Bounded rather than infinite — the exact number is the cap, and the point
  // is that it returned at all.
  assert.ok(count > 0);
  assert.ok(Number.isFinite(count));
});

test('no functions module reads a whole collection group', async () => {
  // The structural guard. `collectionGroup(...).get()` with no cursor is the
  // shape that took seven jobs to the memory ceiling; paged_scan.js is the
  // only sanctioned way to walk one.
  const offenders = [];
  for (const file of readdirSync('.')) {
    if (!file.endsWith('.js') || file.endsWith('.test.mjs')) continue;
    if (file === 'paged_scan.js') continue;
    // Exempt, with the reason stated rather than the file quietly skipped.
    //
    // `subject_runner.js` walks the inventory in subject_data.js for ONE
    // person: their check-ins, their uploaded photos, their listings. The
    // result set is bounded by what a single account has ever done, which is
    // the one collection-group query in this codebase that genuinely cannot
    // grow with the platform. Paging it would add a cursor to a read of a
    // handful of documents and make an erasure harder to follow.
    if (file === 'subject_runner.js') continue;
    const src = readFileSync(file, 'utf8');
    // `.get()` applied to a collectionGroup query, allowing intervening
    // `.where()` clauses and line breaks.
    for (const m of src.matchAll(
      /collectionGroup\([^)]*\)((?:\s*\.where\([^)]*\))*)\s*\.get\(\)/g,
    )) {
      offenders.push(`${file}: ${m[0].replace(/\s+/g, ' ').slice(0, 70)}`);
    }
  }
  assert.deepEqual(
    offenders.sort(),
    [],
    'these read an entire collection group into memory. Use forEachPaged or ' +
      'collectPaged from paged_scan.js.',
  );
});
