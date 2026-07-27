/// Central catalog of every enum referenced by the Technical Build
/// Specification (v1.0). Grouped by the phase that introduces them.
///
/// These are pure value types only. No behavior, no validation beyond
/// what Dart's enum system gives for free. Business rules that govern
/// *which transitions are legal* (e.g. Season state machine, Fixture
/// dispute flow) are documented as TODOs on the owning entity and must
/// be enforced in a service/repository layer — see each entity file.
library playsphere_enums;

// ---------------------------------------------------------------------------
// Phase 1 — Identity & Organization
// ---------------------------------------------------------------------------

enum AuthProvider { password, google, otp }

enum AccountStatus { active, suspended, deleted }

enum OrgType {
  residentialCommunity,
  school,
  corporate,
  cityClub,
  districtAssociation,
  stateCouncil,
  countryCouncil,
}

enum OrgVisibility { public, unlisted }

enum MembershipRole { owner, admin, eventManager, judgeScorer, member }

enum MembershipStatus { invited, active, removed }

enum ProfileVisibility { private, community, statewide }

/// Used by Achievement.visibility_override, which additionally allows
/// "inherit" on top of the three ProfileVisibility values.
enum AchievementVisibility { inherit, private, community, statewide }

// ---------------------------------------------------------------------------
// Phase 2 — Season & Competition Core
// ---------------------------------------------------------------------------

enum SeasonStatus {
  draft,
  registrationOpen,
  registrationClosed,
  inProgress,
  completed,
  cancelled,
}

enum EntrantType { individual, team }

enum CompetitionFormat {
  roundRobin,
  knockout,
  swiss,
  groupThenKnockout,
  leagueTable,
}

enum SportCompetitionStatus { draft, open, locked, inProgress, completed }

enum RegistrationStatus { pending, confirmed, waitlisted, withdrawn }

enum EntrantStatus { active, withdrawn, disqualified }

// ---------------------------------------------------------------------------
// Phase 3 — Team Formation
// ---------------------------------------------------------------------------

enum TeamKind { adHoc, franchise }

enum TeamFormationStrategyType {
  random,
  manual,
  aiBalanced,
  auction,
  draft,
  houseWise,
  departmentWise,
}

enum FranchiseAcquisitionType { retained, auction, draft, freeSigning }

enum AuctionLotStatus { upcoming, live, sold, unsold }

// ---------------------------------------------------------------------------
// Phase 4 — Fixtures, Live Scoring, Standings
// ---------------------------------------------------------------------------

enum StageFormat { roundRobin, knockout, swiss }

enum StageStatus { pending, inProgress, completed }

enum FixtureStatus {
  scheduled,
  live,
  completed,
  walkover,
  abandoned,
  disputed,
}

// ---------------------------------------------------------------------------
// Phase 5 — Rating Engine & Achievement History
// ---------------------------------------------------------------------------

enum RatingStatus { provisional, established, inactive }

enum VerificationTier { casual, sanctioned }

enum RatingEntryReason { matchResult, inactivityDecay, disputeCorrection }

enum AchievementType {
  competitionWin,
  stageFinish,
  personalBest,
  milestone,
}

enum FlaggedRatingEventStatus { open, reviewed, reversed }

// ---------------------------------------------------------------------------
// Phase 6 — Trust & Safety: Guardian / Minor Consent
// ---------------------------------------------------------------------------

enum GuardianRelationship { parent, legalGuardian, otherVerified }

enum GuardianVerificationStatus { pending, verified, rejected }

enum GuardianVerificationMethod {
  idDocument,
  orgAdminAttestation,
  phoneOtpCrossCheck,
}

enum ScoutingInviteStatus { pending, accepted, declined, expired }

enum OrgVerificationStatus { unverified, pending, verified, rejected }

// ---------------------------------------------------------------------------
// Phase 7 — Promotion Pipeline (Season Linking)
// ---------------------------------------------------------------------------

enum SeasonLinkStatus { pending, applied, cancelled }

// ---------------------------------------------------------------------------
// Phase 9 — Venue & Officiating Marketplace (design sketch)
// ---------------------------------------------------------------------------

enum BookingUnit { hourly, slot }

enum VenueBookingStatus { held, confirmed, cancelled }

enum OfficialCertificationStatus { pending, verified, expired }

enum OfficialAssignmentRole { referee, umpire, scorer }

enum OfficialAssignmentStatus { assigned, confirmed, declined }

// ---------------------------------------------------------------------------
// Phase 10 — Governance, Compliance & Monetization (design sketch)
// ---------------------------------------------------------------------------

enum TicketScopeType { fixture, season }
