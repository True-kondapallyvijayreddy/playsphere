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

import { CALLABLE_OPTS } from './app_check.js';
import { logger } from 'firebase-functions';

// The declared inventory of everywhere one person's data lives, and the
// traversal that walks it. Shared with `exportMyData` below so erasure and
// export cannot come to disagree about which collections exist.
import { eraseSubject, exportSubject } from './subject_runner.js';

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
  { ...CALLABLE_OPTS },
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

    // Everything, from the declared inventory.
    //
    // This used to be four hand-written steps — profile, devices, directory
    // listing, player code — and the review found nine more places it had
    // never heard of: the coach, practitioner, shop and official listings a
    // person publishes about themselves, their ground check-ins (a position
    // and a time), their uploaded photos and the bytes behind them, their
    // arena tally, their notification inbox, their guardian-consent records,
    // and the verification documents behind a ground they claimed — which
    // carry a home address and which firestore.rules marks undeletable by any
    // client, so once the auth user was gone nobody could ever remove them.
    //
    // The fault was structural: every feature that stores something about a
    // person had to remember to edit a function in a file it has no other
    // reason to touch. subject_data.js is the declared list instead, walked
    // here and by `exportMyData`, and a test asserts every row is reachable.
    const report = await eraseSubject(uid, {
      profileScrub: snap.exists ? redactedProfile() : null,
    });

    // The sign-in goes last, deliberately, and the ordering is the same
    // argument as before: if the sweep fails, nothing has been deleted and the
    // account still works, so the person can try again. The reverse order
    // leaves un-erased data behind with no session that could ever reach it.
    await getAuth().deleteUser(uid);

    const failures = report.filter((r) => r.error);
    if (failures.length > 0) {
      // Not thrown. The sign-in is already gone and the person is entitled to
      // that having worked; what they are not entitled to is silence about a
      // row that did not erase. Logged at error so it pages rather than
      // scrolls.
      logger.error('account deleted with incomplete erasure', { uid, failures });
    }

    logger.info('account deleted', {
      uid,
      erased: report.filter((r) => r.matched > 0).map((r) => r.row),
      failures: failures.length,
    });
    return { ok: true };
  },
);

/**
 * Hands the caller everything PlaySphere holds about them, as JSON.
 *
 * ## Why this exists
 *
 * The privacy policy has always said "ask, and we will send you your account
 * data in a machine-readable file". Nothing implemented it — there was no
 * automated path and no tooling to produce one by hand either, so the promise
 * rested on somebody writing ad-hoc queries against production. India's DPDP
 * Act gives a Data Principal the right to a summary of the personal data being
 * processed about them; Google Play's data-safety rules expect the same.
 *
 * Walks the same inventory `deleteMyAccount` erases, which is the point of the
 * inventory being declared rather than hand-written: a collection that would
 * be missed by an export is a collection that would be missed by an erasure,
 * and one list makes that impossible to get differently wrong in two places.
 *
 * ## What it does and does not include
 *
 * Everything keyed to this person: their profile, per-sport ratings, career
 * records, competition entries, match history, listings, bookings, orders,
 * check-ins and payment receipts. It does NOT include other people's records
 * that merely mention them — a club's full roster, another player's scorecard
 * — because those are not this person's data to be handed, and a right of
 * access is not a right to the rest of the database.
 *
 * Returned inline rather than as a file in Storage. An export is a handful of
 * documents, the client writes the JSON out itself (`file_download.dart`), and
 * a generated download URL sitting in a bucket is one more copy of somebody's
 * personal data waiting to leak.
 */
export const exportMyData = onCall(
  { ...CALLABLE_OPTS },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to export your data.');
    }

    const data = await exportSubject(uid);
    logger.info('data export produced', {
      uid,
      keys: Object.keys(data).filter((k) => !k.startsWith('_')).length,
      problems: data._problems?.length ?? 0,
    });
    return data;
  },
);
