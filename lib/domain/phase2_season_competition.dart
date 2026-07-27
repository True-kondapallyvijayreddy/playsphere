import 'package:equatable/equatable.dart';

import 'enums.dart';

/// PHASE 2 — Season & Competition Core
///
/// An admin can stand up a season, add sports to it, open
/// registration, and see entrants. See spec §2.

// ---------------------------------------------------------------------------
// 2.1 Season
// ---------------------------------------------------------------------------

/// Purpose: top-level bounded container. "State Games 2026,"
/// "Saturday Badminton Q3."
class SeasonEntity extends Equatable {
  const SeasonEntity({
    required this.id,
    required this.orgId,
    required this.name,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.registrationOpensAt,
    required this.registrationClosesAt,
    this.leagueId,
    this.description,
    this.sharedMediaAlbumId,
  });

  final String id;
  final String orgId;

  /// null for one-off seasons.
  final String? leagueId;

  final String name;
  final SeasonStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime registrationOpensAt;
  final DateTime registrationClosesAt;
  final String? description;

  /// One album per season, auto-created.
  final String? sharedMediaAlbumId;

  /// Legal transitions: draft -> registrationOpen -> registrationClosed
  /// -> inProgress -> completed, with cancelled reachable from any
  /// non-completed state.
  static const Map<SeasonStatus, Set<SeasonStatus>> kLegalTransitions = {
    SeasonStatus.draft: {
      SeasonStatus.registrationOpen,
      SeasonStatus.cancelled,
    },
    SeasonStatus.registrationOpen: {
      SeasonStatus.registrationClosed,
      SeasonStatus.cancelled,
    },
    SeasonStatus.registrationClosed: {
      SeasonStatus.inProgress,
      SeasonStatus.cancelled,
    },
    SeasonStatus.inProgress: {
      SeasonStatus.completed,
      SeasonStatus.cancelled,
    },
    SeasonStatus.completed: {},
    SeasonStatus.cancelled: {},
  };

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - All child SportCompetitions share this season's registration
  //    window and venue calendar by default; a competition may narrow
  //    but never widen the window.
  //  - Block transition to inProgress while any child competition has
  //    zero entrants — warn, don't hard-block (a competition might
  //    legitimately be dropped).
  //  - `completed` is terminal except for admin-triggered result
  //    disputes (Phase 4 §4.5 dispute window).
  //  - Validate every status write against kLegalTransitions.

  @override
  List<Object?> get props => [
        id,
        orgId,
        leagueId,
        name,
        status,
        startDate,
        endDate,
        registrationOpensAt,
        registrationClosesAt,
        description,
        sharedMediaAlbumId,
      ];
}

// ---------------------------------------------------------------------------
// 2.2 SportCompetition
// ---------------------------------------------------------------------------

/// Purpose: one sport's independent tournament inside a season.
/// Cricket and chess in the same season are two SportCompetition
/// rows, each with its own format and standings.
class SportCompetitionEntity extends Equatable {
  const SportCompetitionEntity({
    required this.id,
    required this.seasonId,
    required this.sportId,
    required this.name,
    required this.entrantType,
    required this.format,
    required this.pointsConfigId,
    required this.status,
    this.minEntrants,
    this.maxEntrants,
  });

  final String id;
  final String seasonId;
  final String sportId;
  final String name;

  /// Determines whether registration produces a Team automatically.
  final EntrantType entrantType;
  final CompetitionFormat format;
  final String pointsConfigId;

  /// Mirrors Season status but can lag/lead slightly.
  final SportCompetitionStatus status;
  final int? minEntrants;
  final int? maxEntrants;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - entrantType == team requires a TeamFormationStrategy (Phase 3)
  //    to be configured before status can move to `locked`.
  //  - Deleting a SportCompetition after any Fixture exists is
  //    blocked — cancel instead.

  @override
  List<Object?> get props => [
        id,
        seasonId,
        sportId,
        name,
        entrantType,
        format,
        pointsConfigId,
        status,
        minEntrants,
        maxEntrants,
      ];
}

// ---------------------------------------------------------------------------
// 2.3 Sport
// ---------------------------------------------------------------------------

/// Purpose: platform-wide catalog of sports (cricket, badminton,
/// chess, TT, kabaddi...). Not org-scoped — shared reference data.
///
/// Business rule: this table is seeded/curated by platform admins,
/// not created by org admins. Orgs pick from the catalog; if a sport
/// is missing, that's a platform-level add, not a per-org one — this
/// keeps rating pools comparable.
class SportEntity extends Equatable {
  const SportEntity({
    required this.id,
    required this.name,
    required this.scoringPluginKey,
    required this.defaultEntrantType,
    this.iconUrl,
  });

  final String id;

  /// unique
  final String name;

  /// Maps to a ScoringPlugin implementation — see Phase 4
  /// (phase4_fixtures_scoring.dart, ScoringPlugin interface).
  final String scoringPluginKey;
  final EntrantType defaultEntrantType;
  final String? iconUrl;

  @override
  List<Object?> get props =>
      [id, name, scoringPluginKey, defaultEntrantType, iconUrl];
}

// ---------------------------------------------------------------------------
// 2.4 Registration
// ---------------------------------------------------------------------------

/// Purpose: a person's expressed interest in one SportCompetition.
/// This is what a participant does in step 2 of match day.
class RegistrationEntity extends Equatable {
  const RegistrationEntity({
    required this.id,
    required this.sportCompetitionId,
    required this.playerProfileId,
    required this.registeredByUserId,
    required this.status,
    this.selfDeclaredSkill,
  });

  final String id;
  final String sportCompetitionId;
  final String playerProfileId;

  /// self, admin, or guardian (Phase 6).
  final String registeredByUserId;
  final RegistrationStatus status;

  /// 1-10. Used as a cold-start signal before any RatingRecord
  /// exists.
  final int? selfDeclaredSkill;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - selfDeclaredSkill must be null or in [1, 10].
  //  - One playerProfileId can hold multiple Registrations across
  //    different SportCompetitions in the same season, but only ONE
  //    active (status in {pending, confirmed, waitlisted})
  //    registration per competition.
  //  - A minor's registration requires either an admin-initiated flow
  //    or an already-verified GuardianLink (Phase 6) — enforce at
  //    write time, not just UI hiding.

  @override
  List<Object?> get props => [
        id,
        sportCompetitionId,
        playerProfileId,
        registeredByUserId,
        status,
        selfDeclaredSkill,
      ];
}

// ---------------------------------------------------------------------------
// 2.5 Entrant
// ---------------------------------------------------------------------------

/// Purpose: the generic thing that has standings, fixtures, and
/// points — an individual or a team. Everything downstream (Stage,
/// Fixture, Standing) points at Entrant, never separately at "player"
/// or "team." This is the single most important abstraction in the
/// whole system — do not special-case individual vs team anywhere
/// downstream of this layer.
class EntrantEntity extends Equatable {
  const EntrantEntity({
    required this.id,
    required this.sportCompetitionId,
    required this.entrantKind,
    required this.status,
    this.playerProfileId,
    this.teamId,
    this.seed,
  }) : assert(
          (entrantKind == EntrantType.individual) ==
              (playerProfileId != null),
          'playerProfileId must be set iff entrantKind == individual',
        ),
        assert(
          (entrantKind == EntrantType.team) == (teamId != null),
          'teamId must be set iff entrantKind == team',
        );

  final String id;
  final String sportCompetitionId;
  final EntrantType entrantKind;

  /// set iff entrantKind == individual. Enforced by the assert above
  /// at construction time; the spec additionally requires this as a
  /// DB CHECK constraint, not just app logic — replicate that at the
  /// persistence layer once one exists.
  final String? playerProfileId;

  /// set iff entrantKind == team.
  final String? teamId;

  /// for knockout seeding.
  final int? seed;
  final EntrantStatus status;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Entrant is created automatically from Registration (individual
  //    sports) or from Team-formation output (team sports) — never
  //    created directly by a user action. There should be no public
  //    "create Entrant" command in the API surface.

  @override
  List<Object?> get props => [
        id,
        sportCompetitionId,
        entrantKind,
        playerProfileId,
        teamId,
        seed,
        status,
      ];
}

// ---------------------------------------------------------------------------
// 2.6 League
// ---------------------------------------------------------------------------

/// Purpose: the persistent identity above a season — "IPL," "Maram
/// Garlapati Annual Games." Holds all-time history; each year is a
/// Season underneath it.
class LeagueEntity extends Equatable {
  const LeagueEntity({
    required this.id,
    required this.orgId,
    required this.name,
    this.logoUrl,
    this.foundedYear,
    this.trophyCabinet = const [],
  });

  final String id;
  final String orgId;
  final String name;
  final String? logoUrl;
  final int? foundedYear;

  /// Append-only array of trophy entries.
  final List<TrophyCabinetEntry> trophyCabinet;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - trophyCabinet entries are written once a Season reaches
  //    `completed` and never edited except via the audit-logged
  //    dispute-resolution path (Phase 4 §4.5).

  @override
  List<Object?> get props =>
      [id, orgId, name, logoUrl, foundedYear, trophyCabinet];
}

class TrophyCabinetEntry extends Equatable {
  const TrophyCabinetEntry({
    required this.seasonId,
    required this.winnerEntrantId,
    required this.title,
  });

  final String seasonId;
  final String winnerEntrantId;
  final String title;

  @override
  List<Object?> get props => [seasonId, winnerEntrantId, title];
}

// ---------------------------------------------------------------------------
// 2.7 PointsConfig
// ---------------------------------------------------------------------------

/// Purpose: the settings object that lets the same standings engine
/// render a 5-team Saturday table and a 10-franchise IPL table. Never
/// hardcode points logic in application code — it must be fully
/// data-driven from this object.
class PointsConfigEntity extends Equatable {
  const PointsConfigEntity({
    required this.id,
    required this.winPoints,
    required this.drawPoints,
    required this.lossPoints,
    required this.tiebreakerOrder,
    this.bonusPointRules,
    this.promotionThreshold,
    this.relegationThreshold,
  });

  final String id;
  final double winPoints;
  final double drawPoints;
  final double lossPoints;

  /// e.g. cricket bonus point for big-margin win.
  final Map<String, dynamic>? bonusPointRules;

  /// Ordered list, e.g. ["points", "head_to_head", "net_run_rate",
  /// "game_difference", "random"].
  final List<String> tiebreakerOrder;

  /// top-N entrants promoted, feeds SeasonLink (Phase 7).
  final int? promotionThreshold;

  /// bottom-N flagged, if applicable.
  final int? relegationThreshold;

  @override
  List<Object?> get props => [
        id,
        winPoints,
        drawPoints,
        lossPoints,
        bonusPointRules,
        tiebreakerOrder,
        promotionThreshold,
        relegationThreshold,
      ];
}
