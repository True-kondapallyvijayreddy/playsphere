import '../core/firebase/firestore_refs.dart';
import '../core/models/billing.dart';
import '../core/models/club_product.dart';
import 'billing_repository.dart' show PaymentGateway, FreeCheckout;
import 'org_repository.dart' show guard, guardStream;

/// Club Commerce: every club's own store — products the club sets a price
/// on and fulfils itself, distinct from [ShopRepository]'s curated vendor
/// link-out catalog. See `ClubProduct`'s class doc.
class ClubCommerceRepository {
  const ClubCommerceRepository({this.gateway = const FreeCheckout()});

  /// Same seam `BillingRepository` uses — see its doc. Injected here rather
  /// than hardcoded so the day Razorpay is wired in, this repository and
  /// `BillingRepository` swap providers together, not separately.
  final PaymentGateway gateway;

  // --- Storefront (buyer side) -------------------------------------------

  /// One club's public storefront — active products only, newest first.
  Stream<List<ClubProduct>> watchActiveProducts(String orgId) => guardStream(
        () => Refs.clubProducts
            .where('orgId', isEqualTo: orgId)
            .where('isActive', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) =>
                s.docs.map(ClubProduct.fromDoc).toList(growable: false)),
      );

  // --- Catalog management (club admin side) -------------------------------

  /// Everything the club has ever listed, active or paused — its own
  /// management view.
  Stream<List<ClubProduct>> watchOrgCatalog(String orgId) => guardStream(
        () => Refs.clubProducts
            .where('orgId', isEqualTo: orgId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) =>
                s.docs.map(ClubProduct.fromDoc).toList(growable: false)),
      );

  Future<String> createProduct(
    ClubProduct product, {
    required String createdByUid,
  }) =>
      guard(() async {
        final ref = Refs.clubProducts.doc();
        await ref.set(product.toCreate(createdByUid: createdByUid));
        return ref.id;
      });

  Future<void> updateProduct(ClubProduct product) => guard(
        () => Refs.clubProduct(product.id).update(product.toUpdate()),
      );

  Future<void> setActive(String productId, bool active) => guard(
        () => Refs.clubProduct(productId).update({'isActive': active}),
      );

  // --- Orders --------------------------------------------------------------

  /// Places [order] and records the charge on the shared `payments/` ledger
  /// in one batch — same pattern as `BillingRepository.purchaseOrgPlan`, and
  /// for the same reason: the club is the seller here, not PlaySphere, but
  /// the money (₹0, today) still moved through the one gateway seam every
  /// purchase in the product goes through, so it belongs in the one ledger
  /// every purchase in the product lands in.
  Future<String> placeOrder(ClubOrder order) => guard(() async {
        final gatewayRef = await gateway.collect(
          amountPaise: order.amountPaidPaise,
          description: '${order.productName} — ${order.orgName}',
        );

        final orderRef = Refs.clubOrders.doc();
        final paymentRef = Refs.payments.doc();
        final batch = Refs.db.batch();

        batch.set(orderRef, order.toCreate());
        batch.set(
          paymentRef,
          PlanPayment(
            id: paymentRef.id,
            payerUid: order.buyerUid,
            kind: PlanPaymentKind.clubStore,
            subjectId: orderRef.id,
            planWire: order.productId,
            amountPaise: order.amountPaidPaise,
            listPricePaise: order.unitListPricePaise * order.quantity,
            validUntil: null,
            gateway: gateway.name,
            gatewayRef: gatewayRef,
          ).toCreate(),
        );

        await batch.commit();
        return orderRef.id;
      });

  /// Every order this person has placed, across every club.
  Stream<List<ClubOrder>> watchMyOrders(String buyerUid) => guardStream(
        () => Refs.clubOrders
            .where('buyerUid', isEqualTo: buyerUid)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(ClubOrder.fromDoc).toList(growable: false)),
      );

  /// Every order waiting on one club to fulfil.
  Stream<List<ClubOrder>> watchOrgOrders(String orgId) => guardStream(
        () => Refs.clubOrders
            .where('orgId', isEqualTo: orgId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(ClubOrder.fromDoc).toList(growable: false)),
      );

  Future<void> updateOrderStatus(String orderId, {required String status}) =>
      guard(() => Refs.clubOrder(orderId).update({'status': status}));
}
