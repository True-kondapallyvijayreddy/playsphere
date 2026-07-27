import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'shared/audit_log_entity.dart';

/// PHASE 10 — Governance, Compliance & Monetization *(design sketch
/// only — not build-ready per spec)*.
///
/// Minimum shape to reserve schema space so Phase 1–8 objects don't
/// need painful migrations later. Do not build these with real logic
/// yet — reserving the shape now avoids a schema migration fire drill
/// when this phase is prioritized.

// ---------------------------------------------------------------------------
// Governance
// ---------------------------------------------------------------------------

/// Checked at Registration creation time (age-category bands,
/// residency requirements), scoped to an Organization.
class EligibilityRuleEntity extends Equatable {
  const EligibilityRuleEntity({
    required this.id,
    required this.orgId,
    required this.name,
    this.minAge,
    this.maxAge,
    this.residencyRequirement,
  });

  final String id;
  final String orgId;
  final String name;
  final int? minAge;
  final int? maxAge;
  final String? residencyRequirement;

  // TODO(business-rules, not implemented yet): checked at
  // RegistrationEntity creation time; a registration violating an
  // applicable EligibilityRule should be rejected, not silently
  // accepted and flagged later.

  @override
  List<Object?> get props =>
      [id, orgId, name, minAge, maxAge, residencyRequirement];
}

/// Visible only to sanctioning-body admins. Attached to a
/// PlayerProfile for higher tiers only.
class AntiDopingFlagEntity extends Equatable {
  const AntiDopingFlagEntity({
    required this.id,
    required this.playerProfileId,
    required this.reason,
    required this.raisedByOrgId,
  });

  final String id;
  final String playerProfileId;
  final String reason;
  final String raisedByOrgId;

  @override
  List<Object?> get props =>
      [id, playerProfileId, reason, raisedByOrgId];
}

// ---------------------------------------------------------------------------
// Monetization
// ---------------------------------------------------------------------------

/// Season-scoped sponsorship deal.
class SponsorshipDealEntity extends Equatable {
  const SponsorshipDealEntity({
    required this.id,
    required this.seasonId,
    required this.sponsorName,
    required this.amount,
    required this.placementZones,
  });

  final String id;
  final String seasonId;
  final String sponsorName;

  /// paise.
  final Paise amount;
  final List<String> placementZones;

  @override
  List<Object?> get props =>
      [id, seasonId, sponsorName, amount, placementZones];
}

class TicketProductEntity extends Equatable {
  const TicketProductEntity({
    required this.id,
    required this.scopeType,
    required this.scopeId,
    required this.name,
    required this.price,
    required this.quantityAvailable,
  });

  final String id;

  /// fixture- or season-scoped.
  final TicketScopeType scopeType;

  /// FixtureEntity.id or SeasonEntity.id depending on scopeType.
  final String scopeId;
  final String name;

  /// paise.
  final Paise price;
  final int quantityAvailable;

  @override
  List<Object?> get props =>
      [id, scopeType, scopeId, name, price, quantityAvailable];
}

class TicketOrderEntity extends Equatable {
  const TicketOrderEntity({
    required this.id,
    required this.ticketProductId,
    required this.buyerUserId,
    required this.quantity,
    required this.totalAmount,
  });

  final String id;
  final String ticketProductId;
  final String buyerUserId;
  final int quantity;

  /// paise.
  final Paise totalAmount;

  @override
  List<Object?> get props =>
      [id, ticketProductId, buyerUserId, quantity, totalAmount];
}

/// Tiers by member count / feature flags unlocked, attached to an
/// Organization.
class SubscriptionPlanEntity extends Equatable {
  const SubscriptionPlanEntity({
    required this.id,
    required this.orgId,
    required this.tierName,
    required this.maxMembers,
    required this.unlockedFeatureFlagKeys,
  });

  final String id;
  final String orgId;
  final String tierName;
  final int maxMembers;

  /// keys matching FeatureFlags fields, e.g. "franchiseLeagues".
  final List<String> unlockedFeatureFlagKeys;

  @override
  List<Object?> get props =>
      [id, orgId, tierName, maxMembers, unlockedFeatureFlagKeys];
}

// ---------------------------------------------------------------------------
// Media production
// ---------------------------------------------------------------------------

/// References a set of MatchEvents and is generated via an async job
/// once Fixture.status == completed, for sanctioned-tier,
/// higher-visibility competitions only.
class HighlightReelEntity extends Equatable {
  const HighlightReelEntity({
    required this.id,
    required this.fixtureId,
    required this.matchEventIds,
    required this.videoUrl,
    required this.generatedAt,
  });

  final String id;
  final String fixtureId;
  final List<String> matchEventIds;
  final String videoUrl;
  final DateTime generatedAt;

  // TODO(cost-gate, not implemented yet): generation job must only
  // run for sanctioned-tier, higher-visibility competitions — do not
  // run it on every casual community match.

  @override
  List<Object?> get props =>
      [id, fixtureId, matchEventIds, videoUrl, generatedAt];
}
