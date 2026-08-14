/**
 * Talent discovery — the scheduled job that builds the "Rising Talent" and
 * "Rising Teams" boards.
 *
 * ## Why this is a server job and not a query
 *
 * "The most improved U-17 kabaddi players in Nalgonda" is a ranking over
 * every rated player in a district. `firestore.rules` deliberately refuses to
 * let any client read across other people's profiles, so there is no query a
 * device could run to produce it — and there should not be. The scan happens
 * here, with the Admin SDK, and the client reads a finished, already-filtered
 * document. Same pattern, same reasoning, as `gov.js`.
 *
 * ## Why improvement and not rating
 *
 * A leaderboard sorted by rating finds the players everyone already knows.
 * §6 of the product vision asks for the opposite: the player nobody has
 * noticed, whose results are climbing. See the long-form rationale in
 * `lib/domain/scout/talent_trend.dart` — that file is the reference
 * implementation of the formula, and the numbers below must match it.
 *
 * ## The formula is duplicated, on purpose
 *
 * `RisingSignal` in Dart and `risingSignal()` here compute the same score.
 * The Dart copy exists so the app can explain and re-derive a row it is
 * showing; this copy exists because the ranking has to be built somewhere the
 * client cannot reach. `test/talent_trend_test.dart` pins the outputs:
 *
 * | trail (days ago → rating)                    | matches | delta | score |
 * |----------------------------------------------|---------|-------|-------|
 * | 100→1480, 60→1520, 30→1560, 5→1600           | 4       | +120  | 60.0  |
 * | 100→1500, 60→1520, 30→1540, 5→1560           | 3       |  +60  | 30.0  |
 * | 100→1500 then 6 readings to 1590             | 6       |  +90  | 60.0  |
 *
 * Change one side without the other and that test fails.
 *
 * ## Scale
 *
 * This scans `users`, the `ratings` collection group, `orgs` and completed
 * fixtures on every run. That is the right implementation for the data this
 * product has now and it has a real ceiling — see `docs/ANALYTICS.md` and
 * `analytics.js` for the BigQuery path that takes over when the scan stops
 * fitting in one invocation. The board *shape* does not change when that
 * happens; only where the candidate rows come from.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

import { playerTrendsFromWarehouse } from './analytics.js';

function db() {
  return getFirestore();
}

// ---------------------------------------------------------------------------
// Constants — every one of these mirrors a Dart constant. See the file doc.
// ---------------------------------------------------------------------------

/** `RisingSignal.window` — 90 days. */
export const WINDOW_DAYS = 90;

/** `RisingSignal.shrinkage`. */
const PLAYER_SHRINKAGE = 3;

/** `RisingSignal.minMatches`. */
const PLAYER_MIN_MATCHES = 3;

/** `RisingSignal.provisionalDeviation`. */
const PROVISIONAL_DEVIATION = 110;

/** `TeamFormSignal.shrinkage`. */
const TEAM_SHRINKAGE = 2;

/** `TeamFormSignal.minMatches`. */
const TEAM_MIN_MATCHES = 3;

/** `TalentBoard.maxEntries`. */
const MAX_ENTRIES = 50;

/** `kBoardAny`. */
const ANY = '_any';

/** `AgeGroup` — Khelo India bands, inclusive-upper, youngest match wins. */
const AGE_BANDS = [
  { name: 'u14', label: 'U-14', maxAge: 14 },
  { name: 'u17', label: 'U-17', maxAge: 17 },
  { name: 'u19', label: 'U-19', maxAge: 19 },
  { name: 'u21', label: 'U-21', maxAge: 21 },
  { name: 'senior', label: 'Senior', maxAge: null },
];

// ---------------------------------------------------------------------------
// Pure helpers — mirrors of the Dart domain, kept free of Firestore so the
// arithmetic can be reasoned about (and diffed against Dart) on its own.
// ---------------------------------------------------------------------------

/** Mirrors `TalentBoardKey.slug`. */
export function slug(raw) {
  const trimmed = (raw ?? '').toString().trim();
  if (!trimmed) return ANY;
  const cleaned = trimmed
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return cleaned || ANY;
}

/** Mirrors `TalentBoardKey.docId`. */
export function boardId({ sportId, state, district, ageGroup, audience }) {
  return [
    slug(sportId),
    state ?? ANY,
    district ?? ANY,
    ageGroup ?? ANY,
    audience,
  ].join('__');
}

/** Mirrors `ageOnDate` — whole years elapsed, birthday not yet reached counts
 *  as the younger age. */
export function ageOnDate(dob, on) {
  let age = on.getUTCFullYear() - dob.getUTCFullYear();
  const m = on.getUTCMonth() - dob.getUTCMonth();
  if (m < 0 || (m === 0 && on.getUTCDate() < dob.getUTCDate())) age -= 1;
  return age;
}

/** Mirrors `AgeGroup.fromDateOfBirth`. */
export function ageBandFor(dob, referenceDate) {
  const age = ageOnDate(dob, referenceDate);
  for (const band of AGE_BANDS) {
    if (band.maxAge === null || age <= band.maxAge) return band;
  }
  return AGE_BANDS[AGE_BANDS.length - 1];
}

/**
 * Mirrors `RatingTrail.deltaOver` + `RisingSignal.from`.
 *
 * The baseline is the last reading taken *before* the window opened, not the
 * first one inside it — anchoring inside would discard the gain from the
 * window's first match. See the Dart doc for the full argument.
 */
export function risingSignal(trail, deviation, now, windowDays = WINDOW_DAYS) {
  const snapshots = (Array.isArray(trail) ? trail : [])
    .map((e) => {
      const r = e?.r;
      const t = e?.t;
      if (typeof r !== 'number' || typeof t !== 'string') return null;
      const at = new Date(t);
      return Number.isNaN(at.getTime()) ? null : { r, at };
    })
    .filter(Boolean)
    .sort((a, b) => a.at - b.at);

  if (snapshots.length === 0) {
    return { eligible: false, score: 0, points: 0, matches: 0 };
  }

  const cutoff = new Date(now.getTime() - windowDays * 86400000);
  let baseline = null;
  for (const s of snapshots) {
    if (s.at > cutoff) break;
    baseline = s;
  }
  const truncated = baseline === null;
  const anchor = baseline ?? snapshots[0];
  const matches = snapshots.filter((s) => s.at > anchor.at).length;
  const points = snapshots[snapshots.length - 1].r - anchor.r;
  const confidence = matches / (matches + PLAYER_SHRINKAGE);

  return {
    points,
    matches,
    confidence,
    truncated,
    score: points * confidence,
    provisional: (deviation ?? 350) > PROVISIONAL_DEVIATION,
    eligible: matches >= PLAYER_MIN_MATCHES && points > 0,
  };
}

/** Mirrors `TeamFormSignal.from`. */
export function teamFormSignal({
  matchesInWindow,
  winsInWindow,
  lifetimeMatches,
  lifetimeWins,
}) {
  const recent = matchesInWindow === 0 ? 0 : winsInWindow / matchesInWindow;
  // Falls back to the recent rate, never to zero: a club with no history
  // outside the window would otherwise be handed a momentum of +1.0 built
  // entirely out of missing data.
  const lifetime =
    lifetimeMatches === 0 ? recent : lifetimeWins / lifetimeMatches;
  const confidence = matchesInWindow / (matchesInWindow + TEAM_SHRINKAGE);
  const momentum = recent - lifetime;
  return {
    matchesInWindow,
    winsInWindow,
    recentWinRate: recent,
    lifetimeWinRate: lifetime,
    momentum,
    confidence,
    score: confidence * (recent + momentum),
    eligible: matchesInWindow >= TEAM_MIN_MATCHES,
  };
}

/**
 * Which boards a player may be named on.
 *
 * ## The rule, and why it is this one
 *
 * Being listed on a discovery board is a statement about a person that they
 * did not make themselves, so it is opt-in: only `profileVisibility ==
 * 'public'` — the setting whose own label is "Public career page" — puts
 * anybody on any board. A member who left the default `community` setting
 * alone has not asked to be discoverable and is never listed.
 *
 * On top of that, **a minor is never on a public board.** They appear only on
 * the `scout` variant, which `firestore.rules` gates behind a `scout` or
 * `admin` claim. This is the compromise the feature turns on: the fifteen-
 * year-old who is the best raider in her district has to be findable — she is
 * precisely who §6 exists for, and who §7's sponsorship depends on — but
 * findable by an accountable scout, not by anyone who installs the app.
 *
 * Appearing on a scout board still discloses nothing beyond a name, a band, a
 * district and a trend. *Contacting* her remains gated by the existing
 * `guardianConsents` record, which this changes not at all.
 */
export function audiencesFor({ visibility, isMinor }) {
  if (visibility !== 'public') return [];
  return isMinor ? ['scout'] : ['public', 'scout'];
}

/**
 * Every board scope a row belongs to.
 *
 * A player in Nalgonda, Telangana appears on the district board, the state
 * board and the national board — narrowing is a filter the reader chooses,
 * so each scope needs its own precomputed document. Age works the same way:
 * the row lands on its own band's board and on the all-ages board.
 */
export function scopesFor({ state, district, ageBand }) {
  const geoScopes = [{ state: ANY, district: ANY }];
  if (state !== ANY) {
    geoScopes.push({ state, district: ANY });
    if (district !== ANY) geoScopes.push({ state, district });
  }
  const ageScopes = [ANY, ageBand];
  const out = [];
  for (const g of geoScopes) {
    for (const a of ageScopes) {
      out.push({ ...g, ageGroup: a });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Candidate loading.
// ---------------------------------------------------------------------------

/**
 * Every player with a rating trail, joined to the profile facts a board row
 * needs.
 *
 * Reads the whole `users` collection once and the whole `ratings` collection
 * group once, rather than a rating lookup per user — the join is done in
 * memory because two full scans is two queries and the per-user shape is
 * thousands. See the file doc's scale note.
 */
async function loadPlayerCandidates(now, { requireTrail = true } = {}) {
  const profiles = new Map();
  const usersSnap = await db().collection('users').get();
  for (const doc of usersSnap.docs) {
    const u = doc.data();
    const dobRaw = u.dateOfBirth;
    const dob = dobRaw?.toDate ? dobRaw.toDate() : null;
    // No date of birth means no age band, and an age band is not optional on
    // these boards — every scope is age-filtered. Skipped rather than bucketed
    // into "Senior", which would silently list minors on public boards.
    if (!dob) continue;
    profiles.set(doc.id, {
      uid: doc.id,
      displayName: u.displayName || 'Player',
      photoUrl: u.photoUrl ?? null,
      visibility: u.profileVisibility || 'community',
      dob,
      state: slug(u.geo?.state),
      district: slug(u.geo?.district),
      districtLabel: u.geo?.district ?? null,
    });
  }

  const candidates = [];
  const ratingsSnap = await db().collectionGroup('ratings').get();
  for (const doc of ratingsSnap.docs) {
    const uid = doc.ref.parent.parent?.id;
    const profile = uid ? profiles.get(uid) : null;
    if (!profile) continue;
    const d = doc.data();
    // With the warehouse supplying trends, a rating whose local trail is
    // empty is still a candidate — the changelog remembers movements that
    // predate the trail being introduced, and dropping those rows would make
    // the warehouse path see *less* history than the fallback.
    if (requireTrail && (!Array.isArray(d.trail) || d.trail.length === 0)) {
      continue;
    }

    // The document id is the rating key, which for chess is
    // `chess_blitz` rather than the bare sport (see `ratingKeyFor`). Boards
    // are per sport, so the time control is trimmed back off here.
    const sportId = doc.id.split('_')[0];

    candidates.push({
      ...profile,
      sportId,
      ratingKey: doc.id,
      trail: d.trail,
      deviation: typeof d.deviation === 'number' ? d.deviation : 350,
      isMinor: ageOnDate(profile.dob, now) < 18,
    });
  }
  return candidates;
}

/**
 * Club form over the window, from completed fixtures.
 *
 * ## Which fixtures count
 *
 * Only those whose two entrant ids are org ids — that is, inter-club results
 * (`Fixture.sideForOrg` documents why a challenge fixture stores club ids
 * there). A club's *internal* Sunday match has both sides inside the same
 * club and says nothing about how that club fares against others, so counting
 * it would let a club inflate its own form by playing itself.
 */
async function loadTeamCandidates(now) {
  const orgs = new Map();
  const orgsSnap = await db().collection('orgs').get();
  for (const doc of orgsSnap.docs) {
    const o = doc.data();
    if (o.deletedAt) continue;
    // Same opt-in rule as players: an unlisted club has not asked to be
    // discovered.
    if (o.visibility !== 'public') continue;
    orgs.set(doc.id, {
      orgId: doc.id,
      orgName: o.name || 'Club',
      logoUrl: o.logoUrl ?? null,
      state: slug(o.geo?.state ?? o.state),
      district: slug(o.geo?.district ?? o.district),
      districtLabel: o.geo?.district ?? o.district ?? null,
    });
  }

  const cutoff = new Date(now.getTime() - WINDOW_DAYS * 86400000);
  // key: `${orgId}__${sportId}`
  const form = new Map();
  const recordFor = (orgId, sportId) => {
    const key = `${orgId}__${sportId}`;
    let rec = form.get(key);
    if (!rec) {
      rec = {
        orgId,
        sportId,
        matchesInWindow: 0,
        winsInWindow: 0,
        lifetimeMatches: 0,
        lifetimeWins: 0,
        tournamentWins: 0,
      };
      form.set(key, rec);
    }
    return rec;
  };

  const fixturesSnap = await db()
    .collectionGroup('fixtures')
    .where('status', '==', 'completed')
    .get();

  for (const doc of fixturesSnap.docs) {
    const f = doc.data();
    const a = f.entrantAId;
    const b = f.entrantBId;
    if (typeof a !== 'string' || typeof b !== 'string') continue;
    // Both sides must be clubs, and different ones.
    if (a === b || !orgs.has(a) || !orgs.has(b)) continue;

    const sportId = f.sportId || 'unknown';
    const playedRaw = f.completedAt ?? f.ratingSettledAt ?? f.scheduledAt;
    const playedAt = playedRaw?.toDate ? playedRaw.toDate() : null;
    const inWindow = playedAt !== null && playedAt > cutoff;

    for (const orgId of [a, b]) {
      const rec = recordFor(orgId, sportId);
      const won = f.isDraw !== true && f.winnerEntrantId === orgId;
      rec.lifetimeMatches += 1;
      if (won) rec.lifetimeWins += 1;
      if (inWindow) {
        rec.matchesInWindow += 1;
        if (won) rec.winsInWindow += 1;
      }
    }
  }

  // Tournament titles inside the window, shown alongside the form rather than
  // scored into it — see `RisingTeamEntry.tournamentWins`.
  const ranks = await db()
    .collection('rankingEntries')
    .where('round', '==', 'winner')
    .get();
  for (const doc of ranks.docs) {
    const r = doc.data();
    const orgId = r.orgId;
    if (!orgId || !orgs.has(orgId)) continue;
    const awardedAt = r.awardedAt?.toDate ? r.awardedAt.toDate() : null;
    if (!awardedAt || awardedAt <= cutoff) continue;
    recordFor(orgId, r.sportId || 'unknown').tournamentWins += 1;
  }

  const out = [];
  for (const rec of form.values()) {
    const org = orgs.get(rec.orgId);
    if (!org) continue;
    out.push({ ...org, ...rec });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Board assembly.
// ---------------------------------------------------------------------------

/**
 * Turns candidate rows into board documents.
 *
 * Exported and pure (no Firestore) so it can be exercised directly — the
 * emulator suite drives this with handcrafted rows rather than seeding a
 * database and waiting for a schedule.
 */
export function buildBoards({ players, teams, now, trends = null }) {
  /** boardId -> { key fields, players: [], teams: [] } */
  const boards = new Map();

  const boardFor = (sportId, scope, audience) => {
    const id = boardId({ sportId, ...scope, audience });
    let b = boards.get(id);
    if (!b) {
      b = {
        id,
        sportId: slug(sportId),
        state: scope.state,
        district: scope.district,
        ageGroup: scope.ageGroup,
        audience,
        players: [],
        teams: [],
      };
      boards.set(id, b);
    }
    return b;
  };

  for (const p of players) {
    const audiences = audiencesFor(p);
    if (audiences.length === 0) continue;

    // The warehouse's answer wins when there is one: it is the same formula
    // over the *full* rating history rather than over the last 24 snapshots.
    // A player absent from the trend table simply did not qualify there, so
    // falling back to their trail would resurrect a row the better data
    // already rejected — hence the lookup is only skipped when there is no
    // trend table at all.
    const signal = trends
      ? trends.get(`${p.uid}__${p.sportId}`)
      : risingSignal(p.trail, p.deviation, now);
    if (!signal?.eligible) continue;

    const band = ageBandFor(p.dob, now);
    const row = {
      uid: p.uid,
      displayName: p.displayName,
      score: signal.score,
      ratingDelta: signal.points,
      matchesInWindow: signal.matches,
      ageGroupLabel: band.label,
      photoUrl: p.photoUrl,
      districtLabel: p.districtLabel,
      clubName: p.clubName ?? null,
      provisional: signal.provisional,
      truncatedSpan: signal.truncated,
    };
    for (const scope of scopesFor({
      state: p.state,
      district: p.district,
      ageBand: band.name,
    })) {
      for (const audience of audiences) {
        boardFor(p.sportId, scope, audience).players.push(row);
      }
    }
  }

  for (const t of teams) {
    const signal = teamFormSignal(t);
    if (!signal.eligible) continue;
    const row = {
      orgId: t.orgId,
      orgName: t.orgName,
      score: signal.score,
      matchesInWindow: signal.matchesInWindow,
      winsInWindow: signal.winsInWindow,
      recentWinRate: signal.recentWinRate,
      momentum: signal.momentum,
      logoUrl: t.logoUrl,
      districtLabel: t.districtLabel,
      tournamentWins: t.tournamentWins ?? 0,
    };
    // Clubs have no age band — a club board is the same list at every age
    // scope, which is what puts it on the `_any` scope only. The UI shows
    // teams on the all-ages tab for exactly this reason.
    for (const scope of scopesFor({
      state: t.state,
      district: t.district,
      ageBand: ANY,
    })) {
      // Both audiences: a club is not a person and carries no minor-safety
      // question, so the scout board is a superset containing the same rows.
      for (const audience of ['public', 'scout']) {
        boardFor(t.sportId, scope, audience).teams.push(row);
      }
    }
  }

  // Rank, truncate, stamp.
  const docs = [];
  for (const b of boards.values()) {
    const poolPlayers = b.players.length;
    const poolTeams = b.teams.length;
    b.players.sort((x, y) => y.score - x.score);
    b.teams.sort((x, y) => y.score - x.score);
    docs.push({
      id: b.id,
      data: {
        sportId: b.sportId,
        state: b.state,
        district: b.district,
        ageGroup: b.ageGroup,
        audience: b.audience,
        windowDays: WINDOW_DAYS,
        playerPoolSize: poolPlayers,
        teamPoolSize: poolTeams,
        players: b.players
          .slice(0, MAX_ENTRIES)
          .map((p, i) => ({ ...p, rank: i + 1 })),
        teams: b.teams
          .slice(0, MAX_ENTRIES)
          .map((t, i) => ({ ...t, rank: i + 1 })),
      },
    });
  }
  return docs;
}

/**
 * Writes the boards, and removes the ones that no longer have any rows.
 *
 * The deletion pass is the part that is easy to forget and impossible to
 * live without: a district whose only rising player has since gone quiet must
 * end up with an *empty* board, not last month's board served indefinitely.
 * A stale "rising talent" list is worse than no list — it sends a scout after
 * a player whose form ended in April.
 */
async function publishBoards(docs) {
  const keep = new Set(docs.map((d) => d.id));
  const collection = db().collection('talentBoards');

  let batch = db().batch();
  let queued = 0;
  const flush = async () => {
    if (queued === 0) return;
    await batch.commit();
    batch = db().batch();
    queued = 0;
  };

  for (const doc of docs) {
    batch.set(collection.doc(doc.id), {
      ...doc.data,
      computedAt: FieldValue.serverTimestamp(),
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
  return { written: docs.length, removed };
}

/**
 * Turns the warehouse's trend rows into the same signal shape
 * `risingSignal()` returns, so `buildBoards` cannot tell which produced it.
 *
 * The score is recomputed here rather than selected in SQL on purpose: there
 * is then exactly one place in this file where `points × confidence` is
 * written down, and the view cannot drift away from it silently.
 */
function trendIndex(rows) {
  const map = new Map();
  for (const r of rows) {
    const confidence = r.matches / (r.matches + PLAYER_SHRINKAGE);
    map.set(`${r.uid}__${r.sportId}`, {
      points: r.points,
      matches: r.matches,
      confidence,
      score: r.points * confidence,
      truncated: r.truncated,
      provisional: r.provisional,
      eligible: r.matches >= PLAYER_MIN_MATCHES && r.points > 0,
    });
  }
  return map;
}

/** The whole job, shared by the schedule and the manual trigger. */
async function runTalentBoards() {
  const now = new Date();
  const warehouseRows = await playerTrendsFromWarehouse();
  const trends = warehouseRows ? trendIndex(warehouseRows) : null;

  const [players, teams] = await Promise.all([
    loadPlayerCandidates(now, { requireTrail: trends === null }),
    loadTeamCandidates(now),
  ]);
  const docs = buildBoards({ players, teams, now, trends });
  const result = await publishBoards(docs);
  logger.info(
    `computeTalentBoards (${trends ? 'bigquery' : 'trail'}): ` +
      `${players.length} player-sport rows, ${teams.length} club-sport rows ` +
      `→ ${result.written} boards written, ${result.removed} stale removed.`,
  );
  return {
    ...result,
    source: trends ? 'bigquery' : 'trail',
    playerRows: players.length,
    teamRows: teams.length,
  };
}

/**
 * Nightly, at 02:30 IST — after the day's matches have settled and before
 * anyone opens the app in the morning.
 *
 * Daily rather than on every match: a 90-day trend does not meaningfully move
 * between breakfast and lunch, and rebuilding every board in the country on
 * each settled fixture would be the most expensive thing in the product by an
 * order of magnitude.
 */
export const computeTalentBoards = onSchedule(
  {
    schedule: '30 2 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async () => {
    await runTalentBoards();
  },
);

/** Staff-only manual rebuild, for after a data fix or a formula change. */
export const rebuildTalentBoards = onCall(
  { region: 'asia-south1', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError(
        'permission-denied',
        'Rebuilding talent boards is restricted to PlaySphere staff.',
      );
    }
    return runTalentBoards();
  },
);
