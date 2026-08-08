/// How a club removes one of its own owners.
///
/// ## Why a vote and not a button
///
/// A club used to have exactly one owner, and `assignableBy` refused to hand
/// that role to anybody else. One person therefore held every governance
/// power in a school, a village community or an academy permanently, and the
/// only exit was to abandon the club and start another — losing its entire
/// history, which is the one thing this product exists to keep.
///
/// Making owners plural creates the opposite problem. If any owner could
/// remove any other, the first one to tap wins and the club belongs to
/// whoever is quickest. That is a worse monopoly than the original, because
/// it is unstable.
///
/// So removal is collective and the threshold is a supermajority of the
/// OTHER owners: two thirds, rounded up. It is deliberately hard. A club
/// splitting down the middle should not be able to eject either half, and an
/// owner who has genuinely gone — left the school, stopped turning up — will
/// have the rest of the owners agreeing about it without difficulty.
///
/// Nothing here touches the database. It is the arithmetic the Cloud Function
/// applies and the client displays, kept in one place so the progress bar a
/// member sees and the decision the server makes cannot disagree.
class OwnerVote {
  const OwnerVote._();

  /// How many owners must agree, out of the ones eligible to vote.
  ///
  /// [ownerCount] is every owner INCLUDING the person being removed; they are
  /// excluded here rather than by the caller, because forgetting to would make
  /// every threshold one vote too high and a two-owner club impossible to
  /// resolve at all.
  ///
  /// Two thirds of the remainder, rounded up:
  ///
  /// - 2 owners → 1 other → needs 1. The other owner may remove them. Correct:
  ///   the alternative is a deadlocked club with no way out at all, and the
  ///   person being removed can equally remove the remover, so neither can act
  ///   in secret.
  /// - 3 owners → 2 others → needs 2. Unanimous among the rest.
  /// - 4 owners → 3 others → needs 2.
  /// - 7 owners → 6 others → needs 4.
  static int votesNeeded(int ownerCount) {
    final electorate = ownerCount - 1;
    if (electorate <= 0) return 0;
    // Ceiling of 2/3 without floating point: (2n + 2) ~/ 3 is ceil(2n/3).
    return (2 * electorate + 2) ~/ 3;
  }

  /// Whether [votes] distinct owners agreeing is enough to remove someone from
  /// a club with [ownerCount] owners.
  static bool passes({required int votes, required int ownerCount}) {
    final needed = votesNeeded(ownerCount);
    return needed > 0 && votes >= needed;
  }

  /// Whether an owner may step down of their own accord.
  ///
  /// Anyone may give up their own authority — that is not a governance
  /// decision, it is a personal one, and requiring a vote to resign would trap
  /// people in a role they no longer want. The exception is the last owner: a
  /// club with no owner has nobody who can appoint one, so it would be
  /// permanently un-administrable. They have to appoint a co-owner first.
  static bool canResign(int ownerCount) => ownerCount > 1;
}
