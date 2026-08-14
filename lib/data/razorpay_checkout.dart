import 'package:cloud_functions/cloud_functions.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/billing.dart';
import 'org_repository.dart' show guard, guardStream;

/// What `createPaymentLink` (`functions/razorpay.js`) hands back: somewhere
/// to send the payer, and the row to watch for the answer.
class PendingPayment {
  const PendingPayment({required this.paymentId, required this.url});
  final String paymentId;
  final String url;
}

/// The real-money counterpart to [FreeCheckout] — see `functions/razorpay.js`
/// for why this cannot be a second `PaymentGateway` implementation and has
/// to be its own asynchronous flow instead.
///
/// Nothing here writes an entitlement. This only starts a charge and reads
/// back what the server decided; [BillingRepository] and its synchronous
/// `PaymentGateway` seam remain exactly what they are today for the ₹0
/// launch-offer path.
class RazorpayCheckout {
  const RazorpayCheckout();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Starts a charge for an org plan or a member plan. Throws
  /// [ValidationException] with a message safe to show directly — the
  /// callable's `HttpsError.message` is already written for a human.
  Future<PendingPayment> start({
    required PlanPaymentKind kind,
    required String subjectId,
    required String planWire,
  }) =>
      guard(() async {
        if (kind != PlanPaymentKind.orgPlan &&
            kind != PlanPaymentKind.memberPlan) {
          throw const ValidationException(
            'Only club and Premium plans can be paid for through this flow.',
          );
        }
        try {
          final callable = _functions.httpsCallable('createPaymentLink');
          final result = await callable.call<Map<String, dynamic>>({
            'kind': kind.wire,
            'subjectId': subjectId,
            'plan': planWire,
          });
          final data = result.data;
          return PendingPayment(
            paymentId: data['paymentId'] as String,
            url: data['url'] as String,
          );
        } on FirebaseFunctionsException catch (e) {
          throw ValidationException(
            e.message ?? 'Could not start the payment. Try again.',
          );
        }
      });

  /// Live status of a payment this device started — flips to
  /// [PlanPaymentStatus.paid] the moment Razorpay's webhook lands, which is
  /// what tells the checkout screen to stop waiting and show success.
  ///
  /// Deliberately does not use [PlanPaymentStatus.fromWire], whose default
  /// reads a missing or unrecognised `status` as [PlanPaymentStatus.paid] —
  /// correct for a legacy ₹0 row written before that field existed, wrong
  /// here: this is the one place that default decides whether a real-money
  /// checkout reports success to the payer. Every row this flow itself
  /// writes always carries a recognised value (`createPaymentLink` sets
  /// `created` then `pending`, the webhook sets `paid` or leaves it for
  /// `failed` on a request that never reached the gateway) — an
  /// unrecognised value here is a bug on a row this flow created, not an old
  /// row predating the field, and must fail closed rather than fail open.
  Stream<PlanPaymentStatus> watchStatus(String paymentId) => guardStream(
        () => Refs.payments.doc(paymentId).snapshots().map((doc) {
          final data = doc.data();
          if (data == null) return PlanPaymentStatus.failed;
          return switch (data['status'] as String?) {
            'created' => PlanPaymentStatus.created,
            'pending' => PlanPaymentStatus.pending,
            'paid' => PlanPaymentStatus.paid,
            _ => PlanPaymentStatus.failed,
          };
        }),
      );
}
