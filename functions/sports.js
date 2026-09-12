/**
 * Per-sport totals for the sports directory — "1,245 Tournaments · 8,456
 * Teams" under each row.
 *
 * ## Why a rollup rather than a query the client runs
 *
 * The directory lists fifteen sports on one screen. Counting from the client
 * means fifteen `count()` aggregation queries every time someone opens it,
 * and — more decisively — it means counting across `orgs/*`, most of which
 * are private clubs a signed-in stranger cannot read under
 * `firestore.rules`. Every visitor would get a different, silently smaller
 * number depending on which clubs they happened to belong to, which is worse
 * than no number at all: it looks authoritative and it is wrong.
 *
 * So the same shape `gov.js` uses applies here. The scan runs with the Admin
 * SDK, which sees every club, and publishes one public document per sport
 * that has already had the visibility decision made for it.
 *
 * ## What the numbers actually mean
 *
 * - `tournamentCount` — competitions in that sport. A "tournament" in the
 *   product's own vocabulary (`orgs/{id}/tournaments`) is a *container* for a
 *   multi-sport meet, so counting those would report a school sports week as
 *   one tournament for cricket rather than as the cricket event a club
 *   browsing for cricket is looking for. The competition is the sport-shaped
 *   thing, so that is what gets counted.
 * - `teamCount` / `playerCount` — entrants that started, split by entrant
 *   type. Both are kept for every sport rather than one per sport: badminton
 *   is individual by default but a club league runs it in teams, and a schema
 *   that assumes otherwise cannot represent that.
 *
 * Deleted clubs are excluded, and so is everything under them — a club that
 * leaves the platform must stop inflating the directory it left.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { CALLABLE_OPTS } from './app_check.js';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

/**
 * The rollup, computed by scanning Firestore.
 *
 * Exported so a backfill and the nightly job share one definition — the
 * failure mode where a manual rebuild and the schedule compute subtly
 * different numbers is the thing this product can least afford in a screen
 * whose entire purpose is comparing sports against each other.
 *
 * Three collection-group scans, same ceiling `computeGovAggregatesByScan`
 * documents. Fine at the current data size and the reason this runs nightly
 * rather than on write.
 */
export async function computeSportStatsByScan() {
  const rows = new Map(); // sportId -> row
  const liveOrgs = new Set(); // orgIds that still exist

  function rowFor(sportId) {
    const existing = rows.get(sportId);
    if (existing) return existing;
    const fresh = {
      sportId,
      tournamentCount: 0,
      teamCount: 0,
      playerCount: 0,
    };
    rows.set(sportId, fresh);
    return fresh;
  }

  // ---- Pass 1: which clubs are still live. ----
  const orgsSnap = await db().collection('orgs').get();
  for (const doc of orgsSnap.docs) {
    if (!doc.data().deletedAt) liveOrgs.add(doc.id);
  }

  // ---- Pass 2: competitions, one row per sport. ----
  // Also builds the compKey -> sportId map pass 3 needs, because an entrant
  // document does not carry its own sport — it inherits it from the
  // competition it sits under.
  const compSport = new Map();
  // Paged rather than read whole — see functions/paged_scan.js.
  await forEachPaged(
    db().collectionGroup('competitions'),
    (doc) => {
        const orgId = doc.ref.parent.parent?.id;
        if (!orgId || !liveOrgs.has(orgId)) return;
        const sportId = doc.data().sportId;
        if (!sportId) return; // predates the field; not attributable to a sport
        compSport.set(`${orgId}/${doc.id}`, sportId);
        rowFor(sportId).tournamentCount += 1;
    },
    { label: 'sportStats competitions' },
  );

  // ---- Pass 3: entrants, attributed through their competition. ----
  // Paged rather than read whole — see functions/paged_scan.js.
  await forEachPaged(
    db().collectionGroup('entrants'),
    (doc) => {
        const compRef = doc.ref.parent.parent;
        const orgId = compRef?.parent.parent?.id;
        if (!orgId || !compRef) return;
        const sportId = compSport.get(`${orgId}/${compRef.id}`);
        if (!sportId) return; // deleted club, or a competition with no sport

        const entrant = doc.data();
        // `withdrawn`, not a status enum — an entrant document is created only
        // once someone is a *starter* (see `Entrant`'s doc comment on why that is
        // separate from a registration), so the only way to stop counting is to
        // have pulled out afterwards.
        if (entrant.withdrawn === true) return;
        const row = rowFor(sportId);
        if (entrant.entrantType === 'team') row.teamCount += 1;
        else row.playerCount += 1;
    },
    { label: 'sportStats entrants' },
  );

  await writeSportStats([...rows.values()]);
  return { sportCount: rows.size };
}

/**
 * Publishes one document per sport at `sportStats/{sportId}`.
 *
 * `computedAt` is stamped so the directory can say how fresh the numbers are
 * — a count with no date on a screen that updates nightly invites the
 * assumption that it is live.
 */
export async function writeSportStats(rows) {
  const batch = db().batch();
  for (const row of rows) {
    batch.set(db().collection('sportStats').doc(row.sportId), {
      ...row,
      computedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  logger.info(`sportStats: wrote ${rows.length} sport rows`);
}

/**
 * Nightly at 03:15 IST — after `computeTalentBoards` at 02:30, so the two
 * heavy collection-group scans do not contend for the same instances.
 */
export const computeSportStats = onSchedule(
  {
    schedule: '15 3 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async () => {
    await computeSportStatsByScan();
  },
);

/** Staff-only manual rebuild, for a backfill or after a data fix. */
export const rebuildSportStats = onCall({
    ...CALLABLE_OPTS, region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Rebuilding sport statistics is restricted to PlaySphere staff.',
      );
    }
    return computeSportStatsByScan();
  },
);
