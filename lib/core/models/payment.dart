/// Every money amount in this file is an integer count of paise (1/100 of a
/// rupee) — never a `double`. Razorpay's API itself works in the smallest
/// currency unit for exactly this reason: `double` cannot represent ₹19.99
/// exactly in binary floating point, and a chain of additions/subtractions
/// across a split, a refund and a reconciliation report will eventually
/// drift by a paisa in a way that makes the books not balance. An `int`
/// count of paise has no such failure mode. `amountPaise` on [Payment] is
/// the one number a payer actually authorized; everything downstream
/// (splits, GST, refunds) must always be derivable back to it exactly.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// Lifecycle of one payment, mirroring the Razorpay order/payment/refund
/// flow (CLAUDE.md §10).
///
/// The wire string is what gets persisted and is what `firestore.rules`
/// would key security decisions on, so it is fixed independently of the
/// Dart constant name — renaming the enum in code must never orphan a
/// stored document.
enum PaymentStatus {
  /// A Razorpay order has been created but the payer has not attempted to
  /// pay yet. This is the only status a payment may start in.
  created('created'),

  /// The payer has been handed off to Razorpay's checkout (UPI/card/etc).
  /// Nothing is guaranteed yet — the attempt can still fail.
  attempted('attempted'),

  /// Razorpay has captured the funds. This is the only status from which
  /// money can be owed back to anyone (a refund).
  captured('captured'),

  /// The attempt did not result in captured funds — declined, timed out,
  /// cancelled by the payer. Terminal: a fresh attempt is a NEW payment
  /// record (a new Razorpay order), not a resurrection of this one, so that
  /// every payment row's history stays a straight line.
  failed('failed'),

  /// Some but not all of [Payment.amountPaise] has been refunded.
  partiallyRefunded('partially_refunded'),

  /// The entire captured amount has been refunded. Terminal.
  refunded('refunded');

  const PaymentStatus(this.wire);
  final String wire;

  static PaymentStatus fromWire(String? w) => PaymentStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => PaymentStatus.created,
      );

  bool get isTerminal =>
      this == PaymentStatus.failed || this == PaymentStatus.refunded;
}

/// Razorpay's own identifiers for one payment attempt.
///
/// [orderId] exists from the moment checkout starts; [paymentId] and
/// [signature] only exist once Razorpay reports a result, which is why they
/// are nullable rather than empty strings — an empty string would be
/// indistinguishable from "Razorpay sent one back but it happened to be
/// blank", which should never happen and would hide a real bug.
class RazorpayRefs {
  const RazorpayRefs({this.orderId, this.paymentId, this.signature});

  final String? orderId;
  final String? paymentId;

  /// HMAC signature Razorpay returns with a successful checkout, verified
  /// server-side against the order+payment ids before anything is trusted.
  /// Never re-derive trust from this field on the client — it is stored for
  /// audit, the verification itself must happen on the backend that holds
  /// the webhook secret.
  final String? signature;

  RazorpayRefs copyWith({String? orderId, String? paymentId, String? signature}) =>
      RazorpayRefs(
        orderId: orderId ?? this.orderId,
        paymentId: paymentId ?? this.paymentId,
        signature: signature ?? this.signature,
      );

  Map<String, Object?> toMap() => {
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      };

  factory RazorpayRefs.fromMap(Map<String, dynamic> d) => RazorpayRefs(
        orderId: Fs.strOrNull(d['orderId']),
        paymentId: Fs.strOrNull(d['paymentId']),
        signature: Fs.strOrNull(d['signature']),
      );

  static const empty = RazorpayRefs();
}

/// Configuration for a Razorpay Route split, captured at the time an event's
/// paid registration is set up.
///
/// This is the ORGANIZER'S INTENT (what fraction goes to the platform); the
/// actual paise amounts are computed per-payment by
/// `domain/payments/route_split.dart` because the split must be calculated
/// from each payment's own [Payment.amountPaise], never stored as a
/// precomputed number that could drift from the amount actually captured.
class RouteSplitConfig {
  const RouteSplitConfig({
    required this.organizerAccountId,
    required this.platformFeeBps,
    this.holdUntilEventComplete = false,
  })  : assert(platformFeeBps >= 0 && platformFeeBps <= 10000,
            'platformFeeBps is basis points of the total, 0–10000'),
        assert(organizerAccountId != '', 'organizerAccountId is required');

  /// The organizer's Razorpay Route linked account id. A string reference
  /// only — this file never talks to Razorpay, live or otherwise.
  final String organizerAccountId;

  /// Platform's cut, in basis points of the total (500 = 5%). Basis points
  /// rather than a percent-as-double for the same reason amounts are paise:
  /// an integer has no rounding surprises when it is later used in integer
  /// arithmetic to compute a fee.
  final int platformFeeBps;

  /// When true, the organizer's share is settled only after the event is
  /// marked complete rather than immediately on capture — protects a payer
  /// base from an organizer who takes fees and cancels, at the cost of the
  /// organizer's cash flow. Configured per event, not globally.
  final bool holdUntilEventComplete;

  Map<String, Object?> toMap() => {
        'organizerAccountId': organizerAccountId,
        'platformFeeBps': platformFeeBps,
        'holdUntilEventComplete': holdUntilEventComplete,
      };

  factory RouteSplitConfig.fromMap(Map<String, dynamic> d) => RouteSplitConfig(
        organizerAccountId: Fs.str(d['organizerAccountId']),
        platformFeeBps: Fs.integer(d['platformFeeBps']),
        holdUntilEventComplete: Fs.boolean(d['holdUntilEventComplete']),
      );
}

/// The actual paise split for one captured payment, computed once (by
/// `computeRouteSplit` in the domain layer) and then stored — recomputing it
/// later from a possibly-changed [RouteSplitConfig] must never change what
/// was already promised to an organizer for money already collected.
class RouteSplitResult {
  const RouteSplitResult({
    required this.organizerSharePaise,
    required this.platformFeePaise,
  });

  final int organizerSharePaise;
  final int platformFeePaise;

  int get totalPaise => organizerSharePaise + platformFeePaise;

  Map<String, Object?> toMap() => {
        'organizerSharePaise': organizerSharePaise,
        'platformFeePaise': platformFeePaise,
      };

  factory RouteSplitResult.fromMap(Map<String, dynamic> d) => RouteSplitResult(
        organizerSharePaise: Fs.integer(d['organizerSharePaise']),
        platformFeePaise: Fs.integer(d['platformFeePaise']),
      );
}

/// One refund against a [Payment]. A payment can carry many of these
/// (partial refunds), which is why they live in a list on the payment
/// rather than as a single nullable field.
class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.amountPaise,
    required this.createdAt,
    this.razorpayRefundId,
    this.reason,
  }) : assert(amountPaise > 0, 'a refund of zero or negative paise is not a refund');

  /// Local identifier — for a refund created from a webhook this is the
  /// webhook's own event id, which doubles as the idempotency key (see
  /// `domain/payments/payment_webhook_processor.dart`).
  final String id;

  final String? razorpayRefundId;
  final int amountPaise;
  final String? reason;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'razorpayRefundId': razorpayRefundId,
        'amountPaise': amountPaise,
        'reason': reason,
        'createdAt': Fs.ts(createdAt),
      };

  factory RefundRecord.fromMap(Map<String, dynamic> d) => RefundRecord(
        id: Fs.str(d['id']),
        razorpayRefundId: Fs.strOrNull(d['razorpayRefundId']),
        amountPaise: Fs.integer(d['amountPaise']),
        reason: Fs.strOrNull(d['reason']),
        createdAt: Fs.date(d['createdAt'], DateTime.fromMillisecondsSinceEpoch(0)),
      );
}

/// One entry-fee payment. Stored at (in the eventual Firestore/Postgres
/// schema per CLAUDE.md §5) `payments/{id}`.
///
/// This model carries data only. Every rule about what may happen to a
/// payment — legal status transitions, how a webhook mutates it, how much
/// of it may be refunded — lives in `lib/domain/payments/`, deliberately
/// kept out of this file so that "what is a payment" and "what may a
/// payment do" can be tested independently.
class Payment {
  const Payment({
    required this.id,
    required this.eventId,
    required this.payerUserId,
    required this.amountPaise,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.razorpay = RazorpayRefs.empty,
    this.splitConfig,
    this.splitResult,
    this.refunds = const [],
    this.processedWebhookEventIds = const {},
    this.failureReason,
    this.splitPayGroupId,
  }) : assert(amountPaise >= 0, 'amountPaise must not be negative');

  final String id;
  final String eventId;
  final String payerUserId;

  /// The amount this payer was charged, in paise. For a teammate split-pay
  /// entry this is the PLAYER'S share (see
  /// `domain/payments/split_pay.dart`), not the whole team's entry fee —
  /// each teammate has their own [Payment] row, linked by
  /// [splitPayGroupId].
  final int amountPaise;

  final PaymentStatus status;
  final RazorpayRefs razorpay;

  final RouteSplitConfig? splitConfig;
  final RouteSplitResult? splitResult;

  final List<RefundRecord> refunds;

  /// Razorpay webhook event ids already folded into this payment.
  /// `payment_webhook_processor.dart` checks this set before applying an
  /// incoming webhook — that is the entire idempotency mechanism: Razorpay
  /// is documented to redeliver webhooks (retry-on-no-2xx, and sometimes
  /// duplicates even on success), and a webhook applied twice must not
  /// capture or refund money twice.
  final Set<String> processedWebhookEventIds;

  final String? failureReason;

  /// Groups teammate split-pay rows that together cover one entry fee. Null
  /// for a normal single-payer registration.
  final String? splitPayGroupId;

  final DateTime createdAt;
  final DateTime updatedAt;

  int get totalRefundedPaise =>
      refunds.fold(0, (total, r) => total + r.amountPaise);

  /// How much of [amountPaise] could still be refunded. Only meaningful once
  /// funds have actually been captured; a payment that was never captured
  /// has nothing to refund regardless of this arithmetic, which is why
  /// callers must also check [status] before offering a refund.
  int get remainingRefundablePaise => amountPaise - totalRefundedPaise;

  bool get isFullyRefunded => amountPaise > 0 && totalRefundedPaise >= amountPaise;

  Payment copyWith({
    PaymentStatus? status,
    RazorpayRefs? razorpay,
    RouteSplitConfig? splitConfig,
    RouteSplitResult? splitResult,
    List<RefundRecord>? refunds,
    Set<String>? processedWebhookEventIds,
    String? failureReason,
    DateTime? updatedAt,
  }) =>
      Payment(
        id: id,
        eventId: eventId,
        payerUserId: payerUserId,
        amountPaise: amountPaise,
        status: status ?? this.status,
        razorpay: razorpay ?? this.razorpay,
        splitConfig: splitConfig ?? this.splitConfig,
        splitResult: splitResult ?? this.splitResult,
        refunds: refunds ?? this.refunds,
        processedWebhookEventIds:
            processedWebhookEventIds ?? this.processedWebhookEventIds,
        failureReason: failureReason ?? this.failureReason,
        splitPayGroupId: splitPayGroupId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => Fs.prune({
        'eventId': eventId,
        'payerUserId': payerUserId,
        'amountPaise': amountPaise,
        'status': status.wire,
        'razorpay': razorpay.toMap(),
        'splitConfig': splitConfig?.toMap(),
        'splitResult': splitResult?.toMap(),
        'refunds': refunds.map((r) => r.toMap()).toList(),
        'processedWebhookEventIds': processedWebhookEventIds.toList(),
        'failureReason': failureReason,
        'splitPayGroupId': splitPayGroupId,
        'createdAt': Fs.ts(createdAt),
        'updatedAt': Fs.ts(updatedAt),
      });

  factory Payment.fromMap(String id, Map<String, dynamic> d) => Payment(
        id: id,
        eventId: Fs.str(d['eventId']),
        payerUserId: Fs.str(d['payerUserId']),
        amountPaise: Fs.integer(d['amountPaise']),
        status: PaymentStatus.fromWire(d['status'] as String?),
        razorpay: d['razorpay'] == null
            ? RazorpayRefs.empty
            : RazorpayRefs.fromMap(Fs.map(d['razorpay'])),
        splitConfig: d['splitConfig'] == null
            ? null
            : RouteSplitConfig.fromMap(Fs.map(d['splitConfig'])),
        splitResult: d['splitResult'] == null
            ? null
            : RouteSplitResult.fromMap(Fs.map(d['splitResult'])),
        refunds: (d['refunds'] as List? ?? const [])
            .map((r) => RefundRecord.fromMap(Fs.map(r)))
            .toList(),
        processedWebhookEventIds:
            Fs.strList(d['processedWebhookEventIds']).toSet(),
        failureReason: Fs.strOrNull(d['failureReason']),
        splitPayGroupId: Fs.strOrNull(d['splitPayGroupId']),
        createdAt: Fs.date(d['createdAt'], DateTime.fromMillisecondsSinceEpoch(0)),
        updatedAt: Fs.date(d['updatedAt'], DateTime.fromMillisecondsSinceEpoch(0)),
      );

  factory Payment.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) =>
      Payment.fromMap(snap.id, snap.data() ?? const {});
}
