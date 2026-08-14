import '../../core/models/enums.dart';

/// What actually gets an order from a ground's canteen into a player's hands.
///
/// ## Why this is an interface with one working implementation
///
/// Same shape as `lib/data/billing_repository.dart`'s `PaymentGateway`, and
/// for the same reason. The product vision for this feature is explicit:
/// "bring all the vendors here — Zepto, Zomato, Instamart — for bananas to
/// water to food." Building straight to a specific vendor's API would mean
/// picking one before there is a commercial relationship with any of them,
/// and would leave the other two as a rewrite rather than a second
/// implementation. So the seam exists first: [ManualFulfillment] (the ground
/// hands the order over itself) is the only implementation wired in today,
/// and a real courier integration is a class that implements this interface
/// plus one provider swap — no caller above it changes, exactly as
/// `PaymentGateway`'s own doc promises for Razorpay.
abstract class DeliveryPartner {
  /// Asks this partner to fulfil an order. Returns the partner's own
  /// reference for it (a courier tracking id), or null when no external
  /// partner was involved (the ground fulfils it directly).
  ///
  /// Throws to refuse — a partner that throws must not have accepted the
  /// order, mirroring `PaymentGateway.collect`'s contract exactly.
  Future<String?> requestDelivery({
    required String orderId,
    required String groundId,
    required String description,
  });

  DeliveryPartnerType get type;
}

/// The only fulfilment path that exists today: the ground's own staff hand
/// the order over, in person, the way every canteen at every turf in India
/// already works. Never refuses — there is no external acceptance step to
/// fail.
class ManualFulfillment implements DeliveryPartner {
  const ManualFulfillment();

  @override
  DeliveryPartnerType get type => DeliveryPartnerType.manual;

  @override
  Future<String?> requestDelivery({
    required String orderId,
    required String groundId,
    required String description,
  }) async =>
      null;
}

/// Not yet integrated. Exists so the seam in [DeliveryPartner] has a named
/// place to land a real Zepto integration — see the class doc — rather than
/// requiring a new type to be invented the day that partnership exists.
/// Throwing rather than silently falling back to [ManualFulfillment] is
/// deliberate: a caller that wires this in by mistake, before the real API
/// call exists, must fail loudly, the same way `FreeCheckout` refuses a
/// nonzero charge rather than pretending to collect it.
class ZeptoDelivery implements DeliveryPartner {
  const ZeptoDelivery();

  @override
  DeliveryPartnerType get type => DeliveryPartnerType.zepto;

  @override
  Future<String?> requestDelivery({
    required String orderId,
    required String groundId,
    required String description,
  }) =>
      throw UnimplementedError(
        'Zepto is not integrated yet. Use ManualFulfillment until a real '
        'partnership and API integration exist.',
      );
}

/// See [ZeptoDelivery] — same status, same reasoning, a different vendor.
class ZomatoDelivery implements DeliveryPartner {
  const ZomatoDelivery();

  @override
  DeliveryPartnerType get type => DeliveryPartnerType.zomato;

  @override
  Future<String?> requestDelivery({
    required String orderId,
    required String groundId,
    required String description,
  }) =>
      throw UnimplementedError(
        'Zomato is not integrated yet. Use ManualFulfillment until a real '
        'partnership and API integration exist.',
      );
}

/// See [ZeptoDelivery] — same status, same reasoning, a different vendor.
class InstamartDelivery implements DeliveryPartner {
  const InstamartDelivery();

  @override
  DeliveryPartnerType get type => DeliveryPartnerType.instamart;

  @override
  Future<String?> requestDelivery({
    required String orderId,
    required String groundId,
    required String description,
  }) =>
      throw UnimplementedError(
        'Instamart is not integrated yet. Use ManualFulfillment until a '
        'real partnership and API integration exist.',
      );
}
