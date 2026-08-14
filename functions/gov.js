/**
 * Government dashboard — a rollup an authorized official can actually open,
 * not just the domain logic to compute one.
 *
 * ## Why this is a coarser cube than `lib/domain/gov/gov_aggregate.dart`
 *
 * That file models the full Telangana Sports Policy cube: period × geo level
 * × sport × age group × gender × disability, with k-anonymity suppression
 * and a talent-pipeline funnel. Faithfully filling every cell needs
 * structured age/gender/disability data on every registration, which this
 * product does not yet collect consistently enough to report — building the
 * full cube against thin data would produce a dashboard confidently showing
 * numbers that are mostly "not reported".
 *
 * This computes what the data actually supports today, real and correct
 * rather than complete: clubs, members, competitions and completed matches,
 * rolled up by district. `GovAggregator`'s richer cube is the schema to grow
 * into once registration collects the fields it needs — this does not
 * compete with it, it is the honest subset available right now.
 *
 * ## Why a callable rather than a live query
 *
 * A district's numbers span every club in it, most of them private —
 * unreadable to anyone outside their own membership under `firestore.rules`.
 * There is no query a client could run that would even see this data, by
 * design. So the rollup runs with the Admin SDK, which sees everything, and
 * writes rows that have already had that visibility decision made for them —
 * a client reads a finished answer, never the raw material.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

function districtKeyOf(org) {
  // `geo.district` is the field to prefer — see `GeoLocation`'s doc comment
  // in geo.dart for why the legacy flat `district` string is kept in
  // parallel rather than migrated. Falls back to it for an org that predates
  // `geo`, and to "Unspecified" for one with neither, so every org lands
  // *somewhere* rather than silently dropping out of the count.
  const district =
    org.geo?.district || org.district || 'Unspecified';
  const state = org.geo?.state || 'Unspecified';
  return { state, district, key: `${state}__${district}` };
}

/**
 * The rollup, computed by scanning Firestore.
 *
 * Extracted from the callable so `analytics.js` can use it as the fallback
 * when the BigQuery warehouse is not provisioned. **This is the path with the
 * ceiling** — three unbounded collection scans in one invocation — and
 * `bigquery/views/03_participation_by_district.sql` is what replaces it. Kept
 * because it needs no warehouse, no dataset and no backfill, which is exactly
 * what a fresh project or an emulator run has.
 */
export async function computeGovAggregatesByScan() {
  const rows = new Map(); // key -> { state, district, clubCount, ... }
  const orgDistrict = new Map(); // orgId -> key

  // ---- Pass 1: every non-deleted org, grouped by district. ----
  const orgsSnap = await db().collection('orgs').get();
  for (const doc of orgsSnap.docs) {
    const org = doc.data();
    if (org.deletedAt) continue;
    const { state, district, key } = districtKeyOf(org);
    orgDistrict.set(doc.id, key);
    const row = rows.get(key) ?? {
      state,
      district,
      clubCount: 0,
      memberCount: 0,
      competitionCount: 0,
      completedMatchCount: 0,
    };
    row.clubCount += 1;
    row.memberCount += Number(org.memberCount) || 0;
    rows.set(key, row);
  }

  // ---- Pass 2: every competition, attributed to its org's district. ----
  const compsSnap = await db().collectionGroup('competitions').get();
  for (const doc of compsSnap.docs) {
    const orgId = doc.ref.parent.parent?.id;
    const key = orgId ? orgDistrict.get(orgId) : null;
    if (!key) continue; // org deleted, or predates this org's own row
    rows.get(key).competitionCount += 1;
  }

  // ---- Pass 3: completed fixtures, same attribution. ----
  // Bounded to what a `where` can push down — everything else about "did
  // this match count" (a walkover, a dispute) lives on the same field, so
  // one query answers "how many matches actually happened".
  const fixturesSnap = await db()
    .collectionGroup('fixtures')
    .where('status', '==', 'completed')
    .get();
  for (const doc of fixturesSnap.docs) {
    const orgId = doc.ref.parent.parent?.parent?.parent?.id;
    const key = orgId ? orgDistrict.get(orgId) : null;
    if (!key) continue;
    rows.get(key).completedMatchCount += 1;
  }

  await writeGovAggregates([...rows.values()], 'firestore-scan');
  return { districtCount: rows.size, source: 'firestore-scan' };
}

/**
 * Publishes district rows, whichever engine produced them.
 *
 * `source` is stamped on every row deliberately. The two engines can disagree
 * — the warehouse lags Firestore by however long the export stream takes, and
 * the scan is exact but expensive — so a number that looks wrong is only
 * debuggable if you can tell which one wrote it.
 */
export async function writeGovAggregates(rows, source) {
  const batch = db().batch();
  for (const row of rows) {
    const key = `${row.state}__${row.district}`;
    batch.set(db().collection('gov_aggregates').doc(key), {
      ...row,
      source,
      computedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  logger.info(`gov_aggregates: wrote ${rows.length} district rows via ${source}`);
}

export const computeGovAggregates = onCall(
  { region: 'asia-south1', timeoutSeconds: 300, memory: '512MiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'This dashboard is restricted to PlaySphere platform staff.',
      );
    }
    return computeGovAggregatesByScan();
  },
);
