/**
 * Flushes the "non-critical" notification buffer `sendToUsersDigestAware`
 * (in `index.js`) writes into instead of pushing immediately.
 *
 * ## Why this exists
 *
 * Every one of the ~19 notification triggers in `index.js` used to push the
 * instant it fired. That is right for a match starting or a result landing
 * — those are critical, see `CRITICAL_NOTIFICATION_TYPES` — but it means an
 * active club's admin gets one buzz per membership approval, one per
 * challenge, one per sponsor offer, all day, forever. At ten clubs and a
 * handful of events a year that was never felt. At the volume a season
 * running for a full year across many clubs produces, it is the difference
 * between a push people glance at and one they mute the app over — which
 * loses the *critical* pushes too, since a phone does not distinguish which
 * notification made someone turn the channel off.
 *
 * The fix is not to send fewer notifications — every one of them still
 * writes its own record to `users/{uid}/notifications` the instant it
 * happens, so the in-app screen is exactly as complete as before. It is to
 * stop making the phone buzz once per event for the events that can wait a
 * few minutes, and instead send ONE push covering everything that piled up
 * since the last flush.
 *
 * ## Why a schedule, not a Firestore trigger
 *
 * A trigger on `notificationDigest` writes would fire on every single
 * increment — exactly the fan-out this exists to collapse. A fixed interval
 * is what actually turns "N events" into "1 push".
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

import { pushToUids } from './push.js';

function db() {
  return getFirestore();
}

/**
 * Human, pluralized labels for the digest body. Deliberately only covers
 * the wire types `sendToUsersDigestAware` ever queues — see
 * `CRITICAL_NOTIFICATION_TYPES` in `index.js` for the full set of wire
 * values and which of them never reach here.
 */
const TYPE_LABELS = {
  membership_approved: 'membership update',
  challenge_received: 'challenge',
  tournament_invite: 'tournament invite',
  sponsor_pledge_received: 'sponsor offer',
  sponsor_pledge_resolved: 'sponsor response',
};

function pluralize(word, count) {
  return count === 1 ? word : `${word}s`;
}

function summarize(types) {
  const parts = Object.entries(types || {})
    .filter(([, count]) => Number(count) > 0)
    .map(([type, count]) => `${count} ${pluralize(TYPE_LABELS[type] ?? type, count)}`);
  if (parts.length === 0) return null;
  if (parts.length === 1) return parts[0];
  if (parts.length === 2) return `${parts[0]} and ${parts[1]}`;
  return `${parts.slice(0, -1).join(', ')}, and ${parts[parts.length - 1]}`;
}

/**
 * Every 15 minutes: find every user with a nonzero pending count, send them
 * one push summarizing it, then reset the counter to zero.
 *
 * The reset is a full `.set()`, not a merged one — an empty `types: {}`
 * merged into an existing map leaves the old keys untouched, since merge is
 * recursive per-key rather than a replace. This document is written only by
 * `queueDigest` and this job, so overwriting it whole here is safe.
 */
export const flushNotificationDigests = onSchedule(
  {
    schedule: 'every 15 minutes',
    region: 'asia-south1',
    timeoutSeconds: 300,
  },
  async () => {
    const pending = await db()
      .collectionGroup('notificationDigest')
      .where('pendingCount', '>', 0)
      .get();

    if (pending.empty) return;

    let sent = 0;
    await Promise.all(
      pending.docs.map(async (doc) => {
        const uid = doc.ref.parent.parent?.id;
        if (!uid) return;

        const count = doc.get('pendingCount') ?? 0;
        const summary = summarize(doc.get('types'));

        await pushToUids([uid], {
          id: `digest_${uid}_${Date.now()}`,
          type: 'digest',
          title: count === 1 ? 'You have a new update' : `You have ${count} new updates`,
          body: summary ? `${summary[0].toUpperCase()}${summary.slice(1)}. Open PlaySphere to see them.`
            : 'Open PlaySphere to see them.',
          // Raw wire field, not the `route`/`params` convenience shape —
          // that pair is only unpacked by `notification()` in `index.js`,
          // which this job does not go through. `DeepLink.fromDataPayload`
          // (Dart) reads `deepLinkRoute` directly.
          deepLinkRoute: '/notifications',
        });

        // Full overwrite — see doc comment above for why merge would not
        // actually clear the per-type counts.
        await doc.ref.set({
          pendingCount: 0,
          types: {},
          updatedAt: FieldValue.serverTimestamp(),
        });
        sent += 1;
      }),
    );

    logger.info('notification digest flush complete', { recipients: sent });
  },
);
