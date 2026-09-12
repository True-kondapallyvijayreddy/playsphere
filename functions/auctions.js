/**
 * Player auctions — the writes a client is not allowed to make.
 *
 * ## Why this file exists when almost nothing else in this product does
 *
 * PlaySphere is client + security rules by design (see the header of
 * `index.js`). Rules are the boundary and Cloud Functions are the exception,
 * kept for the handful of things a rule fundamentally cannot express. An
 * auction has four of them, and they are all the same thing wearing different
 * clothes: **two documents that must change together or not at all.**
 *
 *   - A bid locks money. `bids/{teamId}.amountPaise` and
 *     `teams/{teamId}.committedPaise` are one fact stored twice, and a client
 *     that could write the first without the second could bid its entire
 *     purse on every player in the pool. Firestore rules can check a document
 *     against another document, but they cannot make two writes atomic, and
 *     `getAfter()` on a batch still lets the client choose the arithmetic.
 *   - The reveal reads every sealed bid at once. No client may read even one
 *     of them, which is the whole point.
 *   - A trade moves players and cash between two squads. Four documents.
 *   - Closing bidding has to happen at a time nobody is holding the phone.
 *
 * So: bids, reveals, trades and status transitions live here, and
 * `firestore.rules` denies all four paths to clients outright. Everything
 * else about an auction — joining, approving, repricing, naming a side,
 * proposing and accepting a trade — is an ordinary rules-governed write and
 * is deliberately NOT in this file.
 *
 * ## The committed-budget rule, in one paragraph
 *
 * `committedPaise` is the sum of a team's live bids. Every bid write moves it
 * by exactly the delta and refuses if the result would exceed `pursePaise`.
 * Because of that invariant the reveal is a pure per-lot maximum: every
 * winner can always pay, no lot's result depends on any other lot's, and
 * nothing ever has to be unwound. Losing bids release their commitment;
 * winning bids convert it to `spentPaise`. See lib/core/models/auction.dart
 * for why this is preferred to free bidding with a cascade.
 *
 * ## Region
 *
 * asia-south1, like everything else. The scheduler states it explicitly for
 * the reason `arena.js` documents: ES module imports evaluate before the
 * importing module's body, so `setGlobalOptions` in index.js has not run yet
 * and a scheduler with no region silently defaults to Iowa.
 */

import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { CALLABLE_OPTS } from './app_check.js';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

import { persistNotifications, pushToUids } from './push.js';

function db() {
  return getFirestore();
}

/** Mirrors `notification()` in index.js — same payload shape, same deep-link
 * convention. Duplicated rather than exported across files for the reason the
 * player-code generator in family.js is: these two modules do not otherwise
 * depend on each other, and a shared helper would make index.js's whole
 * trigger graph load to send one push. */
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

async function sendToUsers(uids, payload) {
  const unique = await persistNotifications(uids, payload);
  await pushToUids(unique, payload);
}

/** ₹1,00,000 — matches `AuctionMoney.format` on the client so a push and the
 * screen it opens do not disagree about the number. */
function rupees(paise) {
  const value = Math.trunc(paise / 100);
  const digits = Math.abs(value).toString();
  if (digits.length <= 3) return `₹${value}`;
  const tail = digits.slice(-3);
  let head = digits.slice(0, -3);
  const parts = [];
  while (head.length > 2) {
    parts.unshift(head.slice(-2));
    head = head.slice(0, -2);
  }
  if (head) parts.unshift(head);
  return `₹${value < 0 ? '-' : ''}${parts.join(',')},${tail}`;
}

function requireAuth(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function requireString(value, field) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new HttpsError('invalid-argument', `Missing ${field}.`);
  }
  return value;
}

/**
 * The caller's participant row, or a refusal.
 *
 * Every callable here starts with this. Membership of an auction is the
 * participants subcollection and nothing else — no club, no district, no team
 * grants anything — so this is the single place that fact is read.
 */
async function participantOf(auctionId, uid, tx = null) {
  const ref = db()
    .collection('auctions').doc(auctionId)
    .collection('participants').doc(uid);
  const snap = tx ? await tx.get(ref) : await ref.get();
  if (!snap.exists) {
    throw new HttpsError('permission-denied', 'You are not in this auction.');
  }
  const data = snap.data();
  if (data.status !== 'approved') {
    throw new HttpsError('permission-denied', 'Your place is not approved yet.');
  }
  return data;
}

function hasRole(participant, role) {
  return Array.isArray(participant.roles) && participant.roles.includes(role);
}

async function requireOrganizer(auctionId, uid, tx = null) {
  const p = await participantOf(auctionId, uid, tx);
  if (!hasRole(p, 'organizer')) {
    throw new HttpsError('permission-denied', 'Only an organizer can do that.');
  }
  return p;
}

function toMillis(value) {
  return value?.toMillis?.() ?? 0;
}

// ===========================================================================
// Bidding
// ===========================================================================

/**
 * Place, raise, lower or withdraw one sealed bid.
 *
 * `amountPaise: 0` withdraws — one entry point rather than two, because
 * withdrawing and re-bidding are the same transaction with a different delta
 * and splitting them would mean maintaining the invariant in two places.
 *
 * ## What is checked, and why each one is here
 *
 * Everything below is re-checked server-side even though the client greys the
 * button out for most of it. The client's copy of the auction can be seconds
 * stale, and the last seconds are exactly when it matters.
 *
 *   - the auction is bidding, and `bidsCloseAt` has not passed. The deadline
 *     is checked here and not only in the scheduler, because the scheduler
 *     runs every few minutes and there is always a window where the status
 *     still says `bidding` and the clock has run out. A bid accepted in that
 *     window would be a bid placed after the deadline.
 *   - the lot is still in the pool. A sold lot never reopens, in this round
 *     or any later one.
 *   - the amount clears the lot's floor.
 *   - the new commitment fits the purse. THE rule — see the file header.
 *   - the squad cap counts won players plus live bids, because every live bid
 *     is a player this team might be about to own. Checking only won players
 *     would let a full-cap team keep bidding and blow past it at the reveal.
 *
 * Idempotent in the sense that matters: re-sending the same amount is a
 * no-op delta and leaves `amountSetAt` alone, so a retried call cannot cost
 * somebody their tie-break seniority.
 */
export const placeAuctionBid = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  const lotId = requireString(request.data?.lotId, 'lotId');
  const amountPaise = Number(request.data?.amountPaise);

  if (!Number.isInteger(amountPaise) || amountPaise < 0) {
    throw new HttpsError('invalid-argument', 'That is not a valid amount.');
  }
  if (amountPaise > 100000000000) {
    throw new HttpsError('invalid-argument', 'That amount is too large.');
  }

  const participant = await participantOf(auctionId, uid);
  if (!hasRole(participant, 'bidder')) {
    throw new HttpsError('permission-denied', 'You do not own a side here.');
  }

  const auctionRef = db().collection('auctions').doc(auctionId);
  const teamRef = auctionRef.collection('teams').doc(uid);
  const lotRef = auctionRef.collection('lots').doc(lotId);
  const bidRef = lotRef.collection('bids').doc(uid);

  const result = await db().runTransaction(async (tx) => {
    // Every read before every write — Firestore transactions require it, and
    // the four documents here are exactly the ones the invariant spans.
    const [auctionSnap, teamSnap, lotSnap, bidSnap] = await Promise.all([
      tx.get(auctionRef), tx.get(teamRef), tx.get(lotRef), tx.get(bidRef),
    ]);

    if (!auctionSnap.exists) throw new HttpsError('not-found', 'Auction is gone.');
    if (!teamSnap.exists) throw new HttpsError('failed-precondition', 'You have no side in this auction yet.');
    if (!lotSnap.exists) throw new HttpsError('not-found', 'That player is not in the pool.');

    const auction = auctionSnap.data();
    const team = teamSnap.data();
    const lot = lotSnap.data();

    if (auction.status !== 'bidding') {
      throw new HttpsError('failed-precondition', 'Bidding is not open.');
    }
    const closeMs = toMillis(auction.bidsCloseAt);
    if (closeMs && Date.now() >= closeMs) {
      throw new HttpsError('failed-precondition', 'Bidding has closed.');
    }
    if (lot.status !== 'pool') {
      throw new HttpsError('failed-precondition', 'That player is no longer available.');
    }

    const previous = bidSnap.exists ? Number(bidSnap.data().amountPaise) || 0 : 0;
    if (amountPaise === previous) return { unchanged: true, amountPaise };

    const withdrawing = amountPaise === 0;
    const basePrice = Number(lot.basePricePaise) || 0;
    if (!withdrawing && amountPaise < basePrice) {
      throw new HttpsError(
        'failed-precondition',
        `The base price for this player is ${rupees(basePrice)}.`,
      );
    }

    const purse = Number(team.pursePaise) || 0;
    const committed = Number(team.committedPaise) || 0;
    const nextCommitted = committed - previous + amountPaise;
    if (nextCommitted > purse) {
      throw new HttpsError(
        'failed-precondition',
        `That would commit ${rupees(nextCommitted)} of a ${rupees(purse)} purse. `
        + `You have ${rupees(purse - committed + previous)} free for this player.`,
      );
    }

    // A live bid is a player you might be about to own, so it counts against
    // the cap exactly as a won one does.
    const liveBids = Number(team.liveBidCount) || 0;
    const won = Number(team.wonCount) || 0;
    const nextLiveBids = liveBids + (withdrawing ? -1 : (previous === 0 ? 1 : 0));
    const maxSquad = Number.isInteger(auction.maxSquadSize) ? auction.maxSquadSize : null;
    if (maxSquad !== null && won + nextLiveBids > maxSquad) {
      throw new HttpsError(
        'failed-precondition',
        `Squads are capped at ${maxSquad}. You hold ${won} and have ${liveBids} bid(s) live — `
        + 'withdraw one before bidding on somebody else.',
      );
    }

    if (withdrawing) {
      tx.delete(bidRef);
      tx.update(lotRef, { bidCount: FieldValue.increment(-1) });
    } else if (previous === 0) {
      tx.set(bidRef, {
        teamId: uid,
        lotId,
        auctionId,
        teamName: team.name ?? 'Team',
        playerName: lot.displayName ?? 'Player',
        amountPaise,
        round: Number(auction.round) || 1,
        isWinning: false,
        amountSetAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.update(lotRef, { bidCount: FieldValue.increment(1) });
    } else {
      // Changing the amount restarts tie-break seniority. Otherwise the way
      // to win a tie is to bid ₹1 on day one and raise it in the last minute,
      // which is a live auction's behaviour smuggled into a sealed one.
      tx.update(bidRef, {
        amountPaise,
        round: Number(auction.round) || 1,
        amountSetAt: FieldValue.serverTimestamp(),
      });
    }

    tx.update(teamRef, {
      committedPaise: nextCommitted,
      liveBidCount: nextLiveBids,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      unchanged: false,
      amountPaise,
      availablePaise: purse - nextCommitted,
    };
  });

  return result;
});

// ===========================================================================
// Opening and closing
// ===========================================================================

/**
 * Move an auction from registration into bidding.
 *
 * Refuses without at least two sides and one player, which is not pedantry:
 * a sealed auction with one bidder awards every lot at its base price and
 * teaches the organizer nothing except that the feature is broken.
 *
 * Sets `bidsCloseAt` from the caller. "finally at 5 or after 10 days" is
 * whatever the organizer picks here — the design has no opinion about the
 * length of the window, only that there is one and that it is announced
 * before the first bid.
 */
export const openAuctionBidding = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  const closesAtMs = Number(request.data?.bidsCloseAtMs);

  if (!Number.isFinite(closesAtMs) || closesAtMs <= Date.now()) {
    throw new HttpsError('invalid-argument', 'Pick a closing time in the future.');
  }

  await requireOrganizer(auctionId, uid);

  const auctionRef = db().collection('auctions').doc(auctionId);
  const [teams, lots] = await Promise.all([
    auctionRef.collection('teams').count().get(),
    auctionRef.collection('lots').where('status', '==', 'pool').count().get(),
  ]);
  const teamCount = teams.data().count;
  const poolCount = lots.data().count;

  if (teamCount < 2) {
    throw new HttpsError('failed-precondition', 'You need at least two sides before bidding opens.');
  }
  if (poolCount < 1) {
    throw new HttpsError('failed-precondition', 'There are no players in the pool.');
  }

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(auctionRef);
    const auction = snap.data();
    // `revealed` is allowed in as well: that is the "open another round"
    // path, which is the same transition with the unsold lots still sitting
    // in the pool. A sold lot refuses bids by its own status, so nothing has
    // to be cleared between rounds — and a lot can only be unsold if nobody
    // bid on it at all, since any bid at or above the floor wins an
    // uncontested lot.
    if (!['registration', 'revealed'].includes(auction.status)) {
      throw new HttpsError('failed-precondition', 'Bidding cannot be opened from here.');
    }
    const nextRound = auction.status === 'revealed'
      ? (Number(auction.round) || 1) + 1
      : (Number(auction.round) || 1);

    tx.update(auctionRef, {
      status: 'bidding',
      round: nextRound,
      bidsCloseAt: Timestamp.fromMillis(closesAtMs),
      teamCount,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  // Everybody approved: the bidders because the clock has started, the
  // players because being in a pool nobody told you had opened is how a
  // player finds out they went unsold.
  const participants = await auctionRef
    .collection('participants').where('status', '==', 'approved').get();
  const auctionSnap = await auctionRef.get();
  const name = auctionSnap.data()?.name ?? 'Auction';

  await sendToUsers(participants.docs.map((d) => d.id), notification({
    id: `auction_bidding_${auctionId}_${auctionSnap.data()?.round ?? 1}`,
    type: 'auction_bidding_open',
    title: `Bidding is open — ${name}`,
    body: `${poolCount} player(s) in the pool. Bids close ${new Date(closesAtMs).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' })}.`,
    route: '/auctions/:auctionId',
    params: { auctionId },
  }));

  return { ok: true, teamCount, poolCount };
});

/**
 * Orders one lot's bids best-first, in place. The winner is `bids[0]`.
 *
 * Exported and pure because this is the function that actually decides who
 * gets a player, and it is the one piece of the reveal that can be tested
 * without a database. See `functions/auctions.test.mjs`.
 *
 * Three keys, in order:
 *
 *   1. **Amount, descending.** First-price: the highest offer wins and pays
 *      what it offered. Not second-price — "whoever bids high gets the
 *      player" is what an organizer announces at the ground, and a winner
 *      charged a different number than they wrote is a conversation nobody
 *      wants to have.
 *   2. **`amountSetAt`, ascending.** The side that committed that figure
 *      FIRST takes the tie. Note it is when the amount was last changed, not
 *      when the row was created: otherwise the way to win every tie is to bid
 *      ₹1 on day one and raise it in the final minute, which smuggles a live
 *      auction's sniping back into a sealed one.
 *   3. **Team id, ascending.** Arbitrary, and that is the point — it is the
 *      only key left, and it must be DETERMINISTIC so that two runs of the
 *      reveal over the same data can never produce two different squads. The
 *      reveal is written to be re-runnable after a crash, so a non-deterministic
 *      final tie-break would be a player who changes hands on a retry.
 */
export function rankBids(bids) {
  bids.sort((a, b) => {
    const byAmount = (Number(b.amountPaise) || 0) - (Number(a.amountPaise) || 0);
    if (byAmount !== 0) return byAmount;
    const bySeniority = toMillis(a.amountSetAt) - toMillis(b.amountSetAt);
    if (bySeniority !== 0) return bySeniority;
    return a.id < b.id ? -1 : 1;
  });
  return bids;
}

/**
 * The reveal: open every sealed bid at once and award the lots.
 *
 * Pure per-lot maximum, made safe by the committed-budget invariant — see the
 * file header. Ties break on `amountSetAt` (earlier commitment wins) and then
 * on team id, which is arbitrary but deterministic, so two runs of this
 * function over the same data can never produce two different squads.
 *
 * Written to be **re-runnable**. It reads only lots still in the pool and
 * only bids from the current round, so a run that dies halfway through leaves
 * the lots it had already awarded alone and finishes the rest on the next
 * tick. That matters more than it looks: this is the one place in the product
 * where a crash could otherwise mean a player sold twice.
 */
async function revealAuction(auctionRef) {
  const auctionSnap = await auctionRef.get();
  if (!auctionSnap.exists) return null;
  const auction = auctionSnap.data();
  if (auction.status !== 'bidding') return null;

  const round = Number(auction.round) || 1;
  const pool = await auctionRef.collection('lots').where('status', '==', 'pool').get();

  /** teamId -> { spent, won, released } accumulated across every lot. */
  const teamDeltas = new Map();
  const bump = (teamId, key, value) => {
    const entry = teamDeltas.get(teamId) ?? { spent: 0, won: 0, released: 0, lost: 0 };
    entry[key] += value;
    teamDeltas.set(teamId, entry);
  };

  const sales = [];
  let soldThisRound = 0;

  for (const lotDoc of pool.docs) {
    const bids = await lotDoc.ref.collection('bids').get();
    // Only this round's bids can win. A bid left over from an earlier round
    // cannot exist on a pooled lot — an unsold lot is by definition one
    // nobody bid on — but filtering makes that an assertion rather than an
    // assumption somebody has to remember.
    const live = bids.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .filter((b) => (Number(b.round) || 1) === round);

    if (live.length === 0) {
      await lotDoc.ref.update({
        status: 'unsold',
        resolvedAt: FieldValue.serverTimestamp(),
      });
      continue;
    }

    rankBids(live);

    const winner = live[0];
    const price = Number(winner.amountPaise) || 0;
    const lot = lotDoc.data();

    const batch = db().batch();
    batch.update(lotDoc.ref, {
      status: 'sold',
      soldToTeamId: winner.id,
      soldToTeamName: winner.teamName ?? 'Team',
      soldPricePaise: price,
      soldInRound: round,
      acquiredBy: 'auction',
      resolvedAt: FieldValue.serverTimestamp(),
    });
    for (const bid of live) {
      batch.update(lotDoc.ref.collection('bids').doc(bid.id), {
        isWinning: bid.id === winner.id,
      });
    }
    await batch.commit();

    // The winner's commitment becomes spend; every loser's is released. Both
    // legs are accumulated and applied per team below, so a team that lost on
    // forty lots takes one write rather than forty.
    bump(winner.id, 'spent', price);
    bump(winner.id, 'won', 1);
    for (const bid of live) {
      bump(bid.id, 'released', Number(bid.amountPaise) || 0);
      if (bid.id !== winner.id) bump(bid.id, 'lost', 1);
    }
    sales.push({
      lotId: lotDoc.id,
      playerName: lot.displayName ?? 'Player',
      teamId: winner.id,
      price,
    });
    soldThisRound++;
  }

  // `committedPaise` drops by everything that was locked on these lots —
  // winners included, since a winner's lock becomes `spentPaise` instead.
  // After this the two agree for every team, which is what makes
  // `remainingPaise` meaningful during the trade window.
  const teamWrites = db().batch();
  for (const [teamId, delta] of teamDeltas) {
    teamWrites.update(auctionRef.collection('teams').doc(teamId), {
      committedPaise: FieldValue.increment(-delta.released),
      spentPaise: FieldValue.increment(delta.spent),
      wonCount: FieldValue.increment(delta.won),
      liveBidCount: FieldValue.increment(-(delta.won + delta.lost)),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await teamWrites.commit();

  await auctionRef.update({
    status: 'revealed',
    bidsCloseAt: null,
    revealedAt: FieldValue.serverTimestamp(),
    soldCount: FieldValue.increment(soldThisRound),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await notifyReveal(auctionRef, auction, sales, round);
  return { soldThisRound, unsold: pool.size - soldThisRound };
}

/**
 * Tell everybody what happened — and tell each person the part that is about
 * them rather than a broadcast nobody reads.
 *
 * A player hears who bought them and for how much. A team owner hears how
 * many they took and what is left. Everybody else hears that the squads are
 * up.
 */
async function notifyReveal(auctionRef, auction, sales, round) {
  const auctionId = auctionRef.id;
  const name = auction.name ?? 'Auction';
  const route = '/auctions/:auctionId';

  const byTeam = new Map();
  for (const sale of sales) {
    byTeam.set(sale.teamId, [...(byTeam.get(sale.teamId) ?? []), sale]);
  }

  const jobs = [];

  for (const sale of sales) {
    jobs.push(sendToUsers([sale.lotId], notification({
      id: `auction_sold_${auctionId}_${round}_${sale.lotId}`,
      type: 'auction_result',
      title: `You were picked — ${name}`,
      body: `${byTeam.get(sale.teamId)?.[0]?.teamName ?? 'A side'} took you for ${rupees(sale.price)}.`,
      route,
      params: { auctionId },
    })));
  }

  const teams = await auctionRef.collection('teams').get();
  for (const teamDoc of teams.docs) {
    const team = teamDoc.data();
    const mine = byTeam.get(teamDoc.id) ?? [];
    const remaining = (Number(team.pursePaise) || 0) - (Number(team.spentPaise) || 0);
    jobs.push(sendToUsers([teamDoc.id], notification({
      id: `auction_reveal_${auctionId}_${round}_${teamDoc.id}`,
      type: 'auction_result',
      title: `Round ${round} results — ${name}`,
      body: mine.length === 0
        ? `You took nobody this round. ${rupees(remaining)} still unspent.`
        : `You took ${mine.length} player(s): ${mine.map((s) => s.playerName).join(', ')}.`,
      route,
      params: { auctionId },
    })));
  }

  await Promise.all(jobs).catch((error) => {
    // A failed push must never roll back a completed reveal. The squads are
    // already correct in Firestore and the app shows them on next open.
    logger.warn('auction reveal notification failed', { auctionId, error: String(error) });
  });
}

/**
 * The organizer opening the lots by hand, before the deadline.
 *
 * Not a convenience. The scheduler below runs every five minutes, and an
 * organizer standing in front of twenty people who have all finished bidding
 * should not have to explain a five-minute wait to them. Same code path,
 * same result — it only skips the clock.
 */
export const revealAuctionNow = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  await requireOrganizer(auctionId, uid);

  const auctionRef = db().collection('auctions').doc(auctionId);
  const outcome = await revealAuction(auctionRef);
  if (outcome === null) {
    throw new HttpsError('failed-precondition', 'This auction is not taking bids.');
  }
  return outcome;
});

/**
 * The deadline, honoured without anybody holding a phone.
 *
 * Every five minutes, mirroring `closeIdleArenaGames` — which means a reveal
 * lands within five minutes of the announced time rather than on the second.
 * That looseness is acceptable here for the same reason it is there: nothing
 * about the RESULT depends on when this runs, because the bids stopped being
 * accepted at `bidsCloseAt` exactly (`placeAuctionBid` checks the clock, not
 * the status). The only thing a late tick delays is the announcement.
 */
export const revealDueAuctions = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Kolkata',
    // Stated explicitly for the reason arena.js documents at length: a
    // scheduler has no database to infer its region from and would otherwise
    // poll Mumbai from Iowa.
    region: 'asia-south1',
  },
  async () => {
    const due = await db()
      .collection('auctions')
      .where('status', '==', 'bidding')
      .where('bidsCloseAt', '<=', new Date())
      .orderBy('bidsCloseAt')
      // Capped so a backlog cannot become an unbounded write burst; the next
      // tick takes the rest.
      .limit(20)
      .get();

    if (due.empty) return;

    for (const doc of due.docs) {
      try {
        const outcome = await revealAuction(doc.ref);
        if (outcome) {
          logger.info('auction revealed', { auctionId: doc.id, ...outcome });
        }
      } catch (error) {
        // One bad auction must not stop the others. It stays `bidding` and is
        // picked up again on the next tick.
        logger.error('auction reveal failed', { auctionId: doc.id, error: String(error) });
      }
    }
  },
);

/**
 * Lock the squads. The end of the exchange window, by hand.
 *
 * `exchangeClosesAt` already closes trading on its own, and both gates are
 * checked independently — see `executeAuctionTrade`. This exists because an
 * event that starts early should not have to wait for a date the organizer
 * set optimistically a fortnight ago.
 */
export const lockAuctionSquads = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  await requireOrganizer(auctionId, uid);

  const auctionRef = db().collection('auctions').doc(auctionId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(auctionRef);
    if (snap.data()?.status !== 'revealed') {
      throw new HttpsError('failed-precondition', 'Squads can only be locked after the reveal.');
    }
    tx.update(auctionRef, {
      status: 'locked',
      lockedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  // Outstanding offers are killed rather than left hanging: a proposal that
  // can never be accepted is worse in an inbox than one that is gone.
  const open = await auctionRef.collection('trades')
    .where('status', '==', 'proposed').get();
  if (!open.empty) {
    const batch = db().batch();
    open.docs.forEach((d) => batch.update(d.ref, {
      status: 'cancelled',
      decidedAt: FieldValue.serverTimestamp(),
    }));
    await batch.commit();
  }

  return { ok: true, cancelledTrades: open.size };
});

// ===========================================================================
// The exchange window
// ===========================================================================

/**
 * Execute an agreed trade: move the players, move the cash.
 *
 * The counterparty has already ACCEPTED through an ordinary rules-governed
 * write. This is the second half, and it is separate for a reason: splitting
 * agreement from execution means the accept can never half-apply. A client
 * that dies between the two leaves a trade marked `accepted` with no
 * `executedAt`, which this function is idempotent about and will finish when
 * either side opens the screen.
 *
 * ## What is re-checked here even though the rules checked it
 *
 * Both window gates, and every player named. A trade proposed on Tuesday and
 * accepted on Friday may have been overtaken by a lock, by the exchange
 * deadline, or — the one that actually bites — by one of its own players
 * having already moved in a different trade. The rules cannot see any of
 * that, because a rule may not read the eleven lot documents an offer names.
 */
export const executeAuctionTrade = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  const tradeId = requireString(request.data?.tradeId, 'tradeId');

  await participantOf(auctionId, uid);

  const auctionRef = db().collection('auctions').doc(auctionId);
  const tradeRef = auctionRef.collection('trades').doc(tradeId);

  const outcome = await db().runTransaction(async (tx) => {
    const tradeSnap = await tx.get(tradeRef);
    if (!tradeSnap.exists) throw new HttpsError('not-found', 'That offer is gone.');
    const trade = tradeSnap.data();

    if (trade.executedAt) return { alreadyDone: true };
    if (trade.status !== 'accepted') {
      throw new HttpsError('failed-precondition', 'That offer has not been agreed yet.');
    }
    if (![trade.fromTeamId, trade.toTeamId].includes(uid)) {
      throw new HttpsError('permission-denied', 'This is not your trade.');
    }

    const auctionSnap = await tx.get(auctionRef);
    const auction = auctionSnap.data();
    if (auction.status !== 'revealed') {
      throw new HttpsError('failed-precondition', 'Trading is closed for this auction.');
    }
    const closes = toMillis(auction.exchangeClosesAt);
    if (closes && Date.now() >= closes) {
      throw new HttpsError('failed-precondition', 'The exchange window has closed.');
    }

    const fromRef = auctionRef.collection('teams').doc(trade.fromTeamId);
    const toRef = auctionRef.collection('teams').doc(trade.toTeamId);
    const [fromSnap, toSnap] = await Promise.all([tx.get(fromRef), tx.get(toRef)]);
    if (!fromSnap.exists || !toSnap.exists) {
      throw new HttpsError('failed-precondition', 'One of these sides no longer exists.');
    }

    const fromLotIds = Array.isArray(trade.fromLotIds) ? trade.fromLotIds : [];
    const toLotIds = Array.isArray(trade.toLotIds) ? trade.toLotIds : [];

    const lotRefs = [...fromLotIds, ...toLotIds]
      .map((id) => auctionRef.collection('lots').doc(id));
    const lotSnaps = lotRefs.length ? await tx.getAll(...lotRefs) : [];

    // Every named player must still be sold, and still be held by the side
    // that is offering them. This is what catches a player who moved in
    // another trade between the proposal and the acceptance.
    lotSnaps.forEach((snap, index) => {
      const expectedOwner = index < fromLotIds.length ? trade.fromTeamId : trade.toTeamId;
      if (!snap.exists) {
        throw new HttpsError('failed-precondition', 'A player in this offer no longer exists.');
      }
      const lot = snap.data();
      if (lot.status !== 'sold' || lot.soldToTeamId !== expectedOwner) {
        throw new HttpsError(
          'failed-precondition',
          `${lot.displayName ?? 'A player'} has already moved. This offer is out of date.`,
        );
      }
    });

    const fromCash = Number(trade.fromCashPaise) || 0;
    const toCash = Number(trade.toCashPaise) || 0;

    // Cash sent raises your spend; cash received lowers it. `remainingPaise`
    // is purse minus spend, so this is the only place it needs to move.
    const fromSpent = (Number(fromSnap.data().spentPaise) || 0) + fromCash - toCash;
    const toSpent = (Number(toSnap.data().spentPaise) || 0) + toCash - fromCash;

    if (fromSpent > (Number(fromSnap.data().pursePaise) || 0)) {
      throw new HttpsError('failed-precondition', `${trade.fromTeamName} cannot cover that cash.`);
    }
    if (toSpent > (Number(toSnap.data().pursePaise) || 0)) {
      throw new HttpsError('failed-precondition', `${trade.toTeamName} cannot cover that cash.`);
    }

    const maxSquad = Number.isInteger(auction.maxSquadSize) ? auction.maxSquadSize : null;
    const fromWon = (Number(fromSnap.data().wonCount) || 0) - fromLotIds.length + toLotIds.length;
    const toWon = (Number(toSnap.data().wonCount) || 0) - toLotIds.length + fromLotIds.length;
    if (maxSquad !== null && (fromWon > maxSquad || toWon > maxSquad)) {
      throw new HttpsError('failed-precondition', `That would put a squad over the cap of ${maxSquad}.`);
    }

    lotSnaps.forEach((snap, index) => {
      const goingTo = index < fromLotIds.length ? trade.toTeamId : trade.fromTeamId;
      const goingToName = index < fromLotIds.length ? trade.toTeamName : trade.fromTeamName;
      tx.update(snap.ref, {
        soldToTeamId: goingTo,
        soldToTeamName: goingToName,
        // The price they were bought for is left alone on purpose. It is the
        // auction's record of what the market paid for this player, and a
        // trade is a separate transaction between two owners — overwriting it
        // would erase the only number the reveal produced.
        acquiredBy: 'trade',
      });
    });

    tx.update(fromRef, {
      spentPaise: fromSpent,
      committedPaise: fromSpent,
      wonCount: fromWon,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(toRef, {
      spentPaise: toSpent,
      committedPaise: toSpent,
      wonCount: toWon,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(tradeRef, {
      executedAt: FieldValue.serverTimestamp(),
    });

    return { alreadyDone: false, moved: lotSnaps.length };
  });

  if (!outcome.alreadyDone) {
    const trade = (await tradeRef.get()).data();
    await sendToUsers([trade.fromTeamId, trade.toTeamId], notification({
      id: `auction_trade_done_${auctionId}_${tradeId}`,
      type: 'auction_trade',
      title: 'Trade completed',
      body: `${trade.fromTeamName} and ${trade.toTeamName}: ${
        (trade.fromLotNames ?? []).join(', ') || 'cash'
      } for ${(trade.toLotNames ?? []).join(', ') || 'cash'}.`,
      route: '/auctions/:auctionId/trades',
      params: { auctionId },
    })).catch((error) => logger.warn('trade notification failed', { error: String(error) }));
  }

  return outcome;
});

// ===========================================================================
// Notifications for the ordinary, rules-governed writes
// ===========================================================================

// Nothing here is a trigger on the auction subcollections. Approvals and trade
// proposals are client writes and could each carry an onDocumentWritten, but
// four more triggers on a hot subcollection to send four pushes is a poor
// trade against the two callables below, which the acting client is already
// awaiting and which cost nothing when nobody is listening.

/**
 * "Your place is approved" / "you were not taken on."
 *
 * Called by the organizer's client right after it writes the decision. The
 * decision itself is the Firestore write and stands whether or not this
 * succeeds — which is why the client does not await it before updating the
 * screen.
 */
export const notifyAuctionDecision = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  const targetUid = requireString(request.data?.targetUid, 'targetUid');
  await requireOrganizer(auctionId, uid);

  const [auctionSnap, partSnap] = await Promise.all([
    db().collection('auctions').doc(auctionId).get(),
    db().collection('auctions').doc(auctionId)
      .collection('participants').doc(targetUid).get(),
  ]);
  if (!auctionSnap.exists || !partSnap.exists) return { ok: false };

  const name = auctionSnap.data().name ?? 'Auction';
  const part = partSnap.data();
  const approved = part.status === 'approved';
  const asPlayer = Array.isArray(part.roles) && part.roles.includes('player');

  await sendToUsers([targetUid], notification({
    id: `auction_decision_${auctionId}_${targetUid}_${part.status}`,
    type: 'auction_decision',
    title: approved ? `You are in — ${name}` : `${name}`,
    body: approved
      ? (asPlayer
        ? 'You are in the player pool. Sides can bid for you when bidding opens.'
        : 'Your side is approved. Your purse is on the auction screen.')
      : 'You were not taken on for this one.',
    route: '/auctions/:auctionId',
    params: { auctionId },
  }));

  return { ok: true };
});

/** "Somebody has offered you a trade." Same shape and same reasoning as
 * [notifyAuctionDecision] — the proposal is the Firestore write, this is only
 * the tap on the shoulder. */
export const notifyAuctionTrade = onCall(CALLABLE_OPTS, async (request) => {
  const uid = requireAuth(request);
  const auctionId = requireString(request.data?.auctionId, 'auctionId');
  const tradeId = requireString(request.data?.tradeId, 'tradeId');
  await participantOf(auctionId, uid);

  const snap = await db().collection('auctions').doc(auctionId)
    .collection('trades').doc(tradeId).get();
  if (!snap.exists) return { ok: false };
  const trade = snap.data();

  // Whichever side the caller is not. An offer notifies the other party; an
  // acceptance notifies the proposer.
  const recipient = trade.fromTeamId === uid ? trade.toTeamId : trade.fromTeamId;
  const accepted = trade.status === 'accepted';

  await sendToUsers([recipient], notification({
    id: `auction_trade_${auctionId}_${tradeId}_${trade.status}`,
    type: 'auction_trade',
    title: accepted ? 'Your offer was accepted' : `Trade offer from ${trade.fromTeamName}`,
    body: accepted
      ? 'Open it to complete the swap.'
      : `${(trade.fromLotNames ?? []).join(', ') || 'Cash'} for ${(trade.toLotNames ?? []).join(', ') || 'cash'}.`,
    route: '/auctions/:auctionId/trades',
    params: { auctionId },
  }));

  return { ok: true };
});
