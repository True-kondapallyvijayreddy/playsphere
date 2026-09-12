/**
 * The Overall PlaySphere Glicko, denormalised onto the user document.
 *
 * ## Why the server computes a number the client can compute
 *
 * `lib/domain/rating/overall_glicko.dart` is the reference implementation, and
 * a profile screen runs it directly: that screen has already loaded every one
 * of the player's rating documents to draw the per-sport cards, so the
 * composite costs it nothing and is always exactly current.
 *
 * Every OTHER surface is the opposite case. A club roster, a team sheet, a
 * tournament entry list and a player card each render a name and a face from a
 * user document they already hold, and none of them has any reason to open a
 * ratings subcollection. Computing the composite there would mean one extra
 * collection read per row — a forty-player roster paying forty reads to put a
 * number next to forty names, on a screen people open constantly.
 *
 * So the composite is written onto `users/{uid}` as a small `glicko` map, and
 * those screens read it for free. `firestore.rules` freezes the field against
 * every client write (see `userUpdateInvariantsHold`), because a number that a
 * person could set on their own profile is not a rating, it is a claim.
 *
 * ## Why the formula is duplicated
 *
 * Same reasoning as `risingSignal()` in `talent.js`: the Dart copy exists so
 * the app can explain and re-derive the number it is showing without a round
 * trip, and this copy exists because the value has to be denormalised where no
 * client can compute it. `test/overall_glicko_test.dart` pins the outputs both
 * must produce — change one side without the other and it fails.
 *
 * ## When it runs
 *
 * Twice, for two different reasons.
 *
 * `onMatchSettled` calls `refreshOverallForUids` the moment it finishes
 * writing ratings, so a player who has just won walks off the pitch with their
 * headline number already moved. That path recomputes only the handful of
 * people who actually played.
 *
 * The nightly job re-runs everybody, because the composite decays even when
 * nobody plays: a sport untouched for six months is worth half what it was,
 * and a profile that only updated on match days would show a recency-weighted
 * number frozen at the last recency it happened to be computed with.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { CALLABLE_OPTS } from './app_check.js';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { forEachPaged } from './paged_scan.js';
import { logger } from 'firebase-functions';

import { DEFAULT_DEVIATION, DEFAULT_RATING } from './glicko2.js';

function db() {
  return getFirestore();
}

// ---------------------------------------------------------------------------
// Constants — every one mirrors a Dart constant on `OverallGlickoEngine`.
// See the file doc before changing any of them.
// ---------------------------------------------------------------------------

/** `OverallGlickoEngine.defaultHalfLifeDays`. */
const HALF_LIFE_DAYS = 180;

/** `OverallGlickoEngine.defaultRankDecay`. */
const RANK_DECAY = 0.45;

/** `OverallGlickoEngine.defaultEvidenceScale`. */
const EVIDENCE_SCALE = 8;

/** `OverallGlicko.provisionalEvidence`. */
const PROVISIONAL_EVIDENCE = 0.85;

/**
 * How many per-sport ratings ride along in the denormalised map.
 *
 * The map exists to let a player card show "🏏 1842 · 🏸 1618 · ⚽ 1497"
 * without opening a subcollection, and three is what fits beside a name on a
 * phone. It is a display convenience and explicitly not the record: the
 * authoritative per-sport ratings are the rating documents, which the profile
 * reads in full. Capping it also keeps an unbounded subcollection from growing
 * an unbounded field on a document that half the app loads.
 */
const DENORM_SPORTS = 3;

const MS_PER_DAY = 86400000;

// ---------------------------------------------------------------------------
// The formula. Pure — no Firestore — so it can be diffed against Dart and
// exercised directly.
// ---------------------------------------------------------------------------

/**
 * Mirrors `SportRatingEvidence.baseSportId`.
 *
 * Splits on the COLON only. Real sport ids contain underscores —
 * `table_tennis`, `kho_kho`, `athletics_sprint`, `athletics_field` — so
 * splitting on `_` too would truncate table tennis to `table` and merge sprint
 * and field athletics into one pool. `ratingKeyFor` only ever appends a time
 * control after a colon.
 */
export function baseSportId(ratingKey) {
  return String(ratingKey ?? '').split(':')[0];
}

/** Mirrors `OverallGlickoEngine.confidenceFor`. */
export function confidenceFor(deviation) {
  const d = typeof deviation === 'number' ? deviation : DEFAULT_DEVIATION;
  return Math.min(1, Math.max(0, 1 - d / DEFAULT_DEVIATION));
}

/** Mirrors `OverallGlickoEngine.recencyFor`. */
export function recencyFor(lastPlayedAt, asOf) {
  // Null is a data gap, not an absence — see the Dart doc on
  // `SportRatingEvidence.lastPlayedAt` for why this is the opposite of the
  // choice `CrossSportIndex` makes.
  if (!lastPlayedAt) return 1;
  const days = (asOf.getTime() - lastPlayedAt.getTime()) / MS_PER_DAY;
  if (days <= 0) return 1;
  return Math.pow(0.5, days / HALF_LIFE_DAYS);
}

/** Mirrors `OverallGlickoEngine._evidenceWeight`. */
export function evidenceWeight(effectiveMatches) {
  if (effectiveMatches <= 0) return 0;
  return 1 - Math.exp(-effectiveMatches / EVIDENCE_SCALE);
}

/**
 * Mirrors `OverallGlickoEngine.compute`.
 *
 * `entries` are `{ ratingKey, rating, deviation, gamesPlayed, lastPlayedAt }`.
 * Returns null when there is nothing to compute from — never 1500, for the
 * reason spelled out in the Dart doc: 1500 is a real position on this scale
 * and claiming it for somebody who has never played is a statement no result
 * supports.
 */
export function overallGlicko(entries, asOf = new Date()) {
  // Base sport -> the best-evidenced reading of it. Chess is rated per time
  // control and must still count as one sport.
  const bySport = new Map();
  for (const e of entries) {
    if (!(e.gamesPlayed > 0)) continue;
    const confidence = confidenceFor(e.deviation);
    const recency = recencyFor(e.lastPlayedAt, asOf);
    const key = baseSportId(e.ratingKey);
    const held = bySport.get(key);
    if (!held || confidence * recency > held.confidence * held.recency) {
      bySport.set(key, { ...e, sportId: key, confidence, recency });
    }
  }
  if (bySport.size === 0) return null;

  // Strength order, with the same tie-breaks as Dart so a rebuild cannot
  // reorder a breakdown the profile is already showing.
  const ranked = [...bySport.values()].sort((a, b) => {
    if (b.rating !== a.rating) return b.rating - a.rating;
    const ev = b.confidence * b.recency - a.confidence * a.recency;
    if (ev !== 0) return ev;
    return a.sportId < b.sportId ? -1 : a.sportId > b.sportId ? 1 : 0;
  });

  const components = [];
  let weightedSum = 0;
  let weightTotal = 0;
  let effectiveMatches = 0;

  ranked.forEach((r, i) => {
    const rankFactor = Math.pow(RANK_DECAY, i);
    const weight = r.confidence * r.recency * rankFactor;
    components.push({
      sportId: r.sportId,
      rating: r.rating,
      deviation: r.deviation,
      confidence: r.confidence,
      recency: r.recency,
      rankFactor,
      matches: r.gamesPlayed,
      weight,
    });
    weightedSum += r.rating * weight;
    weightTotal += weight;
    effectiveMatches += r.gamesPlayed * r.recency;
  });

  // Every sport carried zero weight: each is either maximally uncertain or
  // decayed to nothing. There is a record, but nothing in it worth blending.
  if (weightTotal <= 0) return null;

  const blend = weightedSum / weightTotal;
  const evidence = evidenceWeight(effectiveMatches);

  return {
    overall: DEFAULT_RATING + (blend - DEFAULT_RATING) * evidence,
    components,
    evidenceWeight: evidence,
    effectiveMatches,
    provisional: evidence < PROVISIONAL_EVIDENCE,
  };
}

/**
 * Maps an unbounded Glicko rating (e.g. 800 - 2400) to a clean 0-100 display score.
 *
 * Tiers:
 * < 1000: 1 - 35 (Novice)
 * 1000 - 1200: 36 - 49 (Beginner)
 * 1200 - 1400: 50 - 62 (Developing)
 * 1400 - 1600: 63 - 74 (Club; 1500 -> 69)
 * 1600 - 1800: 75 - 84 (Strong)
 * 1800 - 2000: 85 - 91 (District)
 * 2000 - 2200: 92 - 96 (State)
 * > 2200: 97 - 99 (Elite)
 */
export function glickoToScore(glicko) {
  if (typeof glicko !== 'number' || isNaN(glicko)) return 50;
  let score;
  if (glicko <= 1000) {
    score = Math.max(1, (glicko / 1000) * 35);
  } else if (glicko <= 1200) {
    score = 35 + ((glicko - 1000) / 200) * 15;
  } else if (glicko <= 1400) {
    score = 50 + ((glicko - 1200) / 200) * 13;
  } else if (glicko <= 1600) {
    score = 63 + ((glicko - 1400) / 200) * 12;
  } else if (glicko <= 1800) {
    score = 75 + ((glicko - 1600) / 200) * 10;
  } else if (glicko <= 2000) {
    score = 85 + ((glicko - 1800) / 200) * 7;
  } else if (glicko <= 2200) {
    score = 92 + ((glicko - 2000) / 200) * 5;
  } else {
    score = Math.min(99, 97 + ((glicko - 2200) / 300) * 2);
  }
  return Math.round(score);
}

/**
 * Calculates a player's user-facing 0-100 score, applying confidence & evidence
 * discounting for provisional ratings so unproven 1-match players cannot outrank
 * established veterans.
 */
export function toDisplayScore(rating, deviation = DEFAULT_DEVIATION, gamesPlayed = 0) {
  if (typeof rating !== 'number' || isNaN(rating)) return 50;
  if (!(gamesPlayed > 0)) return 50;

  const evidence = 1 - Math.exp(-gamesPlayed / 8);
  const conf = Math.min(1, Math.max(0, 1 - (deviation ?? DEFAULT_DEVIATION) / DEFAULT_DEVIATION));
  const trust = Math.min(evidence, conf);
  const effectiveGlicko = DEFAULT_RATING + (rating - DEFAULT_RATING) * trust;
  return glickoToScore(effectiveGlicko);
}

/** The shape written to `users/{uid}.glicko`. */
export function denormalise(result, computedAt) {
  const displayOverall = glickoToScore(result.overall);
  return {
    overall: displayOverall,
    overallGlicko: Math.round(result.overall),
    provisional: result.provisional,
    sports: Object.fromEntries(
      result.components
        .slice(0, DENORM_SPORTS)
        .map((c) => [c.sportId, toDisplayScore(c.rating, c.deviation, c.matches)]),
    ),
    sportsGlicko: Object.fromEntries(
      result.components
        .slice(0, DENORM_SPORTS)
        .map((c) => [c.sportId, Math.round(c.rating)]),
    ),
    sportCount: result.components.length,
    computedAt,
  };
}

// ---------------------------------------------------------------------------
// Firestore.
// ---------------------------------------------------------------------------

/**
 * Reads one player's rating documents and the career lines that date them.
 *
 * `lastPlayedAt` lives on the career record, and a rated walkover moves a
 * rating without writing one — so the rating document's own `updatedAt` is the
 * fallback, exactly as `CareerLine.ratingEvidence` does on the client. Without
 * it a sport played last week can look like a sport with no timestamp at all.
 */
async function evidenceFor(uid) {
  const [ratings, career] = await Promise.all([
    db().collection(`users/${uid}/ratings`).get(),
    db().collection(`users/${uid}/career_stats`).get(),
  ]);

  const lastPlayed = new Map();
  for (const doc of career.docs) {
    const raw = doc.data().lastPlayedAt;
    const at = raw?.toDate ? raw.toDate() : null;
    if (at) lastPlayed.set(doc.id, at);
  }

  return ratings.docs.map((doc) => {
    const d = doc.data();
    const updated = d.updatedAt?.toDate ? d.updatedAt.toDate() : null;
    return {
      ratingKey: doc.id,
      rating: typeof d.rating === 'number' ? d.rating : DEFAULT_RATING,
      deviation: typeof d.deviation === 'number' ? d.deviation : DEFAULT_DEVIATION,
      gamesPlayed: typeof d.gamesPlayed === 'number' ? d.gamesPlayed : 0,
      lastPlayedAt: lastPlayed.get(doc.id) ?? updated,
    };
  });
}

/**
 * Recomputes and writes the composite for a set of players.
 *
 * Merged onto the user document rather than written into a subcollection of
 * its own, so that every screen already holding an `AppUser` gets the number
 * with no additional read. That is the entire reason this function exists —
 * see the file doc.
 *
 * A player with no rated match has their `glicko` field REMOVED rather than
 * set to anything. A stale composite left behind after, say, a data repair
 * that cleared their ratings would keep asserting a standing the record no
 * longer supports.
 */
export async function refreshOverallForUids(uids, asOf = new Date()) {
  const unique = [...new Set(uids.filter(Boolean))];
  if (unique.length === 0) return { updated: 0, cleared: 0 };

  let updated = 0;
  let cleared = 0;
  const batch = db().batch();

  for (const uid of unique) {
    const result = overallGlicko(await evidenceFor(uid), asOf);
    if (result) {
      batch.set(
        db().doc(`users/${uid}`),
        { glicko: denormalise(result, asOf) },
        { merge: true },
      );
      updated += 1;
    } else {
      const snap = await db().doc(`users/${uid}`).get();
      if (snap.exists && snap.data().glicko !== undefined) {
        batch.set(db().doc(`users/${uid}`), { glicko: null }, { merge: true });
        cleared += 1;
      }
    }
  }

  await batch.commit();
  return { updated, cleared };
}

/**
 * The nightly pass over everybody.
 *
 * Scans the `ratings` collection group and joins it to `career_stats` in
 * memory, rather than the per-user reads `refreshOverallForUids` does — two
 * paged scans is two cursors where the per-user shape is thousands of reads.
 *
 * Both scans are paged and sequential; they used to be a `Promise.all` of two
 * unbounded reads, which held every rating and every career row in one
 * instance at the same time. See functions/paged_scan.js for why that stops
 * working long before the platform does.
 */
async function runOverallGlicko(asOf = new Date()) {
  // Both scans are PAGED and run one after the other rather than together.
  //
  // `Promise.all` of two unbounded collection-group reads held every rating
  // and every career row in one 1 GiB instance simultaneously, which is the
  // peak this job could possibly have. Sequential and paged, the resident set
  // is one page plus the two maps below — and those are the answer, so they
  // were always going to be held.
  //
  // The join still needs `lastPlayed` complete before the ratings pass, so
  // career_stats goes first. See functions/paged_scan.js.

  // `${uid}__${ratingKey}` -> last played
  const lastPlayed = new Map();
  await forEachPaged(
    db().collectionGroup('career_stats'),
    (doc) => {
      const uid = doc.ref.parent.parent?.id;
      if (!uid) return;
      const raw = doc.data().lastPlayedAt;
      const at = raw?.toDate ? raw.toDate() : null;
      if (at) lastPlayed.set(`${uid}__${doc.id}`, at);
    },
    { label: 'overallGlicko career_stats' },
  );

  /** uid -> entries */
  const byUid = new Map();
  await forEachPaged(
    db().collectionGroup('ratings'),
    (doc) => {
      const uid = doc.ref.parent.parent?.id;
      if (!uid) return;
      const d = doc.data();
      const updated = d.updatedAt?.toDate ? d.updatedAt.toDate() : null;
      const list = byUid.get(uid) ?? [];
      list.push({
        ratingKey: doc.id,
        rating: typeof d.rating === 'number' ? d.rating : DEFAULT_RATING,
        deviation: typeof d.deviation === 'number' ? d.deviation : DEFAULT_DEVIATION,
        gamesPlayed: typeof d.gamesPlayed === 'number' ? d.gamesPlayed : 0,
        lastPlayedAt: lastPlayed.get(`${uid}__${doc.id}`) ?? updated,
      });
      byUid.set(uid, list);
    },
    { label: 'overallGlicko ratings' },
  );

  let updated = 0;
  let skipped = 0;
  let batch = db().batch();
  let queued = 0;
  const flush = async () => {
    if (queued === 0) return;
    await batch.commit();
    batch = db().batch();
    queued = 0;
  };

  for (const [uid, entries] of byUid) {
    const result = overallGlicko(entries, asOf);
    if (!result) {
      skipped += 1;
      continue;
    }
    batch.set(
      db().doc(`users/${uid}`),
      { glicko: denormalise(result, asOf) },
      { merge: true },
    );
    updated += 1;
    queued += 1;
    if (queued >= 400) await flush();
  }
  await flush();

  logger.info(
    `computeOverallGlicko: ${byUid.size} rated players → ` +
      `${updated} composites written, ${skipped} without a rated match.`,
  );
  return { players: byUid.size, updated, skipped };
}

/**
 * Nightly at 03:00 IST — after `computeTalentBoards` at 02:30, so the two
 * heavy scans do not contend, and before anyone opens the app.
 */
export const computeOverallGlicko = onSchedule(
  {
    schedule: '0 3 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async () => {
    await runOverallGlicko();
  },
);

/** Staff-only manual rebuild, for after a formula change or a data fix. */
export const rebuildOverallGlicko = onCall({
    ...CALLABLE_OPTS, region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Rebuilding overall ratings is restricted to PlaySphere staff.',
      );
    }
    return runOverallGlicko();
  },
);
