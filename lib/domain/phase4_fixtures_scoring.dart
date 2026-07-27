import 'package:equatable/equatable.dart';

import 'enums.dart';

/// PHASE 4 — Fixtures, Live Scoring, Standings
///
/// The actual match-day loop — the platform's core daily-use surface.
/// See spec §4.

// ---------------------------------------------------------------------------
// 4.1 Stage
// ---------------------------------------------------------------------------

/// Purpose: group stage / knockout stage / playoffs inside a
/// competition. Stages chain — top finishers of one feed the entrant
/// pool of the next.
class StageEntity extends Equatable {
  const StageEntity({
    required this.id,
    required this.sportCompetitionId,
    required this.name,
    required this.stageOrder,
    required this.stageFormat,
    required this.status,
    this.feedsFromStageId,
    this.advanceCount,
  });

  final String id;
  final String sportCompetitionId;
  final String name;

  /// sequence within the competition.
  final int stageOrder;

  /// can differ from the parent competition's overall `format` label.
  final StageFormat stageFormat;

  /// null for the first stage.
  final String? feedsFromStageId;

  /// how many entrants advance out of this stage into the next.
  final int? advanceCount;
  final StageStatus status;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Advancing entrants from feedsFromStageId into this stage is a
  //    system-triggered job once the source stage hits `completed` —
  //    never manual copy-paste of entrant lists.

  @override
  List<Object?> get props => [
        id,
        sportCompetitionId,
        name,
        stageOrder,
        stageFormat,
        feedsFromStageId,
        advanceCount,
        status,
      ];
}

// ---------------------------------------------------------------------------
// 4.2 Fixture
// ---------------------------------------------------------------------------

/// Purpose: one scheduled match between entrants within a stage.
class FixtureEntity extends Equatable {
  const FixtureEntity({
    required this.id,
    required this.stageId,
    required this.entrantAId,
    required this.entrantBId,
    required this.status,
    required this.isDraw,
    required this.disputeWindowClosesAt,
    this.scheduledAt,
    this.venueId,
    this.resultEntrantId,
    this.officiatedByUserId,
    this.verificationTier = VerificationTier.casual,
  });

  final String id;
  final String stageId;
  final String entrantAId;
  final String entrantBId;
  final DateTime? scheduledAt;

  /// Phase 9 forward-ref; nullable until then.
  final String? venueId;
  final FixtureStatus status;

  /// winner; null if draw.
  final String? resultEntrantId;
  final bool isDraw;

  /// scorer/judge who entered the result.
  final String? officiatedByUserId;

  /// auto-set on completion; see the dispute-window rule below.
  final DateTime disputeWindowClosesAt;

  /// §5.4: set based on the owning Organization.orgType and whether
  /// officiating was done by a registry-certified official (Phase 9
  /// forward-dependency). Until Phase 9 exists, `sanctioned` can only
  /// be set manually by a districtAssociation-or-higher org admin.
  final VerificationTier verificationTier;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - status == completed starts a configurable dispute window
  //    (default 24h, org-configurable) — set disputeWindowClosesAt at
  //    that transition.
  //  - During the window, an admin can reopen a fixture
  //    (status -> disputed), edit/replay MatchEvents, and re-close
  //    it, which re-triggers Standing recompute and, if already
  //    applied, a RatingHistoryEntry recompute flag (Phase 5
  //    anti-gaming).
  //  - After the window closes, edits require the same reopen flow
  //    but must log `disputed_after_window: true` on the
  //    AuditLogEntry.
  //  - resultEntrantId must be null when isDraw == true, and
  //    non-null (and equal to entrantAId or entrantBId) otherwise.

  @override
  List<Object?> get props => [
        id,
        stageId,
        entrantAId,
        entrantBId,
        scheduledAt,
        venueId,
        status,
        resultEntrantId,
        isDraw,
        officiatedByUserId,
        disputeWindowClosesAt,
        verificationTier,
      ];
}

// ---------------------------------------------------------------------------
// 4.3 MatchEvent (sport-plugin scoring detail)
// ---------------------------------------------------------------------------

/// Purpose: the granular, sport-specific score log. Deliberately
/// generic; the meaning of [eventType] and [payload] is defined per
/// sport plugin (see [ScoringPlugin]).
class MatchEventEntity extends Equatable {
  const MatchEventEntity({
    required this.id,
    required this.fixtureId,
    required this.eventType,
    required this.payload,
    required this.enteredByUserId,
    required this.sequenceNo,
    required this.createdAt,
  });

  final String id;
  final String fixtureId;

  /// plugin-defined, e.g. "point_won", "wicket", "boundary",
  /// "game_won".
  final String eventType;

  /// plugin-defined shape.
  final Map<String, dynamic> payload;
  final String enteredByUserId;

  /// strictly increasing per fixture, used for live replay/undo.
  final int sequenceNo;
  final DateTime createdAt;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - sequenceNo must be strictly increasing per fixtureId; reject
  //    out-of-order inserts.
  //  - Real-time fan-out on every insert via websocket/pubsub to
  //    anyone subscribed to that fixtureId channel.

  @override
  List<Object?> get props => [
        id,
        fixtureId,
        eventType,
        payload,
        enteredByUserId,
        sequenceNo,
        createdAt,
      ];
}

/// Sport plugin interface contract (spec §4.3). Build 3 plugins in
/// v1:
///  - simple_win_loss (chess/TT — just record the final result, no
///    ball-by-ball)
///  - set_based (badminton/volleyball — games/sets won)
///  - run_based (cricket-lite — overs/wickets/runs; does not need to
///    be full BCCI-grade ball-by-ball for v1)
///
/// TODO(implementation): applyEvent must be a pure function of prior
/// state + event — this is what makes live scoring reconstructable
/// and undo-able (delete the last MatchEvent, replay). No concrete
/// plugin is implemented yet; this is the interface only.
abstract class ScoringPlugin {
  /// matches SportEntity.scoringPluginKey.
  String get key;

  Map<String, dynamic> initialState(FixtureEntity fixture);

  /// Must be a pure function of (state, event).
  Map<String, dynamic> applyEvent(
    Map<String, dynamic> state,
    MatchEventEntity event,
  );

  bool isMatchComplete(Map<String, dynamic> state);

  ScoringPluginResult deriveResult(Map<String, dynamic> state);

  /// for live-follow UI.
  Map<String, dynamic> renderSummary(Map<String, dynamic> state);
}

class ScoringPluginResult extends Equatable {
  const ScoringPluginResult({this.winnerEntrantId, required this.isDraw});

  final String? winnerEntrantId;
  final bool isDraw;

  @override
  List<Object?> get props => [winnerEntrantId, isDraw];
}

// ---------------------------------------------------------------------------
// 4.4 Standing (materialized, not hand-edited)
// ---------------------------------------------------------------------------

/// Purpose: the points table row per entrant per competition/stage.
/// Always derived, never directly written by a user.
class StandingEntity extends Equatable {
  const StandingEntity({
    required this.id,
    required this.stageId,
    required this.entrantId,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.points,
    required this.tiebreakValues,
    required this.rank,
  });

  final String id;
  final String stageId;
  final String entrantId;
  final int played;
  final int wins;
  final int draws;
  final int losses;

  /// computed from PointsConfig.
  final double points;

  /// one value per configured tiebreaker, e.g.
  /// {"net_run_rate": 1.24}.
  final Map<String, dynamic> tiebreakValues;

  /// computed after applying PointsConfig.tiebreakerOrder.
  final int rank;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Recompute Standing rows for a stage as an idempotent batch job
  //    triggered on every Fixture reaching `completed` — do NOT
  //    incrementally patch standings row-by-row; recompute the whole
  //    stage's table from source fixtures each time. This avoids an
  //    entire class of drift bugs.

  @override
  List<Object?> get props => [
        id,
        stageId,
        entrantId,
        played,
        wins,
        draws,
        losses,
        points,
        tiebreakValues,
        rank,
      ];
}
