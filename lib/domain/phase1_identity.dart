import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'shared/audit_log_entity.dart';

/// PHASE 1 — Identity & Organization Foundation
///
/// A person can sign up, create an organization, invite others into it
/// with a role, and that role — not the person globally — determines
/// what they can do. See spec §1.

// ---------------------------------------------------------------------------
// 1.1 User
// ---------------------------------------------------------------------------

/// Purpose: one row per real human who has ever signed in. Global, not
/// org-scoped.
class UserEntity extends Equatable with TimestampedSoftDeletable {
  const UserEntity({
    required this.id,
    required this.fullName,
    required this.email,
    required this.dateOfBirth,
    required this.authProvider,
    required this.accountStatus,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.passwordHash,
    this.avatarUrl,
    this.deletedAt,
  });

  final String id;
  final String fullName;

  /// Unique across the whole platform, lowercased. See business rule:
  /// "Email or phone must be unique across the whole platform — one
  /// User row per real person, ever."
  final String email;

  /// Unique if present. Used for OTP login.
  final String? phone;

  final DateTime dateOfBirth;

  /// authProvider == password requires passwordHash to be non-null;
  /// any other provider requires it to be null.
  final AuthProvider authProvider;
  final String? passwordHash;

  final String? avatarUrl;
  final AccountStatus accountStatus;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  /// Computed from dateOfBirth at read time — never stored stale.
  /// TODO(read-model): compute as `age(dateOfBirth) < 18` at query
  /// time in every layer that reads this (API response, UI). Never
  /// persist this value, and never let a cached copy go stale across
  /// a birthday.
  bool get isMinor {
    final now = DateTime.now();
    var age = now.year - dateOfBirth.year;
    final hasHadBirthdayThisYear = now.month > dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day >= dateOfBirth.day);
    if (!hasHadBirthdayThisYear) age -= 1;
    return age < 18;
  }

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Reject create/update if email or phone collides with another
  //    User (case-insensitive on email).
  //  - A User under 18 cannot self-register without a guardian flow
  //    (Phase 6 GuardianLinkEntity) being triggered before the account
  //    becomes usable beyond read-only viewing.
  //  - passwordHash must be null unless authProvider == password, and
  //    non-null when it is.

  @override
  List<Object?> get props => [
        id,
        fullName,
        email,
        phone,
        dateOfBirth,
        authProvider,
        passwordHash,
        avatarUrl,
        accountStatus,
        createdAt,
        updatedAt,
        deletedAt,
      ];
}

// ---------------------------------------------------------------------------
// 1.2 Organization
// ---------------------------------------------------------------------------

/// Purpose: the tenant-like unit — a residential community, school,
/// city club, district association, state council, corporate.
/// Organizations nest via [parentOrgId].
class OrganizationEntity extends Equatable with TimestampedSoftDeletable {
  const OrganizationEntity({
    required this.id,
    required this.name,
    required this.slug,
    required this.orgType,
    required this.visibility,
    required this.creatorUserId,
    required this.featureFlags,
    required this.createdAt,
    required this.updatedAt,
    this.parentOrgId,
    this.logoUrl,
    this.description,
    this.orgVerificationStatus = OrgVerificationStatus.unverified,
    this.deletedAt,
  });

  final String id;
  final String name;

  /// Unique, used in the org's URL.
  final String slug;
  final OrgType orgType;

  /// null == top-level org. Forms a tree, not a graph — one parent
  /// max.
  final String? parentOrgId;

  final String? logoUrl;
  final String? description;

  /// default `public`; unlisted orgs don't appear in search.
  final OrgVisibility visibility;

  /// Becomes first admin automatically (see OrganizationMembershipEntity
  /// creation rule).
  final String creatorUserId;

  /// jsonb map gating which modules render in the admin portal. See
  /// [FeatureFlags] for the typed shape and §1.5 for org_type
  /// defaults.
  final FeatureFlags featureFlags;

  /// Added in Phase 6 (§6.3 ScoutingInvite): required so a
  /// ScoutingInvite's sender_org_id can be checked against
  /// `verified` status. Not sport/season related — purely a
  /// trust-and-safety gate on which orgs may contact players.
  final OrgVerificationStatus orgVerificationStatus;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - parentOrgId must never introduce a cycle; validate the full
  //    ancestor chain on every write that sets/changes it.
  //  - An org's own seasons are independent by default; opting into a
  //    parent's season is an explicit SeasonLink (Phase 7), never
  //    implied by the hierarchy alone.
  //  - Deleting an org is soft-delete only, and must be blocked while
  //    it has any active season (SeasonStatus not in
  //    {completed, cancelled}).
  //  - On create: automatically create an OrganizationMembershipEntity
  //    for creatorUserId with role = owner, status = active.

  @override
  List<Object?> get props => [
        id,
        name,
        slug,
        orgType,
        parentOrgId,
        logoUrl,
        description,
        visibility,
        creatorUserId,
        featureFlags,
        orgVerificationStatus,
        createdAt,
        updatedAt,
        deletedAt,
      ];
}

/// Typed view of Organization.feature_flags (§1.5). Modeled as a
/// concrete class rather than a raw map so callers get compile-time
/// safety, while still round-tripping to the jsonb shape the spec
/// describes.
///
/// TODO(defaults): seed sensible per-OrgType defaults on org creation
/// — a residentialCommunity defaults everything false, a stateCouncil
/// defaults most to true — then let any org upgrade/downgrade
/// manually. Not implemented here; this class is the data shape only.
class FeatureFlags extends Equatable {
  const FeatureFlags({
    this.franchiseLeagues = false,
    this.venueMarketplace = false,
    this.officiatingRegistry = false,
    this.ticketing = false,
    this.sponsorship = false,
    this.mediaProduction = false,
  });

  final bool franchiseLeagues;
  final bool venueMarketplace;
  final bool officiatingRegistry;
  final bool ticketing;
  final bool sponsorship;
  final bool mediaProduction;

  @override
  List<Object?> get props => [
        franchiseLeagues,
        venueMarketplace,
        officiatingRegistry,
        ticketing,
        sponsorship,
        mediaProduction,
      ];
}

// ---------------------------------------------------------------------------
// 1.3 OrganizationMembership
// ---------------------------------------------------------------------------

/// Purpose: THE central authorization object. Role lives here, not on
/// User. This single design decision is why one person can be an
/// admin in one community and a plain participant in another.
class OrganizationMembershipEntity extends Equatable {
  const OrganizationMembershipEntity({
    required this.id,
    required this.orgId,
    required this.userId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.contactDetailsOverride,
    this.medicalNotes,
    this.invitedByUserId,
    this.membershipTag,
  });

  final String id;
  final String orgId;
  final String userId;
  final MembershipRole role;
  final MembershipStatus status;
  final DateTime joinedAt;

  /// org-specific contact info, distinct from the global User profile.
  final Map<String, dynamic>? contactDetailsOverride;

  /// Encrypted at rest; visible only to admin/owner roles of that org
  /// (member sees own only — enforce at the query layer, see
  /// RoleMatrix below).
  final String? medicalNotes;

  final String? invitedByUserId;

  /// Added by §3.3 house_wise/department_wise TeamFormationStrategy:
  /// "requires that tag to exist on OrganizationMembership... add a
  /// membership_tag: string field to OrganizationMembership if this
  /// strategy is used."
  final String? membershipTag;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Unique constraint on (orgId, userId): one membership row per
  //    person per org; role changes mutate this row, never create a
  //    new one.
  //  - An org must always have at least one `owner`; block
  //    removal/demotion of the last owner.
  //  - status == removed retains the row (for historical results
  //    attribution) but blocks all writes from that user in that org.
  //  - medicalNotes must be encrypted at rest and filtered out of any
  //    read response unless the requesting membership's role is
  //    owner/admin, or the requester is viewing their own row.
  //  - Every write to `role` must append an AuditLogEntry (role
  //    changes are exactly the kind of thing disputes hinge on).

  @override
  List<Object?> get props => [
        id,
        orgId,
        userId,
        role,
        status,
        joinedAt,
        contactDetailsOverride,
        medicalNotes,
        invitedByUserId,
        membershipTag,
      ];
}

/// Server-side capability table (§1.3 role matrix). This is a plain
/// data lookup — the actual enforcement ("never trust client role
/// claims") happens by checking this on every write in the
/// service/repository layer, not here.
///
/// TODO(enforcement): wire a permission-check function
/// `bool can(MembershipRole role, Capability cap)` into every command
/// handler / repository write path. Not implemented yet — this table
/// is the source of truth it should read from.
enum Capability {
  deleteOrgOrTransferOwnership,
  createEditSeasons,
  manageMembershipsRoles,
  triggerTeamFormation,
  enterLiveScores,
  registerSelfForEvents,
  viewMedicalNotes,
}

const Map<MembershipRole, Set<Capability>> kRoleCapabilityMatrix = {
  MembershipRole.owner: {
    Capability.deleteOrgOrTransferOwnership,
    Capability.createEditSeasons,
    Capability.manageMembershipsRoles,
    Capability.triggerTeamFormation,
    Capability.enterLiveScores,
    Capability.registerSelfForEvents,
    Capability.viewMedicalNotes,
  },
  MembershipRole.admin: {
    Capability.createEditSeasons,
    Capability.manageMembershipsRoles,
    Capability.triggerTeamFormation,
    Capability.enterLiveScores,
    Capability.registerSelfForEvents,
    Capability.viewMedicalNotes,
  },
  MembershipRole.eventManager: {
    Capability.createEditSeasons,
    Capability.triggerTeamFormation,
    Capability.enterLiveScores,
    Capability.registerSelfForEvents,
  },
  MembershipRole.judgeScorer: {
    Capability.enterLiveScores,
    Capability.registerSelfForEvents,
  },
  MembershipRole.member: {
    Capability.registerSelfForEvents,
    // Note: member "views medical notes (own only)" — this is a
    // row-level exception, not a blanket capability. Enforce
    // separately: a member may always read their own
    // OrganizationMembership.medicalNotes.
  },
};

// ---------------------------------------------------------------------------
// 1.4 PlayerProfile
// ---------------------------------------------------------------------------

/// Purpose: the global, cross-organization identity. One per real
/// person. This is what makes results portable. Every downstream
/// object (RatingRecord, Achievement, Entrant, etc.) references
/// [id] here, never [UserEntity.id] directly.
class PlayerProfileEntity extends Equatable {
  const PlayerProfileEntity({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.visibilityDefault,
    this.primarySportIds = const [],
    this.careerPageSlug,
  });

  final String id;

  /// 1:1 with User, modeled separately so the profile can outlive
  /// auth changes.
  final String userId;

  final String displayName;

  /// Self-declared, cosmetic only — ratings are the real signal.
  final List<String> primarySportIds;

  /// default `community`; overridden per-achievement for minors
  /// (Phase 6) — see AchievementEntity.visibilityOverride and
  /// GuardianLinkEntity business rules.
  final ProfileVisibility visibilityDefault;

  /// Populated once the Phase 8 career page is generated.
  final String? careerPageSlug;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Create automatically the moment a User is created — never
  //    lazily on first sport activity.
  //  - For a minor (UserEntity.isMinor == true) with no *verified*
  //    GuardianLink, visibilityDefault is hard-locked to `private`
  //    regardless of any stored value — resolve this at the query
  //    layer, same as Achievement.visibilityOverride (see Phase 6).

  @override
  List<Object?> get props => [
        id,
        userId,
        displayName,
        primarySportIds,
        visibilityDefault,
        careerPageSlug,
      ];
}
