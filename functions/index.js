/**
 * Push notifications for PlaySphere.
 *
 * ## Why this exists at all
 *
 * Everything else in this product is client + security rules, deliberately —
 * it keeps the system cheap enough to be free for scorers and players. Push is
 * the one thing that cannot work that way: a client must never be able to make
 * other people's phones buzz, so the decision to send has to happen somewhere
 * the client cannot reach.
 *
 * These are therefore triggers, not an API. Nothing here is callable. Each
 * function watches a Firestore write that already means something in the
 * product — an event opening for entries, a match going live, a challenge
 * arriving — and fans it out to the people that write concerns. There is no
 * endpoint through which anyone can ask for a notification to be sent.
 *
 * ## Region
 *
 * asia-south1 (Mumbai), the same region as Firestore. A trigger in another
 * region would cross-region every write in the product for no benefit.
 */

import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated, onDocumentUpdated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { logger } from 'firebase-functions';

import { persistNotifications, pushToUids } from './push.js';

import { awardsFor, ROUND_LABEL, WINDOW_DAYS } from './ranking.js';
import { contributionWeights, ratingKeyFor } from './contribution.js';
import {
  DEFAULT_DEVIATION,
  DEFAULT_RATING,
  DEFAULT_VOLATILITY,
  rate,
} from './glicko2.js';
import { refreshOverallForUids } from './overall_glicko.js';
// Career and officiating credit, settled against the fixture as it IS rather
// than as this trigger's snapshot remembers it — see settlement.js for the
// reopen race that made the difference matter.
import {
  claimRatingSettlement,
  settleCareer,
  settleOfficials,
} from './settlement.js';
import { ratingWithheldReason } from './rating_eligibility.js';

export { createPaymentLink, razorpayWebhook } from './razorpay.js';
// Erasing an account: the profile's personal details AND the sign-in, which a
// client cannot do for itself — see account.js.
export { deleteMyAccount } from './account.js';
export { computeGovAggregates } from './gov.js';
export {
  scoreNewGround,
  onGroundReported,
  onGroundCheckIn,
  flagUnvisitedGround,
} from './grounds.js';
export { syncGovAggregates, runAnalyticsSync } from './analytics.js';
export { computeTalentBoards, rebuildTalentBoards } from './talent.js';
export { computeSportStats, rebuildSportStats } from './sports.js';
export { computeClubStandings, rebuildClubStandings } from './clubs.js';
export { flushNotificationDigests } from './notification_digest.js';
export { backfillMatchSource } from './matchsource.js';
export { backfillFixtureParticipants } from './participants.js';
export { rebuildPlayerCareerStats } from './careerrebuild.js';
export { computeLeaderboards, rebuildLeaderboards } from './leaderboard.js';
export { computeOverallGlicko, rebuildOverallGlicko } from './overall_glicko.js';
export {
  createManagedChildProfile,
  redeemClaimCode,
  onChildProfileClaimed,
} from './family.js';
export {
  placeAuctionBid,
  openAuctionBidding,
  revealAuctionNow,
  revealDueAuctions,
  lockAuctionSquads,
  executeAuctionTrade,
  notifyAuctionDecision,
  notifyAuctionTrade,
} from './auctions.js';

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });

/**
 * How many rating snapshots each rating document keeps — see the `trail`
 * write in `onMatchSettled`.
 *
 * MUST equal `RatingTrail.maxLength` in
 * `lib/domain/scout/talent_trend.dart`. A server keeping fewer snapshots
 * than the client's window expects silently shortens every trend it can
 * measure, with no error anywhere. `test/talent_trend_test.dart` asserts the
 * Dart side of this constant.
 */
const TRAIL_LENGTH = 24;

/**
 * Sends one notification to a set of users, and durably records it for each
 * of them.
 *
 * Data-only messages, on purpose: the client model documents why (see
 * `AppNotification.toDataPayload`) — a `notification` block is displayed by
 * the OS without the app seeing it on some platforms and states, which breaks
 * deep-link routing. The title and body travel inside `data`.
 *
 * Dead tokens are pruned as they are discovered. A phone that was factory
 * reset otherwise stays in the fan-out forever, and every send to it is a
 * wasted call that slowly makes every notification slower.
 *
 * ## Why this also writes to Firestore
 *
 * A push is a moment: missed while the phone was asleep, dismissed from the
 * tray unread, or never delivered because the person had declined
 * notifications or reinstalled the app, it was gone for good — the in-app
 * Notifications screen had nothing to fall back on and, for a plain member
 * with no scoring assignment, no challenge and nothing to approve, nothing
 * to show at all. Every recipient here gets a document under
 * `users/{uid}/notifications` regardless of whether they own a working
 * device token, so the record survives independently of whether the push
 * itself was ever seen. This is the one and only place that write happens —
 * see `firestore.rules`, where the collection is `allow create: if false`
 * from the client for exactly that reason.
 */
async function sendToUsers(uids, payload) {
  const unique = await persistNotifications(uids, payload);
  await pushToUids(unique, payload);
}

/**
 * The [NotificationType]s the Dart model marks `isCritical: true` — see
 * `lib/core/notifications/notification_model.dart`. MUST be kept in sync by
 * hand; there is no shared source between Dart and this file. Anything NOT
 * in this set is routed through the digest instead of pushed immediately by
 * [sendToUsersDigestAware].
 *
 * `official_assigned` is deliberately absent from both this set and the
 * Dart enum — `NotificationType.fromWire` falls back to `eventReminder`
 * (critical) for any unrecognized wire value, so today it already pushes
 * immediately. Leaving it out here preserves that existing behavior rather
 * than silently changing it as a side effect of this file.
 */
const CRITICAL_NOTIFICATION_TYPES = new Set([
  'event_reminder',
  'tournament_announced',
  'event_cancelled',
  'match_start',
  'result',
  'match_rsvp',
  'match_clash',
]);

/**
 * Same in-app record as [sendToUsers], but the *push* for a non-critical
 * type is deferred to the next digest flush (`notification_digest.js`)
 * instead of sent immediately.
 *
 * Why the record still writes immediately either way: the in-app
 * Notifications screen must show every event the moment someone opens the
 * app, whether or not a push for it has gone out yet. Only the "buzz your
 * phone right now" step is batched — see `notification_digest.js` for why
 * that is the part that scales badly at high event volume.
 */
async function sendToUsersDigestAware(uids, payload) {
  const unique = await persistNotifications(uids, payload);
  if (unique.length === 0) return;

  if (CRITICAL_NOTIFICATION_TYPES.has(payload.type)) {
    await pushToUids(unique, payload);
    return;
  }
  await queueDigest(unique, payload);
}

/**
 * Bumps each recipient's pending-digest counter instead of pushing now.
 *
 * One fixed-id doc per user (`notificationDigest/pending`) rather than a
 * growing subcollection — the flush job only ever needs the current totals,
 * never a history, so there is nothing to gain from one doc per event and a
 * real cost (an unbounded collection under every active user) from writing
 * that way.
 */
async function queueDigest(uids, payload) {
  await Promise.all(
    uids.map((uid) =>
      db.collection('users').doc(uid).collection('notificationDigest').doc('pending').set(
        {
          pendingCount: FieldValue.increment(1),
          [`types.${payload.type}`]: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      ).catch((error) => logger.warn('digest queue failed', { uid, error: String(error) })),
    ),
  );
}

/**
 * Roles that may act on a club's behalf.
 *
 * These are WIRE tokens and must match `MembershipRole.wire` in
 * lib/core/models/enums.dart exactly — the enum is snake_case on the wire, and
 * a camelCase copy here matches nothing, fails silently, and simply drops
 * every event manager out of the fan-out.
 */
const ORGANIZER_ROLES = ['owner', 'admin', 'event_manager'];

/** Active members of a club. */
async function activeMemberUids(orgId, { onlyAdmins = false } = {}) {
  let query = db.collection('orgs').doc(orgId).collection('members')
    .where('status', '==', 'active');
  if (onlyAdmins) {
    query = query.where('role', 'in', ORGANIZER_ROLES);
  }
  const snap = await query.get();
  return snap.docs.map((d) => d.id);
}

/**
 * The first line of a message, for a lock screen.
 *
 * Capped well under what a message may actually be: a push body is read at a
 * glance over somebody's shoulder, and the whole point of opening the app is
 * to read the rest.
 */
function previewOf(text) {
  const trimmed = String(text).trim().replace(/\s+/g, ' ');
  return trimmed.length <= 120 ? trimmed : `${trimmed.slice(0, 119)}…`;
}

function notification({ id, type, title, body, route, params = {} }) {
  const payload = { id, type, title, body };
  if (route) {
    payload.deepLinkRoute = route;
    for (const [key, value] of Object.entries(params)) {
      payload[`deepLinkParam_${key}`] = String(value);
    }
  }
  return payload;
}

/**
 * An event opening for entries.
 *
 * The spec calls this the trigger for one-tap registration, and until now
 * members had to open the app and go looking. Fires on the transition INTO
 * `registration_open` rather than on creation, because an event is created as
 * a draft and telling a club about a draft its organizer is still writing
 * would be worse than saying nothing.
 */
export const onEventOpened = onDocumentWritten(
  'orgs/{orgId}/competitions/{compId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;
    if (after.status !== 'registration_open') return;
    if (before && before.status === after.status) return;

    const { orgId, compId } = event.params;
    const uids = await activeMemberUids(orgId);

    const openLine = after.participationModel === 'approval'
      ? 'Apply now.'
      : after.maxEntrants
        ? `${after.maxEntrants} places — first come, first served.`
        : 'Register now.';

    await sendToUsers(uids, notification({
      id: `event_open_${compId}`,
      type: 'event_reminder',
      title: after.name ?? 'New event',
      body: `${after.sportName ?? 'Event'} — ${openLine}`,
      route: '/org/:orgId/event/:compId',
      params: { orgId, compId },
    }));
  },
);

/** The date range on a tournament, as an organizer would say it out loud. */
function tournamentDates(data) {
  const toDate = (value) => (value && typeof value.toDate === 'function')
    ? value.toDate()
    : null;
  const start = toDate(data.startDate);
  if (!start) return null;
  const end = toDate(data.endDate);
  const day = (d) => d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    timeZone: 'Asia/Kolkata',
  });
  if (!end || day(end) === day(start)) return day(start);
  return `${day(start)} – ${day(end)}`;
}

/**
 * A tournament or a season being created.
 *
 * ## Why on CREATE, and not on a later "publish"
 *
 * `onEventOpened` deliberately waits for a status transition, because a single
 * event really is created as a blank draft and filled in afterwards. A
 * tournament is not: both routes into this collection — the tournament sheet
 * and the season form — ask for the name, the dates and (for a season) every
 * sport before the create button will enable, so the document's first write is
 * already the finished announcement. Waiting for a transition that no screen
 * currently performs would mean this notification never fired at all.
 *
 * Goes to EVERY active member rather than to organizers. That is the whole
 * request: a club's members should hear about their club's tournament at the
 * same moment, from the club, rather than from whoever happened to be in the
 * right WhatsApp group.
 *
 * The draws hanging off a season are created immediately after this document
 * and each would otherwise fire its own `onEventOpened` later; those are about
 * entries opening for one sport, and this is about the season existing. They
 * carry different ids so neither replaces the other in the tray.
 */
export const onTournamentCreated = onDocumentCreated(
  'orgs/{orgId}/tournaments/{tournamentId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { orgId, tournamentId } = event.params;
    const uids = await activeMemberUids(orgId);
    if (uids.length === 0) return;

    const org = await db.collection('orgs').doc(orgId).get();
    const dates = tournamentDates(data);

    await sendToUsers(uids, notification({
      id: `tournament_created_${tournamentId}`,
      type: 'tournament_announced',
      title: data.name ?? 'New tournament',
      body: dates
        ? `${org.get('name') ?? 'Your club'} is running this — ${dates}. Tap for the details.`
        : `${org.get('name') ?? 'Your club'} is running this. Tap for the details.`,
      route: '/org/:orgId/tournaments/:tournamentId',
      params: { orgId, tournamentId },
    }));
  },
);

/**
 * A season's timetable being locked and published.
 *
 * ## Who hears about it
 *
 * Everybody who is IN it, which is a wider set than "members of the club that
 * runs it". A district meet's draws are full of entrants from other schools,
 * and those are exactly the people who need to know their child plays at 9:40
 * on Court 3 — telling only the host club's members would notify the
 * organizers and nobody else. So the fan-out is the union of:
 *
 *   * the host club's active members;
 *   * every uid named on an entrant of any event in the season — the entrant
 *     itself for an individual draw, its squad for a team one;
 *   * the active members of every OTHER club with an entrant in the season.
 *
 * The last of those is the one that makes a visiting school's coach and
 * parents hear about it at all, and it is bounded: a season has as many
 * entrant clubs as it has schools, not as it has players.
 *
 * ## Why this is a trigger and not a client write
 *
 * `TournamentRepository.lockSchedule` used to write the notification itself,
 * into `users/{orgId}/notifications` — a path naming a user that does not
 * exist, at a collection whose rule is `allow create: if false`. The denied
 * write failed the whole batch, so publishing a schedule did not merely fail
 * to notify anyone: it failed. Notifications are the server's to write, which
 * is the rule that was already there.
 *
 * Critical, and `event_reminder` rather than a type of its own on the wire so
 * an older build in somebody's pocket still renders it: this is the message
 * that tells a family which morning to be at the ground.
 */
export const onScheduleReleased = onDocumentUpdated(
  'orgs/{orgId}/tournaments/{tournamentId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    // Only the false -> true edge. A later edit to any other field must not
    // re-announce a timetable everybody already has.
    if (before.isScheduleLocked === true || after.isScheduleLocked !== true) return;

    const { orgId, tournamentId } = event.params;

    const comps = await db.collection('orgs').doc(orgId).collection('competitions')
      .where('tournamentId', '==', tournamentId)
      .get();
    if (comps.empty) return;

    const uids = new Set(await activeMemberUids(orgId));
    const entrantOrgIds = new Set();

    const entrantSnaps = await Promise.all(
      comps.docs.map((doc) => doc.ref.collection('entrants').get()),
    );
    for (const snap of entrantSnaps) {
      snap.forEach((doc) => {
        const data = doc.data();
        if (data.withdrawn === true) return;
        if (typeof data.uid === 'string' && data.uid) uids.add(data.uid);
        for (const member of data.memberUids ?? []) {
          if (typeof member === 'string' && member) uids.add(member);
        }
        if (typeof data.clubId === 'string' && data.clubId && data.clubId !== orgId) {
          entrantOrgIds.add(data.clubId);
        }
      });
    }

    const visiting = await Promise.all(
      [...entrantOrgIds].map((id) => activeMemberUids(id)),
    );
    for (const list of visiting) for (const uid of list) uids.add(uid);

    if (uids.size === 0) return;

    const dates = tournamentDates(after);
    await sendToUsers([...uids], notification({
      id: `schedule_released_${tournamentId}`,
      type: 'event_reminder',
      title: `${after.name ?? 'The schedule'} — timetable published`,
      body: dates
        ? `Match times and courts are now final for ${dates}. Tap to see when you play.`
        : 'Match times and courts are now final. Tap to see when you play.',
      route: '/org/:orgId/tournaments/:tournamentId/schedule',
      params: { orgId, tournamentId },
    }));
  },
);

/**
 * A tournament invitation arriving from another club.
 *
 * Goes to the invited club's organizers, not its members, for the same reason
 * `onChallengeReceived` does: entering a club into somebody else's tournament
 * is a decision only they can take. Once they have taken it, the entry becomes
 * an ordinary event in their own club and their members hear about it through
 * the paths that already exist.
 */
export const onTournamentInvite = onDocumentCreated(
  'tournamentInvites/{inviteId}',
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== 'pending') return;
    if (!data.toOrgId) return;

    const dates = tournamentDates(data);

    await sendToUsersDigestAware(
      await activeMemberUids(data.toOrgId, { onlyAdmins: true }),
      notification({
        id: `tournament_invite_${event.params.inviteId}`,
        type: 'tournament_invite',
        title: `${data.fromOrgName ?? 'A club'} has invited you`,
        body: dates
          ? `${data.tournamentName ?? 'Their tournament'} — ${dates}. Take a look and enter.`
          : `${data.tournamentName ?? 'Their tournament'} — take a look and enter.`,
        // The PUBLIC page, not the host club's own tournament screen: the
        // invited club's admins are not members of the host and would be
        // refused by the rules on the org-scoped route.
        route: '/org/:orgId/live-tournament/:tournamentId',
        params: {
          orgId: data.fromOrgId ?? '',
          tournamentId: data.tournamentId ?? '',
        },
      }),
    );
  },
);

/** Everyone who entered a competition, whatever their entry's state. */
async function entrantUids(orgId, compId) {
  const snap = await db.collection('orgs').doc(orgId)
    .collection('competitions').doc(compId)
    .collection('registrations').get();
  // Withdrawn entrants are deliberately INCLUDED for a cancellation. Someone
  // who pulled out on Tuesday still arranged their Saturday around the event
  // not happening; they do not need to hear it was cancelled, but the cost of
  // telling them is one push and the cost of the alternative is a person
  // turning up. Cancelled entries are the one exception — those were never
  // real entries.
  return snap.docs
    .filter((d) => (d.data().status ?? '') !== 'cancelled')
    .map((d) => d.id);
}

/**
 * An event being called off.
 *
 * Fires on the transition INTO `cancelled`, and carries the organizer's reason
 * in the body. That reason is the whole point of the notification: "Sunday
 * Cricket was cancelled" produces a round of WhatsApp messages asking why,
 * which is exactly the work this is meant to remove.
 *
 * Sent to everyone who ENTERED rather than to every member of the club. A club
 * of four hundred with eighteen entrants should wake up eighteen phones — the
 * other 382 people were never coming.
 */
export const onEventCancelled = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;
    if (after.status !== 'cancelled') return;

    const { orgId, compId } = event.params;
    const uids = await entrantUids(orgId, compId);
    if (uids.length === 0) return;

    const reason = (after.cancelReason ?? '').trim();

    await sendToUsers(uids, notification({
      // Includes the compId so a person in two cancelled events gets two
      // notifications rather than one overwriting the other.
      id: `event_cancelled_${compId}`,
      type: 'event_cancelled',
      title: `${after.name ?? 'Event'} was cancelled`,
      body: reason.length > 0 ? reason : 'No reason was given.',
      route: '/org/:orgId/event/:compId',
      params: { orgId, compId },
    }));
  },
);

/**
 * An organizer's note to everyone who entered.
 *
 * Keyed on `organizerNote.seq` rather than on the note's text: an organizer
 * who sends the same "bring studs" twice on two different weekends means it
 * twice, and comparing text would silently swallow the second. The counter is
 * incremented server-side by `noteToEntrants`, so it moves once per send and
 * not at all when some unrelated edit rewrites the document.
 */
export const onOrganizerNote = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const seq = after.organizerNote?.seq;
    if (typeof seq !== 'number') return;
    if (seq === before.organizerNote?.seq) return;

    const text = (after.organizerNote?.text ?? '').trim();
    if (text.length === 0) return;

    const { orgId, compId } = event.params;
    const uids = await entrantUids(orgId, compId);
    if (uids.length === 0) return;

    await sendToUsers(uids, notification({
      // Seq in the id so a second note does not replace the first in the tray.
      id: `event_note_${compId}_${seq}`,
      type: 'event_reminder',
      title: after.name ?? 'Event update',
      body: text,
      route: '/org/:orgId/event/:compId',
      params: { orgId, compId },
    }));
  },
);

/**
 * Tallying a motion to remove an owner.
 *
 * ## Why the server decides
 *
 * `firestore.rules` can guarantee that `votes` only ever grows by the caller's
 * own uid — which is what makes the list countable — but it cannot count it
 * against a threshold that depends on a QUERY (how many owners does this club
 * have?). Rules cannot query. So the threshold is applied here, where the
 * owner count can actually be read, and the removal is performed with admin
 * credentials that no client can borrow.
 *
 * The rule that matters: no client can write `status: passed`, and no client
 * can write a member's role down from owner except through the flow they are
 * already entitled to (stepping down themselves). Every other path to
 * un-owning somebody goes through this function.
 *
 * Threshold: two thirds of the OTHER owners, rounded up. Mirrors
 * `OwnerVote.votesNeeded` in lib/domain/governance/owner_vote.dart — the two
 * must not drift, because the client draws the progress bar from one and the
 * removal happens on the other.
 */
function votesNeeded(ownerCount) {
  const electorate = ownerCount - 1;
  if (electorate <= 0) return 0;
  return Math.ceil((2 * electorate) / 3);
}

export const onOwnerVote = onDocumentWritten(
  'orgs/{orgId}/ownerProposals/{targetUid}',
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;
    if (after.status !== 'open') return;

    const { orgId, targetUid } = event.params;

    // Distinct uids only, and never the target's own. Both are enforced by the
    // rules too; re-checking here costs nothing and means the tally does not
    // depend on the rules being the only way in.
    const votes = [...new Set(after.votes ?? [])].filter((u) => u !== targetUid);

    const ownersSnap = await db.collection('orgs').doc(orgId)
      .collection('members')
      .where('role', '==', 'owner')
      .where('status', '==', 'active')
      .get();

    const ownerUids = ownersSnap.docs.map((d) => d.id);

    // A vote from somebody who has since stopped being an owner does not
    // count. Without this, an owner could appoint a friend, have them vote,
    // and demote them again — manufacturing a majority out of one seat.
    const valid = votes.filter((u) => ownerUids.includes(u));
    const needed = votesNeeded(ownerUids.length);

    if (needed === 0 || valid.length < needed) return;

    // Threshold met. Demote to admin rather than removing from the club: this
    // is a decision about authority, not membership, and ejecting someone from
    // a club they may have founded is not what was voted on.
    const batch = db.batch();
    batch.update(
      db.collection('orgs').doc(orgId).collection('members').doc(targetUid),
      { role: 'admin' },
    );
    batch.update(
      db.collection('orgs').doc(orgId).collection('ownerProposals').doc(targetUid),
      {
        status: 'passed',
        resolvedAt: FieldValue.serverTimestamp(),
        passedWith: valid.length,
        outOf: ownerUids.length,
      },
    );
    // `ownerUids` on the org document is a denormalized mirror of the member
    // rows, kept for screens that need the list without a subcollection query.
    // Maintained here so it can never disagree with the roles, which are what
    // the security rules actually check.
    batch.update(db.collection('orgs').doc(orgId), {
      ownerUids: ownerUids.filter((u) => u !== targetUid),
    });
    await batch.commit();

    await sendToUsersDigestAware(ownerUids, notification({
      id: `owner_removed_${orgId}_${targetUid}`,
      type: 'membership_approved',
      title: 'Ownership changed',
      body: `${after.targetName ?? 'An owner'} is no longer an owner — `
        + `${valid.length} of ${ownerUids.length} owners agreed.`,
      route: '/org/:orgId/members',
      params: { orgId },
    }));
  },
);

/**
 * Somebody being named in a group entry, and the organizer being told a group
 * is ready.
 *
 * Both live here because both are the same document changing state, and
 * because an invitation nobody hears about is the failure mode this whole flow
 * is built to avoid: a leader adds five people, none of them open the app for
 * a week, and the group silently never completes.
 */
export const onGroupEntryChanged = onDocumentWritten(
  'orgs/{orgId}/competitions/{compId}/groupEntries/{groupId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;

    const { orgId, compId, groupId } = event.params;
    const compSnap = await db.collection('orgs').doc(orgId)
      .collection('competitions').doc(compId).get();
    const eventName = compSnap.data()?.name ?? 'an event';

    // Newly created: ask everyone named except the leader, who proposed it.
    if (!before) {
      const invited = (after.memberUids ?? [])
        .filter((u) => u !== after.leaderUid);
      if (invited.length === 0) return;

      await sendToUsers(invited, notification({
        id: `group_invite_${groupId}`,
        type: 'event_reminder',
        title: `${after.leaderName ?? 'Someone'} put you in a team`,
        body: `"${after.name}" for ${eventName}. Accept to confirm your place.`,
        route: '/org/:orgId/event/:compId',
        params: { orgId, compId },
      }));
      return;
    }

    // Completed: everyone has accepted, so it is now the organizer's call.
    if (before.status !== 'pending_approval'
        && after.status === 'pending_approval') {
      const admins = await activeMemberUids(orgId, { onlyAdmins: true });
      if (admins.length === 0) return;

      await sendToUsers(admins, notification({
        id: `group_ready_${groupId}`,
        type: 'event_reminder',
        title: 'A group is waiting for approval',
        body: `"${after.name}" — ${(after.memberUids ?? []).length} players `
          + `for ${eventName}.`,
        route: '/org/:orgId/event/:compId',
        params: { orgId, compId },
      }));
      return;
    }

    // Decided: tell the group either way. A rejection people never hear about
    // is people who turn up.
    if (before.status !== after.status
        && (after.status === 'approved' || after.status === 'rejected')) {
      await sendToUsers(after.memberUids ?? [], notification({
        id: `group_decided_${groupId}`,
        type: 'event_reminder',
        title: after.status === 'approved'
          ? `"${after.name}" is in`
          : `"${after.name}" was not accepted`,
        body: after.status === 'approved'
          ? `You are entered in ${eventName}.`
          : (after.decisionNote ?? `The organizer did not accept this group.`),
        route: '/org/:orgId/event/:compId',
        params: { orgId, compId },
      }));
    }
  },
);

/**
 * A match going live, and a match finishing.
 *
 * Both live in one trigger because both are a status transition on the same
 * document, and everything here returns early unless the STATUS changed — so
 * the ordinary ball-by-ball write, the hottest path in the product, costs one
 * comparison.
 *
 * `onMatchSettled` watches this same document and is deliberately NOT folded in
 * with it, despite the invocation this costs. They fail differently and must be
 * allowed to: a rating that cannot be computed must not swallow the "your match
 * has finished" push, and a dead device token must not abort settlement. One
 * handler would make each the other's single point of failure.
 */
export const onFixtureStatusChanged = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    const { orgId, compId, fixtureId } = event.params;
    const route = '/org/:orgId/event/:compId/watch/:fixtureId';
    const params = { orgId, compId, fixtureId };
    const title = `${after.entrantAName ?? 'A'} v ${after.entrantBName ?? 'B'}`;

    // An inter-club match concerns both clubs. Everything else concerns the
    // club that owns it.
    const orgIds = Array.isArray(after.participantOrgIds) && after.participantOrgIds.length === 2
      ? after.participantOrgIds
      : [orgId];
    const uids = (await Promise.all(orgIds.map((id) => activeMemberUids(id)))).flat();

    if (after.status === 'live') {
      await sendToUsers(uids, notification({
        id: `match_live_${fixtureId}`,
        type: 'match_start',
        title,
        body: 'Live now — follow the score.',
        route,
        params,
      }));
      return;
    }

    if (after.status === 'completed') {
      const mvp = after.mvp?.name;
      await sendToUsers(uids, notification({
        id: `match_result_${fixtureId}`,
        type: 'result',
        title,
        body: mvp
          ? `${after.summary ?? 'Match finished'} · Best performer: ${mvp}`
          : (after.summary ?? 'Match finished'),
        route,
        params,
      }));
    }
  },
);

/** Mirrors `_roleLabel` in `officials_screen.dart` — keep the two in step. */
function officialRoleLabel(role) {
  switch (role) {
    case 'square_leg_umpire': return 'square leg umpire';
    case 'referee': return 'referee';
    case 'third_umpire': return 'third umpire';
    case 'linesman': return 'linesman';
    default: return 'umpire';
  }
}

/**
 * An official being assigned to a match — the ICC-style "you have this one"
 * notice, sent the moment the assignment lands rather than left for the
 * official to discover by opening the app.
 *
 * Fires for both assignment paths that write `Fixture.officials` — the
 * tournament-wide bulk run and the per-match manual pick — since both go
 * through the same field. Only the names newly present in `officials` are
 * notified: a fixture write that touches something else, or that re-saves an
 * unchanged panel, must not re-notify everyone already on it.
 */
export const onOfficialAssigned = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeUids = new Set((before.officials ?? []).map((o) => o.uid));
    const newlyAssigned = (after.officials ?? [])
      .filter((o) => o.uid && !beforeUids.has(o.uid));
    if (newlyAssigned.length === 0) return;

    const { orgId, compId, fixtureId } = event.params;
    const title = `${after.entrantAName ?? 'A'} v ${after.entrantBName ?? 'B'}`;
    const route = '/org/:orgId/event/:compId/watch/:fixtureId';
    const params = { orgId, compId, fixtureId };
    const when = after.scheduledAt
      ? ` — ${after.venue ?? 'venue to follow'}`
      : ' — time and venue to follow';

    await Promise.all(newlyAssigned.map((official) => sendToUsers(
      [official.uid],
      notification({
        id: `official_${fixtureId}_${official.uid}`,
        type: 'official_assigned',
        title,
        body: `You're the ${officialRoleLabel(official.role)} for this match${when}.`,
        route,
        params,
      }),
    )));
  },
);

/**
 * A challenge arriving from another club.
 *
 * Goes to the receiving club's admins rather than every member: it is a
 * decision only they can act on, and a village club of two hundred does not
 * need two hundred phones buzzing about a fixture nobody else can accept.
 */
export const onChallengeReceived = onDocumentCreated(
  'challenges/{challengeId}',
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== 'pending') return;
    if (!data.toOrgId) return;

    const uids = await activeMemberUids(data.toOrgId, { onlyAdmins: true });
    await sendToUsersDigestAware(uids, notification({
      id: `challenge_${event.params.challengeId}`,
      type: 'challenge_received',
      title: `${data.fromOrgName ?? 'A club'} has challenged you`,
      body: 'Accept, pick a slot, or decline.',
      route: '/org/:orgId/challenges',
      params: { orgId: data.toOrgId },
    }));
  },
);

/**
 * A message arriving from another club in the club owners' network.
 *
 * Goes to the receiving club's OWNERS, not its organizers and not its
 * members. The network is an owner-to-owner surface all the way down — see
 * the `clubThreads` rules, which let nobody else read a thread at all — so
 * anyone else notified here would be told about a message they cannot open.
 *
 * The recipient is derived from the thread id rather than read off the
 * message, for the same reason the rules derive it: the id IS the pair
 * (`{a}__{b}`, sorted — see `ClubThread.idFor`), so there is nothing to trust
 * and nothing to look up. A message whose id does not decompose into two
 * clubs, or whose sender is not one of them, is not a message this function
 * has anything to say about.
 *
 * Digest-aware. Two clubs arranging a fixture on a Saturday morning send each
 * other a dozen messages, and a buzz per line is how an owner learns to mute
 * the whole category.
 */
export const onClubMessageSent = onDocumentCreated(
  'clubThreads/{threadId}/messages/{messageId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const pair = String(event.params.threadId).split('__');
    if (pair.length !== 2) return;

    const senderOrgId = data.senderOrgId;
    const recipientOrgId = pair.find((id) => id !== senderOrgId);
    if (!senderOrgId || !recipientOrgId || !pair.includes(senderOrgId)) return;

    const [senderOrg, recipientMembers] = await Promise.all([
      db.collection('orgs').doc(senderOrgId).get(),
      db.collection('orgs').doc(recipientOrgId).collection('members')
        .where('status', '==', 'active')
        .where('role', '==', 'owner')
        .get(),
    ]);

    const uids = recipientMembers.docs.map((d) => d.id);
    if (uids.length === 0) return;

    // The preview, not the message. A club's fixture terms are its own
    // business, and a lock-screen is the one place in this product where
    // somebody else is reading over the recipient's shoulder.
    const body = typeof data.text === 'string' && data.text.trim().length > 0
      ? previewOf(data.text)
      : 'Shared something with your club.';

    await sendToUsersDigestAware(uids, notification({
      id: `club_msg_${event.params.threadId}_${event.params.messageId}`,
      type: 'club_message',
      title: `${senderOrg.get('name') ?? 'A club'} messaged you`,
      body,
      route: '/network/t/:threadId',
      params: { threadId: event.params.threadId },
    }));
  },
);

/**
 * A join request being approved.
 *
 * Goes to exactly one person — the applicant — and it is the notification that
 * closes a loop the person themselves opened, which is why it is not marked
 * critical: missing it is annoying, not costly. The membership is still there
 * the next time they open the app.
 */
export const onMembershipApproved = onDocumentUpdated(
  'orgs/{orgId}/members/{memberUid}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;
    if (after.status !== 'active') return;

    const { orgId, memberUid } = event.params;
    const org = await db.collection('orgs').doc(orgId).get();

    await sendToUsersDigestAware([memberUid], notification({
      id: `member_active_${orgId}_${memberUid}`,
      type: 'membership_approved',
      title: org.get('name') ?? 'Your club',
      body: 'You are in. Your events and matches are waiting.',
      route: '/org/:orgId',
      params: { orgId },
    }));
  },
);

/**
 * A member being pulled off the reserves and into a squad.
 *
 * The most time-critical notification in the product: somebody who was told
 * they were a reserve is now expected on a ground, possibly the next morning,
 * and they have no reason to open the app to find out.
 */
export const onSquadPromotion = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}/squadEntries/{memberUid}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status !== 'waitlisted' || after.status !== 'confirmed') return;

    const { orgId, compId, fixtureId, memberUid } = event.params;
    const fixture = await db
      .collection('orgs').doc(orgId)
      .collection('competitions').doc(compId)
      .collection('fixtures').doc(fixtureId)
      .get();

    await sendToUsers([memberUid], notification({
      id: `squad_promoted_${fixtureId}_${memberUid}`,
      type: 'match_start',
      title: 'You are playing',
      body: `A place opened up in ${fixture.get('entrantAName') ?? 'the squad'} v `
        + `${fixture.get('entrantBName') ?? 'the opposition'}. You are in the side.`,
      route: '/org/:orgId/event/:compId',
      params: { orgId, compId },
    }));
  },
);

/**
 * The same, one level up: a place opening in an event's field.
 */
export const onRegistrationPromotion = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}/registrations/{memberUid}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status !== 'waitlisted' || after.status !== 'confirmed') return;

    const { orgId, compId, memberUid } = event.params;
    const comp = await db
      .collection('orgs').doc(orgId)
      .collection('competitions').doc(compId)
      .get();

    await sendToUsers([memberUid], notification({
      id: `reg_promoted_${compId}_${memberUid}`,
      type: 'event_reminder',
      title: comp.get('name') ?? 'You are in',
      body: 'A place opened up and you were next on the waitlist. You are in.',
      route: '/org/:orgId/event/:compId',
      params: { orgId, compId },
    }));
  },
);

/**
 * Awards ranking points when a tournament is closed.
 *
 * ## Why this is a trigger and not a client write
 *
 * A ranking table decides seeding, selection and funding, which makes it the
 * most valuable thing in this database to forge. Ratings and career stats are
 * currently client-written, and that is a known weakness; repeating it for a
 * ranking list would be a worse one. `rankingEntries` is therefore written
 * only from here, and `firestore.rules` denies every client write to it.
 *
 * ## Why on completion rather than per result
 *
 * How far somebody got is not knowable until the event is over. A player top
 * of a group on Saturday morning is not a group winner, and awarding as
 * results land would mean issuing points and then taking them back — which,
 * on a table people are selected from, is worse than waiting.
 *
 * ## Idempotency
 *
 * The entry id is deterministic — `{tournamentId}_{compId}_{entrantId}` — so
 * re-running this, or an organizer reopening and re-closing a tournament,
 * overwrites the same documents rather than paying anybody twice.
 */
export const onTournamentCompleted = onDocumentUpdated(
  'orgs/{orgId}/tournaments/{tournamentId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === 'completed' || after.status !== 'completed') return;

    const { orgId, tournamentId } = event.params;
    const grade = after.grade ?? 'club';

    const events = await db
      .collection(`orgs/${orgId}/competitions`)
      .where('tournamentId', '==', tournamentId)
      .get();
    if (events.empty) {
      logger.info(`Tournament ${tournamentId} closed with no events.`);
      return;
    }

    const awardedAt = new Date();
    const expiresAt = new Date(
      awardedAt.getTime() + WINDOW_DAYS * 24 * 60 * 60 * 1000,
    );

    let written = 0;
    let batch = db.batch();
    let inBatch = 0;
    const notifiable = [];

    for (const compDoc of events.docs) {
      const comp = compDoc.data();
      const fixturesSnap = await compDoc.ref.collection('fixtures').get();
      const fixtures = fixturesSnap.docs.map((d) => d.data());

      // Only a finished event awards anything. An abandoned draw, or one the
      // organizer never completed, has no finishing positions to score.
      const unfinished = fixtures.some(
        (f) => f.status !== 'completed' && f.status !== 'walkover',
      );
      if (unfinished || fixtures.length === 0) continue;

      const awards = awardsFor({
        format: comp.format ?? 'knockout',
        grade,
        fixtures,
      });
      if (awards.length === 0) continue;

      // Entrant ids are the player's uid for individual events; for team
      // events they are not, and a team cannot hold a personal ranking. Those
      // are skipped rather than credited to a team id that no profile reads.
      const entrantsSnap = await compDoc.ref.collection('entrants').get();
      const uidByEntrant = new Map();
      for (const d of entrantsSnap.docs) {
        const uid = d.data().uid;
        if (uid) uidByEntrant.set(d.id, uid);
      }

      for (const award of awards) {
        const uid = uidByEntrant.get(award.entrantId);
        if (!uid) continue;

        const id = `${tournamentId}_${compDoc.id}_${award.entrantId}`;
        batch.set(db.collection('rankingEntries').doc(id), {
          uid,
          entrantId: award.entrantId,
          displayName: award.displayName,
          orgId,
          tournamentId,
          tournamentName: after.name ?? 'Tournament',
          grade,
          compId: compDoc.id,
          eventName: comp.name ?? 'Event',
          sportId: comp.sportId ?? 'unknown',
          categoryLabel: comp.category?.label ?? 'Open',
          round: award.round,
          points: award.points,
          awardedAt,
          expiresAt,
        });
        notifiable.push({
          uid,
          round: award.round,
          eventName: comp.name ?? 'Event',
          points: award.points,
        });
        written += 1;
        inBatch += 1;

        // Firestore caps a batch at 500 writes.
        if (inBatch >= 400) {
          await batch.commit();
          batch = db.batch();
          inBatch = 0;
        }
      }
    }

    if (inBatch > 0) await batch.commit();
    logger.info(
      `Tournament ${tournamentId}: wrote ${written} ranking entries.`,
    );

    // Tell people what they got.
    //
    // This is the whole point of the ledger from a player's side: a result
    // that changes nothing anybody can see is the Telegram channel again. One
    // notification per person, not per event — somebody entered in singles,
    // doubles and mixed should not get three buzzes for one afternoon.
    const byUid = new Map();
    for (const award of notifiable) {
      const row = byUid.get(award.uid) ?? { best: award, total: 0, count: 0 };
      if (award.points > row.best.points) row.best = award;
      row.total += award.points;
      row.count += 1;
      byUid.set(award.uid, row);
    }

    // Built through `notification()` like every other send in this file, and
    // not by hand. A hand-rolled payload carried a bare `route` key and no
    // `id`; the client reads `deepLinkRoute` (see `DeepLink.fromDataPayload`),
    // so the one notification a player most wants to tap was the one that
    // opened nothing.
    for (const [uid, row] of byUid) {
      const others = row.count - 1;
      await sendToUsers([uid], notification({
        id: `tournament_result_${tournamentId}_${uid}`,
        type: 'result',
        title: `${after.name ?? 'Tournament'} — your result`,
        body:
          `${ROUND_LABEL[row.best.round] ?? 'Took part'} in ` +
          `${row.best.eventName}` +
          (others > 0
            ? `, plus ${others} more event${others === 1 ? '' : 's'}`
            : '') +
          // The total across every event they entered, which is what the
          // "plus N more" clause is promising to account for.
          `. ${row.total} ranking points.`,
        route: '/org/:orgId/live-tournament/:tournamentId',
        params: { orgId, tournamentId },
      }));
    }
  },
);

/**
 * Settles ratings and career statistics when a match finishes.
 *
 * ## Why this is a trigger
 *
 * `firestore.rules` had narrowed client rating writes a long way — assigned
 * scorer only, on a fixture the target actually played in, every field typed
 * and bounded, one game at a time. What it could not check, and said so in its
 * own comment, is whether a bounded single-game delta corresponds to a real
 * result or to a small self-serving nudge repeated over a season. Career
 * tallies were weaker still: they went through `FieldValue.increment()`, whose
 * resolved value rules cannot see, so they were never range-checked at all.
 *
 * Reading the fixture here removes the question entirely. The numbers come
 * from the match, not from whoever happened to be holding the scoring pad.
 *
 * ## Result types are honoured
 *
 * A walkover, a no-show, a disqualification and a concession all produce a
 * winner and none of them is evidence about anybody's skill. Rating those
 * would let a player climb on opponents who never turned up.
 *
 * ## Idempotency
 *
 * `settledFixtures` on each rating document records which matches have already
 * moved it. A retried trigger, or an organizer reopening and re-finishing a
 * match, cannot pay the same result twice.
 */
export const onMatchSettled = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // -----------------------------------------------------------------
    // Career statistics, settled independently of the rating.
    //
    // Independently, because a rating has preconditions a career record does
    // not: Glicko needs a rated opponent, so a match played against a guest
    // moves nobody's rating and must still count on both players' records.
    // `careerContributions` (career.js) applies the client's own rule — the one
    // in `ScopedStats.forPlayer` and `Fixture.countsTowardsRecords` — so the
    // two halves of the product agree by construction rather than coincidence.
    //
    // Credited AND reversed here: an organizer who awarded a walkover to the
    // wrong side, or abandoned a match for a shower that passed, withdraws the
    // ruling and the fixture goes back to `live`
    // (`ScoringService.clearFixtureOutcome`). The credit has to come back off
    // with it, or the appearance and the win stay on both squads' records
    // forever and the real result is never counted.
    //
    // Both directions run inside a transaction that re-reads the fixture, so
    // the decision is made against the match as it IS and not as this
    // invocation's snapshot remembers it — see settlement.js for the reopen
    // race that made the difference matter, and for why each credit records
    // exactly what it added. `previous` is consulted only for fixtures credited
    // before that record existed.
    // -----------------------------------------------------------------
    const careerOutcome = await settleCareer(event.data.after.ref, {
      orgId: event.params.orgId,
      previous: before,
    });
    if (careerOutcome) {
      logger.info(
        `Fixture ${event.params.fixtureId}: career records ${careerOutcome}.`,
      );
    }

    // -----------------------------------------------------------------
    // What the officials actually did.
    //
    // `UmpireProfile.matchesOfficiated` existed from the day the registry
    // shipped and was written by nothing. Registration set it to 0, the
    // directory displayed it, and `UmpireRepository.watchUmpires` SORTED on
    // it — so every official ranked equally on a field that was zero for
    // everybody, and a fifteen-year veteran presented exactly as a person who
    // signed up that morning. Same bug class as the ground `isVerified` tick:
    // a number with no process behind it is worse than no number, because it
    // states something about a person that is not true.
    //
    // Counted on the transition into a resulted status, not on assignment: an
    // official named on a fixture that never happened has not officiated
    // anything, and a scheduled-match count would be a count of an
    // organizer's intentions.
    //
    // Its own marker rather than riding `careerSettledAt`, because that one is
    // only written when there were career contributions to make — a match
    // between two guest sides credits nobody's career and would have left the
    // umpire uncounted forever.
    //
    // Reversed on the same transition as the career totals, for the same
    // reason: an official credited for a walkover that was then withdrawn has
    // not officiated a match, and a marker left behind would additionally stop
    // them being credited when the match is actually played.
    //
    // Same transactional footing too — an officiating credit stranded by a
    // reopened match is the career bug wearing a different number.
    // settleOfficials records which umpires it actually credited, so a
    // withdrawal takes back exactly those rather than recomputing from a list
    // that may have changed in between.
    const officialsOutcome = await settleOfficials(event.data.after.ref, {
      orgId: event.params.orgId,
      compId: event.params.compId,
      fixtureId: event.params.fixtureId,
      previous: before,
    });
    if (officialsOutcome) {
      logger.info(
        `Fixture ${event.params.fixtureId}: ` +
          `officiating credit ${officialsOutcome}.`,
      );
    }

    const wasDone = before.status === 'completed';
    const isDone = after.status === 'completed';
    if (wasDone || !isDone) return;

    // WHERE the match was played decides whether it moves a rating.
    //
    // Glicko is for organised competition only — a season, a tournament or a
    // league table. A single match and a challenge are arranged, staffed and
    // scored by the people playing them: no draw, no organiser who did not want
    // either side to win, no confirmation from the other end. That is the same
    // unverifiable setup the Arena keeps out of every rating (see arena.js),
    // and Glicko is the most valuable thing in this database to forge, since it
    // travels onto rosters, ranking boards and scout searches.
    //
    // Stats still settle for every one of them above — career totals, the
    // sport tally, appearances, officiating credit. A challenge is a real match
    // and counts as one everywhere a match is counted. Only the rating is
    // withheld. See rating_eligibility.js, which also covers result types and
    // fixtures too old to carry a `sourceType`.
    const withheldReason = ratingWithheldReason(after);
    if (withheldReason) {
      logger.info(
        `Fixture ${event.params.fixtureId}: not rated (${withheldReason}).`,
      );
      return;
    }

    // The right to settle this match's ratings, claimed atomically before any
    // arithmetic: the claim re-reads the fixture and stamps `ratingSettledAt`
    // only if it is still completed and still unclaimed.
    //
    // Reading the marker off `after` instead was a snapshot of a moment that
    // may already have passed — two invocations racing over one finished match
    // could both find it unset and both pay it, and a match reopened while this
    // ran was rated on a result that no longer stood. The per-player
    // `settledFixtures` list stays as a second line of defence only: it is
    // bounded, so it forgets, which is exactly how a re-finished match used to
    // be paid for twice.
    if (!(await claimRatingSettlement(event.data.after.ref))) {
      logger.info(
        `Fixture ${event.params.fixtureId}: rating already settled, or the ` +
          'match was reopened before it could be.',
      );
      return;
    }

    const { fixtureId } = event.params;
    // Mirrors `Fixture.ratingKey`. Chess is rated per time control (§7.11) —
    // bullet and classical measure different skills — and every other sport
    // rates as itself. Settling under the bare sport id instead wrote to a
    // document the client never reads, so a chess rating silently stayed at
    // its 1500 default forever.
    const ratingKey = ratingKeyFor(after);

    // uid -> the engine's own player id, needed to look up this player's
    // tally (PlayerTally keys by player id, not by uid — see career.js).
    const playerIdByUid = new Map();
    for (const p of [...(after.lineupA ?? []), ...(after.lineupB ?? [])]) {
      if (p?.uid) playerIdByUid.set(p.uid, p.id);
    }
    // Individual sport matches name nobody in a lineup, so the account behind
    // a side comes off the fixture itself.
    //
    // `entrantAUid`/`entrantBUid` are preferred over the entrant id because
    // they are the field the CLIENT derives `playerUids` from, and the field
    // the rules freeze once the match completes. Reading anything else here is
    // how this trigger and the career screens came to disagree about the same
    // match in the first place — settlement counted a chess game that the
    // player's own match list could not see. One source, one answer.
    //
    // The entrant-id fallback stays for fixtures written before those fields
    // existed and not yet reached by `backfillFixtureParticipants`: for an
    // individual entrant the document id IS the uid (see
    // `CompetitionRepository.closeEntries`), which is what made the old
    // heuristic work. Each side is handled independently to cover mixed
    // fixtures where one side has a line-up and the other does not.
    const soloA =
      after.entrantAUid ??
      ((after.lineupA ?? []).length === 0 ? after.entrantAId : null);
    const soloB =
      after.entrantBUid ??
      ((after.lineupB ?? []).length === 0 ? after.entrantBId : null);

    // scoreState.players is keyed by that same id for these matches, so
    // mapping uid -> uid is what lets playerTally() find the tally.
    if (soloA) playerIdByUid.set(soloA, soloA);
    if (soloB) playerIdByUid.set(soloB, soloB);

    // Who played, per side.
    const sideA = (after.lineupA ?? [])
      .map((p) => p.uid)
      .filter(Boolean);
    const sideB = (after.lineupB ?? [])
      .map((p) => p.uid)
      .filter(Boolean);
    if (sideA.length === 0 && soloA) sideA.push(soloA);
    if (sideB.length === 0 && soloB) sideB.push(soloB);
    if (sideA.length === 0 || sideB.length === 0) return;

    // Compared explicitly rather than by `===` alone: a fixture missing BOTH
    // fields makes `undefined === undefined` true and hands side A a win it
    // never earned.
    const winner = after.winnerEntrantId;
    const isDraw = after.isDraw === true;
    if (!isDraw && typeof winner !== 'string') {
      logger.info(`Fixture ${fixtureId}: no winner recorded, not rated.`);
      return;
    }
    const aWon = winner === after.entrantAId;

    // How much each player contributed, from the same tally the MVP award and
    // the client's projection read. §8.1 is explicit that a team result must
    // not be distributed as pure win/loss — the eleventh man and the centurion
    // moving identically is exactly what it forbids — and this trigger did
    // precisely that until now.
    const weights = new Map([
      ...contributionWeights(after.scoreState, after.lineupA ?? []),
      ...contributionWeights(after.scoreState, after.lineupB ?? []),
    ]);

    // Current ratings for everybody involved.
    const current = new Map();
    for (const uid of [...sideA, ...sideB]) {
      const snap = await db.doc(`users/${uid}/ratings/${ratingKey}`).get();
      const d = snap.exists ? snap.data() : null;
      current.set(uid, {
        rating: d?.rating ?? DEFAULT_RATING,
        deviation: d?.deviation ?? DEFAULT_DEVIATION,
        volatility: d?.volatility ?? DEFAULT_VOLATILITY,
        gamesPlayed: d?.gamesPlayed ?? 0,
        settled: d?.settledFixtures ?? [],
        trail: Array.isArray(d?.trail) ? d.trail : [],
      });
    }

    const average = (uids) => {
      const rs = uids.map((u) => current.get(u)?.rating ?? DEFAULT_RATING);
      return rs.reduce((s, r) => s + r, 0) / rs.length;
    };
    const avgA = average(sideA);
    const avgB = average(sideB);

    // The opponent's real uncertainty, not a hardcoded 350. A side whose
    // players are all established should move a rating further than one nobody
    // has a reading on, and pinning the opponent at the maximum deviation
    // flattened that distinction away.
    const avgDeviation = (uids) => {
      const ds = uids.map((u) => current.get(u)?.deviation ?? DEFAULT_DEVIATION);
      return ds.reduce((s, d) => s + d, 0) / ds.length;
    };
    const rdA = avgDeviation(sideA);
    const rdB = avgDeviation(sideB);

    const batch = db.batch();
    let settled = 0;

    // One instant for every trail entry this match writes. Calling
    // `new Date()` per player would stamp the same match with times a few
    // milliseconds apart, which is harmless for ordering but makes two
    // teammates' trails disagree about when their shared match happened.
    const settledAt = new Date();

    for (const [uids, opponentAvg, opponentRd, won] of [
      [sideA, avgB, rdB, aWon],
      [sideB, avgA, rdA, !aWon],
    ]) {
      const score = isDraw ? 0.5 : won ? 1 : 0;
      for (const uid of uids) {
        const player = current.get(uid);
        // Already paid for this match.
        if (player.settled.includes(fixtureId)) continue;

        const next = rate(player, [
          {
            opponent: { rating: opponentAvg, deviation: opponentRd },
            score,
            weight: weights.get(uid) ?? 1,
          },
        ]);

        batch.set(
          db.doc(`users/${uid}/ratings/${ratingKey}`),
          {
            rating: next.rating,
            deviation: next.deviation,
            volatility: next.volatility,
            gamesPlayed: next.gamesPlayed,
            // Second line of defence only. The durable guard is
            // `ratingSettledAt` on the fixture — this list is bounded and
            // therefore forgets, which is precisely how a re-finished match
            // used to be paid for twice. Kept because it catches a retry of
            // THIS invocation, and because rating documents already carry it.
            settledFixtures: [...player.settled, fixtureId].slice(-50),
            // The rating's own history, and the only record of it anywhere.
            //
            // A rating document holds a single mutable number, so before this
            // trail existed the product could say how good a player IS and had
            // no way at all to say whether they were getting better — which is
            // the signal talent discovery actually runs on (see
            // `lib/domain/scout/talent_trend.dart`). Nothing can reconstruct
            // it after the fact: the previous value is overwritten right here.
            //
            // Bounded for the same reason `settledFixtures` is: an array that
            // grows for a whole career eventually becomes the largest thing in
            // the document and is re-read on every single match. TRAIL_LENGTH
            // snapshots is roughly five months for a weekly player, comfortably
            // longer than the 90-day window the boards measure over.
            trail: [
              ...player.trail,
              { r: next.rating, t: settledAt.toISOString() },
            ].slice(-TRAIL_LENGTH),
            updatedAt: new Date(),
          },
          { merge: true },
        );

        settled += 1;
      }
    }

    // No marker write here any more: `claimRatingSettlement` stamped it in a
    // transaction before any of this arithmetic ran, which is what stops two
    // invocations paying the same match. Writing it again would be harmless but
    // would record the wrong moment — the instant the ratings landed rather
    // than the instant this fixture stopped being available to settle.
    await batch.commit();
    logger.info(`Fixture ${fixtureId}: settled ${settled} player ratings.`);

    // The headline composite on each player's profile, refreshed the moment
    // the ratings under it move — a player should walk off the pitch with
    // their number already changed, not find out at 3am when the nightly pass
    // runs. See `functions/overall_glicko.js` for why this is denormalised
    // onto the user document at all.
    //
    // Deliberately after the commit and outside it. This is a derived display
    // value: if it fails, the ratings it derives from are already safely
    // written and tonight's scheduled pass will produce the same answer.
    // Folding it into the batch above would mean a hiccup computing a rounded
    // number for a card could roll back a settled match result.
    try {
      const refreshed = await refreshOverallForUids(
        [...sideA, ...sideB],
        settledAt,
      );
      logger.info(
        `Fixture ${fixtureId}: refreshed ${refreshed.updated} overall ratings.`,
      );
    } catch (err) {
      logger.warn(
        `Fixture ${fixtureId}: overall rating refresh failed, ` +
          'leaving it to the nightly pass.',
        err,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// Give — the equipment-donation network's impact dashboard.
//
// `giveDonations` and `giveNeeds` are staff/console-written past their first
// stage (see firestore.rules), so these two triggers are the only place the
// aggregate at `give/impactStats` ever moves. Both use FieldValue.increment
// rather than reading the collection, for the same reason ratings do above:
// counting "every donation ever made" on every write would get slower and
// more expensive as the network's whole point — real volume — arrives.
// ---------------------------------------------------------------------------

/** Sum of `quantity` across a donation's equipment lines. */
function itemCountOf(donation) {
  if (!Array.isArray(donation.items)) return 0;
  return donation.items.reduce((sum, i) => sum + (Number(i.quantity) || 0), 0);
}

/**
 * Who is on call for one staff queue.
 *
 * `platformStaff` exists because the thing that actually GRANTS staff access —
 * the `admin` custom claim — cannot be queried. Claims live on auth tokens,
 * and there is no "list every account whose token carries admin" short of
 * walking every user in the project. So before this roster existed, an ad
 * campaign submission, a donation and a raised need each landed in Firestore
 * with nobody to notify, and were only ever discovered by somebody choosing to
 * go and look.
 *
 * Returns [] on any failure rather than throwing: a notification that cannot
 * find its recipients must not take the trigger down with it, because the
 * trigger's other job (the impact tally below) is the one that cannot be
 * reconstructed later. See `StaffMember` in
 * lib/core/models/platform_staff.dart.
 */
async function staffUidsForDesk(desk) {
  try {
    const snap = await db.collection('platformStaff')
      .where('desks', 'array-contains', desk)
      .get();
    return snap.docs.map((d) => d.id);
  } catch (error) {
    logger.warn('staff lookup failed', { desk, error: String(error) });
    return [];
  }
}

export const onDonationCreated = onDocumentCreated(
  'giveDonations/{donationId}',
  async (event) => {
    await db.doc('give/impactStats').set(
      {
        donationsCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // Tell the Give desk something has arrived. A donation is a person
    // standing somewhere with a bag of kit expecting to be met, so the value
    // of this notification decays in hours — but it is deliberately routed
    // through the digest like every other non-critical type, because a team
    // of four woken individually by every donation stops reading any of them.
    const data = event.data?.data();
    if (!data) return;
    const staff = await staffUidsForDesk('give');
    if (staff.length === 0) return;

    const isMoney = data.type === 'money';
    await sendToUsersDigestAware(staff, notification({
      id: `give_donation_${event.params.donationId}`,
      type: 'give_donation_submitted',
      title: isMoney ? 'A money pledge came in' : 'A kit donation came in',
      body: [
        data.donorName || 'Someone',
        isMoney
          ? `pledged \u20B9${Math.round((data.amountPaise || 0) / 100)}`
          : `is donating ${itemCountOf(data)} item(s)`,
        data.city ? `in ${data.city}` : null,
      ].filter(Boolean).join(' '),
      route: '/ops/give',
    }));
  },
);

/**
 * A club has raised a shortfall.
 *
 * Worth its own trigger rather than a branch of the donation one, and for a
 * sharper reason than tidiness: an unverified need is INVISIBLE — see
 * `GiveRepository.watchVerifiedNeeds`. Until somebody on the Give desk
 * verifies it, no donor in the country can see that a village club is six
 * pairs of pads short. Silence here is not a missed notification, it is a need
 * that never reaches the board at all.
 */
export const onGiveNeedRaised = onDocumentCreated(
  'giveNeeds/{needId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const staff = await staffUidsForDesk('give');
    if (staff.length === 0) return;

    await sendToUsersDigestAware(staff, notification({
      id: `give_need_${event.params.needId}`,
      type: 'give_need_raised',
      title: 'A need needs verifying',
      body: [
        data.title || 'A shortfall was raised',
        data.orgName || data.playerName,
        data.city,
      ].filter(Boolean).join(' — '),
      route: '/ops/give/needs',
    }));
  },
);

/**
 * Telling a donor their kit moved.
 *
 * The traceability promise `GiveDonation`'s class doc makes — "delivered to a
 * club in Telangana" — was previously only kept if the donor opened the app
 * and checked. Only the two stages a donor can act on or celebrate are worth a
 * push; the seven intermediate ones are visible on their own screen and
 * notifying each would turn one donation into nine buzzes.
 */
export const onDonationStageNotified = onDocumentUpdated(
  'giveDonations/{donationId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    if (!['collected', 'distributed', 'rejected'].includes(after.status)) return;
    if (!after.donorUid) return;

    const title = after.status === 'collected'
      ? 'Your donation has been collected'
      : after.status === 'distributed'
        ? 'Your donation reached a player'
        : 'One of your donated items could not be reused';

    await sendToUsersDigestAware([after.donorUid], notification({
      id: `give_stage_${event.params.donationId}_${after.status}`,
      type: 'give_donation_advanced',
      title,
      body: after.status === 'rejected'
        ? 'It was not safe to pass on. Thank you for offering it.'
        : 'Follow the rest of its journey in My donations.',
      route: '/give/mine',
    }));
  },
);

/**
 * An advertiser has submitted a campaign.
 *
 * This is the trigger the advertising feature shipped without. A campaign
 * landed `pending` and the only path to approval was somebody opening the
 * Firebase console — so an advertiser's submission genuinely went nowhere,
 * and the product had no way to tell its owner otherwise. See
 * `AdReviewScreen`.
 */
export const onAdCampaignSubmitted = onDocumentCreated(
  'adCampaigns/{campaignId}',
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== 'pending') return;
    const staff = await staffUidsForDesk('ads');
    if (staff.length === 0) return;

    await sendToUsersDigestAware(staff, notification({
      id: `ad_submitted_${event.params.campaignId}`,
      type: 'ad_campaign_submitted',
      title: 'A campaign is waiting for approval',
      body: [
        data.advertiserName || 'An advertiser',
        data.headline ? `— "${data.headline}"` : null,
      ].filter(Boolean).join(' '),
      route: '/ops/ads',
    }));
  },
);

/**
 * The advertiser hearing back.
 *
 * `reviewNote` carries the reason a reviewer typed, and putting it in the body
 * is the whole point of having asked for one — see `AdRepository.review`.
 */
export const onAdCampaignReviewed = onDocumentUpdated(
  'adCampaigns/{campaignId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;
    if (!after.advertiserUid) return;

    const titles = {
      approved: 'Your campaign is live',
      rejected: 'Your campaign was not approved',
      paused: 'Your campaign has been paused',
    };
    const title = titles[after.status];
    if (!title) return;

    await sendToUsersDigestAware([after.advertiserUid], notification({
      id: `ad_reviewed_${event.params.campaignId}_${after.status}`,
      type: 'ad_campaign_reviewed',
      title,
      body: after.reviewNote
        || (after.status === 'approved'
          ? 'It will start appearing in the slots you chose.'
          : 'Open the advertising console for details.'),
      route: '/ads',
    }));
  },
);

export const onDonationStatusChanged = onDocumentUpdated(
  'giveDonations/{donationId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    const count = itemCountOf(after);
    if (count <= 0) return;

    const field = after.status === 'collected' ? 'itemsCollected'
      : after.status === 'distributed' ? 'itemsDistributed'
      : null;
    if (!field) return;

    await db.doc('give/impactStats').set(
      { [field]: FieldValue.increment(count), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  },
);

export const onNeedStatusChanged = onDocumentUpdated(
  'giveNeeds/{needId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    // Only the transition INTO fulfilled counts — a need re-saved while
    // already fulfilled, or one that regresses out of it, must not double
    // count or undercount the tally either way.
    if (after.status !== 'fulfilled' || before.status === 'fulfilled') return;

    await db.doc('give/impactStats').set(
      {
        needsFulfilled: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  },
);

/**
 * Sponsor an Athlete / Sponsor a Team.
 *
 * `sponsorshipListings.sponsorsCount` is function-written for the same
 * reason `GiveImpactStats` is: a client incrementing its own credit count is
 * a client deciding how impressive it looks, not a fact anyone can trust.
 * See `firestore.rules` on `sponsorshipListings` — the client cannot move
 * this field itself.
 */

export const onSponsorPledgeCreated = onDocumentCreated(
  'sponsorPledges/{pledgeId}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const listingSnap = await db.doc(`sponsorshipListings/${data.listingId}`).get();
    const listing = listingSnap.data();
    if (!listing?.createdByUid) return;

    await sendToUsersDigestAware([listing.createdByUid], notification({
      id: `sponsor_pledge_${event.params.pledgeId}`,
      type: 'sponsor_pledge_received',
      title: `${data.sponsorDisplayName ?? 'A sponsor'} has offered to help`,
      body: data.message?.trim() ? data.message : 'Review the offer and respond.',
      route: '/sponsor/listings/:listingId/offers',
      params: { listingId: data.listingId },
    }));
  },
);

export const onSponsorPledgeStatusChanged = onDocumentUpdated(
  'sponsorPledges/{pledgeId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status) return;

    // Only the transition INTO accepted moves the count — a pledge later
    // withdrawn or re-saved must not have been possible from `accepted` in
    // the first place (rules only allow accepted/declined from pending), so
    // this increment fires exactly once per pledge, ever.
    if (after.status === 'accepted') {
      await db.doc(`sponsorshipListings/${after.listingId}`).set(
        { sponsorsCount: FieldValue.increment(1) },
        { merge: true },
      );
    }

    if (after.status === 'accepted' || after.status === 'declined') {
      await sendToUsersDigestAware([after.sponsorUid], notification({
        id: `sponsor_pledge_resolved_${event.params.pledgeId}`,
        type: 'sponsor_pledge_resolved',
        title: after.status === 'accepted'
          ? 'Your sponsorship offer was accepted'
          : 'Your sponsorship offer was declined',
        body: after.status === 'accepted'
          ? 'Thank you for backing them — you are now a recognised sponsor.'
          : 'The listing owner chose not to proceed this time.',
        route: '/sponsor/mine',
      }));
    }
  },
);

/**
 * A club asking who is free, and a member finding out they have promised to be
 * in two places at once.
 *
 * Both live in one trigger because both are the same document changing: a
 * match availability call is an announcement carrying a `match` block and a
 * poll, and the votes ARE the poll. Splitting them would mean two functions
 * fighting over the same write.
 */
export const onMatchRsvp = onDocumentWritten(
  'orgs/{orgId}/announcements/{announcementId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;

    // Only match calls. An ordinary club notice or an ordinary poll passes
    // through here too and must fall straight out.
    const match = after.match;
    if (!match || typeof match !== 'object' || !match.matchDate) return;

    const { orgId, announcementId } = event.params;
    const kickOff = match.matchDate.toDate
      ? match.matchDate.toDate()
      : new Date(match.matchDate);

    // --- The call itself -----------------------------------------------
    //
    // On creation only. An organizer fixing a typo in the venue must not
    // re-notify the whole club, and every vote is an update to this same
    // document — without this test the club would be pushed once per answer.
    if (!before) {
      const members = await activeMemberUids(orgId);
      // A call may name its audience — see `MatchCall.invitedUids`. A club of
      // 120 asking about an eleven-a-side match wants the twenty who might
      // travel, and pushing the other hundred is exactly what the naming was
      // for. Still intersected with the membership so a uid left over from
      // someone who has since left the club is not notified.
      const invited = Array.isArray(match.invitedUids) ? match.invitedUids : [];
      const audience = invited.length === 0
        ? members
        : members.filter((u) => invited.includes(u));
      const recipients = audience.filter((u) => u !== after.authorUid);
      await sendToUsers(recipients, notification({
        id: `match_rsvp_${announcementId}`,
        type: 'match_rsvp',
        title: after.title || 'Match on',
        body: `${formatKickOff(kickOff)}`
          + `${match.venue ? ` at ${match.venue}` : ''}`
          + ' — are you in?',
        route: '/home',
        params: { orgId },
      }));
      return;
    }

    // --- Clashes --------------------------------------------------------
    //
    // Fired for whoever just said yes, and only for them. Recomputing every
    // member's diary on every vote would be a full scan of the club's notice
    // board per tap; the person who changed their answer is the only one
    // whose diary can have changed.
    const newYesUids = newlyConfirmed(before, after);
    if (newYesUids.length === 0) return;

    const others = await db.collection('orgs').doc(orgId)
      .collection('announcements').get();

    for (const uid of newYesUids) {
      const clashes = [];
      others.forEach((doc) => {
        if (doc.id === announcementId) return;
        const other = doc.data();
        const otherMatch = other.match;
        if (!otherMatch?.matchDate) return;
        if (other.poll?.votes?.[uid] !== RSVP_YES) return;
        const when = otherMatch.matchDate.toDate
          ? otherMatch.matchDate.toDate()
          : new Date(otherMatch.matchDate);
        if (Math.abs(when.getTime() - kickOff.getTime()) < CLASH_WINDOW_MS) {
          clashes.push(other.title || 'another match');
        }
      });

      if (clashes.length === 0) continue;

      await sendToUsers([uid], notification({
        id: `match_clash_${announcementId}_${uid}`,
        type: 'match_clash',
        title: 'You are booked twice',
        body: `"${after.title || 'This match'}" clashes with `
          + `${clashes.length === 1 ? `"${clashes[0]}"` : `${clashes.length} other matches`}`
          + '. Both clubs are counting on you.',
        route: '/home',
        params: { orgId },
      }));
    }
  },
);

/**
 * Index of the "In" option, and the window two kick-offs must fall inside to
 * count as a clash.
 *
 * Both are WIRE FORMAT shared with the app: the index is a position in
 * `Poll.options` that is written into every vote, and the window is
 * `kClashWindow` in lib/features/home/home_providers.dart. If either moves,
 * both have to move together — a client that warns about a clash the server
 * does not notice, or the reverse, is worse than neither.
 */
const RSVP_YES = 0;
const CLASH_WINDOW_MS = 3 * 60 * 60 * 1000;

/** Members who have just said yes, and were not saying yes before. */
function newlyConfirmed(before, after) {
  const was = before?.poll?.votes ?? {};
  const now = after?.poll?.votes ?? {};
  return Object.keys(now).filter(
    (uid) => now[uid] === RSVP_YES && was[uid] !== RSVP_YES,
  );
}

/**
 * "Sun, 6:00 pm" — enough to know whether you are free without opening the app.
 *
 * Rendered in IST, not the server's clock. Functions run in UTC, so
 * `getHours()` on a 6pm Hyderabad kick-off returns 12 and the club is told
 * their evening game is at lunchtime. Same timezone every other date in this
 * file is formatted in.
 */
function formatKickOff(when) {
  return when.toLocaleString('en-IN', {
    weekday: 'short',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    timeZone: 'Asia/Kolkata',
  });
}

// ---------------------------------------------------------------------------
// The Arena — idle-game cleanup and the (deliberately Glicko-free) ladder.
// See arena.js for why both have to be server-side.
// ---------------------------------------------------------------------------
export { closeIdleArenaGames, onArenaMatchFinished } from './arena.js';
