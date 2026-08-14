import '../core/firebase/firestore_refs.dart';
import '../core/models/food_order.dart';
import '../domain/food/delivery_partner.dart';
import 'org_repository.dart' show guard, guardStream;

/// Food & delivery at the ground: a canteen menu and the orders against it.
/// See `GroundMenuItem`, `FoodOrder` and `DeliveryPartner`.
class FoodRepository {
  const FoodRepository({this.partner = const ManualFulfillment()});

  /// Same seam shape as `ClubCommerceRepository.gateway` — see
  /// `DeliveryPartner`'s class doc. `ManualFulfillment` is the only
  /// implementation wired in today.
  final DeliveryPartner partner;

  // --- Menu (ground owner side) -------------------------------------------

  Stream<List<GroundMenuItem>> watchActiveMenu(String groundId) => guardStream(
        () => Refs.groundMenuItems
            .where('groundId', isEqualTo: groundId)
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) =>
                s.docs.map(GroundMenuItem.fromDoc).toList(growable: false)),
      );

  Stream<List<GroundMenuItem>> watchFullMenu(String groundId) => guardStream(
        () => Refs.groundMenuItems
            .where('groundId', isEqualTo: groundId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) =>
                s.docs.map(GroundMenuItem.fromDoc).toList(growable: false)),
      );

  Future<String> addMenuItem(
    GroundMenuItem item, {
    required String createdByUid,
  }) =>
      guard(() async {
        final ref = Refs.groundMenuItems.doc();
        await ref.set(item.toCreate(createdByUid: createdByUid));
        return ref.id;
      });

  Future<void> updateMenuItem(GroundMenuItem item) => guard(
        () => Refs.groundMenuItem(item.id).update(item.toUpdate()),
      );

  Future<void> setMenuItemActive(String itemId, bool active) => guard(
        () => Refs.groundMenuItem(itemId).update({'isActive': active}),
      );

  // --- Orders ----------------------------------------------------------

  /// Places [order]. [order.amountPaidPaise] should already reflect
  /// `Pricing.productPricePaise` — this method's job is fulfilment, not
  /// pricing, mirroring the line `ClubCommerceRepository.placeOrder` draws
  /// between the two.
  Future<String> placeOrder(FoodOrder order) => guard(() async {
        final ref = Refs.foodOrders.doc();
        final partnerRef = await partner.requestDelivery(
          orderId: ref.id,
          groundId: order.groundId,
          description: '${order.itemCount} item(s) — ${order.groundName}',
        );
        await ref.set(FoodOrder(
          id: ref.id,
          groundId: order.groundId,
          groundName: order.groundName,
          lines: order.lines,
          buyerUid: order.buyerUid,
          buyerName: order.buyerName,
          deliveryPartner: partner.type,
          partnerRef: partnerRef,
          amountPaidPaise: order.amountPaidPaise,
        ).toCreate());
        return ref.id;
      });

  Stream<List<FoodOrder>> watchMyOrders(String buyerUid) => guardStream(
        () => Refs.foodOrders
            .where('buyerUid', isEqualTo: buyerUid)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(FoodOrder.fromDoc).toList(growable: false)),
      );

  /// Every order waiting on one ground to fulfil.
  Stream<List<FoodOrder>> watchGroundOrders(String groundId) => guardStream(
        () => Refs.foodOrders
            .where('groundId', isEqualTo: groundId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(FoodOrder.fromDoc).toList(growable: false)),
      );

  Future<void> updateOrderStatus(String orderId, {required String status}) =>
      guard(() => Refs.foodOrder(orderId).update({'status': status}));
}
