import '../../core/models/payment.dart';

/// Thrown when code asks for a status change a [Payment] may not legally
/// make. Deliberately a distinct exception type (not a generic
/// [ArgumentError]) so a Cloud Function processing a webhook can catch it
/// specifically and route the event to a dead-letter/alert path rather than
/// mistaking it for a malformed request.
class IllegalPaymentTransitionException implements Exception {
  const IllegalPaymentTransitionException({required this.from, required this.to});

  final PaymentStatus from;
  final PaymentStatus to;

  @override
  String toString() =>
      'IllegalPaymentTransitionException: ${from.wire} -> ${to.wire} is not '
      'a legal payment transition';
}

/// The only rulebook for what a [Payment.status] may become next.
///
/// Money bugs are expensive in a way UI bugs are not: a payment silently
/// jumping `created` → `captured` (skipping `attempted`) could mean a
/// scorecard-lock-style race let a webhook double-apply, or a test fixture
/// that would otherwise have caught a bad assumption instead sailed through.
/// Centralising the legal graph here means every caller — the checkout flow,
/// the webhook processor, an admin refund action — is checked against the
/// same rules, and "can this payment do X" is answerable without reading
/// three files.
///
/// ```text
///   created ----> attempted ----> captured ----> partiallyRefunded --+
///      |               |               |                 ^          |
///      v               v               v                 +----------+
///    failed          failed        refunded  <----------------------+
/// ```
///
/// `failed` and `refunded` are terminal: a failed checkout attempt does not
/// get "retried" in place, it becomes a new [Payment] with a new Razorpay
/// order, so every row's status history stays a straight, auditable line
/// with no way to reopen money that has already been fully returned.
class PaymentStateMachine {
  const PaymentStateMachine();

  static const Map<PaymentStatus, Set<PaymentStatus>> _allowed = {
    PaymentStatus.created: {PaymentStatus.attempted, PaymentStatus.failed},
    PaymentStatus.attempted: {PaymentStatus.captured, PaymentStatus.failed},
    PaymentStatus.captured: {
      PaymentStatus.partiallyRefunded,
      PaymentStatus.refunded,
    },
    // A second (or third...) partial refund stays in the same status, so
    // partiallyRefunded -> partiallyRefunded is legal — only the refunds
    // list on the payment grows, not the state graph.
    PaymentStatus.partiallyRefunded: {
      PaymentStatus.partiallyRefunded,
      PaymentStatus.refunded,
    },
    PaymentStatus.failed: {},
    PaymentStatus.refunded: {},
  };

  bool canTransition(PaymentStatus from, PaymentStatus to) =>
      (_allowed[from] ?? const {}).contains(to);

  /// Applies [to], or throws [IllegalPaymentTransitionException] if the
  /// current status may not become it. Never silently clamps or ignores an
  /// illegal request — a caller that asked for an impossible transition has
  /// a bug, and the loudest possible failure is the one most likely to be
  /// noticed before it reaches production money.
  Payment transition(
    Payment payment,
    PaymentStatus to, {
    required DateTime at,
    String? failureReason,
  }) {
    if (!canTransition(payment.status, to)) {
      throw IllegalPaymentTransitionException(from: payment.status, to: to);
    }
    final withStatus = payment.copyWith(status: to, updatedAt: at);
    // `failed` is the only status this field is ever meaningfully set for;
    // every other transition leaves it as whatever it already was (null, in
    // every normal flow — a payment that never failed never wrote to it).
    if (to == PaymentStatus.failed && failureReason != null) {
      return withStatus.copyWith(failureReason: failureReason);
    }
    return withStatus;
  }
}
