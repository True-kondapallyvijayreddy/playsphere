/**
 * Ratings, settled and taken back against the fixture as it IS.
 *
 * ## Why this is a transaction and not a claim followed by a batch
 *
 * Settlement used to stamp `ratingSettledAt` first and write the ratings in a
 * separate batch afterwards. Nothing ever cleared that stamp, so a match that
 * was reopened (rules branch (b4)) and finished again with a different winner
 * kept the first result's rating movement forever and refused to rate the
 * second: "already settled".
 *
 * Here the fixture, the rating documents and the record of what moved are one
 * transaction. A credit lands only if the fixture is still completed, still
 * unrated and still carries the result the arithmetic was done for; a reversal
 * lands only if it is no longer completed and still carries a rating record.
 * Whichever of two racing invocations commits second sees the other's work.
 *
 * ## What a reversal can and cannot undo
 *
 * Glicko is path-dependent: a player's later matches were rated against the
 * value this match produced. So the reversal is exact only while this match is
 * still the player's latest settlement, in which case the recorded `before` is
 * restored verbatim. Otherwise the recorded delta is subtracted from the rating
 * and the appearance is taken back — the honest approximation, and the same one
 * a federation applies when it annuls a result mid-season.
 *
 * `ratingSettlement` is written only here (firestore.rules freezes it against
 * every client), which is what lets a reversal trust it.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import {
  DEFAULT_DEVIATION,
  DEFAULT_RATING,
  DEFAULT_VOLATILITY,
  rate,
} from './glicko2.js';

function db() {
  return getFirestore();
}

/** Cap on one match's movement of one rating. */
export const MAX_SWING = 50;

/**
 * The rating documents' new values for one match. Pure.
 *
 * `current` maps uid → { rating, deviation, volatility, gamesPlayed, settled,
 * trail }. `sideA`/`sideB` are the verified uids; `weights` maps uid → the
 * contribution weight (1 when absent). Returns one entry per player who has not
 * already been paid for `fixtureId`.
 */
export function computeRatingUpdates({
  current, sideA, sideB, aWon, isDraw, weights, fixtureId, settledAt, trailLength,
}) {
  const average = (uids, key, fallback) => {
    const values = uids.map((u) => current.get(u)?.[key] ?? fallback);
    return values.reduce((s, v) => s + v, 0) / values.length;
  };
  const avgA = average(sideA, 'rating', DEFAULT_RATING);
  const avgB = average(sideB, 'rating', DEFAULT_RATING);
  const rdA = average(sideA, 'deviation', DEFAULT_DEVIATION);
  const rdB = average(sideB, 'deviation', DEFAULT_DEVIATION);

  const out = [];
  for (const [uids, opponentAvg, opponentRd, won] of [
    [sideA, avgB, rdB, aWon],
    [sideB, avgA, rdA, !aWon],
  ]) {
    const score = isDraw ? 0.5 : won ? 1 : 0;
    for (const uid of uids) {
      const player = current.get(uid);
      if (!player || player.settled.includes(fixtureId)) continue;

      const rawWeight = weights.get(uid) ?? 1;
      // A win rewards a big contribution more; a loss is dampened for the
      // player who carried the side and absorbed by the one who did not.
      const effectiveWeight = isDraw ? 1.0 : won ? rawWeight : Math.max(0.2, 2.0 - rawWeight);

      const next = rate(player, [{
        opponent: { rating: opponentAvg, deviation: opponentRd },
        score,
        weight: effectiveWeight,
      }]);
      const delta = Math.max(-MAX_SWING, Math.min(MAX_SWING, next.rating - player.rating));
      const after = {
        rating: player.rating + delta,
        deviation: next.deviation,
        volatility: next.volatility,
        gamesPlayed: next.gamesPlayed,
      };
      out.push({
        uid,
        before: {
          rating: player.rating,
          deviation: player.deviation,
          volatility: player.volatility,
          gamesPlayed: player.gamesPlayed,
        },
        after,
        settledFixtures: [...player.settled, fixtureId].slice(-50),
        trail: [
          ...player.trail,
          { r: after.rating, t: settledAt.toISOString(), f: fixtureId },
        ].slice(-trailLength),
      });
    }
  }
  return out;
}

/**
 * What taking one recorded settlement off one rating document leaves. Pure.
 *
 * `doc` is the rating document as it stands; `record` is the entry
 * `settleRatings` wrote for this player. Returns the fields to write.
 */
export function reversedRating(doc, record, fixtureId) {
  const settled = Array.isArray(doc?.settledFixtures) ? doc.settledFixtures : [];
  const trail = Array.isArray(doc?.trail) ? doc.trail : [];
  const latest = settled.length > 0 && settled[settled.length - 1] === fixtureId;

  const base = latest
    ? { ...record.before }
    : {
      rating: (doc?.rating ?? DEFAULT_RATING) - (record.after.rating - record.before.rating),
      deviation: doc?.deviation ?? record.before.deviation,
      volatility: doc?.volatility ?? record.before.volatility,
      gamesPlayed: Math.max(0, (doc?.gamesPlayed ?? 1) - 1),
    };
  return {
    ...base,
    settledFixtures: settled.filter((id) => id !== fixtureId),
    trail: trail.filter((entry) => entry?.f !== fixtureId),
  };
}

/** A rating document's fields, defaulted, in the shape `rate` takes. */
function currentOf(snap) {
  const d = snap.exists ? snap.data() : null;
  return {
    rating: d?.rating ?? DEFAULT_RATING,
    deviation: d?.deviation ?? DEFAULT_DEVIATION,
    volatility: d?.volatility ?? DEFAULT_VOLATILITY,
    gamesPlayed: d?.gamesPlayed ?? 0,
    settled: Array.isArray(d?.settledFixtures) ? d.settledFixtures : [],
    trail: Array.isArray(d?.trail) ? d.trail : [],
  };
}

/**
 * Settles one finished match's ratings, if it is still finished with the
 * result `expected` describes and nobody has settled it yet.
 *
 * Returns the uids whose ratings moved, or null when nothing was settled.
 */
export async function settleRatings(fixtureRef, {
  fixtureId, ratingKey, sideA, sideB, weights, expected, trailLength,
}) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(fixtureRef);
    if (!snap.exists) return null;
    const fixture = snap.data();
    if (fixture.status !== 'completed' || fixture.ratingSettledAt) return null;
    // The arithmetic was done for this result. A different one is a later
    // write whose own invocation settles it.
    if ((fixture.winnerEntrantId ?? null) !== (expected.winnerEntrantId ?? null)
        || (fixture.isDraw === true) !== (expected.isDraw === true)) {
      return null;
    }

    const refs = [...sideA, ...sideB].map((uid) => db().doc(`users/${uid}/ratings/${ratingKey}`));
    const snaps = refs.length > 0 ? await tx.getAll(...refs) : [];
    const current = new Map();
    [...sideA, ...sideB].forEach((uid, i) => current.set(uid, currentOf(snaps[i])));

    const settledAt = new Date();
    const updates = computeRatingUpdates({
      current,
      sideA,
      sideB,
      aWon: expected.winnerEntrantId === fixture.entrantAId,
      isDraw: expected.isDraw === true,
      weights,
      fixtureId,
      settledAt,
      trailLength,
    });

    for (const u of updates) {
      tx.set(db().doc(`users/${u.uid}/ratings/${ratingKey}`), {
        ...u.after,
        settledFixtures: u.settledFixtures,
        trail: u.trail,
        updatedAt: settledAt,
      }, { merge: true });
    }
    tx.set(fixtureRef, {
      ratingSettledAt: settledAt,
      ratingSettlement: {
        key: ratingKey,
        players: updates.map((u) => ({ uid: u.uid, before: u.before, after: u.after })),
      },
    }, { merge: true });
    return updates.map((u) => u.uid);
  });
}

/**
 * Takes a match's rating movement back off once it is no longer completed, and
 * clears the marker so finishing it again rates the result that then stands.
 *
 * Returns the uids whose ratings moved back, or null when there was nothing to
 * reverse.
 */
export async function reverseRatings(fixtureRef, { fixtureId }) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(fixtureRef);
    if (!snap.exists) return null;
    const fixture = snap.data();
    if (fixture.status === 'completed' || !fixture.ratingSettledAt) return null;

    const record = fixture.ratingSettlement;
    const players = Array.isArray(record?.players) ? record.players : [];
    const key = typeof record?.key === 'string' ? record.key : null;
    const valid = key === null
      ? []
      : players.filter((p) => typeof p?.uid === 'string' && p.before && p.after);

    const refs = valid.map((p) => db().doc(`users/${p.uid}/ratings/${key}`));
    const snaps = refs.length > 0 ? await tx.getAll(...refs) : [];
    valid.forEach((p, i) => {
      if (!snaps[i].exists) return;
      tx.set(refs[i], {
        ...reversedRating(snaps[i].data(), p, fixtureId),
        updatedAt: new Date(),
      }, { merge: true });
    });

    // Cleared even for a fixture settled before records existed. Its players'
    // `settledFixtures` still name it, so re-finishing cannot pay them twice.
    tx.update(fixtureRef, {
      ratingSettledAt: FieldValue.delete(),
      ratingSettlement: FieldValue.delete(),
    });
    return valid.map((p) => p.uid);
  });
}
