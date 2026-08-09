import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/ads/promo.dart';
import 'package:playsphere/core/models/ad_campaign.dart';
import 'package:playsphere/core/models/billing.dart';
import 'package:playsphere/core/models/enums.dart';

/// The rules that decide what somebody has paid for and what they get.
///
/// Entitlement arithmetic is the kind of code that looks obviously right and
/// silently overcharges: a renewal that truncates a term takes money for time
/// the customer already owns, and an expiry compared the wrong way round
/// hands a lapsed plan out for free. Both are asserted here.
void main() {
  final now = DateTime(2026, 8, 8, 12);

  group('plan expiry', () {
    test('a plan with no expiry was never bought', () {
      expect(PlanState.none.isActiveAt(now), isFalse);
      expect(PlanState.none.daysRemainingAt(now), 0);
    });

    test('a plan expiring in the future is active', () {
      final s = PlanState(
        activatedAt: now.subtract(const Duration(days: 30)),
        validUntil: now.add(const Duration(days: 335)),
      );
      expect(s.isActiveAt(now), isTrue);
      expect(s.daysRemainingAt(now), 335);
    });

    test('a plan that expired is not active', () {
      final s = PlanState(
        activatedAt: now.subtract(const Duration(days: 400)),
        validUntil: now.subtract(const Duration(days: 35)),
      );
      expect(s.isActiveAt(now), isFalse);
    });

    test('days remaining never goes negative', () {
      // A lapsed plan reports 0, not "-35 days left" — every caller would
      // have forgotten to handle the negative branch.
      final s = PlanState(
        activatedAt: now.subtract(const Duration(days: 400)),
        validUntil: now.subtract(const Duration(days: 35)),
      );
      expect(s.daysRemainingAt(now), 0);
    });

    test('renewsSoon fires inside the last month and not before', () {
      PlanState until(int days) => PlanState(
            activatedAt: now,
            validUntil: now.add(Duration(days: days)),
          );

      expect(until(10).renewsSoonAt(now), isTrue);
      expect(until(30).renewsSoonAt(now), isTrue);
      expect(until(60).renewsSoonAt(now), isFalse);
    });

    test('an expired plan does not renew soon — it has already gone', () {
      final s = PlanState(
        activatedAt: now.subtract(const Duration(days: 400)),
        validUntil: now.subtract(const Duration(days: 1)),
      );
      expect(s.renewsSoonAt(now), isFalse);
    });
  });

  group('renewal', () {
    test('renewing early adds to the remaining term', () {
      // Two months left, renewed today, should give fourteen months — not
      // twelve. Anything else charges the customer for time they own.
      final s = PlanState(
        activatedAt: now.subtract(const Duration(days: 305)),
        validUntil: now.add(const Duration(days: 60)),
      );
      final extended = s.extendedFrom(now);
      expect(extended, now.add(const Duration(days: 60 + Pricing.termDays)));
    });

    test('renewing after lapsing runs a full term from today', () {
      // Not from the old expiry — that would sell a term already spent.
      final s = PlanState(
        activatedAt: now.subtract(const Duration(days: 500)),
        validUntil: now.subtract(const Duration(days: 100)),
      );
      expect(
        s.extendedFrom(now),
        now.add(const Duration(days: Pricing.termDays)),
      );
    });

    test('a first purchase runs a full term from today', () {
      expect(
        PlanState.none.extendedFrom(now),
        now.add(const Duration(days: Pricing.termDays)),
      );
    });
  });

  group('pricing', () {
    test('the launch offer makes both paid plans payable at zero', () {
      // Guarded on the flag so this test keeps telling the truth after the
      // offer ends, rather than becoming the thing that has to be deleted
      // before the price can go live.
      if (Pricing.introOfferActive) {
        expect(Pricing.orgPricePaise(OrgPlan.club), 0);
        expect(Pricing.memberPricePaise(MemberPlan.premium), 0);
      } else {
        expect(Pricing.orgPricePaise(OrgPlan.club), Pricing.clubYearlyPaise);
        expect(
          Pricing.memberPricePaise(MemberPlan.premium),
          Pricing.premiumYearlyPaise,
        );
      }
    });

    test('the list price is unaffected by the offer', () {
      // What makes the checkout show "₹999 struck through, ₹0 payable"
      // rather than simply looking free.
      expect(Pricing.orgListPricePaise(OrgPlan.club), 99900);
      expect(Pricing.memberListPricePaise(MemberPlan.premium), 9900);
    });

    test('the free tiers cost nothing either way', () {
      expect(Pricing.orgPricePaise(OrgPlan.free), 0);
      expect(Pricing.orgListPricePaise(OrgPlan.free), 0);
      expect(Pricing.memberPricePaise(MemberPlan.free), 0);
    });

    test('whole rupees format without a decimal', () {
      expect(Pricing.formatPaise(99900), '₹999');
      expect(Pricing.formatPaise(9900), '₹99');
      expect(Pricing.formatPaise(150000), '₹1500');
    });

    test('part-rupee amounts keep both decimal places', () {
      // Refunds and splits genuinely land on a paisa.
      expect(Pricing.formatPaise(9950), '₹99.50');
      expect(Pricing.formatPaise(1), '₹0.01');
    });

    test('zero reads as Free rather than ₹0', () {
      expect(Pricing.formatPaise(0), 'Free');
    });
  });

  group('global pricing', () {
    test('matches the vision\'s quoted global figures exactly', () {
      expect(Pricing.orgMonthlyUsdCents, 900); // $9.00/month
      expect(Pricing.memberMonthlyUsdCents, 99); // $0.99/month
    });

    test('the global term is monthly, not a conversion of the yearly one', () {
      expect(Pricing.globalTermDays, 30);
      expect(Pricing.globalTermDays, isNot(Pricing.termDays));
    });

    test('cents format with two decimal places, unlike whole-rupee paise', () {
      expect(Pricing.formatUsdCents(900), r'$9.00');
      expect(Pricing.formatUsdCents(99), r'$0.99');
    });

    test('zero cents reads as Free, same as zero paise', () {
      expect(Pricing.formatUsdCents(0), 'Free');
    });
  });

  group('wire values', () {
    test('an unknown plan string degrades to free, never to paid', () {
      // A document written by a newer client must not accidentally grant a
      // paid tier to an older one — the fallback direction matters.
      expect(OrgPlan.fromWire('enterprise'), OrgPlan.free);
      expect(OrgPlan.fromWire(null), OrgPlan.free);
      expect(MemberPlan.fromWire('platinum'), MemberPlan.free);
    });

    test('known plan strings round-trip', () {
      expect(OrgPlan.fromWire(OrgPlan.club.wire), OrgPlan.club);
      expect(
        MemberPlan.fromWire(MemberPlan.premium.wire),
        MemberPlan.premium,
      );
    });
  });

  group('who may be shown an advert', () {
    const houseAd = Promo(
      id: 'ps',
      headline: 'h',
      body: 'b',
      emoji: '⭐',
      ctaLabel: 'go',
    );
    const paidAd = Promo(
      id: 'dk',
      advertiser: 'Decathlon',
      headline: 'h',
      body: 'b',
      emoji: '🏸',
      ctaLabel: 'go',
    );

    test('Premium members see no advertising at all', () {
      // Premium is sold partly on "no ads". Showing one is a broken promise,
      // not a tuning decision.
      expect(mayShowPromo(paidAd, isPremium: true, isMinor: false), isFalse);
      expect(mayShowPromo(houseAd, isPremium: true, isMinor: false), isFalse);
    });

    test('minors are never shown third-party advertising', () {
      // India's DPDP Act prohibits targeted advertising directed at children.
      expect(mayShowPromo(paidAd, isPremium: false, isMinor: true), isFalse);
    });

    test("minors still see PlaySphere's own promotions", () {
      // "Your club has a match on Sunday" is not an advert.
      expect(mayShowPromo(houseAd, isPremium: false, isMinor: true), isTrue);
    });

    test('a free adult member sees both', () {
      expect(mayShowPromo(paidAd, isPremium: false, isMinor: false), isTrue);
      expect(mayShowPromo(houseAd, isPremium: false, isMinor: false), isTrue);
    });

    test('a paid promo is labelled as an ad and a house one is not', () {
      expect(paidAd.disclosure, 'Ad · Decathlon');
      expect(houseAd.disclosure, 'From PlaySphere');
      expect(paidAd.isHouseAd, isFalse);
      expect(houseAd.isHouseAd, isTrue);
    });
  });

  group('promo slot selection', () {
    test('the shop slot never advertises the shop', () {
      // A banner selling somebody what they are already looking at is the
      // clearest possible signal nobody thought about where it appears.
      for (var seed = 0; seed < 20; seed++) {
        final p = PromoCatalog.forSlot(PromoSlot.shop, seed: seed);
        expect(p?.destination?.startsWith('/shop') ?? false, isFalse);
      }
    });

    test('the grounds slot never advertises grounds', () {
      for (var seed = 0; seed < 20; seed++) {
        final p = PromoCatalog.forSlot(PromoSlot.grounds, seed: seed);
        expect(p?.destination?.startsWith('/grounds') ?? false, isFalse);
      }
    });

    test("a player's own sport is preferred when the catalog has one", () {
      final p = PromoCatalog.forSlot(
        PromoSlot.home,
        playerSportIds: const ['badminton'],
      );
      expect(p, isNotNull);
      expect(p!.sportIds, contains('badminton'));
    });

    test('a player with no career still gets a promo', () {
      // Every new account is in this state. An empty slot on day one would
      // mean the feature only ever appears for established players.
      expect(PromoCatalog.forSlot(PromoSlot.home), isNotNull);
    });

    test('the seed rotates the choice rather than fixing it', () {
      final chosen = {
        for (var seed = 0; seed < 12; seed++)
          PromoCatalog.forSlot(PromoSlot.home, seed: seed)?.id,
      };
      expect(chosen.length, greaterThan(1));
    });

    test('the daily seed is stable within a day and moves between days', () {
      final a = PromoCatalog.dailySeed(DateTime(2026, 8, 8, 9));
      final b = PromoCatalog.dailySeed(DateTime(2026, 8, 8, 21));
      final c = PromoCatalog.dailySeed(DateTime(2026, 8, 9, 9));
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('promo slot selection with live advertiser campaigns', () {
    const campaignPromo = Promo(
      id: 'campaign-abc123',
      advertiser: 'Local Sports Store',
      headline: 'New season, new boots',
      body: 'b',
      emoji: '⚽',
      ctaLabel: 'Shop now',
    );

    test('falls back to the house catalog when no campaign is live', () {
      // Pixel-for-pixel identical to plain forSlot — the overwhelmingly
      // common case until this product has real advertisers.
      final withCampaigns = PromoCatalog.forSlotWithCampaigns(
        PromoSlot.home,
        liveCampaigns: const [],
        seed: 3,
      );
      final plain = PromoCatalog.forSlot(PromoSlot.home, seed: 3);
      expect(withCampaigns?.id, plain?.id);
    });

    test('a live campaign wins over the house catalog when both exist', () {
      final chosen = PromoCatalog.forSlotWithCampaigns(
        PromoSlot.home,
        liveCampaigns: const [campaignPromo],
        seed: 3,
      );
      expect(chosen?.id, 'campaign-abc123');
    });

    test("a live campaign matching the player's sport is preferred over one that doesn't", () {
      const cricketAd = Promo(
        id: 'campaign-cricket',
        advertiser: 'A',
        headline: 'h',
        body: 'b',
        emoji: '🏏',
        ctaLabel: 'go',
        sportIds: ['cricket'],
      );
      const genericAd = Promo(
        id: 'campaign-generic',
        advertiser: 'B',
        headline: 'h',
        body: 'b',
        emoji: '📣',
        ctaLabel: 'go',
      );
      final chosen = PromoCatalog.forSlotWithCampaigns(
        PromoSlot.home,
        liveCampaigns: const [genericAd, cricketAd],
        playerSportIds: const ['cricket'],
      );
      expect(chosen?.id, 'campaign-cricket');
    });
  });

  group('PromoSlot wire round-trip', () {
    test('every slot survives fromWire(wire)', () {
      for (final slot in PromoSlot.values) {
        expect(PromoSlot.fromWire(slot.wire), slot);
      }
    });

    test('an unrecognised wire value falls back to home, not a crash', () {
      expect(PromoSlot.fromWire('nonsense'), PromoSlot.home);
      expect(PromoSlot.fromWire(null), PromoSlot.home);
    });
  });

  group('AdCampaign.toPromo fills the exact Promo shape', () {
    const campaign = AdCampaign(
      id: 'c1',
      advertiserUid: 'uid_1',
      advertiserName: 'Local Sports Store',
      headline: 'New season, new boots',
      body: 'Boots and balls for every side.',
      emoji: '⚽',
      ctaLabel: 'Shop now',
      sportIds: ['football'],
      destination: '/shop?sport=football',
      status: AdCampaignStatus.approved,
    );

    test('id is namespaced so PromoBanner can tell a campaign from a house ad', () {
      expect(campaign.toPromo().id, 'campaign-c1');
    });

    test('advertiser name carries through, so it is never mistaken for a house ad', () {
      final promo = campaign.toPromo();
      expect(promo.isHouseAd, isFalse);
      expect(promo.disclosure, 'Ad · Local Sports Store');
    });

    test('every displayed field round-trips unchanged', () {
      final promo = campaign.toPromo();
      expect(promo.headline, campaign.headline);
      expect(promo.body, campaign.body);
      expect(promo.emoji, campaign.emoji);
      expect(promo.ctaLabel, campaign.ctaLabel);
      expect(promo.sportIds, campaign.sportIds);
      expect(promo.destination, campaign.destination);
    });

    test('isLive is true only once approved', () {
      expect(campaign.isLive, isTrue);
      expect(
        const AdCampaign(
          id: 'c2',
          advertiserUid: 'uid_1',
          advertiserName: 'A',
          headline: 'h',
          body: 'b',
          emoji: '📣',
          ctaLabel: 'go',
        ).isLive,
        isFalse,
      );
    });
  });

  group('sport ids for targeting', () {
    test('a qualified id collapses to its base sport', () {
      // Chess ids carry a `:blitz` qualifier; a chess player is a chess
      // player for the purpose of what they might want to buy.
      expect(sportIdsFor(['chess:blitz', 'chess:rapid']), ['chess']);
    });

    test('duplicates are removed', () {
      expect(
        sportIdsFor(['cricket', 'cricket', 'badminton']).length,
        2,
      );
    });
  });
}
