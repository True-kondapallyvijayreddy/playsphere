/**
 * Ground-listing fraud: scoring it, and pulling the handle when it is
 * confirmed.
 *
 * ## What this is defending against
 *
 * Somebody lists a ground they have nothing to do with, waits for a club to
 * book Sunday evening, rings the number on the listing, asks for a UPI
 * advance "to hold the slot", and stops answering. PlaySphere never touches
 * that money — ground fees are settled at the venue, see `FeeSettlement` in
 * the app — so once it has moved there is nothing to reverse and nobody to
 * charge back. Every defence has to act before the phone call, or fast enough
 * afterwards that the second victim never happens.
 *
 * ## Why any of this is server-side
 *
 * Almost all of PlaySphere is client plus security rules, deliberately, to
 * keep it cheap enough to be free for scorers and players. Three things here
 * cannot work that way:
 *
 * **Suspension.** `firestore.rules` bars the owner from writing
 * `verificationStatus`, which is what makes a kill switch a kill switch. The
 * corollary is that something with the admin SDK has to be the one to write
 * it, and it cannot be a human at midnight.
 *
 * **Report scoring.** A client that told the server how much its own report
 * was worth would be a client that could suspend a competitor at will. The
 * weights live here and the score is recomputed from the whole collection on
 * every report, never incremented.
 *
 * **Cross-account checks.** "Has another owner already listed this spot?" and
 * "does this phone number appear on somebody else's ground?" are queries
 * across documents no single client may read.
 *
 * ## What it deliberately does not do
 *
 * It does not reject listings. Risk flags order the review queue and nothing
 * more, because every signal available here has an innocent explanation — two
 * grounds really can share a boundary wall, a family really can run two turfs
 * off one phone, and an account really can be new. Acting on suspicion alone
 * would take honest listings down silently, and the owner would never find
 * out why.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

function db() {
  return getFirestore();
}

// ---------------------------------------------------------------------------
// Constants that are duplicated in Dart
// ---------------------------------------------------------------------------

/**
 * What each report reason contributes to the suspension score.
 *
 * MUST be kept in step with `GroundReportReason` in
 * `lib/core/models/ground_verification.dart`, which is the source the UI
 * renders from. There is no shared source between Dart and this file — the
 * same hand-sync burden `CRITICAL_NOTIFICATION_TYPES` in `index.js` carries,
 * and accepted for the same reason: the alternative is the client sending the
 * weight, and a report system whose severity is set by the reporter's own
 * client is not a report system.
 *
 * An unknown reason scores 1 rather than 0. A newer app version inventing a
 * reason this build has not heard of should still count for something.
 */
const REPORT_WEIGHTS = {
  askedForAdvance: 3,
  doesNotExist: 3,
  notTheirGround: 3,
  refusedBooking: 2,
  unreachable: 1,
  wrongDetails: 1,
  duplicate: 1,
};

const FRAUD_REASONS = new Set(['askedForAdvance', 'doesNotExist', 'notTheirGround']);

/**
 * The score at which a listing comes down without waiting for a human.
 *
 * Six, which is two independent fraud reports, or one plus three lesser
 * complaints. Chosen against the two ways this can be wrong:
 *
 * Too low, and one malicious account plus a friend can take a competitor's
 * ground off the market — the composite report id already limits each account
 * to one report per ground, so the floor for an attack is two real accounts,
 * and a threshold of 3 would sit exactly on it.
 *
 * Too high, and the scam runs all weekend while complaints accumulate. Two
 * people saying "he asked me for an advance" is not ambiguous, and the cost
 * of being wrong is asymmetric: a wrongly suspended honest owner is restored
 * by a reviewer within a day, while a wrongly-left-up fraudster collects from
 * everyone who books in the meantime.
 */
const AUTO_SUSPEND_SCORE = 6;

/** How close two pins have to be before they are probably the same ground. */
const DUPLICATE_PIN_METRES = 60;

/** An account younger than this listing a ground is worth a reviewer's eye. */
const NEW_ACCOUNT_DAYS = 3;

/** More listings than this from one account in a week is unusual. */
const VELOCITY_LISTINGS = 3;

/** Distinct arrivals before a listing counts as confirmed by the crowd. */
const CONFIRMING_CHECK_INS = 3;

/** How far from the pin an arrival still counts. Mirrors `GroundCheckIn`. */
const CONFIRMING_RADIUS_METRES = 250;

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/**
 * Metres between two points, by the haversine formula.
 *
 * Duplicated from `Geohash.distanceKm` on the Dart side rather than shared,
 * because this file cannot import Dart and the alternative — trusting the
 * distance the client computed — is exactly the thing a check-in must not do.
 * The client's number is what it shows the person; this one is what moves the
 * counter.
 */
function distanceMetres(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

// ---------------------------------------------------------------------------
// Risk scoring, on create
// ---------------------------------------------------------------------------

/**
 * Looks at a brand-new listing and writes down what is odd about it.
 *
 * Runs once, on create. Not on update: an owner correcting their closing time
 * should not re-trigger a scan across every ground in the country, and the
 * facts that matter here — who else is at this pin, how old the account was
 * when it listed — are facts about the moment of listing.
 *
 * Every flag is advisory. See the file header for why none of them blocks.
 */
export const scoreNewGround = onDocumentCreated('grounds/{groundId}', async (event) => {
  const snap = event.data;
  if (!snap) return;

  const ground = snap.data() ?? {};
  const groundId = event.params.groundId;
  const flags = [];

  const lat = typeof ground.latitude === 'number' ? ground.latitude : null;
  const lng = typeof ground.longitude === 'number' ? ground.longitude : null;

  if (lat === null || lng === null) {
    // Only reachable for a listing that did not come through capture — the
    // wizard cannot finish without a fix. Worth flagging precisely because
    // such a listing can never be confirmed by arrivals either: with no pin,
    // there is nothing for a check-in to be near.
    flags.push('noPin');
  }

  try {
    // --- The proofs behind it --------------------------------------------
    const proofs = await db()
      .collection('grounds').doc(groundId)
      .collection('verification')
      .get();

    let worstOffset = 0;
    const fixes = [];
    for (const doc of proofs.docs) {
      if (doc.id === 'claim') continue;
      const p = doc.data() ?? {};
      if (p.isMocked === true) {
        // The client refuses a mocked fix outright, so a stored one means the
        // write did not come from the shipped app. That is a more interesting
        // fact about the account than anything about the ground.
        if (!flags.includes('mockedLocation')) flags.push('mockedLocation');
      }
      if (typeof p.latitude === 'number' && typeof p.longitude === 'number') {
        fixes.push([p.latitude, p.longitude]);
        if (lat !== null && lng !== null) {
          worstOffset = Math.max(worstOffset, distanceMetres(lat, lng, p.latitude, p.longitude));
        }
      }
    }

    if (worstOffset > 300) flags.push('pinFarFromCapture');

    let spread = 0;
    for (let i = 0; i < fixes.length; i++) {
      for (let j = i + 1; j < fixes.length; j++) {
        spread = Math.max(spread, distanceMetres(fixes[i][0], fixes[i][1], fixes[j][0], fixes[j][1]));
      }
    }
    if (spread > 300) flags.push('capturesScattered');

    // --- Somebody else's ground at the same spot --------------------------
    //
    // The single most valuable check here, and the one that directly catches
    // "he listed a turf he does not run": the real operator has very often
    // already listed it. A coarse latitude window narrows the scan — a proper
    // geohash neighbourhood query would be tighter, but this runs once per
    // listing and the window is about 2km, which is a handful of documents in
    // any Indian district today.
    if (lat !== null && lng !== null) {
      const window = 0.02;
      const near = await db().collection('grounds')
        .where('latitude', '>=', lat - window)
        .where('latitude', '<=', lat + window)
        .limit(200)
        .get();

      for (const doc of near.docs) {
        if (doc.id === groundId) continue;
        const other = doc.data() ?? {};
        if (other.ownerUid === ground.ownerUid) continue;
        if (typeof other.latitude !== 'number' || typeof other.longitude !== 'number') continue;
        if (distanceMetres(lat, lng, other.latitude, other.longitude) <= DUPLICATE_PIN_METRES) {
          flags.push('duplicatePin');
          break;
        }
      }
    }

    // --- The same number on somebody else's listing -----------------------
    const phone = typeof ground.contactPhone === 'string' ? ground.contactPhone.trim() : '';
    if (phone.length >= 6) {
      const samePhone = await db().collection('grounds')
        .where('contactPhone', '==', phone)
        .limit(10)
        .get();
      const otherOwner = samePhone.docs.some(
        (d) => d.id !== groundId && (d.data() ?? {}).ownerUid !== ground.ownerUid,
      );
      if (otherOwner) flags.push('reusedPhone');
    }

    // --- The account behind it -------------------------------------------
    const owner = await db().collection('users').doc(ground.ownerUid).get();
    const createdAt = owner.exists ? owner.data()?.createdAt : null;
    if (createdAt?.toMillis) {
      const ageDays = (Date.now() - createdAt.toMillis()) / 86400000;
      if (ageDays < NEW_ACCOUNT_DAYS) flags.push('newAccount');
    }

    const mine = await db().collection('grounds')
      .where('ownerUid', '==', ground.ownerUid)
      .limit(VELOCITY_LISTINGS + 2)
      .get();
    if (mine.size > VELOCITY_LISTINGS) flags.push('listingVelocity');
  } catch (error) {
    // A scan that failed must not leave the listing in limbo. It publishes
    // unflagged, which is the same position every listing was in before this
    // function existed.
    logger.warn('ground risk scan failed', { groundId, error: String(error) });
  }

  if (flags.length === 0) return;

  await snap.ref.update({
    riskFlags: flags,
    riskScoredAt: FieldValue.serverTimestamp(),
  });
  logger.info('ground flagged for review', { groundId, flags });
});

// ---------------------------------------------------------------------------
// Reports and auto-suspension
// ---------------------------------------------------------------------------

/**
 * Recomputes a listing's report score whenever a complaint is filed or
 * amended, and takes the listing down if it crosses the threshold.
 *
 * ## Why the score is recomputed rather than incremented
 *
 * Reports are updatable by their author — somebody who reported a wrong
 * address and then discovered the owner was demanding advances files a
 * correction, not a second complaint. An incrementing counter would add the
 * new weight on top of the old one and reach the threshold on one person's
 * change of mind. Reading the collection costs one small query per report,
 * which is nothing at this volume and is correct at every volume.
 *
 * ## Why suspension writes `isActive: false` too
 *
 * Search filters on `isActive`, and it does so in the Firestore query rather
 * than on the client, so clearing it is what actually removes a suspended
 * listing from results — including for clients running an older build that
 * has never heard of `verificationStatus`. `firestore.rules` stops the owner
 * turning it back on while suspended.
 */
export const onGroundReported = onDocumentWritten('groundReports/{reportId}', async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;

  const report = after.data() ?? {};
  const groundId = report.groundId;
  if (!groundId) return;

  const all = await db().collection('groundReports')
    .where('groundId', '==', groundId)
    .get();

  let score = 0;
  let fraudReports = 0;
  const reporters = new Set();
  for (const doc of all.docs) {
    const r = doc.data() ?? {};
    // The weight is derived from the reason here, never read from the
    // document — the client wrote that field and could put anything in it.
    score += REPORT_WEIGHTS[r.reason] ?? 1;
    reporters.add(r.reporterUid);
    if (FRAUD_REASONS.has(r.reason)) fraudReports += 1;
  }

  const groundRef = db().collection('grounds').doc(groundId);
  const ground = await groundRef.get();
  if (!ground.exists) return;

  const current = ground.data() ?? {};
  const patch = {
    reportScore: score,
    reportCount: all.size,
    lastReportedAt: FieldValue.serverTimestamp(),
  };

  // Two distinct accounts minimum, whatever the score. One person cannot
  // suspend a listing on their own however severe their complaint, because
  // "he asked me for an advance" from a single account is also what a
  // competitor says.
  const shouldSuspend =
    score >= AUTO_SUSPEND_SCORE &&
    reporters.size >= 2 &&
    current.verificationStatus !== 'suspended' &&
    current.verificationStatus !== 'rejected';

  if (shouldSuspend) {
    patch.verificationStatus = 'suspended';
    patch.isActive = false;
    patch.isVerified = false;
    patch.suspendedAt = FieldValue.serverTimestamp();
    patch.reviewNote =
      'Suspended automatically after reports from several people. A '
      + 'PlaySphere reviewer will look at this.';
  }

  await groundRef.update(patch);

  if (shouldSuspend) {
    logger.warn('ground auto-suspended', {
      groundId, score, reporters: reporters.size, fraudReports,
    });
    await notifyOwnerOfSuspension(groundId, current);
  }
});

/**
 * Tells the owner their listing is down and why.
 *
 * Sent even though most recipients of this notification will be the fraudster
 * themselves. The one who is not — an honest owner taken down by a pile-on —
 * has no other way of finding out, and a listing that silently stops earning
 * with no explanation is how you lose the genuine operators this marketplace
 * needs.
 */
async function notifyOwnerOfSuspension(groundId, ground) {
  const uid = ground.ownerUid;
  if (!uid) return;
  try {
    await db().collection('users').doc(uid).collection('notifications').add({
      type: 'ground_suspended',
      title: 'Your ground listing has been paused',
      body: `${ground.name ?? 'Your ground'} is no longer taking bookings while `
        + 'PlaySphere checks reports about it. Existing bookings are unaffected.',
      route: `/grounds/${groundId}`,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
    });
  } catch (error) {
    logger.warn('suspension notice failed', { groundId, error: String(error) });
  }
}

// ---------------------------------------------------------------------------
// Arrivals
// ---------------------------------------------------------------------------

/**
 * Counts an arrival, if the phone really was at the ground.
 *
 * ## Why the distance is recomputed here
 *
 * The client writes a `distanceMetres` it worked out itself, and that number
 * is for the message it shows the person — "you're 40m from the pin". It is
 * not evidence. A client that wanted to walk a fake listing up to "Location
 * confirmed" would simply write zero. So the distance is recomputed from the
 * ground's own pin and the coordinates on the check-in, and only that
 * recomputation is allowed to move the counter.
 *
 * ## Why the counter is a recount rather than an increment
 *
 * `checkInCount` is supposed to mean "how many different people have turned
 * up here". An increment would count one club that books every Sunday as
 * fifty-two people and confirm a listing on one person's habit. Recounting
 * distinct uids across the subcollection is the only version that means what
 * the badge claims it means.
 */
export const onGroundCheckIn = onDocumentCreated(
  'grounds/{groundId}/checkIns/{bookingId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const groundId = event.params.groundId;
    const checkIn = snap.data() ?? {};

    const groundRef = db().collection('grounds').doc(groundId);
    const ground = await groundRef.get();
    if (!ground.exists) return;
    const g = ground.data() ?? {};

    if (typeof g.latitude !== 'number' || typeof g.longitude !== 'number') return;
    if (typeof checkIn.latitude !== 'number' || typeof checkIn.longitude !== 'number') return;

    const real = distanceMetres(g.latitude, g.longitude, checkIn.latitude, checkIn.longitude);
    const counts = real <= CONFIRMING_RADIUS_METRES && checkIn.isMocked !== true;

    // Written back whatever the verdict. A check-in that did NOT count is the
    // most useful record in the system when somebody arrives and finds no
    // ground: timestamped, positioned, and tied to a booking — which is what
    // a reviewer needs and what a screenshot of an argument is not.
    await snap.ref.update({
      serverDistanceMetres: real,
      counted: counts,
      verifiedAt: FieldValue.serverTimestamp(),
    });

    if (!counts) {
      logger.info('check-in did not confirm', { groundId, real });
      return;
    }

    const all = await groundRef.collection('checkIns').get();
    const arrived = new Set();
    for (const doc of all.docs) {
      const c = doc.data() ?? {};
      if (c.counted === true || doc.id === snap.id) arrived.add(c.uid);
    }
    arrived.delete(undefined);

    const patch = { checkInCount: arrived.size };

    // Promotion is a badge, not a status: `GroundTrust` derives "Location
    // confirmed" from the count, so there is nothing to set. What is worth
    // recording is the moment it crossed, for the review queue's ordering.
    if (arrived.size >= CONFIRMING_CHECK_INS && !g.locationConfirmedAt) {
      patch.locationConfirmedAt = FieldValue.serverTimestamp();
    }

    await groundRef.update(patch);
  },
);

// ---------------------------------------------------------------------------
// The pattern nothing else can see
// ---------------------------------------------------------------------------

/**
 * Flags a listing that keeps taking bookings nobody ever arrives at.
 *
 * This is the signal the whole check-in mechanism exists to produce. A
 * phone-advance scam looks completely normal from every other angle: real
 * photos, a real pin, slots filling up. What it cannot fake is people
 * actually turning up, and a listing with a healthy booking count and zero
 * arrivals is not a pattern an honest ground produces.
 *
 * Runs on the booking counter rather than on a schedule so the flag appears
 * while the reviewer still has a chance to act. The floor of five bookings is
 * there because a new ground with two bookings and no check-ins is just a new
 * ground — check-in is a habit that takes a while to spread.
 */
export const flagUnvisitedGround = onDocumentWritten('grounds/{groundId}', async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!after || !before) return;
  if ((after.bookingCount ?? 0) === (before.bookingCount ?? 0)) return;

  const bookings = after.bookingCount ?? 0;
  const arrivals = after.checkInCount ?? 0;
  const flags = Array.isArray(after.riskFlags) ? after.riskFlags : [];

  const suspicious = bookings >= 5 && arrivals === 0;
  const alreadyFlagged = flags.includes('bookedNeverVisited');
  if (suspicious === alreadyFlagged) return;

  const next = suspicious
    ? [...flags, 'bookedNeverVisited']
    : flags.filter((f) => f !== 'bookedNeverVisited');

  await event.data.after.ref.update({ riskFlags: next });
  logger.info('unvisited-ground flag changed', {
    groundId: event.params.groundId, suspicious, bookings, arrivals,
  });
});
