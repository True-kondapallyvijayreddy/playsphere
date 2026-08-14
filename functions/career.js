/**
 * Per-match tally extraction, server-side.
 *
 * Mirrors `PlayerTally.of` (lib/domain/scoring/player_stats.dart) and
 * `CareerAggregator.contributionsFrom` (lib/domain/career/career_stats.dart)
 * — the Dart aggregator was written to compute exactly this shape but has
 * never been reachable from the JS Cloud Function that is the only writer
 * of `career_stats`. This file is the JS side of the same computation,
 * duplicated deliberately for the same reason `contribution.js` duplicates
 * `match_award.dart`: the server has to be the only writer, and both
 * languages need the shape to be independently testable.
 */

/** The key every scoring engine writes its per-player tallies under. Mirrors `PlayerTally.stateKey`. */
const TALLY_KEY = 'players';

/** One player's raw tally from a match's score state. Mirrors `PlayerTally.of`. */
export function playerTally(scoreState, playerId) {
  const all = (scoreState && scoreState[TALLY_KEY]) || {};
  const mine = all[playerId] || {};
  const out = {};
  for (const [k, v] of Object.entries(mine)) {
    if (typeof v === 'number') out[k] = v;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Who a finished match credits, and with what.
//
// These four helpers are the JS mirror of the Dart rules that every career
// screen already reads through — `Fixture.countsTowardsRecords`,
// `Fixture.sideForUid`, `Fixture.outcomeForUid` and
// `ScopedStats.forPlayer` (lib/domain/career/scoped_stats.dart). They exist as
// their own exports rather than inline in the trigger because the trigger and
// the rebuild below must apply exactly one definition of "this match counts
// for you"; two copies is how the stored rollup and the recomputation came to
// disagree in the first place.
// ---------------------------------------------------------------------------

/** Mirrors `FixtureStatus.isResulted`. */
export const RESULTED_STATUSES = new Set(['completed', 'walkover']);

/**
 * Whether a match is settled enough to enter anybody's career record.
 *
 * Mirrors `Fixture.countsTowardsRecords`: a result exists, and no official is
 * still being waited on. Deliberately NOT gated on `resultType` — a walkover
 * is a match that appears on the player's own match list, and a career total
 * that silently excluded it would disagree with the list beside it. Its tally
 * is empty anyway, so it contributes an appearance and nothing else.
 */
export function countsTowardsRecords(fixture) {
  if (!fixture || !RESULTED_STATUSES.has(fixture.status)) return false;
  return (fixture.resultState ?? 'none') !== 'awaitingApproval';
}

/**
 * Everyone with an account who played, per side.
 *
 * Line-ups first, then the individual-event entrant uids — the same two
 * sources and the same precedence as `Fixture.sideForUid`. The entrant *id*
 * is not consulted: it is not a uid, and treating it as one is what wrote
 * `users/side_a/career_stats/*` into this database.
 */
export function registeredSides(fixture) {
  const sideOf = (lineup, entrantUid) => {
    const ids = [];
    for (const p of Array.isArray(lineup) ? lineup : []) {
      if (p && typeof p.uid === 'string' && p.uid.length > 0) {
        // The tally is keyed by the line-up id, which for a registered player
        // IS their uid — see `MatchPlayer`. Kept as the id rather than the uid
        // so a future divergence is a lookup miss, not a wrong number.
        ids.push({ uid: p.uid, playerId: p.id ?? p.uid });
      }
    }
    if (typeof entrantUid === 'string' && entrantUid.length > 0 &&
        !ids.some((p) => p.uid === entrantUid)) {
      // An individual entrant is their own team sheet, and the engines key
      // that player's tally by the same uid.
      ids.push({ uid: entrantUid, playerId: entrantUid });
    }
    return ids;
  };
  return {
    a: sideOf(fixture.lineupA, fixture.entrantAUid),
    b: sideOf(fixture.lineupB, fixture.entrantBUid),
  };
}

/** 'won' | 'lost' | 'drawn' | null. Mirrors `Fixture.outcomeForUid`. */
export function outcomeForSide(fixture, side) {
  if (fixture.isDraw === true) return 'drawn';
  const winner = fixture.winnerEntrantId;
  if (typeof winner !== 'string') return null;
  const mine = side === 'a' ? fixture.entrantAId : fixture.entrantBId;
  return winner === mine ? 'won' : 'lost';
}

/**
 * One match's contribution to every registered player's career.
 *
 * Mirrors `CareerAggregator.contributionsFrom` and, importantly, the client's
 * `ScopedStats.forPlayer`: a player is credited for a match they played,
 * whoever they played. Requiring an account on BOTH sides is a *rating*
 * constraint — Glicko needs a rated opponent — and applying it to career
 * statistics is why a player's 45 points against a guest showed on the splits
 * screen and nowhere in their totals.
 *
 * Guests are skipped: they appear on the scorecard, which is a real record,
 * but have no identity to attach a career to.
 */
export function careerContributions(fixture, { orgId } = {}) {
  if (!countsTowardsRecords(fixture)) return [];
  const sportId = fixture.sportId;
  if (typeof sportId !== 'string' || sportId.length === 0) return [];

  const sides = registeredSides(fixture);
  const out = [];
  for (const side of ['a', 'b']) {
    const outcome = outcomeForSide(fixture, side);
    for (const { uid, playerId } of sides[side]) {
      out.push({
        uid,
        sportId,
        orgId: orgId ?? fixture.orgId ?? null,
        side,
        outcome,
        tally: playerTally(fixture.scoreState, playerId),
        playedAt: playedAtOf(fixture),
      });
    }
  }
  return out;
}

/** When the match happened, best available. Falsy fields fall through. */
function playedAtOf(fixture) {
  for (const key of ['completedAt', 'startedAt', 'scheduledAt', 'updatedAt']) {
    const v = fixture[key];
    if (!v) continue;
    if (typeof v.toDate === 'function') return v.toDate();
    if (v instanceof Date) return v;
  }
  return null;
}

/**
 * Folds contributions into one record per (player, sport).
 *
 * Mirrors `CareerAggregator.accumulate`. Keyed `uid::sportId` — the same key
 * the document path uses, and sport is part of it because a batting average
 * and a raid average are not the same quantity.
 *
 * Pure, so the rebuild and its tests share one definition of the arithmetic.
 */
export function accumulateCareer(contributions) {
  const byKey = new Map();
  for (const c of contributions) {
    const key = `${c.uid}::${c.sportId}`;
    const prior = byKey.get(key) ?? {
      uid: c.uid,
      sportId: c.sportId,
      matchesPlayed: 0,
      wins: 0,
      draws: 0,
      losses: 0,
      tally: {},
      clubsPlayedFor: new Set(),
      lastPlayedAt: null,
    };

    prior.matchesPlayed += 1;
    if (c.outcome === 'won') prior.wins += 1;
    else if (c.outcome === 'drawn') prior.draws += 1;
    else if (c.outcome === 'lost') prior.losses += 1;

    for (const [k, v] of Object.entries(c.tally)) {
      prior.tally[k] = (prior.tally[k] ?? 0) + v;
    }
    if (c.orgId) prior.clubsPlayedFor.add(c.orgId);
    if (c.playedAt && (!prior.lastPlayedAt || c.playedAt > prior.lastPlayedAt)) {
      prior.lastPlayedAt = c.playedAt;
    }

    byKey.set(key, prior);
  }
  return byKey;
}
