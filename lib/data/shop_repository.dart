import '../core/firebase/firestore_refs.dart';
import '../core/models/shop_product.dart';


/// The shop catalog.
///
/// ## Firestore first, bundled catalog as the floor
///
/// Listings live in `products/` so a price change or a seasonal range does
/// not need an app-store release — a ranking of retail products goes stale
/// far faster than a release cycle.
///
/// But the collection can be empty (a fresh project, an environment nobody
/// has seeded) and the device can be offline (a ground with no signal, which
/// is the normal case for this product). Either would leave a shop screen
/// showing nothing at all, which reads as a broken feature rather than an
/// empty shelf. So [DecathlonCatalog] ships inside the app and is what the
/// screen falls back to. A seeded collection always wins.
class ShopRepository {
  const ShopRepository();

  /// Every listing, best-sorted first, falling back to the bundled catalog.
  ///
  /// The bundled catalog is yielded FIRST, before Firestore is even asked.
  /// The shop then has something on its shelves on the first frame, and the
  /// server's answer replaces it a moment later — rather than a spinner on a
  /// screen whose entire content could have been drawn from a constant.
  ///
  /// An error ends the stream quietly for the same reason: the bundled
  /// catalog has already been delivered, so a refused read or a missing index
  /// leaves a slightly stale shop rather than an empty one.
  Stream<List<ShopProduct>> watchProducts() async* {
    yield DecathlonCatalog.all;
    try {
      final snapshots =
          Refs.products.orderBy('sortOrder').limit(200).snapshots();
      await for (final s in snapshots) {
        if (s.docs.isEmpty) continue;
        yield s.docs.map(ShopProduct.fromDoc).toList(growable: false);
      }
    } catch (_) {
      // Deliberately swallowed — see above.
    }
  }
}

/// The launch catalog: Decathlon India, across the sports PlaySphere scores.
///
/// Decathlon is the right first vendor for this product and not an arbitrary
/// pick. It stocks every sport in the app rather than one, it is priced for
/// school and village clubs rather than for a metro gym, and it has physical
/// stores in the tier-2 cities where PlaySphere's clubs actually are — which
/// matters because a player who wants a ball for Sunday cannot wait for a
/// week's delivery.
///
/// URLs point at Decathlon's own category pages rather than at individual
/// SKUs. A deep link to one SKU rots the moment that SKU sells out, and a
/// dead product page is worse than a slightly less specific live one. The
/// per-product pages are what a real affiliate feed would replace this with.
class DecathlonCatalog {
  const DecathlonCatalog._();

  static const _vendor = 'Decathlon';
  static const _base = 'https://www.decathlon.in';

  static const all = <ShopProduct>[
    ShopProduct(
      id: 'dk-badminton-racket',
      name: 'Badminton rackets',
      vendor: _vendor,
      url: '$_base/c/badminton-rackets',
      pricePaise: 49900,
      category: 'Rackets',
      sportIds: ['badminton'],
      emoji: '🏸',
      blurb: 'Artengo and Perfly, from beginner to club level.',
      sortOrder: 10,
    ),
    ShopProduct(
      id: 'dk-shuttlecocks',
      name: 'Shuttlecocks',
      vendor: _vendor,
      url: '$_base/c/shuttlecocks',
      pricePaise: 29900,
      category: 'Balls & shuttles',
      sportIds: ['badminton'],
      emoji: '🪶',
      blurb: 'Nylon for practice, feather for match play.',
      sortOrder: 20,
    ),
    ShopProduct(
      id: 'dk-cricket-bat',
      name: 'Cricket bats',
      vendor: _vendor,
      url: '$_base/c/cricket-bats',
      pricePaise: 99900,
      category: 'Bats',
      sportIds: ['cricket'],
      emoji: '🏏',
      blurb: 'Kashmir willow through to English willow.',
      sortOrder: 30,
    ),
    ShopProduct(
      id: 'dk-cricket-ball',
      name: 'Cricket balls',
      vendor: _vendor,
      url: '$_base/c/cricket-balls',
      pricePaise: 34900,
      category: 'Balls & shuttles',
      sportIds: ['cricket'],
      emoji: '🔴',
      blurb: 'Leather, tennis and rubber — match and practice.',
      sortOrder: 40,
    ),
    ShopProduct(
      id: 'dk-cricket-protective',
      name: 'Pads, gloves & guards',
      vendor: _vendor,
      url: '$_base/c/cricket-protection',
      pricePaise: 79900,
      category: 'Protection',
      sportIds: ['cricket'],
      emoji: '🧤',
      blurb: 'Batting pads, gloves, helmets and abdominal guards.',
      sortOrder: 50,
    ),
    ShopProduct(
      id: 'dk-football',
      name: 'Footballs',
      vendor: _vendor,
      url: '$_base/c/footballs',
      pricePaise: 64900,
      category: 'Balls & shuttles',
      sportIds: ['football'],
      emoji: '⚽',
      blurb: 'Kipsta match and training balls, sizes 3 to 5.',
      sortOrder: 60,
    ),
    ShopProduct(
      id: 'dk-football-boots',
      name: 'Football boots',
      vendor: _vendor,
      url: '$_base/c/football-shoes',
      pricePaise: 129900,
      category: 'Footwear',
      sportIds: ['football'],
      emoji: '👟',
      blurb: 'Firm ground, turf and hard ground studs.',
      sortOrder: 70,
    ),
    ShopProduct(
      id: 'dk-volleyball',
      name: 'Volleyballs & nets',
      vendor: _vendor,
      url: '$_base/c/volleyball',
      pricePaise: 79900,
      category: 'Balls & shuttles',
      sportIds: ['volleyball'],
      emoji: '🏐',
      blurb: 'Match balls, practice balls and portable nets.',
      sortOrder: 80,
    ),
    ShopProduct(
      id: 'dk-basketball',
      name: 'Basketballs',
      vendor: _vendor,
      url: '$_base/c/basketball',
      pricePaise: 89900,
      category: 'Balls & shuttles',
      sportIds: ['basketball'],
      emoji: '🏀',
      blurb: 'Indoor and outdoor, sizes 5 to 7.',
      sortOrder: 90,
    ),
    ShopProduct(
      id: 'dk-tt',
      name: 'Table tennis bats & balls',
      vendor: _vendor,
      url: '$_base/c/table-tennis',
      pricePaise: 39900,
      category: 'Rackets',
      sportIds: ['table_tennis'],
      emoji: '🏓',
      blurb: 'Pongori bats, balls, nets and tables.',
      sortOrder: 100,
    ),
    ShopProduct(
      id: 'dk-tennis',
      name: 'Tennis rackets & balls',
      vendor: _vendor,
      url: '$_base/c/tennis',
      pricePaise: 129900,
      category: 'Rackets',
      sportIds: ['tennis'],
      emoji: '🎾',
      blurb: 'Artengo rackets, balls, grips and strings.',
      sortOrder: 110,
    ),
    ShopProduct(
      id: 'dk-court-shoes',
      name: 'Court & indoor shoes',
      vendor: _vendor,
      url: '$_base/c/sports-shoes',
      pricePaise: 149900,
      category: 'Footwear',
      emoji: '👟',
      blurb: 'Non-marking grip for indoor halls and courts.',
      sortOrder: 120,
    ),
    ShopProduct(
      id: 'dk-jerseys',
      name: 'Jerseys & team kit',
      vendor: _vendor,
      url: '$_base/c/sports-t-shirts',
      pricePaise: 29900,
      category: 'Clothing',
      emoji: '🎽',
      blurb: 'Training tees, shorts, track pants and bibs.',
      sortOrder: 130,
    ),
    ShopProduct(
      id: 'dk-bottles',
      name: 'Bottles & hydration',
      vendor: _vendor,
      url: '$_base/c/water-bottles',
      pricePaise: 19900,
      category: 'Accessories',
      emoji: '🧴',
      blurb: 'Squeeze bottles and insulated flasks for the dugout.',
      sortOrder: 140,
    ),
    ShopProduct(
      id: 'dk-bags',
      name: 'Kit bags',
      vendor: _vendor,
      url: '$_base/c/sports-bags',
      pricePaise: 59900,
      category: 'Accessories',
      emoji: '🎒',
      blurb: 'Racket covers, duffels and wheeled cricket kit bags.',
      sortOrder: 150,
    ),
    ShopProduct(
      id: 'dk-kabaddi',
      name: 'Mats & training gear',
      vendor: _vendor,
      url: '$_base/c/fitness-mats',
      pricePaise: 99900,
      category: 'Training',
      sportIds: ['kabaddi', 'kho_kho'],
      emoji: '🤼',
      blurb: 'Mats, cones, ladders and resistance gear.',
      sortOrder: 160,
    ),
  ];

  /// The categories present in the catalog, in display order.
  static List<String> categoriesOf(List<ShopProduct> products) {
    final seen = <String>[];
    for (final p in products) {
      final c = p.category;
      if (c != null && !seen.contains(c)) seen.add(c);
    }
    return seen;
  }
}
