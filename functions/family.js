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
 *
 * ## The custody mirror
 *
 * `users/{guardianUid}.managedChildUids` is a denormalized list of the
 * unclaimed children an account may act as. It exists for exactly one
 * reason: `firestore.rules` can look up a child's document when the child's
 * uid is in the path, but a collection-group query — "every fixture my child
 * played in", which matches on a `playerUids` ARRAY — gives it no uid to look
 * up. Reading the list off the caller's own document is one cached read no
 * matter how many documents the query returns. See `wardUids()` there.
 *
 * It is an index, never the authority: `custodianUid`/`claimedAt` on the
 * child's own document still gate everything that actually confers custody.
 * This file is its only writer — added by [createManagedChildProfile],
 * removed by [onChildProfileClaimed] — and the rules freeze the field
 * against every client write.
 */

import crypto from 'node:crypto';

import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
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

export const CLAIM_CODE_LENGTH = 12;

/**
 * A claim code as typed, reduced to what is stored — or null if it cannot be
 * one. Mirrors `ClaimCode.normalize` (lib/core/models/claim_code.dart) and the
 * shape the `claimCodes` create rule in firestore.rules enforces: twelve
 * characters of the player-code alphabet, forgiving about case, spaces, dashes
 * and O/I/L heard for 0/1.
 *
 * Twelve, not the six digits codes used to be: this function's caller is
 * reachable signed out and a hit is a sign-in token for a child's account, so
 * the code length is the actual defence against guessing. A malformed input
 * is refused without a Firestore read.
 */
export function normalizeClaimCode(input) {
  // Typed before coercing, because `String(value)` is happy to invent a
  // well-formed code out of something that never was one: `String({})` is
  // "[object Object]", which strips to OBJECTOBJECT — twelve characters, every
  // one of them in the alphabet. A callable payload is JSON, so a caller
  // chooses the type.
  if (typeof input !== 'string' && typeof input !== 'number') return null;
  const s = String(input)
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .replace(/O/g, '0')
    .replace(/[IL]/g, '1');
  if (s.length !== CLAIM_CODE_LENGTH) return null;
  for (const ch of s) {
    if (!CODE_ALPHABET.includes(ch)) return null;
  }
  return s;
}

/**
 * Whether the child a code names can still be handed over by the guardian who
 * minted it — decided at REDEMPTION, not only when the code was created.
 *
 * A code outlives its creation by up to thirty minutes. Without this check, a
 * code left unused after the child claimed through a second one still minted
 * a token for what was by then the child's own account, with their Google
 * login on it.
 */
export function childIsClaimable(childData, guardianUid) {
  return Boolean(childData)
    && childData.claimedAt == null
    && typeof guardianUid === 'string'
    && childData.custodianUid === guardianUid;
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
 * How many unclaimed profiles one account may be running at a time.
 *
 * A ceiling rather than a judgement about family size: each call mints a real
 * Firebase Auth user, a `users` document and a player code, from any signed-in
 * caller, and nothing else bounds that. A household with more than ten children
 * without phones is rare enough to handle by hand; a script making ten thousand
 * accounts is not.
 *
 * Counted from the custody mirror, which lists only children who have NOT yet
 * claimed their profile — so handing a child their account back frees a place,
 * and a guardian who has raised a family through the product is never stuck.
 */
export const MAX_MANAGED_CHILDREN = 10;

/**
 * Why this account may not add a child right now, or null when it may.
 *
 * Separated from the Admin SDK calls for the same testability reason as
 * [resolveClaim] and [validateChildInput]: returns `[code, message]` for an
 * `HttpsError`, and the caller is the only thing that throws.
 *
 * A guardian with no `dateOfBirth` on file is treated as an adult. The field is
 * required at signup and cannot be edited afterwards, so the only accounts
 * missing it predate that rule; refusing them would block a real guardian to
 * punish a gap they cannot fix.
 */
export function guardianRefusalReason(guardianData, now, { cap = MAX_MANAGED_CHILDREN } = {}) {
  if (!guardianData) {
    return [
      'failed-precondition',
      'Finish setting up your own profile before adding a child.',
    ];
  }

  const raw = guardianData.dateOfBirth;
  const dob = typeof raw?.toDate === 'function'
    ? raw.toDate()
    : (raw instanceof Date ? raw : null);
  if (dob) {
    const ageYears = (now.getTime() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000);
    if (ageYears < 18) {
      return [
        'failed-precondition',
        'Only an adult can create and manage a child profile. Ask a parent or '
          + 'guardian to add it from their own account.',
      ];
    }
  }

  const wards = Array.isArray(guardianData.managedChildUids)
    ? guardianData.managedChildUids.length
    : 0;
  if (wards >= cap) {
    return [
      'resource-exhausted',
      `You are already managing ${cap} child profiles, which is the limit. `
        + 'Hand one over to its own device first, or contact support.',
    ];
  }

  return null;
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

    // Who is asking, and how many profiles they are already running. Before
    // this, any signed-in account — a child's own account included — could mint
    // unlimited Firebase Auth users, `users` documents and player codes, one
    // call each, with nothing bounding it. See [guardianRefusalReason].
    const guardianSnap = await db().collection('users').doc(guardianUid).get();
    const refusal = guardianRefusalReason(
      guardianSnap.exists ? guardianSnap.data() : null,
      new Date(),
    );
    if (refusal) {
      const [code, message] = refusal;
      throw new HttpsError(code, message);
    }

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

    // The custody mirror the rules read — see the file header. Written
    // after the child document and not in the same batch on purpose: a
    // mirror entry pointing at a child that does not exist would grant
    // nothing (every rule that consults it also matches on real data), while
    // a child with no mirror entry is merely invisible to the collection-
    // group queries until this lands.
    await db()
      .collection('users')
      .doc(guardianUid)
      .set(
        { managedChildUids: FieldValue.arrayUnion(childUid) },
        { merge: true },
      );

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
  {
    region: 'asia-south1',
    // A ceiling on how fast anybody can guess, and on what guessing costs the
    // project. Claims are a handful a day, which two instances serve with room
    // to spare; a script hammering this is queued by the platform instead of
    // scaled up to meet it. The code length is the actual defence — see
    // normalizeClaimCode — and this caps the rate it is measured against.
    maxInstances: 2,
  },
  async (request) => {
    const invalid = () => new HttpsError(
      'failed-precondition',
      'This code is invalid or has expired. Ask your guardian for a new one.',
    );

    if (!String(request.data?.code ?? '').trim()) {
      throw new HttpsError('invalid-argument', 'Enter the code your guardian gave you.');
    }
    // A malformed code gets the same answer as a wrong one, and no read.
    const code = normalizeClaimCode(request.data.code);
    if (!code) throw invalid();

    const codeRef = db().collection('claimCodes').doc(code);
    const claim = await db().runTransaction(async (tx) => {
      const snap = await tx.get(codeRef);
      const codeData = snap.exists ? snap.data() : null;
      const childUid = resolveClaim(codeData, new Date());
      if (!childUid) return null;

      const childSnap = await tx.get(db().collection('users').doc(childUid));
      const child = childSnap.exists ? childSnap.data() : null;

      // Burned whether or not it redeems. A code for a child who is no longer
      // claimable is dead, and leaving it live only keeps it worth guessing.
      tx.update(codeRef, { usedAt: FieldValue.serverTimestamp() });
      if (!childIsClaimable(child, codeData.guardianUid)) return null;
      return { childUid, displayName: child.displayName ?? null };
    });

    // Deliberately one generic error for not-found, expired, already-used and
    // no-longer-claimable — distinguishing them would just be a hint to a
    // guesser.
    if (!claim) throw invalid();

    return {
      customToken: await fbAuth().createCustomToken(claim.childUid),
      displayName: claim.displayName,
    };
  },
);

/**
 * Rebuilds every guardian's custody mirror from the authoritative fields.
 *
 * Needed once, for the children created before the mirror existed — without
 * it their guardians can switch into the profile and then find the child's
 * clubs and match history empty, which is the exact failure the mirror was
 * added to fix. Idempotent, so re-running it is only ever a no-op: it
 * computes the whole list per guardian and writes it wholesale rather than
 * appending, which also repairs any drift a failed trigger left behind.
 *
 * Run from a terminal via run_ward_backfill.mjs.
 */
export async function backfillCustodyMirror({ dryRun = false } = {}) {
  const snap = await db()
    .collection('users')
    .where('custodianUid', '!=', null)
    .get();

  const byGuardian = new Map();
  for (const doc of snap.docs) {
    const data = doc.data();
    // Claimed children are deliberately absent: the mirror lists only the
    // profiles an account may still act as.
    if (data.claimedAt) continue;
    const guardian = data.custodianUid;
    if (!guardian) continue;
    if (!byGuardian.has(guardian)) byGuardian.set(guardian, []);
    byGuardian.get(guardian).push(doc.id);
  }

  // Anyone still carrying a mirror whose children have all since been
  // claimed. Computing only the additions would leave those entries granting
  // reads forever if the prune trigger had ever failed for them.
  const existing = await db()
    .collection('users')
    .where('managedChildUids', '!=', null)
    .get();
  const stale = existing.docs
    .filter((d) => !byGuardian.has(d.id) && (d.data().managedChildUids ?? []).length > 0)
    .map((d) => d.id);

  if (!dryRun) {
    for (const [guardianUid, childUids] of byGuardian) {
      await db()
        .collection('users')
        .doc(guardianUid)
        .set({ managedChildUids: childUids }, { merge: true });
    }
    for (const guardianUid of stale) {
      await db()
        .collection('users')
        .doc(guardianUid)
        .set({ managedChildUids: [] }, { merge: true });
    }
  }

  return {
    guardians: byGuardian.size,
    children: [...byGuardian.values()].reduce((n, l) => n + l.length, 0),
    cleared: stale.length,
  };
}

/**
 * Ends the guardian's custody the moment the child claims their profile.
 *
 * The claim itself is a client write — the child's own newly-linked session
 * setting `claimedAt`, which `firestore.rules` permits exactly once and only
 * from that session. Every rule that reads custody straight off the child's
 * document therefore stops matching in the same instant, with no server
 * involvement at all. The mirror is the one thing that cannot update itself:
 * it lives on the GUARDIAN's document, and the child's session has no right
 * to write there. So this trigger prunes it.
 *
 * Until it runs the mirror is briefly stale, which is why nothing sensitive
 * is allowed to depend on it alone — it widens collection-group READS by a
 * few seconds, and every write that matters still consults
 * `custodianUid`/`claimedAt` directly.
 */
export const onChildProfileClaimed = onDocumentUpdated(
  { region: 'asia-south1', document: 'users/{userId}' },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const custodianUid = after.custodianUid ?? before.custodianUid;
    if (!custodianUid) return;
    // Only the null → set transition. Any later write to a claimed profile
    // must not re-run the prune, and must not be able to undo it either.
    if (before.claimedAt || !after.claimedAt) return;

    const childUid = event.params.userId;

    await db()
      .collection('users')
      .doc(custodianUid)
      .set(
        { managedChildUids: FieldValue.arrayRemove(childUid) },
        { merge: true },
      );

    // Every device registered against this child up to now is the GUARDIAN's
    // phone — a managed child has no device of their own, so the guardian's
    // registers itself under the child's uid to receive their reminders (see
    // `pushRegistrationProvider`). The moment the child has their own login
    // those registrations are somebody else's phone buzzing for them, so they
    // go. The child's own device re-registers on their next app start.
    const devices = await db()
      .collection('users')
      .doc(childUid)
      .collection('devices')
      .get();
    await Promise.all(devices.docs.map((d) => d.ref.delete()));

    logger.info('onChildProfileClaimed: custody ended', {
      childUid,
      custodianUid,
      devicesCleared: devices.size,
    });
  },
);
