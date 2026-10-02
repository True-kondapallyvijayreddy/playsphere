/**
 * Knockout advancement, settled by the server.
 *
 * ## Why this is not only the scoring pad's job
 *
 * The pad advances a winner into the next round on the device that scored the
 * last point, so a bracket moves the instant a match ends even off signal. But
 * that write lands on a DIFFERENT fixture, and `firestore.rules` admits it only
 * for somebody holding the club's scorer rank. The people who most often score
 * a knockout match — a season-panel umpire from another club, or two players
 * scoring their own individual tie — pass every rule on the match they are
 * scoring and none on the next one. When the advancement rode in the same batch
 * as the winning point, the rule refused the whole batch and the point itself
 * was lost.
 *
 * So the pad now advances best-effort and separately, and this trigger makes
 * the bracket right for everybody: whenever a fixture has a decided winner, the
 * slot it feeds holds that winner (and the loser slot, the loser), as long as
 * the next match has not started. A result changed by a reopen or a protest
 * re-points the slot; one that has already been played is left alone, because
 * that match's record is somebody's afternoon.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

const DECIDED = new Set(['completed', 'walkover']);

/**
 * The winner and loser a fixture hands on, or null when it hands on nothing.
 * Pure.
 */
export function decidedSides(fixture) {
  if (!fixture || !DECIDED.has(fixture.status) || fixture.isDraw === true) return null;
  const winner = fixture.winnerEntrantId;
  if (typeof winner !== 'string' || winner.length === 0) return null;
  const aWon = winner === fixture.entrantAId;
  if (!aWon && winner !== fixture.entrantBId) return null;
  const side = (isA) => ({
    id: isA ? fixture.entrantAId : fixture.entrantBId,
    name: isA ? fixture.entrantAName : fixture.entrantBName,
    uid: (isA ? fixture.entrantAUid : fixture.entrantBUid) ?? null,
  });
  return { winner: side(aWon), loser: side(!aWon) };
}

/**
 * The update that puts `entrant` into `slot` of `target`, or null when the slot
 * already holds them or must not be touched. Pure.
 *
 * `source` is the fixture feeding the slot. A slot may be filled when it is
 * empty, or re-pointed when it currently holds one of the source's own two
 * entrants — the previous verdict of the same match.
 */
export function slotUpdate({ target, slot, entrant, source }) {
  if (!target || !entrant?.id || (slot !== 'a' && slot !== 'b')) return null;
  if (target.status !== 'scheduled' || (target.lastSeq ?? 0) > 0) return null;
  const S = slot === 'a' ? 'A' : 'B';
  const current = target[`entrant${S}Id`] ?? '';
  if (current === entrant.id) return null;
  const fromSource = current === source.entrantAId || current === source.entrantBId;
  if (current !== '' && !fromSource) return null;

  const previousUid = target[`entrant${S}Uid`] ?? null;
  const update = {
    [`entrant${S}Id`]: entrant.id,
    [`entrant${S}Name`]: entrant.name ?? 'To be decided',
    [`entrant${S}Uid`]: entrant.uid ?? null,
  };
  const players = new Set(Array.isArray(target.playerUids) ? target.playerUids : []);
  if (previousUid) players.delete(previousUid);
  if (entrant.uid) players.add(entrant.uid);
  update.playerUids = [...players];
  return update;
}

export const onFixtureDecidedAdvance = onDocumentWritten(
  { region: 'asia-south1', document: 'orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}' },
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    if (!after) return;
    const sides = decidedSides(after);
    if (!sides) return;
    // Only when the verdict is new — not on every write to a finished match.
    const prior = decidedSides(before);
    if (prior && prior.winner.id === sides.winner.id
        && before.feedsWinnerToFixtureId === after.feedsWinnerToFixtureId
        && before.feedsLoserToFixtureId === after.feedsLoserToFixtureId) {
      return;
    }

    const { orgId, compId } = event.params;
    const fixtures = db().collection('orgs').doc(orgId)
      .collection('competitions').doc(compId).collection('fixtures');

    for (const [targetId, slot, entrant] of [
      [after.feedsWinnerToFixtureId, after.feedsWinnerToSlot, sides.winner],
      [after.feedsLoserToFixtureId, after.feedsLoserToSlot, sides.loser],
    ]) {
      if (typeof targetId !== 'string' || targetId.length === 0) continue;
      try {
        await db().runTransaction(async (tx) => {
          const ref = fixtures.doc(targetId);
          const snap = await tx.get(ref);
          if (!snap.exists) return;
          const update = slotUpdate({ target: snap.data(), slot, entrant, source: after });
          if (update) tx.update(ref, { ...update, updatedAt: FieldValue.serverTimestamp() });
        });
      } catch (error) {
        logger.warn('advancement failed', { orgId, compId, targetId, error: String(error) });
      }
    }
  },
);
