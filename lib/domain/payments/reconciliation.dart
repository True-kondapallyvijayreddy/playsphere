import '../../core/models/payment.dart';

/// One payment's expected-vs-settled comparison line.
///
/// "Expected" is derived purely from the [Payment] record itself (captured
/// minus refunded); "settled" comes from whatever ledger actually recorded
/// money moving (a Razorpay settlement report, a bank statement import).
/// The two are computed from independent sources on purpose — reconciling a
/// number against a copy of itself proves nothing.
class ReconciliationLine {
  const ReconciliationLine({
    required this.paymentId,
    required this.expectedPaise,
    required this.settledPaise,
  });

  final String paymentId;
  final int expectedPaise;
  final int settledPaise;

  int get discrepancyPaise => settledPaise - expectedPaise;
  bool get isReconciled => discrepancyPaise == 0;
}

/// The result of comparing what PlaySphere's own records say should have
/// settled against what actually did, across a batch of payments.
///
/// This exists because a webhook can be missed, a Route transfer can fail
/// after capture, or a refund can be issued directly in the Razorpay
/// dashboard without going through this app at all — any of which leaves
/// the payment row's status correct for what PlaySphere knows, but wrong
/// for what actually happened to the money. Reconciliation is the check
/// that catches that class of bug, which idempotent webhook handling alone
/// cannot.
class ReconciliationReport {
  const ReconciliationReport({required this.lines, required this.generatedAt});

  final List<ReconciliationLine> lines;
  final DateTime generatedAt;

  int get totalExpectedPaise => lines.fold(0, (sum, l) => sum + l.expectedPaise);
  int get totalSettledPaise => lines.fold(0, (sum, l) => sum + l.settledPaise);
  int get totalDiscrepancyPaise => totalSettledPaise - totalExpectedPaise;

  List<ReconciliationLine> get mismatches =>
      lines.where((l) => !l.isReconciled).toList(growable: false);

  bool get isFullyReconciled => mismatches.isEmpty;
}

/// Builds a [ReconciliationReport] from data the caller supplies — this
/// function does no I/O of its own (per the domain-layer rule: Firestore
/// reads/writes happen at the edges, not here), so the same logic runs
/// identically whether [payments] came from a live query or a fixture in a
/// test.
///
/// A captured payment's "expected" settlement is `amountPaise -
/// totalRefundedPaise` — what should still be with the platform/organizer
/// after any refunds already recorded. A payment that never captured
/// (created/attempted/failed) expects zero: no money should have moved.
ReconciliationReport reconcile({
  required List<Payment> payments,
  required Map<String, int> settledPaiseByPaymentId,
  required DateTime generatedAt,
}) {
  final lines = payments.map((p) {
    final expected = p.status == PaymentStatus.created ||
            p.status == PaymentStatus.attempted ||
            p.status == PaymentStatus.failed
        ? 0
        : p.amountPaise - p.totalRefundedPaise;
    final settled = settledPaiseByPaymentId[p.id] ?? 0;
    return ReconciliationLine(
      paymentId: p.id,
      expectedPaise: expected,
      settledPaise: settled,
    );
  }).toList(growable: false);

  return ReconciliationReport(lines: lines, generatedAt: generatedAt);
}
