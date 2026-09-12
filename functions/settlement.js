/**
 * Career totals and officiating credit, settled against the fixture as it IS
 * rather than as the trigger's snapshot remembers it.
 *
 * ## The race this exists to close
 *
 * `onMatchSettled` is handed `before`/`after` photographs of one write. By the
 * time it has read a dozen documents and committed a batch, seconds have
 * passed and the fixture may have moved on — and the product has a control
 * built for moving it on fast: a scorer who taps match point by mistake presses
 * Reopen, which rules branch (b4) admits precisely so that mistake is
 * recoverable.
 *
 * Crediting from the snapshot meant: the credit for result A landed on a
 * fixture that was live again, `careerSettledAt` stayed set, and when the match
 * was actually played out to result B the credit branch skipped it as already
 * counted. One mistaken tap left a player's record wrong in both directions at
 * once — crediting a result that never stood, and never crediting the one that
 * did.
 *
 * Re-reading inside a transaction closes it. A credit lands only if the fixture
 * is still resulted and still uncredited at the instant of the write; a reversal
 * only if it is still credited and no longer resulted. Whichever of the two
 * racing invocations commits second sees the other's work and does nothing.
 *
 * ## Why the settlement is written down
 *
 * Reversal used to recompute what to take back from the PRE-write snapshot,
 * which is right only while nothing changed in between. An organizer may move a
 * finished match from `completed` to `walkover` — resulted either way, so
 * neither branch fires — and the reversal would then subtract a walkover's
 * figures from a `completed` match's credit. So each credit records exactly
 * what it added, and the reversal undoes exactly that.
 *
 * `previous` is still accepted for fixtures credited before this file existed,
 * which carry no record. Same behaviour as before for them, exact for
 * everything new.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import { RESULTED_STATUSES, careerContributions } from './career.js';

function db() {
  return getFirestore();
}

/**
 * One career document's worth of movement, in the given direction.
 *
 * `sign` is +1 to credit and -1 to reverse; every field moves together, so the
 * two directions cannot drift apart the way two hand-written blocks did.
 */
export function careerMovement(contribution, sign) {
  const tally = {};
  for (const [k, v] of Object.entries(contribution.tally ?? {})) {
    if (v !== 0) tally[k] = FieldValue.increment(sign * v);
  }
  return {
    matchesPlayed: FieldValue.increment(sign),
    wins: FieldValue.increment(contribution.outcome === 'won' ? sign : 0),
    draws: FieldValue.increment(contribution.outcome === 'drawn' ? sign : 0),
    losses: FieldValue.increment(contribution.outcome === 'lost' ? sign : 0),
    ...(Object.keys(tally).length > 0 ? { tally } : {}),
  };
}

/** What a credit records about itself, so a reversal can be exact. */
export function settlementRecord(contributions) {
  return contributions.map((c) => ({
    uid: c.uid,
    sportId: c.sportId,
    outcome: c.outcome,
    tally: c.tally ?? {},
  }));
}

/**
 * Credits or reverses one fixture's career records, whichever the fixture's
 * current state calls for, or does nothing when it is already in step.
 *
 * Returns a short verb for the log: 'credited', 'reversed' or null.
 */
export async function settleCareer(fixtureRef, { orgId, previous } = {}) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(fixtureRef);
    if (!snap.exists) return null;
    const fixture = snap.data();

    const credited = Boolean(fixture.careerSettledAt);
    const resulted = RESULTED_STATUSES.has(fixture.status);

    if (!credited && resulted) {
      const contributions = careerContributions(fixture, { orgId });
      if (contributions.length === 0) return null;
      for (const c of contributions) {
        tx.set(
          db().doc(`users/${c.uid}/career_stats/${c.sportId}`),
          {
            uid: c.uid,
            sportId: c.sportId,
            lastPlayedAt: c.playedAt ?? new Date(),
            clubsPlayedFor: FieldValue.arrayUnion(orgId),
            ...careerMovement(c, 1),
          },
          { merge: true },
        );
      }
      // The marker and the record ride with the increments they account for:
      // an increment cannot be undone, so a fixture re-finished after a retry
      // must never be counted twice.
      tx.set(
        fixtureRef,
        {
          careerSettledAt: new Date(),
          careerSettlement: settlementRecord(contributions),
        },
        { merge: true },
      );
      return 'credited';
    }

    if (credited && !resulted) {
      const recorded = Array.isArray(fixture.careerSettlement)
        ? fixture.careerSettlement
        : careerContributions(previous ?? fixture, { orgId });
      for (const c of recorded) {
        tx.set(
          db().doc(`users/${c.uid}/career_stats/${c.sportId}`),
          careerMovement(c, -1),
          { merge: true },
        );
      }
      // Cleared whether or not there was anything to reverse. The marker's job
      // is to say "this fixture has been counted", and it has not been any more.
      tx.set(
        fixtureRef,
        {
          careerSettledAt: FieldValue.delete(),
          careerSettlement: FieldValue.delete(),
        },
        { merge: true },
      );
      return 'reversed';
    }

    return null;
  });
}

/**
 * The officiating counter, on the same transactional footing and for the same
 * reason.
 *
 * Only people who actually hold a registry profile are counted: an organizer
 * may name anybody as an official, and a blind merge would mint an
 * `umpires/{uid}` document carrying nothing but a count, which the directory
 * then renders as a nameless official certified in no sport.
 */
export async function settleOfficials(fixtureRef, { orgId, compId, fixtureId, previous } = {}) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(fixtureRef);
    if (!snap.exists) return null;
    const fixture = snap.data();

    const credited = Boolean(fixture.officialsSettledAt);
    const resulted = RESULTED_STATUSES.has(fixture.status);

    if (!credited && resulted) {
      const uids = [...new Set(
        (fixture.officials ?? []).map((o) => o?.uid).filter(Boolean),
      )];
      let registered = [];
      if (uids.length > 0) {
        const profiles = await tx.getAll(
          ...uids.map((uid) => db().doc(`umpires/${uid}`)),
        );
        registered = profiles.filter((d) => d.exists).map((d) => d.id);
      }

      for (const uid of registered) {
        tx.set(
          db().doc(`umpires/${uid}`),
          { matchesOfficiated: FieldValue.increment(1) },
          { merge: true },
        );
        // The audit trail behind the number, keyed by fixture id so it is
        // naturally one row per match however many times this runs. It is what
        // makes the counter rebuildable — a tally nobody can account for is one
        // people argue with.
        tx.set(
          db().doc(`umpires/${uid}/matches/${fixtureId}`),
          {
            fixtureId,
            orgId,
            compId,
            sportId: fixture.sportId ?? fixture.scoringPluginKey ?? null,
            role: (fixture.officials ?? []).find((o) => o?.uid === uid)?.role
              ?? 'main_umpire',
            entrantAName: fixture.entrantAName ?? null,
            entrantBName: fixture.entrantBName ?? null,
            playedAt: fixture.scheduledAt ?? null,
            recordedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      // Written even when nobody was credited: the question "have the officials
      // on this fixture been settled" has been answered either way, and
      // re-reading those profiles on every future write buys nothing.
      tx.set(
        fixtureRef,
        { officialsSettledAt: new Date(), officialsSettlement: registered },
        { merge: true },
      );
      return registered.length > 0 ? 'credited' : null;
    }

    if (credited && !resulted) {
      const recorded = Array.isArray(fixture.officialsSettlement)
        ? fixture.officialsSettlement
        : [...new Set(
            ((previous ?? fixture).officials ?? []).map((o) => o?.uid).filter(Boolean),
          )];
      for (const uid of recorded) {
        tx.set(
          db().doc(`umpires/${uid}`),
          { matchesOfficiated: FieldValue.increment(-1) },
          { merge: true },
        );
        // The audit row goes with the count it accounts for. Left behind, a
        // rebuild from these rows would put the number straight back.
        tx.delete(db().doc(`umpires/${uid}/matches/${fixtureId}`));
      }
      tx.set(
        fixtureRef,
        {
          officialsSettledAt: FieldValue.delete(),
          officialsSettlement: FieldValue.delete(),
        },
        { merge: true },
      );
      return 'reversed';
    }

    return null;
  });
}

/**
 * Claims the right to settle this fixture's RATINGS, atomically.
 *
 * The rating pass reads a rating document per player and writes one back, which
 * is too much to hold in one transaction against a hot fixture. So the claim is
 * separated from the work: this stamps `ratingSettledAt` only if the fixture is
 * still completed and still unclaimed, and the caller does the arithmetic only
 * if it won the claim. Two invocations racing over the same finished match
 * therefore cannot both pay it, and a match that has already been reopened is
 * never rated on a result that no longer stands.
 */
export async function claimRatingSettlement(fixtureRef) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(fixtureRef);
    if (!snap.exists) return false;
    const fixture = snap.data();
    if (fixture.ratingSettledAt) return false;
    if (fixture.status !== 'completed') return false;
    tx.set(fixtureRef, { ratingSettledAt: new Date() }, { merge: true });
    return true;
  });
}

export { logger };
