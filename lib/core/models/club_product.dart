import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// One item a club sells under its own name, at `clubProducts/{productId}`.
///
/// ## Why this is not `ShopProduct`
///
/// `lib/core/models/shop_product.dart` is a curated, vendor-hosted affiliate
/// catalog — the whole point of it is that PlaySphere never touches the
/// money or the inventory; [url] sends the buyer to somebody else's
/// checkout. A club's own jersey is the opposite shape: the club sets the
/// price, the club fulfils the order by hand, and there is no external
/// checkout to send anyone to. Collapsing the two would either force the
/// Decathlon catalog through a cart it deliberately avoids, or force a
/// club's jersey through a vendor `url` field that makes no sense for it.
///
/// ## Money
///
/// [listPricePaise] is the club's real, set price — shown struck through
/// once `Pricing.introOfferActive` flips off, exactly like an org's ₹999
/// plan. See `Pricing.productPricePaise`.
class ClubProduct {
  const ClubProduct({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.name,
    this.description = '',
    required this.category,
    required this.listPricePaise,
    this.imageUrl,
    this.sizes = const [],
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
  });

  final String id;
  final String orgId;

  /// Denormalized at creation, same reasoning as `GiveNeed.orgName` — a
  /// storefront renders without a join per card.
  final String orgName;

  final String name;
  final String description;
  final ClubProductCategory category;
  final int listPricePaise;
  final String? imageUrl;

  /// e.g. `['S', 'M', 'L', 'XL']`. Empty means one-size / not applicable.
  final List<String> sizes;

  /// Whether this appears on the public storefront. A club pausing a
  /// sold-out jersey sets this false rather than deleting it — the product
  /// still needs to exist for past orders to render its name correctly.
  final bool isActive;

  final String? createdByUid;
  final DateTime? createdAt;

  factory ClubProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ClubProduct(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      orgName: Fs.str(d['orgName']),
      name: Fs.str(d['name']),
      description: Fs.str(d['description']),
      category: ClubProductCategory.fromWire(d['category'] as String?),
      listPricePaise: Fs.intOrNull(d['listPricePaise']) ?? 0,
      imageUrl: Fs.strOrNull(d['imageUrl']),
      sizes: (d['sizes'] as List?)?.map((e) => e.toString()).toList(growable: false) ??
          const [],
      isActive: d['isActive'] == null ? true : Fs.boolean(d['isActive'], true),
      createdByUid: Fs.strOrNull(d['createdByUid']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate({required String createdByUid}) => Fs.prune({
        'orgId': orgId,
        'orgName': orgName,
        'name': name,
        'description': description,
        'category': category.wire,
        'listPricePaise': listPricePaise,
        'imageUrl': imageUrl,
        'sizes': sizes,
        'isActive': true,
        'createdByUid': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Map<String, Object?> toUpdate() => Fs.prune({
        'name': name,
        'description': description,
        'category': category.wire,
        'listPricePaise': listPricePaise,
        'imageUrl': imageUrl,
        'sizes': sizes,
        'isActive': isActive,
      });
}

/// One buyer's order against one [ClubProduct], at `clubOrders/{orderId}`.
///
/// Self-contained, deliberately not also mirrored into the shared
/// `payments/` ledger `PlanPayment` writes to. See `GroundRepository`'s
/// booking-creation comment: a payments row records money PlaySphere itself
/// collected, and neither a ground booking nor a club-store order under the
/// launch offer is that — the club (not PlaySphere) is the seller, and
/// [amountPaidPaise] already carries what was actually taken, on the order
/// itself, exactly like `GroundBooking.amountPaise` does for a booking.
class ClubOrder {
  const ClubOrder({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.productId,
    required this.productName,
    this.size,
    this.quantity = 1,
    required this.buyerUid,
    required this.buyerName,
    required this.unitListPricePaise,
    required this.amountPaidPaise,
    this.status = ClubOrderStatus.placed,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String orgName;
  final String productId;
  final String productName;
  final String? size;
  final int quantity;

  final String buyerUid;
  final String buyerName;

  final int unitListPricePaise;

  /// What was actually collected for the whole order — `0` while
  /// `Pricing.introOfferActive`, `unitListPricePaise * quantity` once it
  /// is not. Kept alongside the list price for the same "we gave away
  /// ₹X of launch offers" reporting `PlanPayment.listPricePaise` exists for.
  final int amountPaidPaise;

  final ClubOrderStatus status;
  final DateTime? createdAt;

  factory ClubOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ClubOrder(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      orgName: Fs.str(d['orgName']),
      productId: Fs.str(d['productId']),
      productName: Fs.str(d['productName']),
      size: Fs.strOrNull(d['size']),
      quantity: Fs.intOrNull(d['quantity']) ?? 1,
      buyerUid: Fs.str(d['buyerUid']),
      buyerName: Fs.str(d['buyerName']),
      unitListPricePaise: Fs.intOrNull(d['unitListPricePaise']) ?? 0,
      amountPaidPaise: Fs.intOrNull(d['amountPaidPaise']) ?? 0,
      status: ClubOrderStatus.fromWire(d['status'] as String?),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  /// The only shape a client may create — always [ClubOrderStatus.placed].
  /// There is no server-side function computing [amountPaidPaise] today, so
  /// `firestore.rules` instead bounds the client's claim to exactly what the
  /// launch offer allows (`0`) — see its comment on `clubOrders`, and
  /// `FreeCheckout`'s doc for why that boundary matters.
  Map<String, Object?> toCreate() => Fs.prune({
        'orgId': orgId,
        'orgName': orgName,
        'productId': productId,
        'productName': productName,
        'size': size,
        'quantity': quantity,
        'buyerUid': buyerUid,
        'buyerName': buyerName,
        'unitListPricePaise': unitListPricePaise,
        'amountPaidPaise': amountPaidPaise,
        'status': ClubOrderStatus.placed.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
