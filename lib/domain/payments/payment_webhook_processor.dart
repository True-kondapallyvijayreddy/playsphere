import '../../core/models/payment.dart';
import 'payment_state_machine.dart';

/// The Razorpay webhook event types this app reacts to. Deliberately a
/// small, closed set matching exactly the state transitions
/// [PaymentStateMachine] allows — Razorpay sends more event types than this
/// (e.g. `order.paid`), but only these three actually change a [Payment]'s
/// status.
enum PaymentWebhookType {
  paymentCaptured,
  paymentFailed,
  refundProcessed,
}

/// One inbound Razorpay webhook delivery.
///
/// [id] is Razorpay's own event id (the `x-razorpay-event-id` header, or
/// the `id` field of the event payload) — it is what makes processing
/// idempotent, NOT a hash of the payload or a locally generated id. Two
/// deliveries of the "same" webhook always carry the same [id]; that is the
/// one fact this whole idempotency scheme leans on.
class PaymentWebhookEvent {
  const PaymentWebhookEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.razorpayPaymentId,
    this.razorpaySignature,
    this.refundId,
    this.refundAmountPaise,
    this.failureReason,
  });

  final String id;
  final PaymentWebhookType type;
  final DateTime occurredAt;

  final String? razorpayPaymentId;
  final String? razorpaySignature;

  final String? refundId;
  final int? refundAmountPaise;

  final String? failureReason;
}

/// Thrown when a `refund.processed` webhook asks for more than a payment
/// has left to refund. This must be a hard rejection rather than a clamp:
/// silently capping the refund at whatever remains would make the webhook
/// processor lie about what it did, and the discrepancy would only surface
/// later, in reconciliation, disconnected from the event that caused it.
class RefundExceedsRemainingAmountException implements Exception {
  const RefundExceedsRemainingAmountException({
    required this.requestedPaise,
    required this.remainingPaise,
  });

  final int requestedPaise;
  final int remainingPaise;

  @override
  String toString() =>
      'RefundExceedsRemainingAmountException: requested $requestedPaise '
      'paise but only $remainingPaise paise remain refundable';
}

/// Applies inbound Razorpay webhooks to a [Payment], idempotently.
///
/// Razorpay's own documentation is explicit that webhooks may be delivered
/// more than once (retried on any non-2xx response, and occasionally
/// duplicated regardless) — a payments integration that is not idempotent
/// against that will eventually double-capture or double-refund a real
/// payment. The guard is simple and lives in one place: before doing
/// anything else, check whether [PaymentWebhookEvent.id] is already in
/// [Payment.processedWebhookEventIds]; if so, return the payment unchanged.
/// Every other rule in this class only runs once per distinct event id,
/// which is what makes "deliver the same webhook twice" produce the exact
/// same [Payment] both times.
class PaymentWebhookProcessor {
  const PaymentWebhookProcessor({
    this.stateMachine = const PaymentStateMachine(),
  });

  final PaymentStateMachine stateMachine;

  Payment apply(Payment payment, PaymentWebhookEvent event) {
    if (payment.processedWebhookEventIds.contains(event.id)) {
      return payment;
    }

    late final Payment updated;
    switch (event.type) {
      case PaymentWebhookType.paymentCaptured:
        updated = stateMachine
            .transition(payment, PaymentStatus.captured, at: event.occurredAt)
            .copyWith(
              razorpay: payment.razorpay.copyWith(
                paymentId: event.razorpayPaymentId,
                signature: event.razorpaySignature,
              ),
            );

      case PaymentWebhookType.paymentFailed:
        updated = stateMachine.transition(
          payment,
          PaymentStatus.failed,
          at: event.occurredAt,
          failureReason: event.failureReason,
        );

      case PaymentWebhookType.refundProcessed:
        final amount = event.refundAmountPaise ?? 0;
        if (amount <= 0) {
          throw ArgumentError.value(
            amount,
            'refundAmountPaise',
            'a refund webhook must carry a positive amount',
          );
        }
        final remaining = payment.remainingRefundablePaise;
        if (amount > remaining) {
          throw RefundExceedsRemainingAmountException(
            requestedPaise: amount,
            remainingPaise: remaining,
          );
        }
        final target = amount == remaining
            ? PaymentStatus.refunded
            : PaymentStatus.partiallyRefunded;
        final record = RefundRecord(
          id: event.id,
          razorpayRefundId: event.refundId,
          amountPaise: amount,
          reason: event.failureReason,
          createdAt: event.occurredAt,
        );
        updated = stateMachine
            .transition(payment, target, at: event.occurredAt)
            .copyWith(refunds: [...payment.refunds, record]);
    }

    return updated.copyWith(
      processedWebhookEventIds: {
        ...updated.processedWebhookEventIds,
        event.id,
      },
      updatedAt: event.occurredAt,
    );
  }
}
