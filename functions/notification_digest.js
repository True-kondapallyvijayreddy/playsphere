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

import { PAGE_SIZE, forEachPaged } from './paged_scan.js';
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
  club_message: 'club message',
  give_donation_submitted: 'donation',
  give_need_raised: 'need to verify',
  give_donation_advanced: 'donation update',
  ad_campaign_submitted: 'campaign to review',
  ad_campaign_reviewed: 'campaign decision',
};

/** A wire type nobody has labelled yet, as words rather than a token. */
function labelFor(type) {
  return TYPE_LABELS[type] ?? String(type).replace(/_/g, ' ');
}

function pluralize(word, count) {
  return count === 1 ? word : `${word}s`;
}

/**
 * The per-type counts on a pending-digest document. Reads the `types` map, and
 * also the literal `types.<wire>` fields an earlier version wrote by mistake
 * (a dotted key under merge is a field name, not a path), so a backlog queued
 * before the fix still reads right.
 */
export function pendingTypes(data) {
  const out = {};
  const add = (type, n) => {
    const count = Number(n) || 0;
    if (count > 0) out[type] = (out[type] ?? 0) + count;
  };
  for (const [type, n] of Object.entries(data?.types ?? {})) add(type, n);
  for (const [key, n] of Object.entries(data ?? {})) {
    if (key.startsWith('types.')) add(key.slice('types.'.length), n);
  }
  return out;
}

export function summarize(types) {
  const parts = Object.entries(types || {})
    .filter(([, count]) => Number(count) > 0)
    .map(([type, count]) => `${count} ${pluralize(labelFor(type), count)}`);
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
    // Paged, and one page at a time rather than `Promise.all` over the whole
    // result.
    //
    // This runs every fifteen minutes and its result set grows with the
    // active user base: "every account with something waiting" is a small
    // fraction of the platform and an unbounded number of documents. Reading
    // them all and then fanning out a push for each concurrently is two
    // ceilings at once — the resident set, and however many FCM calls the
    // runtime will let one instance have in flight. See paged_scan.js.
    //
    // Pages are processed in order and each page's pushes go out together, so
    // the concurrency is bounded by PAGE_SIZE rather than by how many people
    // happen to have notifications waiting.
    let sent = 0;
    const page = [];
    const flushPage = async () => {
      if (page.length === 0) return;
      const batch = page.splice(0, page.length);
      await Promise.all(batch.map(async (doc) => {
        const uid = doc.ref.parent.parent?.id;
        if (!uid) return;

        // Claimed before the push, in a transaction: whatever arrives while the
        // push is on its way lands on the zeroed counter and goes out with the
        // next flush, instead of being wiped by an overwrite afterwards.
        const claimed = await db().runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          const data = fresh.exists ? fresh.data() : {};
          const pending = Number(data.pendingCount) || 0;
          if (pending <= 0) return null;
          tx.set(doc.ref, {
            pendingCount: 0,
            types: {},
            updatedAt: FieldValue.serverTimestamp(),
          });
          return { count: pending, types: pendingTypes(data) };
        });
        if (!claimed) return;
        const { count } = claimed;
        const summary = summarize(claimed.types);

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

        sent += 1;
      }));
    };

    await forEachPaged(
      db().collectionGroup('notificationDigest').where('pendingCount', '>', 0),
      async (doc) => {
        page.push(doc);
        if (page.length >= PAGE_SIZE) await flushPage();
      },
      { label: 'notificationDigest flush' },
    );
    await flushPage();

    logger.info('notification digest flush complete', { recipients: sent });
  },
);
