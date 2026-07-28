import '../models/enums.dart';

/// Every distinct thing a person can be allowed to do inside an organization.
///
/// This table is the *client-side mirror* of the role checks in
/// `firestore.rules`. It exists to grey out buttons and to fail fast with a
/// helpful message — it prevents nothing on its own. A modified client can
/// call any capability it likes; the write still dies at the database.
///
/// When you change a rule here, change `firestore.rules` in the same commit.
/// The security tests in `test/security/` assert the two agree.
enum Capability {
  /// Rename, re-tier, soft-delete or transfer the organization.
  manageOrganization,

  /// Approve joiners, change roles, remove members.
  manageMembers,

  /// Create and edit competitions, categories, draws and schedules.
  manageCompetitions,

  /// Approve, reject or waitlist entries.
  manageRegistrations,

  /// Enter live scores for a fixture they are assigned to.
  scoreMatches,

  /// Enter this organization's competitions as a player.
  registerSelf,

  /// See aggregate dashboards for the organization.
  viewAnalytics,

  /// Read the audit trail of who changed which result.
  viewAuditLog,
}

/// Pure role → capability lookup. No I/O, trivially testable.
class PermissionMatrix {
  const PermissionMatrix._();

  static const Map<MembershipRole, Set<Capability>> _table = {
    MembershipRole.owner: {
      Capability.manageOrganization,
      Capability.manageMembers,
      Capability.manageCompetitions,
      Capability.manageRegistrations,
      Capability.scoreMatches,
      Capability.registerSelf,
      Capability.viewAnalytics,
      Capability.viewAuditLog,
    },
    // An admin runs the organization day to day but cannot delete it or hand
    // it to someone else — those stay with the owner so an admin account
    // being compromised cannot cost a school its entire history.
    MembershipRole.admin: {
      Capability.manageMembers,
      Capability.manageCompetitions,
      Capability.manageRegistrations,
      Capability.scoreMatches,
      Capability.registerSelf,
      Capability.viewAnalytics,
      Capability.viewAuditLog,
    },
    // Runs competitions, but has no authority over people. A sports teacher
    // organizing the inter-house tournament should not be able to change who
    // is an admin of the school.
    MembershipRole.eventManager: {
      Capability.manageCompetitions,
      Capability.manageRegistrations,
      Capability.scoreMatches,
      Capability.registerSelf,
      Capability.viewAnalytics,
    },
    // Deliberately single-purpose. A volunteer scorer sees the matches they
    // were assigned and nothing else at all.
    MembershipRole.judgeScorer: {
      Capability.scoreMatches,
      Capability.registerSelf,
    },
    MembershipRole.member: {
      Capability.registerSelf,
    },
  };

  static bool can(MembershipRole role, Capability capability) =>
      _table[role]?.contains(capability) ?? false;

  static Set<Capability> capabilitiesOf(MembershipRole role) =>
      _table[role] ?? const {};

  /// Roles a person holding [actorRole] is permitted to assign to someone
  /// else. Nobody may grant a role at or above their own rank, which is what
  /// stops an admin quietly promoting themselves to owner.
  static List<MembershipRole> assignableBy(MembershipRole actorRole) {
    if (actorRole == MembershipRole.owner) {
      return MembershipRole.values
          .where((r) => r != MembershipRole.owner)
          .toList();
    }
    if (!can(actorRole, Capability.manageMembers)) return const [];
    return MembershipRole.values
        .where((r) => r.rank < actorRole.rank)
        .toList();
  }
}
