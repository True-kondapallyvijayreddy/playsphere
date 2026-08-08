/// House advertising: what PlaySphere shows, where, and to whom.
///
/// ## Why there is no ad network here
///
/// The obvious move is to drop in a mediation SDK and be done. It is the
/// wrong first move for this product, for three reasons that all cost more to
/// undo later than to avoid now.
///
/// A network SDK decides for itself what a child sees. A large share of
/// PlaySphere's members are minors — `AppUser.isMinor` exists precisely
/// because the product has to know — and handing their sessions to an
/// arbitrary demand stack is a compliance problem before it is a revenue one.
///
/// Its inventory is also generic. The whole advertising thesis for PlaySphere
/// is that it knows the sport, the club and the ground, so it can show a
/// badminton player something about badminton. That advantage is worth
/// nothing if the slot is filled by whoever bid highest on "sports app".
///
/// And an SDK is a third-party binary with network access, sitting inside an
/// app that holds children's names, ages and locations.
///
/// So slots are filled from a catalog PlaySphere controls, targeted on facts
/// PlaySphere already has. When there is a real advertiser console, it fills
/// the same [Promo] shape and nothing above it changes.
library;

/// One thing that can occupy an ad slot.
class Promo {
  const Promo({
    required this.id,
    required this.headline,
    required this.body,
    required this.emoji,
    required this.ctaLabel,
    this.sportIds = const [],
    this.destination,
    this.advertiser,
  });

  final String id;
  final String headline;
  final String body;

  /// An emoji rather than an image asset, on purpose. Banners appear on the
  /// home screen and above match lists, which are the screens most likely to
  /// be open on a village ground on a bad 4G connection — and a banner that
  /// arrives half a second after the fixtures do is a banner that shoves the
  /// thing somebody came to read off the screen. A glyph costs nothing and
  /// lays out on the first frame.
  final String emoji;

  final String ctaLabel;

  /// Which sports this is relevant to. Empty means "any" — a general
  /// PlaySphere promotion rather than a product for one game.
  final List<String> sportIds;

  /// Where the CTA goes: an in-app route, or a full URL for a vendor page.
  final String? destination;

  /// Who is paying, when somebody is. Null for PlaySphere's own promotions,
  /// which is what makes [isHouseAd] answerable — the disclosure label has to
  /// distinguish "an advert" from "PlaySphere telling you about PlaySphere".
  final String? advertiser;

  bool get isHouseAd => advertiser == null;

  /// The label shown on the banner. Advertising has to be identifiable as
  /// advertising — that is a legal requirement in India under the ASCI code
  /// and the CCPA guidelines, and it is also the only version of this that a
  /// user would not resent.
  String get disclosure => isHouseAd ? 'From PlaySphere' : 'Ad · $advertiser';
}

/// Where a banner is being shown.
///
/// The slot is part of targeting, not just layout: a promotion that makes
/// sense above a list of upcoming events ("book a ground") is noise on the
/// shop screen, and vice versa.
enum PromoSlot {
  home,
  events,
  shop,
  grounds,
}

/// The catalog, and the rule for choosing from it.
class PromoCatalog {
  const PromoCatalog._();

  static const _all = <Promo>[
    Promo(
      id: 'decathlon-racket',
      advertiser: 'Decathlon',
      emoji: '🏸',
      headline: 'Rackets from ₹499',
      body: 'Artengo badminton and Perfly ranges, in stock at Decathlon.',
      ctaLabel: 'Shop rackets',
      sportIds: ['badminton'],
      destination: '/shop?sport=badminton',
    ),
    Promo(
      id: 'decathlon-cricket',
      advertiser: 'Decathlon',
      emoji: '🏏',
      headline: 'Cricket season kit',
      body: 'Bats, leather balls, pads and gloves from the Kipsta range.',
      ctaLabel: 'Shop cricket',
      sportIds: ['cricket'],
      destination: '/shop?sport=cricket',
    ),
    Promo(
      id: 'decathlon-football',
      advertiser: 'Decathlon',
      emoji: '⚽',
      headline: 'Boots, balls and bibs',
      body: 'Kipsta football gear for the whole side, not just the striker.',
      ctaLabel: 'Shop football',
      sportIds: ['football'],
      destination: '/shop?sport=football',
    ),
    Promo(
      id: 'decathlon-shoes',
      advertiser: 'Decathlon',
      emoji: '👟',
      headline: 'Court and running shoes',
      body: 'Grip for indoor courts, cushioning for the road.',
      ctaLabel: 'Shop shoes',
      destination: '/shop',
    ),
    Promo(
      id: 'ps-grounds',
      emoji: '🏟️',
      headline: 'Need a ground for Sunday?',
      body: 'Search turfs and courts near you and book by the hour.',
      ctaLabel: 'Find a ground',
      destination: '/grounds',
    ),
    Promo(
      id: 'ps-list-ground',
      emoji: '📋',
      headline: 'Own a ground?',
      body: 'List it on PlaySphere and take bookings from every club nearby.',
      ctaLabel: 'List your ground',
      destination: '/grounds/mine',
    ),
    Promo(
      id: 'ps-premium',
      emoji: '⭐',
      headline: 'Your full career record',
      body: 'Premium adds every match, deeper analytics and no ads.',
      ctaLabel: 'See Premium',
      destination: '/premium',
    ),
  ];

  /// Picks the promo to show in [slot].
  ///
  /// Prefers one matching a sport the viewer actually plays, and falls back to
  /// a general promotion. [seed] rotates the choice so the same person does
  /// not stare at the same banner every time they open the app — it is
  /// normally something that changes slowly, like the day of the year, rather
  /// than a random number, so the banner does not reshuffle on every rebuild.
  ///
  /// Returns null when the slot should stay empty. A slot with nothing worth
  /// putting in it renders nothing at all, rather than a filler ad.
  static Promo? forSlot(
    PromoSlot slot, {
    List<String> playerSportIds = const [],
    int seed = 0,
  }) {
    final pool = _all.where((p) => _fits(p, slot)).toList(growable: false);
    if (pool.isEmpty) return null;

    final matching = pool
        .where((p) =>
            p.sportIds.isNotEmpty &&
            p.sportIds.any(playerSportIds.contains))
        .toList(growable: false);

    final chosen = matching.isNotEmpty ? matching : pool;
    return chosen[seed.abs() % chosen.length];
  }

  /// Whether a promo belongs in a slot.
  ///
  /// The rules are deliberately about relevance rather than inventory: the
  /// shop screen does not advertise the shop, and the grounds screen does not
  /// advertise grounds, because a banner selling somebody what they are
  /// already looking at is the clearest possible signal that nobody thought
  /// about where it would appear.
  static bool _fits(Promo p, PromoSlot slot) => switch (slot) {
        PromoSlot.home => true,
        PromoSlot.events => p.id != 'ps-list-ground',
        PromoSlot.shop => p.destination == null ||
            !p.destination!.startsWith('/shop'),
        PromoSlot.grounds => p.destination == null ||
            !p.destination!.startsWith('/grounds'),
      };

  /// A seed that changes once a day, so the rotation is stable within a
  /// session and different between days.
  static int dailySeed(DateTime now) =>
      now.year * 1000 + now.difference(DateTime(now.year)).inDays;
}

/// Sports this player has actually played, for targeting.
///
/// Takes the ids off the career record rather than asking, because the whole
/// contextual-advertising argument rests on PlaySphere knowing what somebody
/// plays without having to run a survey.
List<String> sportIdsFor(Iterable<String> careerSportIds) =>
    careerSportIds.map((s) => s.split(':').first).toSet().toList();

/// Whether ads may be shown to this viewer at all.
///
/// Two independent reasons to say no, and both are hard rules rather than
/// preferences. Premium is sold partly on "no ads", so showing one to a payer
/// is a broken promise. And minors are not shown third-party advertising —
/// house promotions about PlaySphere's own features are fine, anything with
/// an [Promo.advertiser] is not. India's DPDP Act prohibits targeted
/// advertising directed at children outright, so this is not a matter of
/// taste.
bool mayShowPromo(Promo promo, {required bool isPremium, required bool isMinor}) {
  if (isPremium) return false;
  if (isMinor && !promo.isHouseAd) return false;
  return true;
}
