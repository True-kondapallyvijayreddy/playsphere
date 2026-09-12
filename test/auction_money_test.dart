import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/auction.dart';

/// Pure-domain tests for the auction's money and code handling.
///
/// Everything here is arithmetic and string handling that runs on somebody's
/// purse. The rules suite (test/security/auctions.test.mjs) proves nobody can
/// write these numbers from a client; this proves the ones we do show are the
/// right ones.
void main() {
  group('AuctionMoney.groupIndian', () {
    test('groups in the Indian 2-2-3 pattern', () {
      // The reason this exists rather than a thousands separator: the people
      // using this read "one lakh", and `100,000` is the wrong shape for them.
      expect(AuctionMoney.groupIndian(100000), '1,00,000');
      expect(AuctionMoney.groupIndian(1234567), '12,34,567');
      expect(AuctionMoney.groupIndian(10000000), '1,00,00,000');
    });

    test('leaves three digits and fewer alone', () {
      expect(AuctionMoney.groupIndian(0), '0');
      expect(AuctionMoney.groupIndian(7), '7');
      expect(AuctionMoney.groupIndian(999), '999');
    });

    test('handles the boundary at four digits', () {
      expect(AuctionMoney.groupIndian(1000), '1,000');
      expect(AuctionMoney.groupIndian(99999), '99,999');
    });

    test('keeps the sign on a negative', () {
      // A purse cannot go negative, but the bid sheet renders "free after this
      // bid" live as somebody types, and that goes negative for as long as it
      // takes them to delete a digit.
      expect(AuctionMoney.groupIndian(-100000), '-1,00,000');
    });
  });

  group('AuctionMoney.format', () {
    test('renders paise as grouped rupees', () {
      expect(AuctionMoney.format(10000000), '₹1,00,000');
      expect(AuctionMoney.format(100000), '₹1,000');
    });

    test('renders zero as ₹0, never as "Free"', () {
      // The whole reason this is not `Pricing.formatPaise`. "Free" is right
      // for a shop listing and nonsense for a purse with nothing left in it —
      // which is the single most important number on the bidding screen.
      expect(AuctionMoney.format(0), '₹0');
    });

    test('drops sub-rupee paise rather than rounding up', () {
      // Never round a purse UP: a side shown ₹1 it does not have will have a
      // bid refused with a number that contradicts the screen.
      expect(AuctionMoney.format(199), '₹1');
    });
  });

  group('AuctionMoney.compact', () {
    test('uses lakhs and crores', () {
      expect(AuctionMoney.compact(10000000), '₹1.0L');
      expect(AuctionMoney.compact(25000000), '₹2.5L');
      expect(AuctionMoney.compact(1000000000), '₹1.0Cr');
    });

    test('uses thousands between ₹1,000 and ₹1,00,000', () {
      expect(AuctionMoney.compact(1250000), '₹12.5K');
    });

    test('does not abbreviate below ₹1,000', () {
      expect(AuctionMoney.compact(50000), '₹500');
      expect(AuctionMoney.compact(0), '₹0');
    });
  });

  group('AuctionMoney.parseRupees', () {
    test('accepts what people actually type', () {
      expect(AuctionMoney.parseRupees('100000'), 10000000);
      expect(AuctionMoney.parseRupees('1,00,000'), 10000000);
      expect(AuctionMoney.parseRupees('₹50000'), 5000000);
      expect(AuctionMoney.parseRupees('  25000  '), 2500000);
    });

    test('rejects nothing usable', () {
      expect(AuctionMoney.parseRupees(''), isNull);
      expect(AuctionMoney.parseRupees('abc'), isNull);
      expect(AuctionMoney.parseRupees('₹'), isNull);
    });

    test('rejects an absurd paste rather than overflowing', () {
      // Forty digits multiplied by 100 wraps to a negative purse on a 64-bit
      // int, and a negative purse is one the rules would accept.
      expect(AuctionMoney.parseRupees('9' * 40), isNull);
    });

    test('treats a minus sign as separator noise, never as a negative', () {
      // The strip-non-digits approach means "-5000" parses as 5000. That is
      // deliberate: there is no such thing as a negative bid, and silently
      // reading one as positive is better than rejecting a number somebody
      // typed a stray hyphen into.
      expect(AuctionMoney.parseRupees('-5000'), 500000);
    });

    test('multiplication by 100 is exact', () {
      // Entry is in whole rupees, so no rounding decision is ever made on
      // somebody's money.
      for (final r in [1, 7, 999, 100000]) {
        expect(AuctionMoney.parseRupees('$r'), r * 100);
      }
    });
  });

  group('AuctionCode', () {
    test('generates the PSA-XXXXX shape', () {
      final code = AuctionCode.generate();
      expect(code, matches(RegExp(r'^PSA-[0-9A-Z]{5}$')));
      for (final ch in code.substring(4).split('')) {
        expect(AuctionCode.alphabet.contains(ch), isTrue);
      }
    });

    test('normalizes the ways a code gets retyped', () {
      expect(AuctionCode.normalize('psa-4k7m2'), 'PSA-4K7M2');
      expect(AuctionCode.normalize('PSA4K7M2'), 'PSA-4K7M2');
      expect(AuctionCode.normalize(' psa 4k7m2 '), 'PSA-4K7M2');
    });

    test('forgives the letters the alphabet exists to avoid', () {
      // Somebody reading a code aloud says "oh" for zero and "eye" for one,
      // and the listener types the letter.
      expect(AuctionCode.normalize('PSA-O1L23'), 'PSA-01123');
    });

    test('rejects a wrong length', () {
      expect(AuctionCode.normalize('PSA-123'), isNull);
      expect(AuctionCode.normalize('PSA-1234567'), isNull);
      expect(AuctionCode.normalize(''), isNull);
    });

    test('round-trips its own output', () {
      for (var i = 0; i < 50; i++) {
        final code = AuctionCode.generate();
        expect(AuctionCode.normalize(code), code);
      }
    });
  });

  group('AuctionTeam money', () {
    AuctionTeam team({
      int purse = 10000000,
      int committed = 0,
      int spent = 0,
      int won = 0,
      int liveBids = 0,
    }) =>
        AuctionTeam(
          id: 'u1',
          auctionId: 'a1',
          ownerUid: 'u1',
          ownerName: 'Owner',
          name: 'Test XI',
          pursePaise: purse,
          committedPaise: committed,
          spentPaise: spent,
          wonCount: won,
          liveBidCount: liveBids,
        );

    test('available is purse minus what is locked', () {
      // THE number on the bidding screen: what a NEW bid may still commit.
      expect(team(committed: 4000000).availablePaise, 6000000);
    });

    test('remaining is purse minus what was actually paid', () {
      // A different number from `available`, and the difference is the whole
      // point of the committed-budget model: money locked behind a losing bid
      // comes back, money spent does not.
      expect(team(committed: 4000000, spent: 1000000).remainingPaise, 9000000);
    });

    test('the two agree once every bid has resolved', () {
      final settled = team(committed: 3000000, spent: 3000000);
      expect(settled.availablePaise, settled.remainingPaise);
    });

    test('a zero purse does not divide by zero', () {
      // An organizer running a no-money "draw for sides" auction sets the
      // purse to zero, and the bar on the team card must still render.
      expect(team(purse: 0).committedFraction, 0);
    });

    test('committedFraction is clamped to 0..1', () {
      expect(team(committed: 5000000).committedFraction, 0.5);
      expect(team(purse: 1000, committed: 999999).committedFraction, 1);
    });
  });

  group('Auction gates', () {
    Auction auction({
      AuctionStatus status = AuctionStatus.bidding,
      DateTime? bidsCloseAt,
      DateTime? exchangeClosesAt,
    }) =>
        Auction(
          id: 'a1',
          name: 'Maram 2026',
          sportId: 'cricket',
          sportName: 'Cricket',
          status: status,
          visibility: AuctionVisibility.unlisted,
          createdByUid: 'u1',
          createdByName: 'Organizer',
          joinCode: 'PSA-4K7M2',
          defaultPursePaise: 10000000,
          defaultBasePricePaise: 100000,
          round: 1,
          bidsCloseAt: bidsCloseAt,
          exchangeClosesAt: exchangeClosesAt,
        );

    final now = DateTime(2026, 12, 1, 12);

    test('bids are open before the deadline', () {
      expect(
        auction(bidsCloseAt: now.add(const Duration(hours: 1))).bidsOpenAt(now),
        isTrue,
      );
    });

    test('bids are shut after the deadline even while status says bidding', () {
      // The gap the scheduled reveal leaves: it runs every five minutes, so
      // there is always a window where the status is stale and the clock has
      // run out. The server checks the same two things.
      expect(
        auction(bidsCloseAt: now.subtract(const Duration(minutes: 1)))
            .bidsOpenAt(now),
        isFalse,
      );
    });

    test('bids are shut in every status but bidding', () {
      for (final s in AuctionStatus.values) {
        if (s == AuctionStatus.bidding) continue;
        expect(
          auction(status: s, bidsCloseAt: now.add(const Duration(days: 1)))
              .bidsOpenAt(now),
          isFalse,
          reason: '${s.wire} must not accept bids',
        );
      }
    });

    test('trading needs a reveal', () {
      expect(
        auction(
          status: AuctionStatus.bidding,
          exchangeClosesAt: now.add(const Duration(days: 1)),
        ).tradingOpenAt(now),
        isFalse,
      );
    });

    test('trading is open inside the window', () {
      expect(
        auction(
          status: AuctionStatus.revealed,
          exchangeClosesAt: now.add(const Duration(days: 1)),
        ).tradingOpenAt(now),
        isTrue,
      );
    });

    test('trading shuts at exchangeClosesAt', () {
      expect(
        auction(
          status: AuctionStatus.revealed,
          exchangeClosesAt: now.subtract(const Duration(minutes: 1)),
        ).tradingOpenAt(now),
        isFalse,
      );
    });

    test('locking shuts trading even inside the date window', () {
      // Two independent gates, so an organizer whose event starts early is
      // covered by the button and one who forgets the button is covered by
      // the date.
      expect(
        auction(
          status: AuctionStatus.locked,
          exchangeClosesAt: now.add(const Duration(days: 7)),
        ).tradingOpenAt(now),
        isFalse,
      );
    });
  });

  group('wire values are stable', () {
    test('an unknown status falls back to draft, never to something later', () {
      // Failing open into a state where money can move would be the worst
      // possible default.
      expect(AuctionStatus.fromWire('who_knows'), AuctionStatus.draft);
      expect(AuctionStatus.fromWire(null), AuctionStatus.draft);
    });

    test('an unknown join status falls back to pending', () {
      expect(AuctionJoinStatus.fromWire('nonsense'), AuctionJoinStatus.pending);
    });

    test('an unknown lot status falls back to pool', () {
      expect(AuctionLotStatus.fromWire('nonsense'), AuctionLotStatus.pool);
    });

    test('an unknown role is dropped rather than invented', () {
      expect(AuctionRole.fromWire('superuser'), isNull);
    });

    test('visibility defaults to unlisted, not public', () {
      // A private auction leaking onto the public board is a real harm; a
      // public one failing to appear is an inconvenience.
      expect(AuctionVisibility.fromWire('nonsense'), AuctionVisibility.unlisted);
    });

    test('isRevealed covers revealed and locked only', () {
      expect(AuctionStatus.revealed.isRevealed, isTrue);
      expect(AuctionStatus.locked.isRevealed, isTrue);
      expect(AuctionStatus.bidding.isRevealed, isFalse);
      expect(AuctionStatus.cancelled.isRevealed, isFalse);
    });
  });

  group('AuctionTrade.summary', () {
    AuctionTrade trade({
      List<String> from = const [],
      List<String> to = const [],
      int fromCash = 0,
      int toCash = 0,
    }) =>
        AuctionTrade(
          id: 't1',
          auctionId: 'a1',
          fromTeamId: 'u1',
          fromTeamName: 'A XI',
          toTeamId: 'u2',
          toTeamName: 'B XI',
          fromLotIds: from,
          toLotIds: to,
          fromCashPaise: fromCash,
          toCashPaise: toCash,
          status: AuctionTradeStatus.proposed,
        );

    test('reads as a sentence for a straight swap', () {
      expect(
        trade(from: ['p1', 'p2'], to: ['p3']).summary,
        '2 players for 1 player',
      );
    });

    test('includes cash on the side that pays it', () {
      expect(
        trade(from: ['p1'], to: ['p2'], fromCash: 500000).summary,
        '1 player + ₹5,000 for 1 player',
      );
    });

    test('says "nothing" rather than rendering an empty side', () {
      expect(trade(to: ['p1']).summary, 'nothing for 1 player');
    });

    test('handles a pure cash offer', () {
      expect(
        trade(to: ['p1'], fromCash: 1000000).summary,
        '₹10,000 for 1 player',
      );
    });
  });
}
