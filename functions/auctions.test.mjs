// Unit tests for the auction reveal's tie-break order.
//
// `rankBids` is the function that decides who actually gets a player, and it
// is the only part of the reveal that runs without a database — everything
// else in `revealAuction` is Firestore reads and writes, covered by the rules
// suite in test/security/auctions.test.mjs.
//
// The determinism tests matter more than they look. The reveal is written to
// be re-runnable after a crash, so if the final tie-break were unstable a
// retry could hand the same player to a different side than the first run
// did — and both sides would have been told they won.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { rankBids } from './auctions.js';

/** A Firestore Timestamp is duck-typed here — `toMillis()` is all that is read. */
const at = (ms) => ({ toMillis: () => ms });

const bid = (id, amountPaise, setAtMs) => ({
  id,
  amountPaise,
  amountSetAt: setAtMs === undefined ? undefined : at(setAtMs),
});

const order = (bids) => rankBids([...bids]).map((b) => b.id);

describe('rankBids — amount first', () => {
  it('puts the highest offer first', () => {
    assert.deepEqual(
      order([bid('a', 100), bid('b', 300), bid('c', 200)]),
      ['b', 'c', 'a'],
    );
  });

  it('ignores seniority when the amounts differ', () => {
    // The earliest bid loses to a later, larger one. First-price, not
    // first-come.
    assert.deepEqual(
      order([bid('early', 100, 1), bid('late', 500, 9999)]),
      ['late', 'early'],
    );
  });

  it('handles a single bid', () => {
    assert.deepEqual(order([bid('only', 100, 1)]), ['only']);
  });

  it('handles no bids', () => {
    assert.deepEqual(order([]), []);
  });
});

describe('rankBids — ties break on when the amount was set', () => {
  it('gives a tie to whoever committed that figure first', () => {
    assert.deepEqual(
      order([bid('later', 500, 2000), bid('earlier', 500, 1000)]),
      ['earlier', 'later'],
    );
  });

  it('does not reward a raise into a tie', () => {
    // The scenario the seniority key exists to kill: bid ₹1 on day one, raise
    // to the leader's figure in the last minute. `amountSetAt` moves on the
    // raise, so the sniper sorts LAST despite being in the auction longest.
    const incumbent = bid('incumbent', 500, 1000);
    const sniper = bid('sniper', 500, 99000); // raised at the death
    assert.deepEqual(order([sniper, incumbent]), ['incumbent', 'sniper']);
  });

  it('breaks a three-way tie in commitment order', () => {
    assert.deepEqual(
      order([bid('c', 500, 3000), bid('a', 500, 1000), bid('b', 500, 2000)]),
      ['a', 'b', 'c'],
    );
  });
});

describe('rankBids — the final key is deterministic', () => {
  it('falls back to team id when amount and time both tie', () => {
    assert.deepEqual(
      order([bid('zeta', 500, 1000), bid('alpha', 500, 1000)]),
      ['alpha', 'zeta'],
    );
  });

  it('gives the same winner however the input is ordered', () => {
    // The property that makes the reveal safe to re-run: a crash halfway
    // through must not be able to change a result on retry.
    const bids = [
      bid('m', 500, 1000),
      bid('a', 500, 1000),
      bid('z', 500, 1000),
      bid('f', 500, 1000),
    ];
    const forward = order(bids);
    const reversed = order([...bids].reverse());
    const shuffled = order([bids[2], bids[0], bids[3], bids[1]]);
    assert.deepEqual(forward, reversed);
    assert.deepEqual(forward, shuffled);
    assert.equal(forward[0], 'a');
  });
});

describe('rankBids — malformed rows cannot crash a reveal', () => {
  it('treats a missing amount as zero rather than throwing', () => {
    // A reveal that throws leaves an auction stuck in `bidding` for everybody,
    // so every field is read defensively. A row with no amount simply loses.
    const ranked = order([{ id: 'broken' }, bid('real', 100, 1)]);
    assert.deepEqual(ranked, ['real', 'broken']);
  });

  it('treats a missing timestamp as the earliest possible', () => {
    // Consistent with `toMillis` returning 0, and harmless: the only rows
    // without one are malformed, and they can only reach this comparison by
    // already tying on amount.
    assert.deepEqual(
      order([bid('timed', 500, 5000), bid('untimed', 500)]),
      ['untimed', 'timed'],
    );
  });

  it('coerces a numeric string amount', () => {
    assert.deepEqual(
      order([bid('str', '900', 1), bid('num', 500, 1)]),
      ['str', 'num'],
    );
  });
});

describe('rankBids sorts in place and returns the same array', () => {
  it('returns its argument', () => {
    const bids = [bid('a', 1, 1), bid('b', 2, 1)];
    assert.equal(rankBids(bids), bids);
    assert.equal(bids[0].id, 'b');
  });
});
