/**
 * Reading a whole collection without holding a whole collection in memory.
 *
 * ## What was wrong
 *
 * Seven scheduled jobs ran unpaginated collection-group scans and kept the
 * entire result set alive at once:
 *
 *   * `clubs.js` read EVERY fixture ever played;
 *   * `leaderboard.js` read every `career_stats` document, HOURLY;
 *   * `overall_glicko.js` read all ratings and all career stats, together;
 *   * `talent.js`, `sports.js`, `gov.js` and `careerrebuild.js` did the same
 *     for their own domains.
 *
 * Every one was already configured at the ceiling — 1 GiB of memory, 540
 * seconds — so there was nothing left to raise. At 50,000 players and 500,000
 * fixtures the hourly leaderboard alone is around 3.6 million reads a day
 * before a single person opens the app, and the club-standings job hits the
 * memory wall first: a cricket fixture's `scoreState` carries batting and
 * bowling maps and a 42-ball timeline, so half a million of them is not a
 * working set that fits anywhere.
 *
 * The failure mode is the bad one. A scheduled function that runs out of
 * memory or time is a log line nobody reads, so rankings, leaderboards and
 * talent boards simply stop updating, and the first person to notice is a
 * player asking why their rating has not moved in a fortnight.
 *
 * ## What this does instead
 *
 * Cursor-paged reads, one page alive at a time, with the caller's accumulator
 * the only thing that grows. The accumulator is the point: these jobs aggregate
 * — a tally per club, a top-20 per board — so the useful state is small even
 * when the input is enormous. What was large was never the answer, only the
 * way it was read.
 *
 * Ordered by `__name__` (document id) rather than by a data field, for three
 * reasons: every document has one, it is unique so a cursor cannot skip or
 * repeat a row, and it needs no index — a collection-group query ordered by a
 * data field needs its own composite index, which is exactly the cost
 * `clubs.js` was avoiding by scanning unfiltered in the first place.
 *
 * ## Why not just stream
 *
 * `.stream()` exists and would also work. It holds one document at a time,
 * which is better, and it holds one gRPC stream open for the length of the
 * job, which is worse: a 540-second scan on a stream that drops in the middle
 * restarts from nothing, while a cursor restarts from the last page. For a job
 * that already lives close to its timeout, resumability is worth more than the
 * per-document saving.
 */

import { logger } from 'firebase-functions';

/**
 * Documents per page.
 *
 * Large enough that the round trips are not the cost, small enough that one
 * page of fat documents (a cricket `scoreState`) is nowhere near the heap.
 * 500 fixtures at a generous 20 KB each is 10 MB resident.
 */
export const PAGE_SIZE = 500;

/**
 * A safety stop, in pages.
 *
 * Not a limit on the data — 4,000 pages is two million documents — but on a
 * bug. A cursor that fails to advance loops forever and burns the whole
 * invocation budget on one collection; this turns that into a loud log line
 * and a job that still finishes.
 */
const MAX_PAGES = 4000;

/**
 * Calls `onDocument` for every document of `query`, one page at a time.
 *
 * `query` must be a Query, not a CollectionReference with filters already
 * consumed — the cursor is applied here with `orderBy(__name__)` and
 * `startAfter`, so the caller's own `where` clauses are preserved and the
 * ordering is this function's business.
 *
 * Returns how many documents were visited, which every caller logs: a job
 * whose scanned count suddenly halves has found an index problem, and a job
 * whose count grows past what a page-at-a-time scan can finish in 540 seconds
 * is the warning that the next split is due.
 */
export async function forEachPaged(query, onDocument, { label = 'scan' } = {}) {
  let cursor = null;
  let seen = 0;
  let pages = 0;

  for (;;) {
    let page = query.orderBy('__name__').limit(PAGE_SIZE);
    if (cursor) page = page.startAfter(cursor);

    const snap = await page.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      // Awaited rather than collected: the caller's callback is an aggregation
      // step, and letting these run concurrently across a page is how an
      // accumulator ends up interleaved.
      await onDocument(doc);
    }

    seen += snap.size;
    cursor = snap.docs[snap.docs.length - 1];
    pages += 1;

    // A short page means the collection is exhausted. Checked after the work
    // rather than before, so the last partial page is still processed.
    if (snap.size < PAGE_SIZE) break;

    if (pages >= MAX_PAGES) {
      logger.error(
        `${label}: stopped after ${MAX_PAGES} pages (${seen} documents). ` +
          'Either the cursor is not advancing, or this collection has ' +
          'outgrown a single-job scan and needs sharding.',
      );
      break;
    }
  }

  return seen;
}

/**
 * The same traversal, collecting into an array.
 *
 * For callers that genuinely need the whole set in memory — a rebuild that
 * recomputes a total from every row — where the win is resumability and a
 * bounded working set per page rather than a bounded total. Kept separate so
 * the choice to hold everything is visible at the call site rather than
 * hidden in a helper that sounds like it streams.
 */
export async function collectPaged(query, { label = 'scan' } = {}) {
  const out = [];
  await forEachPaged(query, (doc) => out.push(doc), { label });
  return out;
}
