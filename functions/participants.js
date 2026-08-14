/**
 * Backfills `entrantAUid` / `entrantBUid` and repairs `playerUids` on matches
 * played in individual events — badminton singles, chess, a tennis draw.
 *
 * ## The drift this closes
 *
 * An individual event names its competitors on the *entrant* document and
 * never fills a line-up. `Fixture.playerUids` was derived from the two
 * line-ups alone, so for those matches it was permanently empty — while
 * `onMatchSettled` settled them anyway, because it has always had an entrant
 * fallback (see `index.js`, `playerIdByUid`).
 *
 * The two halves of the product therefore disagreed about the same season: a
 * career total counted a chess match that the player's own match list, stat
 * breakdown and head-to-head could not see, because every one of those reads
 * `collectionGroup('fixtures').where('playerUids', arrayContains: uid)`.
 *
 * ## Why this has to run server-side
 *
 * `firestore.rules` freezes `playerUids` and the line-ups once a match is
 * `completed` — deliberately, because inventing who played after the fact is
 * the attack with no earlier value to contradict it. That freeze makes a
 * client-side repair impossible by design, so the fix belongs to the Admin
 * SDK, which is exactly the boundary the freeze assumes.
 *
 * ## Only individual entrants
 *
 * `Entrant.memberUids` is a squad, not a team sheet. Folding a club's
 * twenty-five names into `playerUids` would credit a match to fourteen people
 * who watched it, and because the settlement rules gate career-stat writes on
 * that same field it would hand a scorer the right to write results onto
 * their profiles. A team's line-up stays the only evidence a team's player
 * played. Mirrors `Entrant.soloUid` in
 * `lib/core/models/competition.dart` — the two must agree.
 *
 * ## Idempotent by construction
 *
 * Every write is computed from the entrant documents and the line-ups as they
 * stand, and compared against what the fixture already holds; a fixture that
 * is already correct is not written at all. Running it twice costs reads and
 * changes nothing.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

/**
 * The account behind an entrant when the entrant IS one person, else null.
 *
 * Mirrors `Entrant.soloUid`. Both `entrantType` and `uid` are checked for the
 * same reason the Dart side checks both: the wire value falls back to
 * `individual` when unrecognised, so the type alone is not proof, and a team
 * entrant carrying its captain's uid must not be mistaken for them.
 */
export function soloUidOf(entrant) {
  if (!entrant) return null;
  const type = entrant.entrantType ?? 'individual';
  if (type !== 'individual') return null;
  const uid = entrant.uid;
  return typeof uid === 'string' && uid.length > 0 ? uid : null;
}

/**
 * Everyone with an account who played, from both sources.
 *
 * The union, not a choice between them: a draw where one side is a club team
 * and the other a lone qualifier is a real shape, and taking a single source
 * would drop half of it.
 */
export function participantsOf(fixture, soloA, soloB) {
  const uids = new Set();
  for (const side of [fixture.lineupA, fixture.lineupB]) {
    if (!Array.isArray(side)) continue;
    for (const player of side) {
      if (player && typeof player.uid === 'string' && player.uid.length > 0) {
        uids.add(player.uid);
      }
    }
  }
  if (soloA) uids.add(soloA);
  if (soloB) uids.add(soloB);
  return [...uids];
}

/** True when `next` holds something `current` does not already have. */
function addsAnything(current, next) {
  const have = new Set(Array.isArray(current) ? current : []);
  return next.some((uid) => !have.has(uid));
}

export async function backfillParticipants({ dryRun = false } = {}) {
  let scanned = 0;
  let updated = 0;
  let entrantUidsWritten = 0;
  let playerUidsRepaired = 0;

  // Entrants are read per competition rather than as one collection-group
  // sweep, because a fixture has to be matched to the entrants of ITS OWN
  // competition — entrant ids are only unique within one draw, and a global
  // map keyed by entrant id would cheerfully resolve `entrant_1` from another
  // club's tournament onto this one's final.
  const soloUidByComp = new Map();

  async function soloUidsFor(compRef) {
    const key = compRef.path;
    if (soloUidByComp.has(key)) return soloUidByComp.get(key);
    const snap = await compRef.collection('entrants').get();
    const map = new Map();
    for (const doc of snap.docs) {
      const uid = soloUidOf(doc.data());
      if (uid) map.set(doc.id, uid);
    }
    soloUidByComp.set(key, map);
    return map;
  }

  let batch = db().batch();
  let pending = 0;

  const fixturesSnap = await db().collectionGroup('fixtures').get();
  for (const doc of fixturesSnap.docs) {
    scanned += 1;
    const fixture = doc.data();

    const compRef = doc.ref.parent.parent;
    if (!compRef) continue; // orphaned fixture, nothing to resolve against

    const byEntrant = await soloUidsFor(compRef);
    // A challenge names clubs and a quick match names sides, so neither has
    // entrant documents to find — `byEntrant` is empty and both of these stay
    // null, which is correct: those shapes carry real line-ups.
    const soloA = byEntrant.get(fixture.entrantAId) ?? null;
    const soloB = byEntrant.get(fixture.entrantBId) ?? null;

    const update = {};

    // Written even when null is already the answer ONLY if the field is
    // absent, so a re-run does not rewrite every fixture in the database to
    // the value it already holds.
    if (soloA !== (fixture.entrantAUid ?? null)) update.entrantAUid = soloA;
    if (soloB !== (fixture.entrantBUid ?? null)) update.entrantBUid = soloB;
    if (update.entrantAUid !== undefined || update.entrantBUid !== undefined) {
      entrantUidsWritten += 1;
    }

    // Additions only, and via arrayUnion rather than a computed list.
    //
    // A line-up that was edited and a player who was later removed are the
    // organizer's business; this function exists to add the people an
    // individual event never recorded, not to re-adjudicate who played a team
    // match years ago from whatever the roster says today.
    const participants = participantsOf(fixture, soloA, soloB);
    if (addsAnything(fixture.playerUids, participants)) {
      update.playerUids = FieldValue.arrayUnion(...participants);
      playerUidsRepaired += 1;
    }

    if (Object.keys(update).length === 0) continue;
    updated += 1;

    if (!dryRun) {
      update.participantsBackfilledAt = FieldValue.serverTimestamp();
      batch.update(doc.ref, update);
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
    `participants backfill: scanned ${scanned}, ` +
      `${dryRun ? 'would update' : 'updated'} ${updated} ` +
      `(${entrantUidsWritten} entrant uids, ${playerUidsRepaired} playerUids)`,
  );
  return {
    scanned,
    updated,
    entrantUidsWritten,
    playerUidsRepaired,
    dryRun,
  };
}

/**
 * Staff-only, and offered with a dry run.
 *
 * This touches every historical match in the database and writes the field the
 * settlement rules authorize against. Being able to see what it *would* do, on
 * real data, before it does it is worth the few lines it costs.
 */
export const backfillFixtureParticipants = onCall(
  { region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Backfilling match participants is restricted to PlaySphere staff.',
      );
    }
    return backfillParticipants({ dryRun: request.data?.dryRun === true });
  },
);
