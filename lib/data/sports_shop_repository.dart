import '../core/firebase/firestore_refs.dart';
import '../core/models/sports_shop.dart';
import 'org_repository.dart' show guard, guardStream;

/// Listing a sports shop, and finding one.
///
/// Deliberately the same shape as `CoachRepository` and
/// `SportsMedicRepository` — one anchor word in an `array-contains`, the rest
/// of the words checked in Dart, verified first in the sort. A club looking
/// for somewhere to order kit and a parent looking for a physiotherapist are
/// performing the same act on the same kind of collection, and a third search
/// mechanism for one job would be a third thing to get wrong.
///
/// What differs is the ranking. See [searchShops].
class SportsShopRepository {
  const SportsShopRepository();

  // --- The owner's own listing --------------------------------------------

  /// Creates or replaces this account's shop listing.
  ///
  /// One method rather than register/update, for the reason
  /// `SportsMedicRepository.saveMyProfile` gives: the document id is the uid,
  /// so there is no id to hand back and "have I got one already?" is not a
  /// question the caller should have to answer before saving.
  Future<void> saveMyShop(SportsShop shop, {required bool isNew}) =>
      guard(() async {
        final ref = Refs.sportsShop(shop.uid);
        if (isNew) {
          await ref.set(shop.toCreate());
        } else {
          await ref.update(shop.toUpdate());
        }
      });

  /// One shop's listing, or null if this account has never made one.
  Stream<SportsShop?> watchShop(String uid) => guardStream(
        () => Refs.sportsShop(uid).snapshots().map(
              (d) => d.exists ? SportsShop.fromDoc(d) : null,
            ),
      );

  // --- Finding one --------------------------------------------------------

  /// Shops in one city, most useful first.
  ///
  /// Queried on `cityKey` rather than filtered in Dart, because "which shops
  /// are in Warangal" is the question this directory exists to answer and it
  /// must not degrade into reading the whole collection as the list grows.
  Stream<List<SportsShop>> watchShopsInCity(String city, {int limit = 40}) =>
      guardStream(
        () => Refs.sportsShops
            .where('isActive', isEqualTo: true)
            .where('cityKey', isEqualTo: city.trim().toLowerCase())
            .limit(limit)
            .snapshots()
            .map((s) => s.docs.map(SportsShop.fromDoc).toList()),
      );

  /// Finds shops by any words somebody might type — a shop name, an area, a
  /// sport — narrowed by what they stock, what they do, and where.
  ///
  /// ## Why a bare city is enough but nothing at all is not
  ///
  /// Same rule as the coach, ground and practitioner searches: reading a
  /// whole collection to fill a screen nobody has addressed is the unbounded
  /// query this design exists to avoid. A city, a stock category or a service
  /// each narrows on the server or bounds the read, so any one of them is
  /// enough to run a search with no words typed — which matters here more
  /// than in the other directories, because "what sports shops are near me"
  /// is the whole question most people arrive with.
  ///
  /// ## Why the sport filter does not exclude generalists
  ///
  /// `SportsShop.stocksFor` returns true for an empty `sportIds`. A general
  /// sports shop genuinely does sell a shuttle and a football, and hiding it
  /// from somebody searching badminton would be the directory withholding the
  /// right answer on a technicality. Same rule as `SportsMedicProfile`.
  Future<List<SportsShop>> searchShops({
    String keywords = '',
    ShopStock? stock,
    ShopService? service,
    String? sportId,
    String? city,
    int limit = 60,
  }) =>
      guard(() async {
        final words = SportsShop.tokenizeQuery(keywords);
        final cityKey = city?.trim().toLowerCase();

        var query = Refs.sportsShops.where('isActive', isEqualTo: true);

        if (words.isNotEmpty) {
          // Longest word as a proxy for rarest — Firestore allows one
          // `array-contains` per query, so it is spent on the word most
          // likely to narrow hardest.
          final anchor = words.reduce((a, b) => b.length > a.length ? b : a);
          query = query.where('searchTokens', arrayContains: anchor);
        } else if (cityKey != null && cityKey.isNotEmpty) {
          query = query.where('cityKey', isEqualTo: cityKey);
        } else if (stock == null && service == null && sportId == null) {
          // Nothing asked at all.
          return const <SportsShop>[];
        }

        final snap = await query.limit(limit).get();

        final matching = <SportsShop>[];
        for (final doc in snap.docs) {
          final shop = SportsShop.fromDoc(doc);
          // Every word has to match, not only the anchor. Recomputed from the
          // model rather than read off the document, so the test applied here
          // is the one that produced the stored array.
          final tokens = shop.searchTokens.toSet();
          if (!words.every(tokens.contains)) continue;
          if (stock != null && !shop.sells(stock)) continue;
          if (service != null && !shop.offers(service)) continue;
          if (sportId != null && !shop.stocksFor(sportId)) continue;
          if (cityKey != null && cityKey.isNotEmpty && shop.cityKey != cityKey) {
            continue;
          }
          matching.add(shop);
        }

        // Verified first, then the ones that will take a club order, then the
        // longest established. Somebody scrolling this list is deciding who
        // to ring about a season's kit, and those are the three facts that
        // decide it — a shop that has been there twenty years is a shop that
        // will still be there when the jerseys need replacing.
        matching.sort((a, b) {
          if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
          final aBulk = a.offers(ShopService.clubOrders);
          final bBulk = b.offers(ShopService.clubOrders);
          if (aBulk != bBulk) return aBulk ? -1 : 1;
          return (a.establishedYear ?? 9999)
              .compareTo(b.establishedYear ?? 9999);
        });
        return matching;
      });
}
