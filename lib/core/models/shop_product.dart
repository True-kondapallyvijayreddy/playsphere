import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One item in the PlaySphere shop, at `products/{productId}`.
///
/// ## What this is, and what it deliberately is not
///
/// It is a *listing*, not stock. PlaySphere does not hold inventory, does not
/// take the payment, does not ship, and does not handle returns — the vendor
/// does all four, on their own site, under their own terms. This document is
/// a curated pointer at a real product page.
///
/// That is not a stopgap. A marketplace with its own cart is a warehouse, a
/// logistics contract, a returns policy, a customer-service team and a
/// consumer-protection liability, and it earns roughly the same referral
/// margin as a link does until it is running at real volume. The link-out is
/// what a sports network the size of PlaySphere should be doing on day one.
///
/// So [url] is the important field: it is where the money actually changes
/// hands, and everything else here exists to make a player want to tap it.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.vendor,
    required this.url,
    required this.pricePaise,
    this.category,
    this.sportIds = const [],
    this.emoji = '🎽',
    this.blurb,
    this.imageUrl,
    this.sortOrder = 0,
  });

  final String id;
  final String name;

  /// Who sells it. Shown on every card and on the confirmation before a
  /// link-out, because a player must never be unclear about whose checkout
  /// they are about to be standing in.
  final String vendor;

  /// The vendor's product page.
  final String url;

  /// Indicative price in paise, as listed when the catalog was last updated.
  ///
  /// Explicitly indicative: PlaySphere does not control the vendor's pricing
  /// and cannot promise it has not moved since. The UI says so rather than
  /// implying a price it cannot honour — a shown price that turns out wrong
  /// at the vendor's checkout is the fastest way to lose the trust that makes
  /// the referral worth anything.
  final int pricePaise;

  /// "Rackets", "Footwear", "Balls" — free text, because the useful
  /// vocabulary differs per sport and a fixed enum would need a release to
  /// add "Kabaddi mats".
  final String? category;

  /// Which sports this is for. Empty means "any sport" — a water bottle.
  /// Drives both the shop's filter and the ordering, so a badminton player
  /// sees rackets before they see football boots.
  final List<String> sportIds;

  final String emoji;
  final String? blurb;

  /// Optional; the cards are designed to look right without one. See
  /// `Promo.emoji` for the same reasoning: these screens get opened on a
  /// ground on bad 4G, and a grid that only resolves once a dozen images
  /// arrive is a grid nobody scrolls.
  final String? imageUrl;

  final int sortOrder;

  bool matchesSport(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);

  factory ShopProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ShopProduct(
      id: doc.id,
      name: Fs.str(d['name'], 'Product'),
      vendor: Fs.str(d['vendor'], 'Partner'),
      url: Fs.str(d['url']),
      pricePaise: Fs.integer(d['pricePaise']),
      category: Fs.strOrNull(d['category']),
      sportIds: Fs.strList(d['sportIds']),
      emoji: Fs.str(d['emoji'], '🎽'),
      blurb: Fs.strOrNull(d['blurb']),
      imageUrl: Fs.strOrNull(d['imageUrl']),
      sortOrder: Fs.integer(d['sortOrder']),
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'vendor': vendor,
        'url': url,
        'pricePaise': pricePaise,
        'category': category,
        'sportIds': sportIds,
        'emoji': emoji,
        'blurb': blurb,
        'imageUrl': imageUrl,
        'sortOrder': sortOrder,
      };
}
