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
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { logger } from 'firebase-functions';

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });

/**
 * Sends one notification to a set of users.
 *
 * Data-only messages, on purpose: the client model documents why (see
 * `AppNotification.toDataPayload`) — a `notification` block is displayed by
 * the OS without the app seeing it on some platforms and states, which breaks
 * deep-link routing. The title and body travel inside `data`.
 *
 * Dead tokens are pruned as they are discovered. A phone that was factory
 * reset otherwise stays in the fan-out forever, and every send to it is a
 * wasted call that slowly makes every notification slower.
 */
async function sendToUsers(uids, payload) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return;

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

/** Active members of a club. */
async function activeMemberUids(orgId, { onlyAdmins = false } = {}) {
  let query = db.collection('orgs').doc(orgId).collection('members')
    .where('status', '==', 'active');
  if (onlyAdmins) {
    query = query.where('role', 'in', ['owner', 'admin', 'eventManager']);
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

/**
 * A match going live, and a match finishing.
 *
 * Both are the same trigger because both are a status transition on the same
 * document, and splitting them would double the invocations on the hottest
 * write path in the product — a fixture is written on every ball.
 *
 * Everything here returns early unless the STATUS changed, so the ordinary
 * ball-by-ball write costs one comparison.
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
