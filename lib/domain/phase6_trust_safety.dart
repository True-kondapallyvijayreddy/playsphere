import 'package:equatable/equatable.dart';

import 'enums.dart';

/// PHASE 6 — Trust & Safety: Guardian / Minor Consent
///
/// Minors can participate with a real adult accountable for their
/// visibility, before any statewide discovery layer goes live. See
/// spec §6.

// ---------------------------------------------------------------------------
// 6.1 GuardianLink
// ---------------------------------------------------------------------------

/// Purpose: ties a minor User to a verified adult User. This is a
/// real, verified relationship, not a checkbox.
class GuardianLinkEntity extends Equatable {
  const GuardianLinkEntity({
    required this.id,
    required this.minorUserId,
    required this.guardianUserId,
    required this.relationship,
    required this.verificationStatus,
    required this.verificationMethod,
    this.verifiedAt,
  });

  final String id;
  final String minorUserId;

  /// must itself be an adult account (UserEntity.isMinor == false).
  final String guardianUserId;
  final GuardianRelationship relationship;
  final GuardianVerificationStatus verificationStatus;

  /// pick at least one real method for v1 — org-admin attestation (a
  /// school confirming the relationship) is the cheapest to ship
  /// first.
  final GuardianVerificationMethod verificationMethod;
  final DateTime? verifiedAt;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - guardianUserId must resolve to a User with isMinor == false at
  //    write time.
  //  - A minor's Registration for an event CAN be created by an org
  //    admin even with no GuardianLink yet (so a school can register
  //    kids for a local sports day without friction) — but the
  //    resulting PlayerProfile.visibilityDefault for that minor is
  //    hard-locked to `private` until a GuardianLink reaches
  //    verificationStatus == verified.
  //  - One minor can have multiple verified guardians (both parents);
  //    any verified guardian can set visibility.

  @override
  List<Object?> get props => [
        id,
        minorUserId,
        guardianUserId,
        relationship,
        verificationStatus,
        verificationMethod,
        verifiedAt,
      ];
}

// ---------------------------------------------------------------------------
// 6.2 Visibility settings — reuses PlayerProfile.visibilityDefault
// and Achievement.visibilityOverride from Phase 5. Documented here as
// a resolver contract since it's the guardian-specific rule layered
// on top for minors.
// ---------------------------------------------------------------------------

/// TODO(implementation): none of this is implemented yet.
///  - If User.isMinor == true, only a `verified` guardian (via
///    GuardianLinkEntity) may write to PlayerProfile.visibilityDefault
///    or any Achievement.visibilityOverride for that profile —
///    enforce server-side, not just by hiding the control in UI.
///  - Nothing defaults above `private` for a minor with no verified
///    guardian, full stop, regardless of any org admin action.
abstract class VisibilityResolver {
  /// Resolves the effective visibility a given viewer should see for
  /// a player's profile/achievement, applying the minor-lock rule
  /// above on top of the stored default/override.
  ProfileVisibility resolveEffectiveVisibility({
    required bool subjectIsMinor,
    required bool subjectHasVerifiedGuardian,
    required ProfileVisibility storedDefault,
    AchievementVisibility? achievementOverride,
  });
}

// ---------------------------------------------------------------------------
// 6.3 ScoutingInvite
// ---------------------------------------------------------------------------

/// Purpose: the only channel through which a verified academy/scout
/// account can reach a minor — always routed to the guardian, never
/// the child directly.
class ScoutingInviteEntity extends Equatable {
  const ScoutingInviteEntity({
    required this.id,
    required this.playerProfileId,
    required this.senderOrgId,
    required this.senderUserId,
    required this.message,
    required this.status,
    this.routedToGuardianUserId,
  });

  final String id;

  /// target.
  final String playerProfileId;

  /// must have OrganizationEntity.orgVerificationStatus == verified.
  final String senderOrgId;

  /// must hold a role in senderOrgId.
  final String senderUserId;
  final String message;
  final ScoutingInviteStatus status;

  /// required if target is a minor; null if adult (invite goes
  /// directly to the player).
  final String? routedToGuardianUserId;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - If playerProfileId belongs to a minor with no verified
  //    GuardianLink, block invite creation entirely — there is no
  //    fallback recipient, the invite simply cannot be sent.
  //  - If target is a minor, routedToGuardianUserId is required and
  //    must be a verified guardian for that minor.

  @override
  List<Object?> get props => [
        id,
        playerProfileId,
        senderOrgId,
        senderUserId,
        message,
        status,
        routedToGuardianUserId,
      ];
}

// ---------------------------------------------------------------------------
// 6.4 Turning 18 — job, not object.
// ---------------------------------------------------------------------------
//
// TODO(scheduled-job, not implemented): a daily job checks
// UserEntity.dateOfBirth for anyone crossing 18 since the last run:
// isMinor is already derived (no write needed), and a system
// notification should be inserted prompting the now-adult user to
// review their own visibility settings — but this must NOT force a
// re-consent gate or block existing visibility. GuardianLink rows are
// not deleted; verificationStatus is left as-is, but the guardian's
// write-access to visibility settings is revoked at the
// permission-check level (governed by isMinor, computed live — no
// data migration needed).
