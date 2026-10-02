/**
 * Telling a player their club has picked them.
 *
 * ## Why this is a trigger and not a write from the app
 *
 * `users/{uid}/notifications` is `allow create: if false` — no client writes a
 * notification to anybody, including a club secretary writing to their own
 * members, because a collection any client could write to is a collection any
 * client could impersonate. So the app records the DECISION, in a document it
 * is allowed to write and whose rules say who may write it
 * (`orgs/{orgId}/seasonNominations`, organizers of that club only), and this
 * turns that decision into the message.
 *
 * ## What the message has to carry
 *
 * A selection the player cannot act on is worse than none: it tells somebody
 * they are playing on Sunday and leaves them nowhere to say yes. A singles
 * draw is entered by the player themselves — see `SeasonNomination` for why
 * the club cannot do it for them — so the notification deep-links to the
 * season's register page, which is where their own entry is made.
 */

import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

import { persistNotifications, pushToUids } from './push.js';

export const onSeasonNominated = onDocumentWritten(
  { region: 'asia-south1', document: 'orgs/{orgId}/seasonNominations/{nominationId}' },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    // Un-picked, or a rewrite of a row that already exists. The deterministic
    // id means an organizer correcting a squad re-writes rows rather than
    // creating them, and a second identical notification for a selection
    // somebody was already told about is noise that makes them stop reading
    // the first one.
    if (!after) return;
    if (before) return;

    const uid = after.uid;
    if (!uid) return;

    const club = after.clubName || 'Your club';
    const draw = after.compName || 'an event';
    const season = after.tournamentName;

    const payload = {
      id: `nominated_${after.tournamentId}_${after.compId}_${uid}`,
      type: 'event_reminder',
      title: `${club} has selected you`,
      body: season
        ? `You are picked for ${draw} at ${season}. Open it to enter — your ` +
          'place is not booked until you do.'
        : `You are picked for ${draw}. Open it to enter — your place is not ` +
          'booked until you do.',
      // The register page rather than the season page: it is the one screen
      // that lists every draw with its entry button, which is the single
      // thing this person now has to do.
      deepLinkRoute: '/org/:orgId/tournaments/:tournamentId/register',
      deepLinkParam_orgId: after.hostOrgId,
      deepLinkParam_tournamentId: after.tournamentId,
    };

    const unique = await persistNotifications([uid], payload);
    await pushToUids(unique, payload);
    logger.info(
      `Told ${uid} they were selected for ${after.compId} by ${after.orgId}`,
    );
  },
);
