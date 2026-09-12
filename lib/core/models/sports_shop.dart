import 'package:cloud_firestore/cloud_firestore.dart';

import 'coach.dart';
import 'firestore_codec.dart';

/// What a shop actually stocks, at `sportsShops/{uid}`.
///
/// A small closed list rather than free text, for the same reason
/// [SportsMedicRole] is one: this is the filter the directory turns on. A
/// captain whose team needs eleven pairs of studs and a parent buying a first
/// racket are looking for different shops, and neither should have to read
/// forty free-text descriptions to tell them apart.
enum ShopStock {
  equipment('equipment', 'Equipment', '\u{1F3D0}'),
  footwear('footwear', 'Footwear', '\u{1F45F}'),
  apparel('apparel', 'Apparel & kit', '\u{1F455}'),
  fitness('fitness', 'Fitness & gym', '\u{1F3CB}'),
  nutrition('nutrition', 'Nutrition', '\u{1F95B}');

  const ShopStock(this.wire, this.label, this.emoji);

  final String wire;
  final String label;
  final String emoji;

  static ShopStock fromWire(String? w) => ShopStock.values.firstWhere(
        (e) => e.wire == w,
        // Equipment is what almost every shop in this directory sells, so an
        // unreadable document degrades to the least surprising row rather
        // than vanishing from the list.
        orElse: () => ShopStock.equipment,
      );

  static List<ShopStock> listFromWire(Object? v) => [
        for (final w in Fs.strList(v))
          if (ShopStock.values.any((e) => e.wire == w)) ShopStock.fromWire(w),
      ];
}

/// What a shop does beyond selling something off a shelf.
///
/// [clubOrders] is the one that earns this directory its place in PlaySphere
/// rather than in a general local-business listing: a club kitting out a
/// twenty-player squad is the single largest purchase in grassroots sport,
/// and "who will do bulk team kit in my district" is a question no general
/// map search answers. The rest are the services people ring a sports shop
/// about rather than order online — a racket restrung before Sunday, a bat
/// re-gripped, studs fitted to a growing foot.
enum ShopService {
  clubOrders('club_orders', 'Bulk & club orders'),
  stringing('stringing', 'Racket stringing'),
  kitPrinting('kit_printing', 'Names & numbers'),
  repairs('repairs', 'Repairs & servicing'),
  fitting('fitting', 'Fitting & trials'),
  homeDelivery('home_delivery', 'Home delivery');

  const ShopService(this.wire, this.label);

  final String wire;
  final String label;

  static ShopService fromWire(String? w) => ShopService.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => ShopService.clubOrders,
      );

  static List<ShopService> listFromWire(Object? v) => [
        for (final w in Fs.strList(v))
          if (ShopService.values.any((e) => e.wire == w))
            ShopService.fromWire(w),
      ];
}

/// A local sports shop that has listed itself, at `sportsShops/{uid}`.
///
/// ## Why this is not part of the `products` catalogue or a club store
///
/// PlaySphere already sells two ways, and this is neither. `ShopProduct` is a
/// curated catalogue of items with prices and an outbound link — a shelf.
/// `ClubProduct` is one club selling its own merchandise to its own members.
/// This is a third thing: a real shop, on a real street, that a club rings up
/// to ask whether they can do twenty jerseys by Friday.
///
/// Nothing is bought through PlaySphere here, and that is deliberate rather
/// than unfinished. The transaction that matters in this market is a
/// negotiated bulk order settled at the counter — the same reason match entry
/// fees are collected at the venue and never in-app (see `Pricing`). What the
/// product can honestly provide is the introduction, which is exactly what
/// was missing: a club with a kit budget had no way to find the shop two
/// districts over that does team printing.
///
/// ## Why the document id is the uid
///
/// Same as [CoachProfile] and `SportsMedicProfile`: one account is one
/// listing, "am I listed?" stays a single `get`, the rule stays
/// `uid() == shopUid`, and nobody lands in the directory three times by
/// tapping Save three times. An owner with two branches names the second in
/// [address]; they are one business with one phone number and one reputation.
///
/// ## What PlaySphere asserts about a shop
///
/// Nothing, except [isVerified], which no client can write. There is no
/// rating and no review. A one-star review economy on a directory this small
/// is a weapon a competitor uses, not information a buyer can trust — and a
/// shop with four ratings tells a reader nothing either way.
class SportsShop {
  const SportsShop({
    required this.uid,
    required this.shopName,
    this.ownerName,
    this.logoUrl,
    this.headline,
    this.about,
    this.stocks = const [ShopStock.equipment],
    this.services = const [],
    this.sportIds = const [],
    this.city = '',
    this.district,
    this.address,
    this.pincode,
    this.contactPhone,
    this.whatsappPhone,
    this.email,
    this.hours,
    this.establishedYear,
    this.isActive = true,
    this.isVerified = false,
    this.createdAt,
  });

  /// Also the document id — the owner's account.
  final String uid;

  /// The name on the board outside. The one thing a customer already knows.
  final String shopName;

  /// Copied from the account on every save, never typed — same discipline as
  /// `CoachProfile.displayName`. Shown so a club knows who they will be
  /// speaking to, not to identify the business.
  final String? ownerName;

  final String? logoUrl;

  /// One line in their own words: "Cricket specialists since 1998, Nalgonda".
  final String? headline;
  final String? about;

  final List<ShopStock> stocks;
  final List<ShopService> services;

  /// Sports they actually stock for.
  ///
  /// Empty means "all sports", and is a legitimate answer rather than an
  /// incomplete listing — a general sports shop genuinely does sell a
  /// shuttle, a football and a skipping rope. Same rule as
  /// `SportsMedicProfile.sportIds`, and the opposite of `CoachProfile`,
  /// where an empty list means somebody has not finished.
  final List<String> sportIds;

  final String city;
  final String? district;
  final String? address;
  final String? pincode;

  final String? contactPhone;

  /// Kept apart from [contactPhone] because a bulk order is negotiated over
  /// WhatsApp in this market — a club sends a list and a photo of last
  /// season's jersey — while the shop line is answered during opening hours.
  final String? whatsappPhone;

  final String? email;

  /// Free text — "Mon-Sat 10am-9pm, Sunday closed". Never parsed and never
  /// used to compute an open/closed badge: half these shops close for two
  /// hours in the afternoon and none of them would keep a structured
  /// timetable accurate.
  final String? hours;

  final int? establishedYear;

  /// The owner's own switch. Delisting rather than deleting, so a shop that
  /// shuts for a season can come back without retyping everything.
  final bool isActive;

  /// PlaySphere's judgement, never the shop's, and unwritable by any client —
  /// `firestore.rules` enforces it. Means somebody confirmed the shop exists
  /// at the address given. It is not a statement about price or quality.
  final bool isVerified;

  final DateTime? createdAt;

  String get cityKey => city.trim().toLowerCase();

  bool stocksFor(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);

  bool offers(ShopService service) => services.contains(service);

  bool sells(ShopStock stock) => stocks.contains(stock);

  /// The line under the name in the directory: what they sell, and where.
  String get subtitleLine => [
        if (stocks.isNotEmpty) stocks.map((s) => s.label).join(', '),
        if (city.isNotEmpty) city,
      ].join('  ·  ');

  /// Every word this shop should be findable by.
  ///
  /// Reuses `CoachProfile.tokenize` rather than copying it, for the reason
  /// that class gives: there are already several directories in this package
  /// doing exactly this, and another copy would be another thing to fix the
  /// day one of them learns to split `table_tennis`.
  List<String> get searchTokens => CoachProfile.tokenize([
        shopName,
        city,
        district,
        address,
        headline,
        ownerName,
        for (final s in stocks) s.label,
        for (final s in services) s.label,
        ...sportIds,
      ]);

  static List<String> tokenizeQuery(String raw) => CoachProfile.tokenize([raw]);

  factory SportsShop.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      SportsShop.fromMap(doc.id, doc.data() ?? const {});

  /// The parsing, split from [fromDoc] so it can be exercised without a
  /// Firestore snapshot — the same split `UmpireProfile` already makes.
  ///
  /// Worth having as its own entry point because the degradation rules here
  /// are real logic rather than plumbing: an empty `stocks` list becomes
  /// [ShopStock.equipment] and an unrecognised wire value is dropped, both so
  /// a half-written or newer document still renders a row somebody can act
  /// on. Those are the behaviours a test needs to reach.
  factory SportsShop.fromMap(String id, Map<String, dynamic> d) {
    return SportsShop(
      uid: id,
      shopName: Fs.str(d['shopName'], 'Sports shop'),
      ownerName: Fs.strOrNull(d['ownerName']),
      logoUrl: Fs.strOrNull(d['logoUrl']),
      headline: Fs.strOrNull(d['headline']),
      about: Fs.strOrNull(d['about']),
      stocks: () {
        final s = ShopStock.listFromWire(d['stocks']);
        // Never empty: a shop that sells nothing is a row somebody taps and
        // cannot act on. Equipment is what every listing starts from.
        return s.isEmpty ? const [ShopStock.equipment] : s;
      }(),
      services: ShopService.listFromWire(d['services']),
      sportIds: Fs.strList(d['sportIds']),
      city: Fs.str(d['city']),
      district: Fs.strOrNull(d['district']),
      address: Fs.strOrNull(d['address']),
      pincode: Fs.strOrNull(d['pincode']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      whatsappPhone: Fs.strOrNull(d['whatsappPhone']),
      email: Fs.strOrNull(d['email']),
      hours: Fs.strOrNull(d['hours']),
      establishedYear: Fs.intOrNull(d['establishedYear']),
      isActive: Fs.boolean(d['isActive'], true),
      isVerified: Fs.boolean(d['isVerified']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        ...toUpdate(),
        // Spelled out rather than omitted so the intent survives somebody
        // later tidying this map: neither is the client's to set, and the
        // rules refuse the write if either is wrong.
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Everything the owner may edit. Excludes [isVerified] and [createdAt].
  Map<String, Object?> toUpdate() => {
        'shopName': shopName.trim(),
        'ownerName': ownerName,
        'logoUrl': logoUrl,
        'headline': headline,
        'about': about,
        'stocks': [for (final s in stocks) s.wire],
        'services': [for (final s in services) s.wire],
        'sportIds': sportIds,
        'city': city.trim(),
        'cityKey': cityKey,
        'district': district,
        'districtKey': district?.trim().toLowerCase(),
        'address': address,
        'pincode': pincode,
        'contactPhone': contactPhone,
        'whatsappPhone': whatsappPhone,
        'email': email,
        'hours': hours,
        'establishedYear': establishedYear,
        'isActive': isActive,
        // Recomputed on every write, never entered — a listing edited to add
        // a sport has to become findable by it in the same save.
        'searchTokens': searchTokens,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  SportsShop copyWith({
    String? shopName,
    String? ownerName,
    String? logoUrl,
    String? headline,
    String? about,
    List<ShopStock>? stocks,
    List<ShopService>? services,
    List<String>? sportIds,
    String? city,
    String? district,
    String? address,
    String? pincode,
    String? contactPhone,
    String? whatsappPhone,
    String? email,
    String? hours,
    int? establishedYear,
    bool? isActive,
  }) =>
      SportsShop(
        uid: uid,
        shopName: shopName ?? this.shopName,
        ownerName: ownerName ?? this.ownerName,
        logoUrl: logoUrl ?? this.logoUrl,
        headline: headline ?? this.headline,
        about: about ?? this.about,
        stocks: stocks ?? this.stocks,
        services: services ?? this.services,
        sportIds: sportIds ?? this.sportIds,
        city: city ?? this.city,
        district: district ?? this.district,
        address: address ?? this.address,
        pincode: pincode ?? this.pincode,
        contactPhone: contactPhone ?? this.contactPhone,
        whatsappPhone: whatsappPhone ?? this.whatsappPhone,
        email: email ?? this.email,
        hours: hours ?? this.hours,
        establishedYear: establishedYear ?? this.establishedYear,
        isActive: isActive ?? this.isActive,
        isVerified: isVerified,
        createdAt: createdAt,
      );
}
