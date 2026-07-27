import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'shared/audit_log_entity.dart';

/// PHASE 3 — Team Formation
///
/// Turn a pool of registrations into teams, via a pluggable strategy,
/// and produce Entrant rows for team competitions. See spec §3.

// ---------------------------------------------------------------------------
// 3.1 Team
// ---------------------------------------------------------------------------

/// Purpose: two flavors under one table — ad-hoc (dissolves after the
/// event) and franchise (persists across seasons).
class TeamEntity extends Equatable {
  const TeamEntity({
    required this.id,
    required this.orgId,
    required this.teamKind,
    required this.name,
    required this.isActive,
    this.logoUrl,
    this.leagueId,
    this.ownerUserId,
  }) : assert(
          teamKind != TeamKind.franchise ||
              (leagueId != null && ownerUserId != null),
          'franchise teams require leagueId and ownerUserId',
        );

  final String id;
  final String orgId;
  final TeamKind teamKind;
  final String name;
  final String? logoUrl;

  /// required if teamKind == franchise — franchises belong to a
  /// league identity, not a single season.
  final String? leagueId;

  /// required if teamKind == franchise.
  final String? ownerUserId;

  /// franchises can go dormant between seasons without being deleted.
  final bool isActive;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - adHoc teams are created fresh per SportCompetition and are
  //    never reused across seasons, even if the roster happens to
  //    repeat — this keeps history honest.
  //  - franchise teams persist; their roster changes year to year via
  //    FranchiseRosterEntryEntity, never by editing history.

  @override
  List<Object?> get props =>
      [id, orgId, teamKind, name, logoUrl, leagueId, ownerUserId, isActive];
}

// ---------------------------------------------------------------------------
// 3.2 TeamMembership
// ---------------------------------------------------------------------------

/// Purpose: who's on a given team for a given competition (ad-hoc
/// case) — separate from the franchise's year-spanning roster.
class TeamMembershipEntity extends Equatable {
  const TeamMembershipEntity({
    required this.id,
    required this.teamId,
    required this.sportCompetitionId,
    required this.playerProfileId,
    this.isCaptain = false,
  });

  final String id;
  final String teamId;

  /// Scopes membership to one competition run, even for franchises.
  final String sportCompetitionId;
  final String playerProfileId;
  final bool isCaptain;

  @override
  List<Object?> get props =>
      [id, teamId, sportCompetitionId, playerProfileId, isCaptain];
}

// ---------------------------------------------------------------------------
// 3.3 TeamFormationStrategy
// ---------------------------------------------------------------------------

/// Purpose: config object on a SportCompetition describing how
/// registrants become teams. This is the "interchangeable strategy
/// engine" — implement as a strategy interface (see
/// [TeamFormationStrategy] below), not an if/else ladder.
class TeamFormationStrategyEntity extends Equatable {
  const TeamFormationStrategyEntity({
    required this.id,
    required this.sportCompetitionId,
    required this.strategyType,
    this.teamCount,
    this.params,
  });

  final String id;

  /// one-to-one with SportCompetition.
  final String sportCompetitionId;
  final TeamFormationStrategyType strategyType;

  /// required for random/aiBalanced.
  final int? teamCount;

  /// strategy-specific, e.g. {"balance_metric": "per_sport_rating"}
  /// for aiBalanced.
  final Map<String, dynamic>? params;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - houseWise/departmentWise requires
  //    OrganizationMembershipEntity.membershipTag to be populated for
  //    every registrant being grouped.
  //  - Running formTeams must be idempotent given the same inputs and
  //    a fixed random seed — store the seed used (see [randomSeed] on
  //    the strategy run, not modeled as a persisted field here since
  //    the spec treats it as an execution-time value; a
  //    TeamFormationRun log entity would carry it).

  @override
  List<Object?> get props =>
      [id, sportCompetitionId, strategyType, teamCount, params];
}

/// Strategy interface contract from spec §3.3:
/// ```
/// interface TeamFormationStrategy {
///   formTeams(registrations, competition, params): Team[]
/// }
/// ```
/// TODO(implementation): implement one concrete class per
/// [TeamFormationStrategyType]:
///  - random — shuffle registrants into teamCount equal-size groups.
///  - manual — admin drags-and-drops in UI; system just persists the
///    admin's grouping.
///  - aiBalanced — reads each registrant's current per-sport
///    RatingRecord (Phase 5; falls back to
///    RegistrationEntity.selfDeclaredSkill if unrated) and minimizes
///    variance in total team rating across teamCount groups.
///    Implement as a greedy snake-draft (highest-rated player
///    alternates team assignment) as v1 — do not over-engineer with a
///    solver initially.
///  - auction — used for franchises; see AuctionLotEntity.
///  - draft — franchises take turns picking from a shared pool, order
///    configurable (worst-record-first, random, etc).
///  - houseWise / departmentWise — groups by
///    OrganizationMembershipEntity.membershipTag.
abstract class TeamFormationStrategy {
  List<TeamEntity> formTeams({
    required List<dynamic> registrations, // List<RegistrationEntity>
    required dynamic competition, // SportCompetitionEntity
    required Map<String, dynamic> params,
  });
}

// ---------------------------------------------------------------------------
// 3.4 FranchiseRosterEntry / AuctionLot
// ---------------------------------------------------------------------------

/// Purpose: franchise-specific mechanics — retained players plus an
/// auction/draft to fill the rest.
class FranchiseRosterEntryEntity extends Equatable {
  const FranchiseRosterEntryEntity({
    required this.id,
    required this.teamId,
    required this.seasonId,
    required this.playerProfileId,
    required this.acquisitionType,
    this.acquisitionPrice,
  });

  final String id;

  /// franchise only.
  final String teamId;

  /// which year's roster this entry belongs to.
  final String seasonId;
  final String playerProfileId;
  final FranchiseAcquisitionType acquisitionType;

  /// paise, if auction.
  final Paise? acquisitionPrice;

  @override
  List<Object?> get props =>
      [id, teamId, seasonId, playerProfileId, acquisitionType, acquisitionPrice];
}

class AuctionLotEntity extends Equatable {
  const AuctionLotEntity({
    required this.id,
    required this.seasonId,
    required this.playerProfileId,
    required this.basePrice,
    required this.status,
    this.winningTeamId,
    this.finalPrice,
  });

  final String id;
  final String seasonId;

  /// player up for auction.
  final String playerProfileId;

  /// paise.
  final Paise basePrice;
  final AuctionLotStatus status;

  /// set on `sold`.
  final String? winningTeamId;

  /// paise.
  final Paise? finalPrice;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - An AuctionLot going `sold` must atomically create the matching
  //    FranchiseRosterEntryEntity (acquisitionType = auction,
  //    acquisitionPrice = finalPrice) — never leave these two objects
  //    able to disagree. Wrap both writes in one transaction.

  @override
  List<Object?> get props => [
        id,
        seasonId,
        playerProfileId,
        basePrice,
        status,
        winningTeamId,
        finalPrice,
      ];
}
