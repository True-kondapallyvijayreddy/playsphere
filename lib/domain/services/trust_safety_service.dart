import '../enums.dart';
import '../phase1_identity.dart';
import '../phase5_rating_achievement.dart';
import '../phase6_trust_safety.dart';

/// Trust & Safety Service enforcing minor safety rules (§6, §9).
class PlaySphereTrustSafetyService {
  const PlaySphereTrustSafetyService();

  /// Resolves profile visibility (§6.2, §9.3).
  ProfileVisibility resolveProfileVisibility({
    required UserEntity user,
    required PlayerProfileEntity profile,
    required List<GuardianLinkEntity> guardianLinks,
  }) {
    if (!user.isMinor) {
      return profile.visibilityDefault;
    }

    final hasVerifiedGuardian = guardianLinks.any(
      (g) =>
          g.minorUserId == user.id &&
          g.verificationStatus == GuardianVerificationStatus.verified,
    );

    if (!hasVerifiedGuardian) {
      return ProfileVisibility.private;
    }

    return profile.visibilityDefault;
  }

  /// Resolves visibility for a specific achievement (§6.2).
  AchievementVisibility resolveAchievementVisibility({
    required UserEntity user,
    required PlayerProfileEntity profile,
    required AchievementEntity achievement,
    required List<GuardianLinkEntity> guardianLinks,
  }) {
    final effectiveProfileVis = resolveProfileVisibility(
      user: user,
      profile: profile,
      guardianLinks: guardianLinks,
    );

    if (effectiveProfileVis == ProfileVisibility.private) {
      return AchievementVisibility.private;
    }

    if (achievement.visibilityOverride != AchievementVisibility.inherit) {
      return achievement.visibilityOverride;
    }

    switch (effectiveProfileVis) {
      case ProfileVisibility.private:
        return AchievementVisibility.private;
      case ProfileVisibility.community:
        return AchievementVisibility.community;
      case ProfileVisibility.statewide:
        return AchievementVisibility.statewide;
    }
  }

  /// Validates whether a scouting invite can be delivered (§6.3, §9.5).
  bool canSendScoutingInvite({
    required OrgVerificationStatus senderOrgStatus,
    required UserEntity targetUser,
    required List<GuardianLinkEntity> targetGuardianLinks,
  }) {
    if (senderOrgStatus != OrgVerificationStatus.verified) {
      return false;
    }

    if (targetUser.isMinor) {
      return targetGuardianLinks.any(
        (g) =>
            g.minorUserId == targetUser.id &&
            g.verificationStatus == GuardianVerificationStatus.verified,
      );
    }

    return true;
  }
}
