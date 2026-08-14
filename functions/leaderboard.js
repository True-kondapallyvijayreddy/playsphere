/**
 * App-wide, per-sport stat leaderboards — "who leads the league in runs",
 * the "Orange Cap" style ranking CricHeroes and every top tournament
 * (IPL, a World Cup, the FIFA scoring charts) show, and this product never
 * had: `career_stats` has always held a lifetime tally per player, but
 * nothing ever put one player's number next to everyone else's.
 *
 * ## Why this is precomputed, not a query the client runs
 *
 * Ranking every player in the country against each other means reading
 * every registered player's `career_stats`, most of whose profiles
 * `firestore.rules` does not let a stranger read directly. Same shape as
 * `sports.js`'s directory totals and `talent.js`'s discovery boards: the
 * scan runs once with the Admin SDK, which can see everything, and
 * publishes a small number of already-decided public documents.
 *
 * ## Why hourly, not on every match finalize
 *
 * `career_stats` updates live, by increment, on every settled fixture — see
 * `functions/index.js`'s `onMatchSettled`. Recomputing every leaderboard in
 * the country on every one of those writes would be the most expensive
 * thing this product does, for a board nobody needs to be second-fresh:
 * `docs/superpowers/specs/2026-08-09-stats-hub-design.md` reasoned through
 * the same trade-off first. This rebuilds the same *shape* that spec
 * described from the `career_stats.tally` field that already exists today,
 * not the separate collection its own Cloud Function would have written.
 *
 * ## Who can be ranked
 *
 * Same opt-in `talent.js` already established for discovery boards, applied
 * here for the same reason: `profileVisibility !== 'public'` or a minor,
 * and a player's number is never published next to their name. There is no
 * "scout" variant the way discovery boards have one — a stat leaderboard is
 * not a recruiting tool, so a minor is simply never ranked rather than
 * ranked somewhere gated.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

import { headlineStatsFor } from './headline_stats.js';
import { ageOnDate } from './talent.js';

function db() {
  return getFirestore();
}

const TOP_N = 50;
const COLLECTION = 'leaderboards';

/**
 * Every eligible player, joined from `users` and `career_stats` — the same
 * two-full-scan-then-join-in-memory shape `talent.js`'s
 * `loadPlayerCandidates` uses, for the same reason: one query per user does
 * not scale, and the current data size makes two full scans cheap.
 */
export async function loadLeaderboardCandidates() {
  const profiles = new Map();
  const usersSnap = await db().collection('users').get();
  const now = new Date();
  for (const doc of usersSnap.docs) {
    const u = doc.data();
    const dobRaw = u.dateOfBirth;
    const dob = dobRaw?.toDate ? dobRaw.toDate() : null;
    const isMinor = dob ? ageOnDate(dob, now) < 18 : true; // unknown age: treat as a minor, the safe default
    profiles.set(doc.id, {
      uid: doc.id,
      displayName: u.displayName || 'Player',
      photoUrl: u.photoUrl ?? null,
      eligible: (u.profileVisibility || 'community') === 'public' && !isMinor,
    });
  }

  const candidates = [];
  const statsSnap = await db().collectionGroup('career_stats').get();
  for (const doc of statsSnap.docs) {
    const c = doc.data();
    if (typeof c.uid !== 'string' || typeof c.sportId !== 'string') continue;
    const profile = profiles.get(c.uid);
    if (!profile || !profile.eligible) continue;
    candidates.push({
      uid: c.uid,
      displayName: profile.displayName,
      photoUrl: profile.photoUrl,
      sportId: c.sportId,
      tally: c.tally && typeof c.tally === 'object' ? c.tally : {},
    });
  }
  return candidates;
}

/**
 * Pure: candidates -> one document per (sportId, statKey), top [TOP_N] by
 * value, largest first.
 *
 * A candidate with no value for a key (never bowled, never played the sport
 * at all) contributes no row for it rather than a zero — a player who has
 * never bowled does not belong on a wickets leaderboard ahead of one who
 * has taken exactly one.
 */
export function buildLeaderboards(candidates) {
  const boards = new Map(); // "sportId:statKey" -> entries[]
  for (const c of candidates) {
    for (const key of headlineStatsFor(c.sportId)) {
      const value = c.tally[key];
      if (typeof value !== 'number' || !(value > 0)) continue;
      const boardKey = `${c.sportId}:${key}`;
      const list = boards.get(boardKey) ?? [];
      list.push({
        uid: c.uid,
        displayName: c.displayName,
        photoUrl: c.photoUrl,
        value,
      });
      boards.set(boardKey, list);
    }
  }

  const result = new Map();
  for (const [boardKey, list] of boards) {
    list.sort((a, b) => b.value - a.value);
    result.set(
      boardKey,
      list.slice(0, TOP_N).map((row, i) => ({ ...row, rank: i + 1 })),
    );
  }
  return result;
}

/**
 * Writes every current board, and deletes any board this run did not
 * produce — the same write-then-prune shape `talent.js`'s `publishBoards`
 * uses, so a sport that loses its last eligible player (or a headline-stat
 * key that gets renamed in a later release) does not leave a stale board
 * standing forever.
 */
async function publishLeaderboards(boards) {
  const keep = new Set(boards.keys());
  const collection = db().collection(COLLECTION);

  let batch = db().batch();
  let queued = 0;
  const flush = async () => {
    if (queued === 0) return;
    await batch.commit();
    batch = db().batch();
    queued = 0;
  };

  for (const [boardKey, entries] of boards) {
    const [sportId, statKey] = boardKey.split(':');
    batch.set(collection.doc(boardKey), {
      sportId,
      statKey,
      entries,
      updatedAt: FieldValue.serverTimestamp(),
    });
    queued += 1;
    if (queued >= 400) await flush();
  }

  const existing = await collection.select().get();
  let removed = 0;
  for (const doc of existing.docs) {
    if (keep.has(doc.id)) continue;
    batch.delete(doc.ref);
    removed += 1;
    queued += 1;
    if (queued >= 400) await flush();
  }
  await flush();
  return { written: boards.size, removed };
}

/** Exported for `run_leaderboard_rebuild.mjs` — see that script's own doc. */
export async function runLeaderboards() {
  const candidates = await loadLeaderboardCandidates();
  const boards = buildLeaderboards(candidates);
  const result = await publishLeaderboards(boards);
  logger.info(
    `rebuildLeaderboards: ${candidates.length} eligible candidate rows → ` +
      `${result.written} boards written, ${result.removed} stale removed.`,
  );
  return { candidateRows: candidates.length, ...result };
}

/** Hourly — see the file doc for why not on every match finalize. */
export const computeLeaderboards = onSchedule(
  {
    schedule: 'every 60 minutes',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    timeoutSeconds: 300,
    memory: '512MiB',
  },
  async () => {
    await runLeaderboards();
  },
);

/** Staff-only manual rebuild, for after a data fix or a new sport's launch. */
export const rebuildLeaderboards = onCall(
  { region: 'asia-south1', timeoutSeconds: 300, memory: '512MiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Rebuilding leaderboards is restricted to PlaySphere staff.',
      );
    }
    return runLeaderboards();
  },
);
