/**
 * Guardian-managed child profiles.
 *
 * ## The problem this solves
 *
 * PlaySphere is Google-only sign-in, and `AppUser` is "one document per real
 * human, at users/{uid}" — see the doc comment on that class. Both are right
 * defaults, and both assume the person has a device and a Google account of
 * their own. A lot of this product's actual users don't yet: a village or
 * school family with one shared parent phone and several children.
 *
 * So a guardian can create a profile for a child up front — same uid shape,
 * same player code, same everything an ordinary account gets — and operate
 * it themselves (see the `custodianUid`-gated branch of the `users/{userId}`
 * update rule in firestore.rules) until the child has a phone. At that point
 * the child redeems a short-lived code the guardian generated, which hands
 * them a custom token signed in AS the exact same uid, and they link their
 * own Google account to it client-side. No migration: the uid, the player
 * code, any matches already played, all just keep being theirs.
 *
 * ## Why these two functions specifically need Admin privileges
 *
 * Everything else in this flow — creating the claim code, editing an
 * unclaimed child's profile, flipping `claimedAt` once linked — is a plain
 * client write, governed by firestore.rules, matching this codebase's
 * general philosophy that rules are the actual boundary (see the doc
 * comment on GuardianConsent for the fullest statement of that idea). Only
 * two things a client fundamentally cannot do on its own: mint a Firebase
 * Auth user with no credential attached, and mint a custom token for a uid
 * it isn't signed in as. Those are exactly what live here, and nothing
 * else does.
 */

import crypto from 'node:crypto';

import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

function fbAuth() {
  return getAuth();
}

const GENDER_WIRE_VALUES = new Set(['male', 'female', 'other', 'prefer_not_to_say']);

// Mirrors lib/core/models/player_code.dart exactly — same alphabet, same
// shape. Kept as a second definition rather than a shared one because
// Dart and this Node runtime don't share code; if the format ever
// changes, both need the same edit, and PlayerCode.normalize on the
// client already forgives the O/I/L reads either generator could ever
// need to produce.
const CODE_PREFIX = 'PSOS';
const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const CODE_LENGTH = 5;

export function generatePlayerCode() {
  let body = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    body += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  }
  return `${CODE_PREFIX}-${body}`;
}

/**
 * Claims a fresh `playerCodes/{code}` document for `uid`, retrying on
 * collision — the server-side twin of `UserRepository.ensureCode`
 * (lib/data/org_repository.dart). A managed child needs this at CREATION
 * time, not lazily on first sign-in like an ordinary account gets it from
 * `playerCodeProvider`: the whole point of the code is that a captain can
 * add the child to a team sheet before they ever have a device.
 */
async function claimPlayerCode(uid, displayName) {
  const usersRef = db().collection('users').doc(uid);
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = generatePlayerCode();
    const codeRef = db().collection('playerCodes').doc(candidate);
    try {
      await db().runTransaction(async (tx) => {
        const existing = await tx.get(codeRef);
        if (existing.exists) {
          throw new Error('CODE_TAKEN');
        }
        tx.create(codeRef, {
          uid,
          displayName,
          photoUrl: null,
          createdAt: FieldValue.serverTimestamp(),
        });
        tx.update(usersRef, { playerCode: candidate });
      });
      return candidate;
    } catch (e) {
      if (attempt === 4) throw e;
      // Otherwise a fresh candidate on the next loop.
    }
  }
  return null;
}

/**
 * The redemption decision, isolated from the Firestore transaction around
 * it so it can be unit-tested directly with plain objects — same reasoning
 * as `participantsOf`/`soloUidOf` in participants.js: the rule a database
 * write enforces should be checkable without a database.
 *
 * `now` is a parameter rather than read internally for the same reason
 * `AgeGroup.fromDateOfBirth`/`isActiveAt` on the Dart side take an instant
 * explicitly — a test can pin it exactly, and the caller's transaction
 * reuses one `now` for both this decision and the timestamp it writes.
 *
 * Accepts `expiresAt` as either a Firestore Timestamp (`.toDate()`) or a
 * plain `Date`, so a test can hand this a plain object without pulling in
 * `firebase-admin/firestore` at all.
 */
export function resolveClaim(codeData, now) {
  if (!codeData) return null;
  if (codeData.usedAt) return null;
  const expiresAt =
    typeof codeData.expiresAt?.toDate === 'function'
      ? codeData.expiresAt.toDate()
      : codeData.expiresAt;
  if (!(expiresAt instanceof Date) || expiresAt.getTime() <= now.getTime()) {
    return null;
  }
  return codeData.childUid || null;
}

/**
 * Validates a `createManagedChildProfile` request, isolated from Admin SDK
 * calls for the same testability reason as [resolveClaim]. Returns
 * `{ displayName, dateOfBirth }` on success or `{ error: [code, message] }`
 * on failure, where `code` is an `HttpsError` code — the caller is the only
 * thing that actually throws.
 */
export function validateChildInput({ displayName, dateOfBirth, gender }, now) {
  const name = String(displayName ?? '').trim();
  if (!name) {
    return { error: ['invalid-argument', 'A name is required.'] };
  }

  const dob = typeof dateOfBirth === 'string' ? new Date(dateOfBirth) : null;
  if (!dob || Number.isNaN(dob.getTime()) || dob >= now) {
    return {
      error: [
        'invalid-argument',
        'A valid date of birth, in the past, is required.',
      ],
    };
  }

  if (!GENDER_WIRE_VALUES.has(gender)) {
    return { error: ['invalid-argument', 'A valid gender value is required.'] };
  }

  const ageYears = (now.getTime() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
  if (ageYears >= 18) {
    return {
      error: [
        'failed-precondition',
        'A managed profile is for a child without their own device yet — ' +
          'an adult should sign in with their own Google account instead.',
      ],
    };
  }

  return { displayName: name, dateOfBirth: dob, gender };
}

/**
 * A guardian creates a profile for a child who has no device or Google
 * account of their own yet.
 *
 * Mints a bare Firebase Auth user (a uid, no sign-in method attached) and
 * writes `users/{childUid}` in the same shape `AppUser.toCreate()` produces,
 * with `custodianUid` pointing at the caller and `claimedAt` null. Both of
 * those fields are permanently locked against client writes by
 * firestore.rules the moment they're set here — see
 * `userUpdateInvariantsHold`/`isCustodianOfUnclaimed` there.
 */
export const createManagedChildProfile = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const guardianUid = request.auth?.uid;
    if (!guardianUid) {
      throw new HttpsError('unauthenticated', 'Sign in to add a child.');
    }

    const validated = validateChildInput(request.data ?? {}, new Date());
    if (validated.error) {
      const [code, message] = validated.error;
      throw new HttpsError(code, message);
    }
    const { displayName, dateOfBirth, gender } = validated;

    const childRecord = await fbAuth().createUser({});
    const childUid = childRecord.uid;

    const now = Timestamp.now();
    await db()
      .collection('users')
      .doc(childUid)
      .set({
        uid: childUid,
        displayName,
        email: '',
        dateOfBirth: Timestamp.fromDate(dateOfBirth),
        gender,
        photoUrl: null,
        phone: null,
        profileVisibility: 'private',
        profileComplete: true,
        orgIds: [],
        playerCode: null,
        plan: 'free',
        isMinor: true,
        custodianUid: guardianUid,
        claimedAt: null,
        createdAt: now,
        updatedAt: now,
      });

    let playerCode = null;
    try {
      playerCode = await claimPlayerCode(childUid, displayName);
    } catch (e) {
      // Recoverable later the same way any account's code is recovered —
      // see `playerCodeProvider` in providers.dart. Must never block
      // account creation itself.
      logger.warn('createManagedChildProfile: playerCode backfill failed', e);
    }

    return { childUid, playerCode };
  },
);

/**
 * The child's half of the handoff. Reachable signed out — there is no
 * Firebase Auth session yet at the point this is called.
 *
 * Validates and burns a `claimCodes/{code}` document (one atomic
 * transaction closes the double-redeem race) and, only if that succeeds,
 * mints a custom token for the exact uid the code names. The client signs
 * in with that token — same uid, same player code, same match history,
 * nothing migrated — and then links its own Google credential to finish
 * the claim (`AuthService.linkGoogleAccount`, client-side; this function
 * has no part in that step).
 */
export const redeemClaimCode = onCall(
  { region: 'asia-south1' },
  async (request) => {
    // Codes are six digits — see UserRepository.createClaimCode — so
    // trimming is the only normalization there is anything to do.
    const code = String(request.data?.code ?? '').trim();
    if (!code) {
      throw new HttpsError('invalid-argument', 'Enter the code your guardian gave you.');
    }

    const codeRef = db().collection('claimCodes').doc(code);
    const childUid = await db().runTransaction(async (tx) => {
      const snap = await tx.get(codeRef);
      const resolved = resolveClaim(snap.exists ? snap.data() : null, new Date());
      if (!resolved) return null;
      tx.update(codeRef, { usedAt: FieldValue.serverTimestamp() });
      return resolved;
    });

    // Deliberately one generic error for not-found, expired and
    // already-used — distinguishing them would just be a hint to a guesser.
    if (!childUid) {
      throw new HttpsError(
        'failed-precondition',
        'This code is invalid or has expired. Ask your guardian for a new one.',
      );
    }

    const [customToken, childDoc] = await Promise.all([
      fbAuth().createCustomToken(childUid),
      db().collection('users').doc(childUid).get(),
    ]);

    return {
      customToken,
      displayName: childDoc.exists ? childDoc.data()?.displayName ?? null : null,
    };
  },
);
