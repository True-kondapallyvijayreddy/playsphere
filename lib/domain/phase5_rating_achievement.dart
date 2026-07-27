import 'package:equatable/equatable.dart';

import 'enums.dart';

/// PHASE 5 — Rating Engine & Portable Achievement History
///
/// Every completed fixture writes into a portable, per-sport rating
/// and an achievement timeline that follows the PlayerProfile,
/// independent of org. See spec §5.

// ---------------------------------------------------------------------------
// 5.1 RatingRecord
// ---------------------------------------------------------------------------

/// Purpose: current rating state, one row per (player, sport).
/// Unique constraint: (playerProfileId, sportId).
class RatingRecordEntity extends Equatable {
  const RatingRecordEntity({
    required this.id,
    required this.playerProfileId,
    required this.sportId,
    required this.currentRating,
    required this.ratingStatus,
    required this.lastResultAt,
    required this.matchesPlayed,
  });

  final String id;
  final String playerProfileId;
  final String sportId;

  /// default seed 1200 on first-ever result.
  final double currentRating;

  /// provisional for first N results (config, default N=10).
  final RatingStatus ratingStatus;

  /// drives decay calc.
  final DateTime lastResultAt;
  final int matchesPlayed;

  @override
  List<Object?> get props => [
        id,
        playerProfileId,
        sportId,
        currentRating,
        ratingStatus,
        lastResultAt,
        matchesPlayed,
      ];
}

// ---------------------------------------------------------------------------
// 5.2 RatingHistoryEntry
// ---------------------------------------------------------------------------

/// Purpose: append-only ledger — never mutate
/// RatingRecord.currentRating without writing the corresponding
/// history row. This is both the audit trail and the source for the
/// rating-over-time chart on the career page.
class RatingHistoryEntryEntity extends Equatable {
  const RatingHistoryEntryEntity({
    required this.id,
    required this.ratingRecordId,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.expectedScore,
    required this.actualScore,
    required this.kFactorUsed,
    required this.verificationTier,
    required this.entryReason,
    this.fixtureId,
  });

  final String id;
  final String ratingRecordId;

  /// null for decay-driven entries.
  final String? fixtureId;
  final double ratingBefore;
  final double ratingAfter;

  /// the Expected(A) value computed pre-match.
  final double expectedScore;

  /// 1 / 0.5 / 0.
  final double actualScore;
  final double kFactorUsed;
  final VerificationTier verificationTier;
  final RatingEntryReason entryReason;

  @override
  List<Object?> get props => [
        id,
        ratingRecordId,
        fixtureId,
        ratingBefore,
        ratingAfter,
        expectedScore,
        actualScore,
        kFactorUsed,
        verificationTier,
        entryReason,
      ];
}

/// Rating calculation service contract (spec §5.2). Implement
/// exactly, do not approximate:
/// ```
/// Expected(A) = 1 / (1 + 10 ^ ((RatingB - RatingA) / 400))
/// NewRating(A) = RatingA + K * (ActualResult - Expected(A))
/// ```
/// TODO(implementation): none of the below is implemented yet — these
/// are documented contracts only.
///  - K selection: pull from a config table keyed by
///    (ratingStatus, verificationTier) — e.g. provisional=32,
///    established+casual=20, established+sanctioned=16. Do not
///    hardcode K in the calculation function; inject it.
///  - On a draw, both entrants get ActualResult = 0.5.
///  - Trigger point: a Fixture transitioning to `completed`, applied
///    only after the dispute window closes (use a
///    `pending_rating_apply` flag finalized when the window closes,
///    per spec recommendation) so ratings aren't churned by disputes.
///  - Team-sport rating updates: apply the same formula per player
///    using the team's aggregate rating (average of member ratings)
///    as that side's RatingA/RatingB, then apply the resulting delta
///    to each team member individually. This is a documented v1
///    approximation, not full round-robin pairwise reallocation.
abstract class RatingCalculationService {
  double expectedScore({required double ratingA, required double ratingB});

  double newRating({
    required double ratingA,
    required double kFactor,
    required double actualResult,
    required double expected,
  });

  double kFactorFor({
    required RatingStatus ratingStatus,
    required VerificationTier verificationTier,
  });
}

// ---------------------------------------------------------------------------
// 5.3 Inactivity decay job — not a new object, documented for
// completeness of the domain model's TODOs.
// ---------------------------------------------------------------------------
//
// TODO(scheduled-job, not implemented): nightly job scans
// RatingRecordEntity rows where lastResultAt is older than a
// configurable threshold (default 6 months) and nudges currentRating
// a small step toward the population mean for that sport, writing a
// RatingHistoryEntryEntity with entryReason = inactivityDecay. Once
// decayed, ratingStatus flips to `inactive` and the UI shows
// "unrated (inactive)" until a new result re-anchors it.

// ---------------------------------------------------------------------------
// 5.5 Achievement
// ---------------------------------------------------------------------------

/// Purpose: the timeline entries that assemble into the auto-built
/// career page — wins, top finishes, records, not just raw rating.
class AchievementEntity extends Equatable {
  const AchievementEntity({
    required this.id,
    required this.playerProfileId,
    required this.sportId,
    required this.achievementType,
    required this.description,
    required this.verificationTier,
    this.seasonId,
    this.visibilityOverride = AchievementVisibility.inherit,
  });

  final String id;
  final String playerProfileId;
  final String sportId;
  final AchievementType achievementType;
  final String? seasonId;

  /// auto-generated, e.g. "Winner — Badminton Doubles, Maram
  /// Garlapati Annual Games 2026".
  final String description;

  /// inherited from source fixtures/competition.
  final VerificationTier verificationTier;

  /// default `inherit` from PlayerProfile.visibilityDefault, but
  /// overridable per-achievement — this is the field Phase 6's
  /// guardian per-achievement control writes to.
  final AchievementVisibility visibilityOverride;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Generated automatically by a job on Season.status -> completed
  //    and SportCompetition.status -> completed — never manually
  //    created by a user, to keep the record trustworthy.
  //  - If the owning PlayerProfile belongs to a minor with no
  //    verified GuardianLink, resolved visibility is `private`
  //    regardless of visibilityOverride (see Phase 6).

  @override
  List<Object?> get props => [
        id,
        playerProfileId,
        sportId,
        achievementType,
        seasonId,
        description,
        verificationTier,
        visibilityOverride,
      ];
}

// ---------------------------------------------------------------------------
// 5.6 Anti-gaming safeguards
// ---------------------------------------------------------------------------

/// Purpose: review queue for suspicious rating swings. Rules,
/// implemented as jobs/checks against this table — not new logic
/// here, just the data shape.
class FlaggedRatingEventEntity extends Equatable {
  const FlaggedRatingEventEntity({
    required this.id,
    required this.ratingHistoryEntryId,
    required this.reason,
    required this.status,
    this.reviewedByUserId,
  });

  final String id;
  final String ratingHistoryEntryId;
  final String reason;
  final FlaggedRatingEventStatus status;
  final String? reviewedByUserId;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Reject rating application if Fixture.entrantAId ==
  //    Fixture.entrantBId, or if either entrant has no confirmed
  //    opponent (a "friendly bye" never updates ratings).
  //  - Flag-for-review: any RatingHistoryEntry where
  //    abs(ratingAfter - ratingBefore) > threshold (config, e.g. 80
  //    points) gets a row here for an admin to confirm or reverse.
  //  - Rate-limit: a playerProfileId cannot be party to more than N
  //    completed Fixtures against the same opponent within a rolling
  //    24h window (config, default N=3) without those extra results
  //    being auto-flagged — prevents rating-farming via repeated fake
  //    matches.

  @override
  List<Object?> get props =>
      [id, ratingHistoryEntryId, reason, status, reviewedByUserId];
}
