/**
 * Rebuilds `users/{uid}/career_stats/{sportId}` from the matches themselves.
 *
 * ## The drift this closes
 *
 * `CareerAggregator` (lib/domain/career/career_stats.dart) opens with the
 * property the whole record rests on: a career statistic "can always be
 * recomputed from the matches, and any stored rollup can be checked against a
 * recomputation". Nothing had ever performed that recomputation, and the
 * stored rollup had drifted from it in three separate ways:
 *
 *  1. **No `tally` at all.** `onMatchSettled` wrote `matchesPlayed` and the
 *     win/draw/loss counts from the day settlement moved server-side, and did
 *     not write the sport-specific breakdown until much later. Every career
 *     stat document written before that was missing the one field the profile
 *     screens actually render — so a full cricket career showed as "3 matches"
 *     and "No totals recorded for cricket yet" underneath it. The fixtures had
 *     the runs and the wickets in `scoreState.players` the entire time.
 *
 *  2. **Phantom players.** An earlier settlement path treated the *entrant id*
 *     as a uid when a side had no line-up. Entrant ids are `side_a`, `side_b`
 *     or a registration document id, so it created career records under user
 *     documents that do not exist — which `ScoutRepository`'s collection-group
 *     sweep over `career_stats` then offers up as discoverable talent.
 *
 *  3. **Inflated appearances.** Before `ratingSettledAt` existed, a match that
 *     was reopened and re-finished was settled twice, and `matchesPlayed` was
 *     incremented twice with it. An increment cannot be un-done; only a
 *     recomputation can.
 *
 * ## Why absolute writes, and why pruning
 *
 * Every field here is computed from the fixtures and written whole, replacing
 * the document. Incrementing a repair on top of a wrong number leaves it
 * wrong. For the same reason a career document whose recomputation is empty —
 * the phantoms above — is deleted rather than left sitting at whatever it
 * drifted to: a rebuild that leaves records no match supports has not
 * rebuilt anything.
 *
 * ## Idempotent
 *
 * The answer is a function of the fixtures alone, so running it twice writes
 * the same values twice. Documents already equal to their recomputation are
 * not written at all, so a second run costs reads and nothing else.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

import { accumulateCareer, careerContributions } from './career.js';

function db() {
  return getFirestore();
}

/** The stored shape, from an accumulated record. */
function documentFor(record) {
  return {
    uid: record.uid,
    sportId: record.sportId,
    matchesPlayed: record.matchesPlayed,
    wins: record.wins,
    draws: record.draws,
    losses: record.losses,
    tally: record.tally,
    clubsPlayedFor: [...record.clubsPlayedFor].sort(),
    ...(record.lastPlayedAt ? { lastPlayedAt: record.lastPlayedAt } : {}),
    careerRebuiltAt: new Date(),
  };
}

/**
 * `JSON.stringify` with object keys sorted, at every depth.
 *
 * The tally is a map, and a map has no order: Firestore hands back whatever
 * order it stored, while `accumulateCareer` builds one in the order the
 * counters happened to be added. Comparing the two with a plain stringify made
 * every equal-but-differently-ordered tally look changed, which rewrote 17
 * correct records on every run and quietly cost this function the idempotency
 * promised above.
 *
 * `clubsPlayedFor` needs the same treatment for the same reason. It is a set
 * upstream (`accumulateCareer` builds it as one) and only becomes an array to
 * be stored, but the two writers disagree on order and always will: the
 * settlement trigger appends with `FieldValue.arrayUnion` in arrival order
 * (`index.js`), while `documentFor` sorts. Compared by position those two
 * never converge, so a trigger-written record is rewritten by every rebuild
 * for the rest of time. Sorted here, "same clubs" means what it says.
 */
function canonical(value) {
  const byKey = ([a], [b]) => (a < b ? -1 : a > b ? 1 : 0);
  return JSON.stringify(value ?? null, (_key, v) => {
    if (!v || typeof v !== 'object') return v;
    // Sorted copy: mutating the argument would reorder the record that is
    // about to be written, and `documentFor` already decided that order.
    if (Array.isArray(v)) return [...v].sort();
    return Object.fromEntries(Object.entries(v).sort(byKey));
  });
}

/** Whether a stored document already says what the recomputation says. */
function alreadyCorrect(stored, next) {
  if (!stored) return false;
  const same = (a, b) => canonical(a) === canonical(b);
  return (
    stored.matchesPlayed === next.matchesPlayed &&
    stored.wins === next.wins &&
    stored.draws === next.draws &&
    stored.losses === next.losses &&
    same(stored.tally, next.tally) &&
    same(stored.clubsPlayedFor, next.clubsPlayedFor)
  );
}

/**
 * @param {object} options
 * @param {boolean} [options.dryRun] Report what would change, write nothing.
 * @param {boolean} [options.prune] Delete career records no match supports.
 *   On by default — see the note above on phantom players.
 * @param {string} [options.uid] Restrict the rebuild to one player.
 */
export async function rebuildCareerStats({
  dryRun = false,
  prune = true,
  uid = null,
} = {}) {
  // Every match ever played, in one sweep. Unfiltered because
  // `collectionGroup('fixtures').where('status', ...)` needs a collection-group
  // index this project does not have, and the whole set has to be read to
  // recompute a total anyway — a partial read produces a partial career.
  const fixturesSnap = await db().collectionGroup('fixtures').get();

  const contributions = [];
  let counted = 0;
  for (const doc of fixturesSnap.docs) {
    // orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}
    const orgId = doc.ref.parent.parent?.parent.parent?.id ?? null;
    const some = careerContributions(doc.data(), { orgId });
    if (some.length > 0) counted += 1;
    for (const c of some) {
      if (uid && c.uid !== uid) continue;
      contributions.push(c);
    }
  }

  const records = accumulateCareer(contributions);

  const statsSnap = await db().collectionGroup('career_stats').get();
  const stored = new Map();
  for (const doc of statsSnap.docs) {
    // users/{uid}/career_stats/{sportId}
    const owner = doc.ref.parent.parent?.id;
    if (!owner) continue;
    if (uid && owner !== uid) continue;
    stored.set(`${owner}::${doc.id}`, doc);
  }

  let batch = db().batch();
  let pending = 0;
  const flush = async (force = false) => {
    if (pending >= 400 || (force && pending > 0)) {
      await batch.commit();
      batch = db().batch();
      pending = 0;
    }
  };

  let written = 0;
  let unchanged = 0;
  let created = 0;
  const pruned = [];

  for (const [key, record] of records) {
    const next = documentFor(record);
    const existing = stored.get(key);
    if (alreadyCorrect(existing?.data(), next)) {
      unchanged += 1;
      continue;
    }
    if (!existing) created += 1;
    written += 1;
    if (!dryRun) {
      const ref = existing
        ? existing.ref
        : db().doc(`users/${record.uid}/career_stats/${record.sportId}`);
      // Replaced whole rather than merged: a stale counter in `tally` that no
      // match supports has to disappear, and merge would keep it forever.
      batch.set(ref, next);
      pending += 1;
      await flush();
    }
  }

  for (const [key, doc] of stored) {
    if (records.has(key)) continue;
    pruned.push(doc.ref.path);
    if (prune && !dryRun) {
      batch.delete(doc.ref);
      pending += 1;
      await flush();
    }
  }

  if (!dryRun) await flush(true);

  const result = {
    fixturesScanned: fixturesSnap.size,
    fixturesCounted: counted,
    playersSports: records.size,
    written,
    created,
    unchanged,
    pruned: prune ? pruned.length : 0,
    prunable: pruned,
    dryRun,
  };
  logger.info(
    `career rebuild: ${counted}/${fixturesSnap.size} matches counted, ` +
      `${dryRun ? 'would write' : 'wrote'} ${written} of ${records.size} records, ` +
      `${prune ? 'pruned' : 'found'} ${pruned.length} unsupported`,
  );
  return result;
}

/**
 * Staff-only, and offered with a dry run.
 *
 * Absolute writes over every career record in the database is the most
 * consequential thing in this codebase; seeing the counts on real data before
 * committing to them costs one extra call.
 */
export const rebuildPlayerCareerStats = onCall(
  { region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Rebuilding career statistics is restricted to PlaySphere staff.',
      );
    }
    return rebuildCareerStats({
      dryRun: request.data?.dryRun === true,
      prune: request.data?.prune !== false,
      uid: typeof request.data?.uid === 'string' ? request.data.uid : null,
    });
  },
);
