import 'package:equatable/equatable.dart';

import 'enums.dart';

/// PHASE 7 — Promotion Pipeline (Season Linking)
///
/// Results at one org's season can feed a higher-tier org's season,
/// purely through data, with zero special-cased "promotion" logic.
/// See spec §7.

// ---------------------------------------------------------------------------
// 7.1 SeasonLink
// ---------------------------------------------------------------------------

/// Purpose: declares that top finishers of a source season/stage
/// become entrants in a specific stage of a different season
/// (typically owned by a parent-tier org).
class SeasonLinkEntity extends Equatable {
  const SeasonLinkEntity({
    required this.id,
    required this.sourceStageId,
    required this.targetStageId,
    required this.status,
    this.promoteCount,
  });

  final String id;

  /// where finishers are read from.
  final String sourceStageId;

  /// where they're inserted as entrants.
  final String targetStageId;

  /// how many top finishers transfer; defaults to
  /// StageEntity(sourceStageId).advanceCount if unset.
  final int? promoteCount;
  final SeasonLinkStatus status;

  // TODO(business-rules, enforce in service layer — none implemented yet):
  //  - Applying a SeasonLink (on sourceStage.status -> completed)
  //    creates new Entrant rows in the target competition referencing
  //    the SAME PlayerProfile/Team, never duplicating identity.
  //  - If the target competition's entrantType differs from the
  //    source's (individual vs team), the link is invalid — validate
  //    at creation time, not at apply time.

  @override
  List<Object?> get props =>
      [id, sourceStageId, targetStageId, promoteCount, status];
}
