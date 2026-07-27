import '../../domain/enums.dart';

/// Permission Capability Matrix matching PlaySphere Build Playbook §4.3
enum Capability {
  manageOrganization,
  manageSeasonsAndCompetitions,
  manageTeamsAndAuctions,
  scoreMatches,
  registerSelf,
  viewAnalytics,
}

class PermissionMatrix {
  PermissionMatrix._();

  static bool can(MembershipRole role, Capability capability) {
    switch (role) {
      case MembershipRole.owner:
        return true;
      case MembershipRole.admin:
        return capability != Capability.manageOrganization;
      case MembershipRole.eventManager:
        return capability == Capability.manageSeasonsAndCompetitions ||
            capability == Capability.manageTeamsAndAuctions ||
            capability == Capability.scoreMatches ||
            capability == Capability.registerSelf ||
            capability == Capability.viewAnalytics;
      case MembershipRole.judgeScorer:
        return capability == Capability.scoreMatches || capability == Capability.registerSelf;
      case MembershipRole.member:
        return capability == Capability.registerSelf;
    }
  }
}
