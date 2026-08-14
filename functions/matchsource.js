/**
 * Backfills `sourceType` / `sourceId` onto matches created before those
 * fields existed — `docs/Heart_of_the_playsphere.md` §12.
 *
 * ## Why a backfill and not only a client-side fallback
 *
 * `Fixture.resolvedSource` already derives an origin for a fixture that has
 * none, so match history is never blank while this has not run. That fallback
 * is deliberately crude, though: it can only see `tournamentId`, so it calls
 * everything else a single match — including every challenge ever played,
 * which is exactly the distinction §20's history exists to draw.
 *
 * This does what the client cannot: it reads the competition each fixture
 * belongs to, and the challenge collection, and writes the real answer down.
 *
 * ## Idempotent by construction
 *
 * Only fixtures with no `sourceType` are touched. Running it twice is a
 * no-op, and a fixture whose source was recorded correctly at creation is
 * never second-guessed by a heuristic.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

/**
 * The source a competition's matches came from.
 *
 * Mirrors `Competition.matchSource` in `lib/core/models/competition.dart`.
 * The two must agree — a backfill that classified history differently from
 * how new matches are labelled would produce a match list where the same kind
 * of game reads two ways depending on when it was played.
 */
function sourceForCompetition(comp) {
  if (comp.tournamentId) {
    return { type: 'season', id: comp.tournamentId };
  }
  if (comp.format === 'league_table') {
    return { type: 'league', id: comp.id };
  }
  return { type: 'tournament', id: comp.id };
}

export async function backfillMatchSources({ dryRun = false } = {}) {
  // ---- Challenges first: their competition ids are the strongest signal. --
  //
  // An accepted challenge records the competition it created, so this is an
  // exact mapping rather than a guess — and a challenge match would otherwise
  // be indistinguishable from an ordinary one-off event.
  const challengeByCompId = new Map();
  const challengesSnap = await db().collection('challenges').get();
  for (const doc of challengesSnap.docs) {
    const compId = doc.data().createdCompId;
    if (compId) challengeByCompId.set(compId, doc.id);
  }

  // ---- Every competition, so a fixture can be classified from its parent. --
  const compById = new Map();
  const compsSnap = await db().collectionGroup('competitions').get();
  for (const doc of compsSnap.docs) {
    compById.set(doc.id, { id: doc.id, ...doc.data() });
  }

  let scanned = 0;
  let updated = 0;
  const counts = {};

  // Batched in chunks: a platform with tens of thousands of fixtures would
  // otherwise build one commit larger than Firestore accepts.
  let batch = db().batch();
  let pending = 0;

  const fixturesSnap = await db().collectionGroup('fixtures').get();
  for (const doc of fixturesSnap.docs) {
    scanned += 1;
    const fixture = doc.data();
    // Never overwrite. A fixture created after this shipped already knows
    // where it came from, and it knows better than any heuristic here.
    if (fixture.sourceType) continue;

    const compId = doc.ref.parent.parent?.id;
    if (!compId) continue;

    let source;
    if (challengeByCompId.has(compId)) {
      source = { type: 'challenge', id: challengeByCompId.get(compId) };
    } else {
      const comp = compById.get(compId);
      if (!comp) continue; // orphaned fixture; leave it to the client fallback
      // A competition holding exactly one fixture, with no tournament above
      // it, is a quick match — the shape `createQuickMatch` writes.
      source =
        !comp.tournamentId && comp.fixtureCount === 1
          ? { type: 'single_match', id: comp.id }
          : sourceForCompetition(comp);
    }

    counts[source.type] = (counts[source.type] ?? 0) + 1;
    updated += 1;

    if (!dryRun) {
      batch.update(doc.ref, {
        sourceType: source.type,
        sourceId: source.id,
        sourceBackfilledAt: FieldValue.serverTimestamp(),
      });
      pending += 1;
      if (pending >= 400) {
        await batch.commit();
        batch = db().batch();
        pending = 0;
      }
    }
  }

  if (!dryRun && pending > 0) await batch.commit();

  logger.info(
    `matchSource backfill: scanned ${scanned}, ${dryRun ? 'would update' : 'updated'} ${updated}`,
    counts,
  );
  return { scanned, updated, counts, dryRun };
}

/**
 * Staff-only, and offered with a dry run.
 *
 * This rewrites a field on every historical match in the database. Being able
 * to see what it *would* do, on real data, before it does it is worth the few
 * lines it costs.
 */
export const backfillMatchSource = onCall(
  { region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Backfilling match sources is restricted to PlaySphere staff.',
      );
    }
    return backfillMatchSources({ dryRun: request.data?.dryRun === true });
  },
);
