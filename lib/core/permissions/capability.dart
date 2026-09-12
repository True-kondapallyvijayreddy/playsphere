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

  // --- Departmental capabilities -----------------------------------------
  //
  // Each of these is reachable two ways: by holding a senior enough rank, or
  // by being handed the matching [ClubPortfolio]. That is the whole point of
  // portfolios — a club treasurer who is not an admin, a groundsman who is
  // not an organizer.

  /// Set fees, see who has paid, and run the club store and its orders.
  manageFinance,

  /// Home ground, courts, and the season venue plan.
  manageVenues,

  /// Club kit and inventory, and equipment donations.
  manageEquipment,

  /// Appoint umpires to fixtures and hand out the scoring pen.
  manageOfficials,

  /// Physios, injury records and emergency contacts.
  manageMedical,

  /// Announcements, the club gallery and the club's files.
  manageCommunications,
}

/// Pure role → capability lookup. No I/O, trivially testable.
class PermissionMatrix {
  const PermissionMatrix._();

  static const Map<MembershipRole, Set<Capability>> _table = {
    // The owner is the super user. Rather than list the departmental
    // capabilities here and risk this set drifting out of step when a new
    // portfolio is added, the owner is given every capability there is —
    // see `capabilitiesOf`, which special-cases them.
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
    //
    // An admin does NOT get the departmental capabilities by rank. That is
    // deliberate and it is the reason portfolios are worth having: an owner
    // can appoint an admin to run the club without also handing them the
    // bank details, and can appoint a treasurer who is not an admin at all.
    // An admin who should also keep the books gets the finance portfolio,
    // explicitly, in one tap.
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

  /// What each portfolio adds, on top of whatever the rank already gave.
  ///
  /// Every entry here is a *departmental* capability. A portfolio never grants
  /// governance — no portfolio can approve a member, edit a draw or touch the
  /// organization itself, because a brief over one department is not a route
  /// to running the club. The one and only way to gain governance is rank.
  static const Map<ClubPortfolio, Set<Capability>> _portfolioTable = {
    ClubPortfolio.finance: {
      Capability.manageFinance,
      Capability.viewAnalytics,
    },
    ClubPortfolio.grounds: {Capability.manageVenues},
    ClubPortfolio.equipment: {Capability.manageEquipment},
    // Appointing an umpire and being able to score are different jobs, and a
    // fixtures secretary who cannot pick up the pen themselves is useless at
    // 9am when the assigned official has not turned up.
    ClubPortfolio.officials: {
      Capability.manageOfficials,
      Capability.scoreMatches,
    },
    ClubPortfolio.medical: {Capability.manageMedical},
    ClubPortfolio.communications: {Capability.manageCommunications},
  };

  static bool can(MembershipRole role, Capability capability) =>
      capabilitiesOf(role).contains(capability);

  static Set<Capability> capabilitiesOf(MembershipRole role) {
    // The owner holds everything, including every departmental capability and
    // any added after this line was written. Enumerating them in `_table`
    // instead would mean a new portfolio silently locks the owner out of the
    // very thing they are supposed to be delegating.
    if (role == MembershipRole.owner) return Capability.values.toSet();
    return _table[role] ?? const {};
  }

  /// What one portfolio grants on its own.
  static Set<Capability> capabilitiesOfPortfolio(ClubPortfolio portfolio) =>
      _portfolioTable[portfolio] ?? const {};

  /// The real answer for a person: their rank's capabilities plus every
  /// portfolio they hold. This is what the UI must ask — `capabilitiesOf`
  /// alone would grey out the store button for the club's own treasurer.
  static Set<Capability> effectiveCapabilities({
    required MembershipRole role,
    Set<ClubPortfolio> portfolios = const {},
  }) {
    final caps = {...capabilitiesOf(role)};
    for (final p in portfolios) {
      caps.addAll(capabilitiesOfPortfolio(p));
    }
    return caps;
  }

  /// Every portfolio [role] holds without being given it. Owners hold all of
  /// them; nobody else holds any by rank alone.
  static Set<ClubPortfolio> implicitPortfoliosOf(MembershipRole role) =>
      role == MembershipRole.owner
          ? ClubPortfolio.values.toSet()
          : const {};

  /// The portfolios somebody may hand to another member.
  ///
  /// Two conditions, both needed. You must be able to manage members at all —
  /// a portfolio holder is still a member appointment. And you may only pass
  /// on a brief you actually hold yourself, held either by rank or by grant.
  ///
  /// That second rule is the portfolio version of "nobody may grant a role at
  /// or above their own rank": authority spreads only sideways from someone
  /// who already has it, never upwards out of nothing. An owner holds every
  /// portfolio, so an owner can appoint every department. An admin with the
  /// grounds brief can hand grounds to the person who actually opens the
  /// gate, which is the delegation clubs really do — but cannot invent
  /// themselves a finance brief on the way past.
  static Set<ClubPortfolio> portfoliosAssignableBy({
    required MembershipRole actorRole,
    Set<ClubPortfolio> actorPortfolios = const {},
  }) {
    if (!can(actorRole, Capability.manageMembers)) return const {};
    return {...implicitPortfoliosOf(actorRole), ...actorPortfolios};
  }

  /// Roles a person holding [actorRole] is permitted to assign to someone
  /// else. Nobody may grant a role at or above their own rank, which is what
  /// stops an admin quietly promoting themselves to owner.
  static List<MembershipRole> assignableBy(MembershipRole actorRole) {
    if (actorRole == MembershipRole.owner) {
      // Owners may appoint OTHER owners, and this is the line that makes that
      // true. It used to exclude `owner` from the list, which meant the person
      // who created a club held every governance power in it permanently and
      // the only way out was to abandon the club and lose its history.
      //
      // Appointing is unilateral; removing is not. See `OwnerVote` — an owner
      // can bring somebody in on their own authority, but getting one out
      // takes two thirds of the others. That asymmetry is deliberate: sharing
      // power should be easy and taking it back should be hard, which is the
      // opposite of what a symmetric rule would give.
      return MembershipRole.values.toList();
    }
    if (!can(actorRole, Capability.manageMembers)) return const [];
    return MembershipRole.values
        .where((r) => r.rank < actorRole.rank)
        .toList();
  }
}
