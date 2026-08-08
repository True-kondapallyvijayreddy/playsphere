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

import { awardsFor, ROUND_LABEL, WINDOW_DAYS } from './ranking.js';
import { contributionWeights, ratingKeyFor } from './contribution.js';
import {
  DEFAULT_DEVIATION,
  DEFAULT_RATING,
  DEFAULT_VOLATILITY,
  rate,
} from './glicko2.js';

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });

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
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return;

  const record = { ...payload, createdAt: FieldValue.serverTimestamp(), read: false };
  // One write per recipient rather than a single batch: recipients can run
  // past Firestore's 500-writes-per-batch ceiling for a club-wide
  // announcement, and no single failure here should cancel the others'.
  await Promise.all(
    unique.map((uid) =>
      db.collection('users').doc(uid).collection('notifications').add(record)
        .catch((error) => logger.warn('notification persist failed', { uid, error: String(error) })),
    ),
  );

  // Firestore `in` queries cap at 30, and a club can be far larger than that,
  // so tokens are gathered per user. These are small reads on a collection
  // that holds one document per device.
  const tokenDocs = await Promise.all(
    unique.map((uid) => db.collection('users').doc(uid).collection('devices').get()),
  );

  /** @type {{token: string, ref: FirebaseFirestore.DocumentReference}[]} */
  const targets = [];
  tokenDocs.forEach((snap) => {
    snap.forEach((doc) => {
      const token = doc.get('token');
      if (typeof token === 'string' && token.length > 0) {
        targets.push({ token, ref: doc.ref });
      }
    });
  });

  if (targets.length === 0) return;

  // sendEachForMulticast caps at 500 tokens per call.
  const chunks = [];
  for (let i = 0; i < targets.length; i += 500) chunks.push(targets.slice(i, i + 500));

  for (const chunk of chunks) {
    const response = await getMessaging().sendEachForMulticast({
      tokens: chunk.map((t) => t.token),
      data: payload,
      android: { priority: 'high' },
      apns: { headers: { 'apns-priority': '10' } },
    });

    const dead = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error?.code ?? '';
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        dead.push(chunk[index].ref.delete());
      } else {
        logger.warn('push failed', { code, message: result.error?.message });
      }
    });
    await Promise.all(dead);
  }
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
export const onEventOpened = onDocumentUpdated(
  'orgs/{orgId}/competitions/{compId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;
    if (after.status !== 'registration_open') return;

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

    await sendToUsers(
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

    await sendToUsers(ownerUids, notification({
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
    await sendToUsers(uids, notification({
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

    await sendToUsers([memberUid], notification({
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

    const wasDone = before.status === 'completed';
    const isDone = after.status === 'completed';
    if (wasDone || !isDone) return;

    // Settled once, whenever that was.
    //
    // The per-player `settledFixtures` list below is bounded — it has to be, an
    // unbounded array on a rating document grows for a whole career — and a
    // bounded list is a bounded memory: a fixture reopened and re-finished
    // after fifty more matches had already pushed it off the end, and was paid
    // for twice. This marker lives on the fixture, so it never expires.
    //
    // Writing it back does not re-enter this trigger: the write leaves `status`
    // at `completed`, so the next invocation returns at `wasDone` above.
    if (after.ratingSettledAt) {
      logger.info(`Fixture ${event.params.fixtureId}: already settled.`);
      return;
    }

    const resultType = after.resultType ?? 'normal';
    if (resultType !== 'normal' && resultType !== 'retired') {
      logger.info(`Fixture ${event.params.fixtureId}: ${resultType}, not rated.`);
      return;
    }

    const { orgId, fixtureId } = event.params;
    const sportId = after.sportId ?? 'unknown';
    // Mirrors `Fixture.ratingKey`. Chess is rated per time control (§7.11) —
    // bullet and classical measure different skills — and every other sport
    // rates as itself. Settling under the bare sport id instead wrote to a
    // document the client never reads, so a chess rating silently stayed at
    // its 1500 default forever.
    const ratingKey = ratingKeyFor(after);

    // Who played, per side. Individual events name nobody in a line-up — the
    // entrant id is the uid — so both shapes are handled.
    const sideA = (after.lineupA ?? [])
      .map((p) => p.uid)
      .filter(Boolean);
    const sideB = (after.lineupB ?? [])
      .map((p) => p.uid)
      .filter(Boolean);
    if (sideA.length === 0 && after.entrantAId) sideA.push(after.entrantAId);
    if (sideB.length === 0 && after.entrantBId) sideB.push(after.entrantBId);
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
            updatedAt: new Date(),
          },
          { merge: true },
        );

        batch.set(
          db.doc(`users/${uid}/career_stats/${sportId}`),
          {
            uid,
            sportId,
            matchesPlayed: FieldValue.increment(1),
            wins: FieldValue.increment(score === 1 ? 1 : 0),
            draws: FieldValue.increment(score === 0.5 ? 1 : 0),
            losses: FieldValue.increment(score === 0 ? 1 : 0),
            lastPlayedAt: new Date(),
            clubsPlayedFor: FieldValue.arrayUnion(orgId),
          },
          { merge: true },
        );
        settled += 1;
      }
    }

    // Stamped in the SAME batch as the ratings it accounts for, so the marker
    // and the payment cannot come apart: either both land or neither does.
    batch.set(
      event.data.after.ref,
      { ratingSettledAt: new Date() },
      { merge: true },
    );

    await batch.commit();
    logger.info(`Fixture ${fixtureId}: settled ${settled} player ratings.`);
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

export const onDonationCreated = onDocumentCreated(
  'giveDonations/{donationId}',
  async () => {
    await db.doc('give/impactStats').set(
      {
        donationsCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
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

    await sendToUsers([listing.createdByUid], notification({
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
      await sendToUsers([after.sponsorUid], notification({
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
