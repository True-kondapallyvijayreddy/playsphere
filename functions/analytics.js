/**
 * The analytics warehouse: BigQuery in, Firestore rollups out.
 *
 * ## The shape of the whole thing
 *
 * ```
 * Firestore  ──(firestore-bigquery-export extensions)──▶  BigQuery
 *                                                            │
 *                                                    SQL views in bigquery/views
 *                                                            │
 *                                        this file, on a schedule ──▶ Firestore
 *                                                                        │
 *                                                                   the app reads
 * ```
 *
 * The last hop is the one that is easy to get wrong. **No client ever queries
 * BigQuery.** It cannot: there is no client-side auth story for it that does
 * not involve handing out a credential that can read the entire warehouse,
 * and the data in there is every private club's membership. So the warehouse
 * answers a question once, on a schedule, and the answer lands in Firestore
 * as a small document whose visibility `firestore.rules` already governs.
 *
 * ## Why the warehouse exists at all
 *
 * Two things Firestore genuinely cannot do:
 *
 * 1. **Aggregate across collections it will not let anyone read.** The gov
 *    dashboard's district rollup is three unbounded collection scans in one
 *    function invocation (`computeGovAggregatesByScan`). It works today and
 *    it is the first thing that stops working — not because the arithmetic is
 *    hard but because the read is.
 *
 * 2. **Remember.** A rating document holds one number and overwrites it. The
 *    bounded 24-entry `trail` is a deliberate, cheap approximation of history
 *    (see `onMatchSettled`); the changelog in BigQuery is the actual thing,
 *    unbounded, and is what makes "how did this district's U-17 cohort
 *    develop over two seasons" a question with an answer.
 *
 * ## Degrading honestly
 *
 * Every job here checks whether the warehouse is actually provisioned and
 * falls back to the Firestore path when it is not, logging which one ran. A
 * fresh project, an emulator run and a CI checkout all have no dataset, and
 * the dashboards must still work in all three — a feature that silently
 * produces nothing until someone runs a `bq mk` is a feature that will be
 * found broken in production.
 *
 * Setup, backfill and cost notes: `docs/ANALYTICS.md`.
 */

import { BigQuery } from '@google-cloud/bigquery';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

import { computeGovAggregatesByScan, writeGovAggregates } from './gov.js';

/** Must match `DATASET_ID` / `DATASET_LOCATION` in `extensions/*.env`. */
export const DATASET = 'playsphere_analytics';
const LOCATION = 'asia-south1';

let client = null;
function bq() {
  client ??= new BigQuery({ location: LOCATION });
  return client;
}

/**
 * Whether the warehouse is usable right now.
 *
 * Checks for the dataset *and* the specific view, because the two fail
 * separately and mean different things: no dataset means the extensions were
 * never installed, while a missing view means they were but
 * `bigquery/views/*.sql` was never applied. Both fall back; only the second
 * is a deployment mistake worth shouting about.
 */
async function warehouseReady(viewName) {
  try {
    const [datasetExists] = await bq().dataset(DATASET).exists();
    if (!datasetExists) {
      logger.info(`BigQuery dataset ${DATASET} not provisioned — using Firestore.`);
      return false;
    }
    const [viewExists] = await bq().dataset(DATASET).table(viewName).exists();
    if (!viewExists) {
      logger.warn(
        `BigQuery dataset ${DATASET} exists but view ${viewName} does not. ` +
          'Apply bigquery/views/*.sql — see docs/ANALYTICS.md. Falling back.',
      );
    }
    return viewExists;
  } catch (err) {
    // A permissions problem, a quota, a transient outage. The dashboard is
    // not the place to surface any of them: fall back and keep serving.
    logger.warn('BigQuery availability check failed; using Firestore.', err);
    return false;
  }
}

async function query(sql, params = {}) {
  const [rows] = await bq().query({ query: sql, params, location: LOCATION });
  return rows;
}

// ---------------------------------------------------------------------------
// Government participation rollup.
// ---------------------------------------------------------------------------

async function govAggregatesFromWarehouse() {
  const rows = await query(`
    SELECT state, district, club_count, member_count,
           competition_count, completed_match_count, sports_played
    FROM \`${DATASET}.participation_by_district\`
  `);
  return rows.map((r) => ({
    state: r.state ?? 'Unspecified',
    district: r.district ?? 'Unspecified',
    clubCount: Number(r.club_count) || 0,
    memberCount: Number(r.member_count) || 0,
    competitionCount: Number(r.competition_count) || 0,
    completedMatchCount: Number(r.completed_match_count) || 0,
    sportsPlayed: Number(r.sports_played) || 0,
  }));
}

async function runGovSync() {
  if (!(await warehouseReady('participation_by_district'))) {
    return computeGovAggregatesByScan();
  }
  const rows = await govAggregatesFromWarehouse();
  await writeGovAggregates(rows, 'bigquery');
  return { districtCount: rows.length, source: 'bigquery' };
}

/**
 * Nightly at 01:30 IST — an hour before `computeTalentBoards`, so the boards
 * are built against a warehouse that has already been refreshed rather than
 * against yesterday's.
 */
export const syncGovAggregates = onSchedule(
  {
    schedule: '30 1 * * *',
    timeZone: 'Asia/Kolkata',
    region: LOCATION,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const result = await runGovSync();
    logger.info(`syncGovAggregates: ${JSON.stringify(result)}`);
  },
);

// ---------------------------------------------------------------------------
// Talent trends, from the unbounded history.
// ---------------------------------------------------------------------------

/**
 * Every player's 90-day rating trend, computed in the warehouse.
 *
 * This is the query `functions/talent.js` uses in place of reading each
 * rating document's bounded trail. Same formula, same eligibility floor — see
 * `bigquery/views/04_player_rating_trend.sql`, which carries the reasoning —
 * but computed against the full history, so an active player's "90-day"
 * figure genuinely covers ninety days instead of however far 24 snapshots
 * happened to reach.
 *
 * Returns null when the warehouse is not ready, which is the signal for the
 * caller to use the trail instead.
 */
export async function playerTrendsFromWarehouse() {
  if (!(await warehouseReady('player_rating_trend_90d'))) return null;
  try {
    const rows = await query(`
      SELECT uid, sport_id, current_deviation, rating_delta,
             matches_in_window, truncated_span, provisional
      FROM \`${DATASET}.player_rating_trend_90d\`
      WHERE matches_in_window >= 3 AND rating_delta > 0
    `);
    return rows.map((r) => ({
      uid: r.uid,
      sportId: r.sport_id,
      deviation: Number(r.current_deviation) || 350,
      points: Number(r.rating_delta) || 0,
      matches: Number(r.matches_in_window) || 0,
      truncated: r.truncated_span === true,
      provisional: r.provisional === true,
    }));
  } catch (err) {
    logger.warn('Warehouse trend query failed; falling back to trails.', err);
    return null;
  }
}

/** Staff-only manual run, for after a backfill or a view change. */
export const runAnalyticsSync = onCall(
  { region: LOCATION, timeoutSeconds: 540, memory: '512MiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Analytics sync is restricted to PlaySphere platform staff.',
      );
    }
    return runGovSync();
  },
);
