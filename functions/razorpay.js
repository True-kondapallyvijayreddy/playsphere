/**
 * Real money, for the day `Pricing.introOfferActive` (lib/core/models/
 * billing.dart) flips to `false`.
 *
 * ## Why this cannot be the synchronous `PaymentGateway.collect()` seam
 *
 * `FreeCheckout.collect()` (lib/data/billing_repository.dart) is
 * synchronous-shaped: call it, get a reference back or an exception, write
 * the entitlement in the same breath. A card payment cannot honestly work
 * that way across Android, iOS *and* web with one code path — the only
 * checkout that behaves identically on all three without a native SDK per
 * platform is a hosted page the browser or the OS opens, and a hosted page
 * reports back on its own schedule, not the tapping thread's.
 *
 * So this is a second, additive flow, not a second `PaymentGateway`
 * implementation: `createPaymentLink` hands the client a URL to open, and
 * the entitlement is granted only when Razorpay's webhook — server to
 * server, never the client — confirms the money actually arrived. The
 * client's own "the browser came back" moment proves nothing; anyone can
 * close a tab and claim success.
 *
 * ## Why the amount is never accepted from the client
 *
 * `[kind, subjectId, plan]` go in; `amountPaise` never does. A client that
 * could name its own price is a client that could buy a ₹999 plan for ₹1,
 * and the whole point of moving entitlement-writing server-side is that the
 * server has to be the one place that fact cannot happen. The price table
 * below is the one source of truth for what things cost, mirroring (and
 * documented as mirroring) `Pricing` in billing.dart — the two are not
 * generated from one definition, so a price change is two edits, not one;
 * `test/security/` and this file's own guard on `introOfferActive` are what
 * catch the two drifting apart.
 */

import crypto from 'node:crypto';

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions';

const RAZORPAY_KEY_ID = defineSecret('RAZORPAY_KEY_ID');
const RAZORPAY_KEY_SECRET = defineSecret('RAZORPAY_KEY_SECRET');
const RAZORPAY_WEBHOOK_SECRET = defineSecret('RAZORPAY_WEBHOOK_SECRET');

// Mirrors `Pricing.introOfferActive` in billing.dart. Flip both in the same
// change — see that file's doc comment for why the flag exists at all.
const INTRO_OFFER_ACTIVE = true;

// Mirrors `Pricing.clubYearlyPaise` / `Pricing.premiumYearlyPaise`.
const PRICE_TABLE = {
  org_plan: { club: 99_900 },
  member_plan: { premium: 9_900 },
};

const TERM_DAYS = 365;

function db() {
  return getFirestore();
}

function priceFor(kind, planWire) {
  const row = PRICE_TABLE[kind];
  const amount = row?.[planWire];
  if (typeof amount !== 'number' || amount <= 0) return null;
  return amount;
}

/**
 * Creates a Razorpay Payment Link for one plan purchase and a matching
 * `payments/{id}` row, both server-side.
 *
 * The Firestore row is written with the Admin SDK, not by the client, so it
 * can carry the real amount from the first write — `firestore.rules`' create
 * rule on `payments/` only has to hold a client-initiated write to
 * `amountPaise == 0`, because this path never goes through that rule at all.
 */
export const createPaymentLink = onCall(
  { region: 'asia-south1', secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to buy a plan.');
    }
    if (INTRO_OFFER_ACTIVE) {
      throw new HttpsError(
        'failed-precondition',
        'Plans are free during the launch offer — there is nothing to pay ' +
          'for yet.',
      );
    }

    const { kind, subjectId, plan } = request.data ?? {};
    if (typeof kind !== 'string' || typeof subjectId !== 'string' ||
        typeof plan !== 'string') {
      throw new HttpsError('invalid-argument', 'Missing kind, subjectId or plan.');
    }
    if (kind !== 'org_plan' && kind !== 'member_plan') {
      throw new HttpsError('invalid-argument', `Unknown kind "${kind}".`);
    }
    const amountPaise = priceFor(kind, plan);
    if (amountPaise == null) {
      throw new HttpsError(
        'invalid-argument',
        `"${plan}" is not a paid ${kind} this function knows how to price.`,
      );
    }

    // For an org plan, only someone who can actually manage that org should
    // be able to start a charge against it — otherwise anyone signed in
    // could generate a payment link that, once paid, activates a plan on a
    // club they have no relationship with. Membership is who actually
    // exercises the plan once bought, but the *charge* belongs to whoever
    // can bind the club to it.
    if (kind === 'org_plan') {
      const member = await db().doc(`orgs/${subjectId}/members/${uid}`).get();
      const role = member.exists ? member.data().role : null;
      if (role !== 'owner' && role !== 'admin') {
        throw new HttpsError(
          'permission-denied',
          'Only this club\'s owner or admin can buy its plan.',
        );
      }
    } else if (subjectId !== uid) {
      // Premium is always bought for the signed-in person, never on behalf
      // of someone else — there is no membership-style relationship to check.
      throw new HttpsError(
        'permission-denied',
        'Premium can only be bought for your own account.',
      );
    }

    const paymentRef = db().collection('payments').doc();
    const validUntil = new Date(Date.now() + TERM_DAYS * 24 * 60 * 60 * 1000);

    await paymentRef.set({
      payerUid: uid,
      kind,
      subjectId,
      plan,
      amountPaise,
      listPricePaise: amountPaise,
      currency: 'INR',
      validUntil,
      gateway: 'razorpay',
      gatewayRef: null,
      status: 'created',
      createdAt: FieldValue.serverTimestamp(),
    });

    const auth = Buffer.from(
      `${RAZORPAY_KEY_ID.value()}:${RAZORPAY_KEY_SECRET.value()}`,
    ).toString('base64');

    let res;
    try {
      res = await fetch('https://api.razorpay.com/v1/payment_links', {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          amount: amountPaise,
          currency: 'INR',
          description:
            kind === 'org_plan'
              ? 'PlaySphere club plan — 1 year'
              : 'PlaySphere Premium — 1 year',
          // The webhook reads this straight off the payload — no query
          // needed to find which Firestore row a payment belongs to.
          reference_id: paymentRef.id,
          notes: { paymentId: paymentRef.id, kind, subjectId, plan },
        }),
      });
    } catch (err) {
      logger.error('Razorpay payment_links request failed', err);
      await paymentRef.update({ status: 'failed' });
      throw new HttpsError('unavailable', 'Could not reach the payment provider.');
    }

    if (!res.ok) {
      const body = await res.text().catch(() => '');
      logger.error('Razorpay payment_links rejected', res.status, body);
      await paymentRef.update({ status: 'failed' });
      throw new HttpsError('internal', 'The payment provider declined this request.');
    }

    const link = await res.json();
    await paymentRef.update({
      gatewayRef: link.id,
      status: 'pending',
    });

    return { paymentId: paymentRef.id, url: link.short_url };
  },
);

/**
 * Razorpay calls this directly — never the client. Verifies the payload is
 * really from Razorpay before trusting a word of it, then grants the
 * entitlement itself rather than telling the client to.
 */
export const razorpayWebhook = onRequest(
  { region: 'asia-south1', secrets: [RAZORPAY_WEBHOOK_SECRET] },
  async (req, res) => {
    const signature = req.get('X-Razorpay-Signature');
    const rawBody = req.rawBody;
    if (!signature || !rawBody) {
      res.status(400).send('Missing signature');
      return;
    }

    const expected = crypto
      .createHmac('sha256', RAZORPAY_WEBHOOK_SECRET.value())
      .update(rawBody)
      .digest('hex');

    // Constant-time compare — a signature check that leaks timing
    // information via an early `!==` return is a signature check an
    // attacker can eventually forge one byte at a time.
    const signatureBuf = Buffer.from(signature);
    const expectedBuf = Buffer.from(expected);
    const validSignature =
      signatureBuf.length === expectedBuf.length &&
      crypto.timingSafeEqual(signatureBuf, expectedBuf);
    if (!validSignature) {
      logger.warn('Razorpay webhook signature mismatch');
      res.status(400).send('Bad signature');
      return;
    }

    const event = req.body;
    const paymentLink = event?.payload?.payment_link?.entity;
    const eventType = event?.event;
    if (eventType !== 'payment_link.paid' || !paymentLink) {
      // Every other event (expired, cancelled, a payment's own webhook
      // firing alongside the link's) is acknowledged and ignored — Razorpay
      // retries on anything but 2xx, and there is nothing to do for these.
      res.status(200).send('ignored');
      return;
    }

    const paymentId = paymentLink.reference_id;
    if (!paymentId) {
      res.status(200).send('no reference_id');
      return;
    }

    const paymentRef = db().collection('payments').doc(paymentId);

    try {
      await db().runTransaction(async (tx) => {
        const snap = await tx.get(paymentRef);
        if (!snap.exists) {
          logger.error(`Webhook for unknown payment ${paymentId}`);
          return;
        }
        const data = snap.data();
        // Idempotent: Razorpay can and does deliver a webhook more than
        // once for the same event. Only the first delivery may still find
        // `status: 'pending'` — every retry after that finds `'paid'` and
        // does nothing, which is what makes double-delivery safe rather
        // than a double-granted entitlement or a plan extended twice.
        if (data.status === 'paid') return;

        const gatewayRef =
          paymentLink.payments?.[paymentLink.payments.length - 1]
            ?.payment_id ?? paymentLink.id;

        tx.update(paymentRef, {
          status: 'paid',
          gatewayRef,
          paidAt: FieldValue.serverTimestamp(),
        });

        const validUntil = data.validUntil;
        if (data.kind === 'org_plan') {
          tx.update(db().doc(`orgs/${data.subjectId}`), {
            plan: data.plan,
            planActivatedAt: FieldValue.serverTimestamp(),
            planValidUntil: validUntil,
            planPaymentId: paymentId,
          });
        } else if (data.kind === 'member_plan') {
          tx.update(db().doc(`users/${data.subjectId}`), {
            plan: data.plan,
            planActivatedAt: FieldValue.serverTimestamp(),
            planValidUntil: validUntil,
            planPaymentId: paymentId,
          });
        }
      });
    } catch (err) {
      logger.error('Razorpay webhook processing failed', err);
      res.status(500).send('error');
      return;
    }

    res.status(200).send('ok');
  },
);
