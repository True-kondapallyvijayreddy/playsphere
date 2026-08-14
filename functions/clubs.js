/**
 * The club ladder — "Club Rankings" on the rankings screen.
 *
 * ## What a club result actually is
 *
 * A club ladder needs every club's results counted the same way, and until
 * now the honest answer was that they could not be: a ranking entry records
 * who *ran* a tournament, not which club each competitor came from, and
 * `Entrant.clubId` is read by the draw generator for association protection
 * but written by no current entry flow.
 *
 * There is exactly one shape in this database where a club is a competitor in
 * its own right, with an identity stable across every event it ever plays: an
 * inter-club fixture puts the two clubs' own org ids in `entrantAId` and
 * `entrantBId` (see `CommunityRepository.acceptChallenge`, and
 * `Fixture.sideForOrg` which relies on the same fact). That is what this
 * counts, and it is why the ladder is built from fixtures rather than from
 * `rankingEntries`.
 *
 * The consequence is worth stating plainly on the screen, and is: a club that
 * only runs internal events has no position here. That is correct rather than
 * unfortunate — it has not played anybody.
 *
 * ## Why a rollup rather than a query the client runs
 *
 * Same reason as `sports.js`: the scan crosses `orgs/*`, most of which are
 * private clubs a signed-in stranger cannot read under `firestore.rules`.
 * Counting from the client would give every visitor a different, silently
 * smaller ladder depending on which clubs they happen to belong to — which is
 * worse than no ladder, because it looks authoritative and is wrong. The
 * Admin SDK sees every club and publishes one public document per sport with
 * the visibility decision already made.
 *
 * ## Windows
 *
 * The rankings screen offers All time / 12 months / 3 months / 30 days, and a
 * stored total cannot forget, so each club row carries a tally per window
 * rather than one total the client tries to slice. Four small tallies is a
 * cheaper answer than either publishing every result or denying the control.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

/**
 * The windows the client offers, in days. `all` is unbounded.
 *
 * Mirrors `_Window` in `lib/features/rankings/rankings_screen.dart`. The two
 * must agree — a ladder offering a window the screen cannot select, or the
 * reverse, is a control that silently does nothing.
 */
export const WINDOWS = { all: null, d365: 365, d90: 90, d30: 30 };

/**
 * Three points for a win, one for a draw.
 *
 * The convention every league table in the world uses, and deliberately not
 * Glicko: a rating answers "how good is this club now" from a handful of
 * matches, and a ladder answers "what have they done this season". Clubs are
 * compared on the second.
 */
export const WIN_POINTS = 3;
export const DRAW_POINTS = 1;

function emptyTally() {
  return { played: 0, won: 0, drawn: 0, lost: 0, points: 0 };
}

function emptyRow(clubId) {
  const row = { clubId, name: '', logoUrl: null };
  for (const key of Object.keys(WINDOWS)) row[key] = emptyTally();
  return row;
}

/** Which windows a result dated [at] still counts inside. */
export function windowsFor(at, now) {
  const keys = ['all'];
  if (!(at instanceof Date) || Number.isNaN(at.getTime())) return keys;
  const ageDays = (now.getTime() - at.getTime()) / 86400000;
  // A result dated in the future is a clock problem, not a reason to drop it
  // from every bounded window — count it as current.
  for (const [key, days] of Object.entries(WINDOWS)) {
    if (days !== null && ageDays <= days) keys.push(key);
  }
  return keys;
}

/** Adds one result to every window it belongs in. */
function credit(row, windows, outcome) {
  for (const key of windows) {
    const tally = row[key];
    tally.played += 1;
    if (outcome === 'won') {
      tally.won += 1;
      tally.points += WIN_POINTS;
    } else if (outcome === 'drawn') {
      tally.drawn += 1;
      tally.points += DRAW_POINTS;
    } else {
      tally.lost += 1;
    }
  }
}

/**
 * The sport a fixture belongs to.
 *
 * Mirrors `Fixture.sport` — the stored id, falling back to the scoring plugin
 * for fixtures written before `sportId` existed. A fixture attributable to
 * neither is skipped rather than filed under a guess.
 */
function sportOf(fixture) {
  const id = fixture.sportId ?? fixture.scoringPluginKey;
  return typeof id === 'string' && id.length > 0 ? id : null;
}

function dateOf(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  return value instanceof Date ? value : null;
}

export async function computeClubStandingsByScan({ now = new Date() } = {}) {
  // sportId -> clubId -> row
  const bySport = new Map();
  const liveOrgs = new Map(); // orgId -> { name, logoUrl }

  // ---- Pass 1: which clubs are still live, and what they are called. ----
  const orgsSnap = await db().collection('orgs').get();
  for (const doc of orgsSnap.docs) {
    const org = doc.data();
    if (org.deletedAt) continue;
    liveOrgs.set(doc.id, {
      name: org.name ?? 'Club',
      logoUrl: org.logoUrl ?? null,
    });
  }

  function rowFor(sportId, clubId) {
    let clubs = bySport.get(sportId);
    if (!clubs) {
      clubs = new Map();
      bySport.set(sportId, clubs);
    }
    let row = clubs.get(clubId);
    if (!row) {
      row = emptyRow(clubId);
      const org = liveOrgs.get(clubId);
      row.name = org?.name ?? 'Club';
      row.logoUrl = org?.logoUrl ?? null;
      clubs.set(clubId, row);
    }
    return row;
  }

  // ---- Pass 2: every decided inter-club fixture. ----
  //
  // An unfiltered collection-group scan, the same ceiling `sports.js` and
  // `gov.js` document and the reason this runs nightly rather than on write.
  // Filtering server-side on `status` would need its own collection-group
  // index for one nightly job; filtering here costs reads and no schema.
  let scanned = 0;
  let counted = 0;
  const fixturesSnap = await db().collectionGroup('fixtures').get();
  for (const doc of fixturesSnap.docs) {
    scanned += 1;
    const f = doc.data();

    // Walkovers count here, and deliberately NOT on the tournament
    // leaderboard, which drops them because "turning up is not a good
    // tournament". The two boards answer different questions: that one is
    // evidence a player played well, this one is a league table, and every
    // league in the world awards a forfeit as a win with full points. A club
    // that failed to field a side lost the fixture.
    if (f.status !== 'completed' && f.status !== 'walkover') continue;
    // The marker of an inter-club match. Without it the entrant ids are
    // players or club teams rather than clubs, and nothing here applies.
    if (!Array.isArray(f.participantOrgIds) || f.participantOrgIds.length < 2) {
      continue;
    }

    const a = f.entrantAId;
    const b = f.entrantBId;
    if (!a || !b || a === b) continue;
    // Both sides must still be clubs that exist. A club that leaves the
    // platform must stop appearing in the ladder it left, and must not leave
    // its opponents' wins pointing at nothing either.
    if (!liveOrgs.has(a) || !liveOrgs.has(b)) continue;

    const sportId = sportOf(f);
    if (!sportId) continue;

    const at = dateOf(f.completedAt) ?? dateOf(f.scheduledAt);
    const windows = windowsFor(at, now);

    const isDraw = f.isDraw === true;
    const winner = f.winnerEntrantId;
    // Compared explicitly rather than by absence: a fixture that recorded
    // neither a winner nor a draw is an unfinished result, not a shared point.
    if (!isDraw && winner !== a && winner !== b) continue;

    const rowA = rowFor(sportId, a);
    const rowB = rowFor(sportId, b);
    if (isDraw) {
      credit(rowA, windows, 'drawn');
      credit(rowB, windows, 'drawn');
    } else {
      credit(rowA, windows, winner === a ? 'won' : 'lost');
      credit(rowB, windows, winner === b ? 'won' : 'lost');
    }
    counted += 1;
  }

  await writeClubStandings(bySport);
  return { scanned, counted, sportCount: bySport.size };
}

/**
 * Ranks one sport's clubs. Highest points first.
 *
 * Ordered on the all-time tally, because a document holds one order and the
 * client re-sorts for whichever window it is showing. Ties break on wins and
 * then on name, so the list is stable between two reads of the same data.
 */
export function rankRows(rows) {
  return [...rows].sort((x, y) => {
    const byPoints = y.all.points - x.all.points;
    if (byPoints !== 0) return byPoints;
    const byWins = y.all.won - x.all.won;
    if (byWins !== 0) return byWins;
    return x.name.localeCompare(y.name);
  });
}

/** Publishes one document per sport at `clubStandings/{sportId}`. */
export async function writeClubStandings(bySport) {
  const batch = db().batch();
  for (const [sportId, clubs] of bySport) {
    batch.set(db().collection('clubStandings').doc(sportId), {
      sportId,
      // Capped: a ladder is a top-N board and nobody scrolls to club four
      // hundred. The cap is also what keeps one document under Firestore's
      // 1 MiB limit as the platform grows.
      clubs: rankRows([...clubs.values()]).slice(0, 200),
      computedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  logger.info(`clubStandings: wrote ${bySport.size} sport rows`);
}

/**
 * Nightly at 03:45 IST — after `computeSportStats` at 03:15, so the two heavy
 * collection-group scans do not contend for the same instances.
 */
export const computeClubStandings = onSchedule(
  {
    schedule: '45 3 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async () => {
    const result = await computeClubStandingsByScan();
    logger.info('clubStandings nightly complete', result);
  },
);

/** Staff-only manual rebuild, for after a backfill or a rules change. */
export const rebuildClubStandings = onCall(
  { region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Rebuilding club standings is restricted to PlaySphere staff.',
      );
    }
    return computeClubStandingsByScan();
  },
);
