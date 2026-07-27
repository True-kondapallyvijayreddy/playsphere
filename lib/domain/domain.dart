/// Barrel export for the full domain model described in
/// "PlaySphere — Technical Build Specification v1.0".
///
/// Import this single file to get every entity, enum, and interface
/// contract across all 10 phases. See README_DOMAIN_MODEL.md at the
/// project root for what's implemented vs stubbed.
library playsphere_domain;

export 'enums.dart';
export 'shared/audit_log_entity.dart';

export 'phase1_identity.dart';
export 'phase2_season_competition.dart';
export 'phase3_team_formation.dart';
export 'phase4_fixtures_scoring.dart';
export 'phase5_rating_achievement.dart';
export 'phase6_trust_safety.dart';
export 'phase7_promotion.dart';
export 'phase8_discovery.dart';
export 'phase9_venue_officiating.dart';
export 'phase10_governance_monetization.dart';

export 'services/rating_service.dart';
export 'services/team_formation_service.dart';
export 'services/standings_service.dart';
export 'services/scoring_plugins.dart';
export 'services/trust_safety_service.dart';
export 'services/promotion_pipeline_service.dart';
