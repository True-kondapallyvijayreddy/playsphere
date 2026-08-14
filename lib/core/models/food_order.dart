import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// One thing a ground's canteen sells, at `groundMenuItems/{itemId}`.
///
/// Deliberately its own model rather than reusing `ClubProduct` — a jersey
/// and a bottle of water share nothing except "a price and a name": a menu
/// item has no sizes, is scoped to a ground rather than a club, and belongs
/// to a completely different fulfilment path (see `FoodOrder`).
class GroundMenuItem {
  const GroundMenuItem({
    required this.id,
    required this.groundId,
    required this.groundName,
    required this.name,
    this.description = '',
    required this.category,
    required this.priceInPaise,
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
  });

  final String id;
  final String groundId;
  final String groundName;
  final String name;
  final String description;
  final FoodItemCategory category;
  final int priceInPaise;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;

  factory GroundMenuItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroundMenuItem(
      id: doc.id,
      groundId: Fs.str(d['groundId']),
      groundName: Fs.str(d['groundName']),
      name: Fs.str(d['name']),
      description: Fs.str(d['description']),
      category: FoodItemCategory.fromWire(d['category'] as String?),
      priceInPaise: Fs.intOrNull(d['priceInPaise']) ?? 0,
      isActive: d['isActive'] == null ? true : Fs.boolean(d['isActive'], true),
      createdByUid: Fs.strOrNull(d['createdByUid']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate({required String createdByUid}) => Fs.prune({
        'groundId': groundId,
        'groundName': groundName,
        'name': name,
        'description': description,
        'category': category.wire,
        'priceInPaise': priceInPaise,
        'isActive': true,
        'createdByUid': createdByUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Map<String, Object?> toUpdate() => Fs.prune({
        'name': name,
        'description': description,
        'category': category.wire,
        'priceInPaise': priceInPaise,
        'isActive': isActive,
      });
}

/// One line of an order — a menu item, a quantity, and the price at the
/// moment it was ordered (so a later menu price change never rewrites a
/// receipt for an order already placed).
class FoodOrderLine {
  const FoodOrderLine({
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.unitPricePaise,
  });

  final String menuItemId;
  final String name;
  final int quantity;
  final int unitPricePaise;

  Map<String, Object?> toMap() => {
        'menuItemId': menuItemId,
        'name': name,
        'quantity': quantity,
        'unitPricePaise': unitPricePaise,
      };

  factory FoodOrderLine.fromMap(Map<String, dynamic> m) => FoodOrderLine(
        menuItemId: Fs.str(m['menuItemId']),
        name: Fs.str(m['name']),
        quantity: Fs.intOrNull(m['quantity']) ?? 1,
        unitPricePaise: Fs.intOrNull(m['unitPricePaise']) ?? 0,
      );

  static List<FoodOrderLine> listFromRaw(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((m) => FoodOrderLine.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false)
      : const [];

  static List<Map<String, Object?>> listToRaw(List<FoodOrderLine> lines) =>
      lines.map((l) => l.toMap()).toList(growable: false);
}

/// One order against one ground's canteen, at `foodOrders/{orderId}`.
///
/// [deliveryPartner] records who actually carried it — see
/// `lib/domain/food/delivery_partner.dart`. Every order today is fulfilled
/// by [DeliveryPartnerType.manual] because that is the only implementation
/// wired in; the field exists so a real courier partnership is a value this
/// document can already hold, not a schema change to add one.
class FoodOrder {
  const FoodOrder({
    required this.id,
    required this.groundId,
    required this.groundName,
    this.lines = const [],
    required this.buyerUid,
    required this.buyerName,
    this.deliveryPartner = DeliveryPartnerType.manual,
    this.partnerRef,
    required this.amountPaidPaise,
    this.status = FoodOrderStatus.placed,
    this.createdAt,
  });

  final String id;
  final String groundId;
  final String groundName;
  final List<FoodOrderLine> lines;

  final String buyerUid;
  final String buyerName;

  final DeliveryPartnerType deliveryPartner;

  /// The partner's own tracking reference, when one was involved — null for
  /// [DeliveryPartnerType.manual], mirroring `PlanPayment.gatewayRef`.
  final String? partnerRef;

  final int amountPaidPaise;
  final FoodOrderStatus status;
  final DateTime? createdAt;

  int get itemCount => lines.fold(0, (total, l) => total + l.quantity);

  factory FoodOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return FoodOrder(
      id: doc.id,
      groundId: Fs.str(d['groundId']),
      groundName: Fs.str(d['groundName']),
      lines: FoodOrderLine.listFromRaw(d['lines']),
      buyerUid: Fs.str(d['buyerUid']),
      buyerName: Fs.str(d['buyerName'], 'A player'),
      deliveryPartner: DeliveryPartnerType.fromWire(d['deliveryPartner'] as String?),
      partnerRef: Fs.strOrNull(d['partnerRef']),
      amountPaidPaise: Fs.intOrNull(d['amountPaidPaise']) ?? 0,
      status: FoodOrderStatus.fromWire(d['status'] as String?),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  /// The only shape a client may create — always [FoodOrderStatus.placed].
  /// See `firestore.rules` on `foodOrders` for the launch-offer bound on
  /// [amountPaidPaise], same posture as `ClubOrder.toCreate`.
  Map<String, Object?> toCreate() => Fs.prune({
        'groundId': groundId,
        'groundName': groundName,
        'lines': FoodOrderLine.listToRaw(lines),
        'buyerUid': buyerUid,
        'buyerName': buyerName,
        'deliveryPartner': deliveryPartner.wire,
        'partnerRef': partnerRef,
        'amountPaidPaise': amountPaidPaise,
        'status': FoodOrderStatus.placed.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
