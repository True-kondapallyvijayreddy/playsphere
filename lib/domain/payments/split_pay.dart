/// Splits one entry fee evenly across the teammates paying it together.
///
/// `totalPaise ~/ playerCount` leaves a remainder whenever the fee does not
/// divide evenly (₹500 entry / 3 players = ₹166.66...) — a real case, not an
/// edge case, since entry fees are round rupee amounts and team sizes are
/// rarely factors of 100. The remainder paise are handed out one each to
/// the first `totalPaise % playerCount` players in the input order, so the
/// list always sums to exactly [totalPaise]: no paisa is left uncollected
/// (which would under-fund the event) and none is invented (which would
/// overcharge someone).
///
/// Deliberately NOT the "largest remainder" or any other allocation method
/// that tries to be fair about *which* players pay the extra paisa: every
/// player is buying the identical thing (a place on the same entry), so
/// there is no principled basis to prefer one player's share over
/// another's. First-N-in-input-order is simplest, fully deterministic, and
/// trivial for an organizer to audit against the request they made — call
/// it with players already in the order the UI collected them.
///
/// Returns a list of length [playerCount], one amount per player, index
/// order preserved so the caller can zip it back against their player list.
List<int> splitEntryFeeAmongPlayers({
  required int totalPaise,
  required int playerCount,
}) {
  if (playerCount <= 0) {
    throw ArgumentError.value(playerCount, 'playerCount', 'must be positive');
  }
  if (totalPaise < 0) {
    throw ArgumentError.value(totalPaise, 'totalPaise', 'must not be negative');
  }

  final base = totalPaise ~/ playerCount;
  final remainder = totalPaise % playerCount;

  return List<int>.generate(
    playerCount,
    (i) => base + (i < remainder ? 1 : 0),
    growable: false,
  );
}
