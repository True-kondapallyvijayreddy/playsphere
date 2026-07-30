/// One tier of a cancellation refund schedule: "cancel at least
/// [minTimeBeforeEvent] before the event starts and get
/// [refundPercentBps]/10000 of what you paid back."
class RefundTier {
  const RefundTier({
    required this.minTimeBeforeEvent,
    required this.refundPercentBps,
  }) : assert(refundPercentBps >= 0 && refundPercentBps <= 10000,
            'refundPercentBps is basis points, 0..10000');

  final Duration minTimeBeforeEvent;
  final int refundPercentBps;
}

/// Per-event cancellation refund policy (CLAUDE.md §10: "refund/cancellation
/// policies per event").
///
/// A flat "full refund up to 24h before" is common for pickup games but
/// wrong for a tournament that has already paid for a venue booking and
/// printed brackets — different events genuinely need different schedules,
/// so this takes its schedule as configuration rather than assuming one.
///
/// [tiers] MUST be supplied sorted from most generous to least (largest
/// [RefundTier.minTimeBeforeEvent] first) — [refundableAmountPaise] returns
/// the first tier whose threshold the cancellation clears, so an
/// out-of-order list would silently apply the wrong percentage.
class RefundPolicy {
  const RefundPolicy(this.tiers);

  /// No refund under any circumstances — the explicit choice an organizer
  /// must opt out of, matching "no cancellation policy configured" with "no
  /// money back" rather than silently defaulting to full refunds.
  const RefundPolicy.noRefunds() : tiers = const [];

  final List<RefundTier> tiers;

  int refundableAmountPaise({
    required int paidPaise,
    required DateTime eventStartsAt,
    required DateTime cancelledAt,
  }) {
    if (paidPaise < 0) {
      throw ArgumentError.value(paidPaise, 'paidPaise', 'must not be negative');
    }
    final timeBeforeEvent = eventStartsAt.difference(cancelledAt);
    for (final tier in tiers) {
      if (timeBeforeEvent >= tier.minTimeBeforeEvent) {
        // Integer round-half-up of paidPaise * refundPercentBps / 10000,
        // kept in whole paise the same way every other money figure in
        // this domain layer is — see gst_invoice.dart's `_roundHalfUp` for
        // the identical technique and the reasoning against using `double`.
        return (2 * paidPaise * tier.refundPercentBps + 10000) ~/ 20000;
      }
    }
    return 0;
  }
}
