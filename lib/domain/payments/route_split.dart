import '../../core/models/payment.dart';

/// Computes a Razorpay Route split for one captured payment.
///
/// The rounding rule is the entire design here: the platform fee is
/// **floored**, and the organizer receives whatever is left over —
/// `organizerSharePaise = totalPaise - platformFeePaise`. That single line
/// is what guarantees `organizerSharePaise + platformFeePaise ==
/// totalPaise` for every possible input, including totals that do not
/// divide evenly by the fee percentage (e.g. ₹499 at a 3.7% fee). Computing
/// both shares independently and rounding each one is the classic way to
/// lose or invent a paisa — two roundings against the same total can each
/// go "the wrong way" and disagree with the total by a paisa, which is a
/// discrepancy an organizer will notice the moment they reconcile a payout
/// against what the app showed them.
///
/// Flooring the fee (rather than the organizer's share) is a deliberate
/// choice of who absorbs the leftover paisa: the platform, not the
/// organizer, eats the rounding — an organizer never receives less than
/// `totalPaise - ceil(fee)` and the platform never collects more than the
/// configured [RouteSplitConfig.platformFeeBps] implies.
RouteSplitResult computeRouteSplit({
  required int totalPaise,
  required int platformFeeBps,
}) {
  if (totalPaise < 0) {
    throw ArgumentError.value(totalPaise, 'totalPaise', 'must not be negative');
  }
  if (platformFeeBps < 0 || platformFeeBps > 10000) {
    throw ArgumentError.value(
      platformFeeBps,
      'platformFeeBps',
      'must be basis points in 0..10000',
    );
  }

  final platformFeePaise = (totalPaise * platformFeeBps) ~/ 10000;
  final organizerSharePaise = totalPaise - platformFeePaise;

  return RouteSplitResult(
    organizerSharePaise: organizerSharePaise,
    platformFeePaise: platformFeePaise,
  );
}

/// Whether an organizer's Route transfer should be released now.
///
/// [RouteSplitConfig.holdUntilEventComplete] exists so an organizer cannot
/// collect fees for an event, then cancel it, and keep money for a service
/// never rendered — the transfer sits until the event is marked complete.
/// Kept as a one-line pure function (rather than folded into a bigger
/// settlement job) so the payout scheduler can call it per-payment without
/// duplicating the hold logic, and so it is trivially testable against both
/// states of the flag.
bool routeSplitShouldRelease({
  required RouteSplitConfig config,
  required bool eventCompleted,
}) =>
    !config.holdUntilEventComplete || eventCompleted;
