import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import 'owner_vote.dart';

/// Which way out of a club somebody has.
enum ClubExitPath {
  /// Not an owner. Leaving is their own business and takes one tap.
  leave,

  /// An owner, but not the only one. The other owners keep the club, so they
  /// step down and leave in the same act.
  stepDownAndLeave,

  /// The only owner. Somebody else has to be given the club first, or it would
  /// be left with nobody who can appoint an owner ever again.
  handOverAndLeave,

  /// The only owner AND the only member. There is nobody to hand it to.
  nobodyToHandTo,
}

/// How a person leaves a club.
///
/// ## Why an owner cannot simply leave
///
/// Only an owner can appoint an owner. A club whose last owner walks out has
/// nobody who can ever appoint another, so it is stuck for good — its seasons,
/// records and members with it. The rules refuse an owner's own delete for the
/// same reason. So the sole owner's way out is to name a successor, who is
/// made owner in the same batch that steps the leaver down: there is no instant
/// at which the club has no owner.
///
/// Nothing here touches the database. It is the decision the leave flow and
/// `OrgRepository.handOverClub` share, so the dialog cannot offer a path
/// the repository would refuse.
class ClubExit {
  const ClubExit._();

  /// Which path [me] has, given everyone on the roster.
  ///
  /// Only ACTIVE rows count. A pending applicant cannot be handed a club they
  /// have not been let into, and a removed one is not a member at all.
  static ClubExitPath pathFor({
    required Membership me,
    required List<Membership> roster,
  }) {
    if (me.role != MembershipRole.owner) return ClubExitPath.leave;

    final owners = roster
        .where((m) => m.isActive && m.role == MembershipRole.owner)
        .length;
    if (OwnerVote.canResign(owners)) return ClubExitPath.stepDownAndLeave;

    return successorsFor(me: me, roster: roster).isEmpty
        ? ClubExitPath.nobodyToHandTo
        : ClubExitPath.handOverAndLeave;
  }

  /// Who the club may be handed to, most senior first.
  ///
  /// Every active member who is not already an owner — making a co-owner the
  /// owner changes nothing. Seniority leads because the admin who
  /// has been running events alongside the owner is almost always the answer,
  /// and on a four-hundred-student roster they should not have to be searched
  /// for. Names break ties so the list does not reshuffle between opens.
  static List<Membership> successorsFor({
    required Membership me,
    required List<Membership> roster,
  }) =>
      roster
          .where((m) =>
              m.isActive && m.uid != me.uid && m.role != MembershipRole.owner)
          .toList()
        ..sort((a, b) {
          final byRank = b.role.rank.compareTo(a.role.rank);
          if (byRank != 0) return byRank;
          return a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
        });
}
