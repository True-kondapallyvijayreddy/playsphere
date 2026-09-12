/**
 * Deleting your own account, properly.
 *
 * ## What was wrong with deleting it client-side
 *
 * `AuthService.deleteAccount` called `user.delete()`, which removes the Firebase
 * Auth credential and nothing else. `users/{uid}` stayed exactly as it was —
 * display name, email address, phone number, date of birth, photo, district —
 * and `firestore.rules` refuses to delete it (`allow delete: if false`), so no
 * client could have cleaned up even if it tried. The confirmation dialog told
 * people their sign-in was gone, which was true, and left the impression their
 * details were too, which was not.
 *
 * Google Play's data-deletion policy and India's DPDP Act both expect the
 * personal data to go, not just the login.
 *
 * ## What this keeps, and why
 *
 * The document is scrubbed in place rather than deleted. A match result, a
 * scorecard and a club's roster history are other people's records as much as
 * this person's, and every one of them points at this uid — deleting the
 * document would leave every scorecard the player appears on pointing at
 * nothing. So the identifiers go and the skeleton stays:
 *
 *   - display name, email, phone, photo and place: redacted
 *   - profile hidden (`private`) and marked deleted
 *   - `dateOfBirth` RETAINED, deliberately. Age is what every minor-safety gate
 *     in firestore.rules reads, and a null there makes those gates unanswerable
 *     for records the account still appears on. It is not reachable from
 *     anywhere once the profile is private and the login is gone.
 *
 * Past matches keep their own copies of the name as it was when they were
 * played (line-ups store a name per player), which is what makes an old
 * scorecard still legible without this document.
 *
 * ## Why Admin, and why it deletes the login itself
 *
 * A client cannot scrub a document the rules freeze, and `user.delete()` needs
 * a recent sign-in, which is where the old flow's re-authentication dance came
 * from. Doing both here removes that: the scrub happens under Admin privileges
 * and the Auth user is deleted in the same call, so there is no window where
 * the profile is wiped but the login still works, or the reverse.
 */

import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

/** What is left of a profile once its owner has gone. */
export function redactedProfile() {
  return {
    displayName: 'Deleted player',
    email: '',
    phone: null,
    photoUrl: null,
    geo: {},
    profileVisibility: 'private',
    profileComplete: false,
    deletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Why this account cannot be deleted yet, or null when it can.
 *
 * Unclaimed children are the one blocker. They are separate accounts that only
 * this one can operate — `custodianUid` points here and nothing else can mint a
 * claim code for them — so deleting the guardian would strand every one of them
 * permanently, reachable by nobody. Handing them over first is a real, finite
 * step the person can take, and the message says so.
 *
 * Pure, so the rule is checkable without a database.
 */
export function deletionRefusalReason(userData) {
  const wards = Array.isArray(userData?.managedChildUids)
    ? userData.managedChildUids
    : [];
  if (wards.length > 0) {
    return [
      'failed-precondition',
      `You are still managing ${wards.length} child profile`
        + `${wards.length === 1 ? '' : 's'}. Hand each one over to its own `
        + 'device first — open the child, then "Get code" — or ask support to '
        + 'move them, then delete your account.',
    ];
  }
  return null;
}

/**
 * Scrubs the caller's profile and deletes their sign-in, in that order.
 *
 * Ordered deliberately: if the scrub fails, nothing has been deleted and the
 * account still works, so the person can try again. The reverse order would
 * leave an un-scrubbed profile behind with no session that could ever reach it.
 */
export const deleteMyAccount = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to delete your account.');
    }

    const userRef = db().collection('users').doc(uid);
    const snap = await userRef.get();
    const refusal = deletionRefusalReason(snap.exists ? snap.data() : null);
    if (refusal) {
      const [code, message] = refusal;
      throw new HttpsError(code, message);
    }

    if (snap.exists) {
      await userRef.set(redactedProfile(), { merge: true });
    }

    // The push tokens are the other place a person's device is named. Left
    // behind, they would keep this account's notifications arriving on a phone
    // that no longer has an account on it.
    const devices = await userRef.collection('devices').get();
    await Promise.all(devices.docs.map((d) => d.ref.delete()));

    // The discovery listing is the one place the profile was deliberately
    // searchable. It is a separate document keyed by uid, and it does not go
    // private when the profile does — see `playerDirectory` in firestore.rules.
    await db().collection('playerDirectory').doc(uid).delete().catch(() => {});

    // The public code → player lookup carries a name and a photo of its own.
    // Scrubbed rather than deleted, so the code stays spent and cannot be
    // handed to somebody else later.
    await db()
      .collection('playerCodes')
      .where('uid', '==', uid)
      .get()
      .then((codes) => Promise.all(
        codes.docs.map((d) => d.ref.set(
          { displayName: 'Deleted player', photoUrl: null },
          { merge: true },
        )),
      ))
      .catch((err) => logger.warn('playerCode scrub failed', { uid, err }));

    await getAuth().deleteUser(uid);

    logger.info('account deleted', { uid, devicesCleared: devices.size });
    return { ok: true };
  },
);
