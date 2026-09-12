/**
 * Shared push + persistence primitives for `index.js` and
 * `notification_digest.js`.
 *
 * Pulled out of `index.js` rather than imported back from it: the digest
 * flush job (`notification_digest.js`) needs the same "resolve device
 * tokens, multicast, prune dead tokens" logic that every trigger in
 * `index.js` already uses, and `index.js` re-exports the digest flush job —
 * so if this lived in `index.js`, the two files would import each other.
 * Circular ES module imports between them would still work in practice (the
 * functions are only called, never read, at each other's module-init time)
 * but it is a trap for the next change, not a guarantee worth relying on.
 * This file depends on nothing in `index.js`, so the dependency only runs
 * one way.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

/**
 * Writes one notification document per recipient under
 * `users/{uid}/notifications`, regardless of whether they own a working
 * device token — see `sendToUsers` in `index.js` for why that persistence
 * is unconditional. Returns the deduplicated uid list, since every caller
 * needs it again for the push step.
 */
async function persistNotifications(uids, payload) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return unique;

  const record = { ...payload, createdAt: FieldValue.serverTimestamp(), read: false };
  await Promise.all(
    unique.map((uid) =>
      db().collection('users').doc(uid).collection('notifications').add(record)
        .catch((error) => logger.warn('notification persist failed', { uid, error: String(error) })),
    ),
  );
  return unique;
}

/**
 * Sends one data-only push to every device token belonging to `uids`,
 * pruning tokens FCM reports as dead. Does not touch Firestore beyond that
 * pruning — callers that also want the in-app record must call
 * `persistNotifications` themselves (`sendToUsers` and
 * `sendToUsersDigestAware` in `index.js` both do, at different times).
 */
async function pushToUids(uids, payload) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return;

  // Firestore `in` queries cap at 30, and a club can be far larger than
  // that, so tokens are gathered per user. These are small reads on a
  // collection that holds one document per device.
  const tokenDocs = await Promise.all(
    unique.map((uid) => db().collection('users').doc(uid).collection('devices').get()),
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

export { db, persistNotifications, pushToUids };
