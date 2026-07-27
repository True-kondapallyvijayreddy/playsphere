import '../enums.dart';
import '../phase4_fixtures_scoring.dart';
import '../phase7_promotion.dart';

class PromotedEntrantResult {
  const PromotedEntrantResult({
    required this.entrantId,
    required this.sourceStageId,
    required this.targetStageId,
    required this.sourceRank,
    required this.promotedAt,
  });

  final String entrantId;
  final String sourceStageId;
  final String targetStageId;
  final int sourceRank;
  final DateTime promotedAt;
}

/// Entrant promotion pipeline engine (§7, §6).
class PromotionPipelineService {
  const PromotionPipelineService();

  /// Evaluates a SeasonLink and produces promoted entrants into the parent season stage.
  List<PromotedEntrantResult> executePromotion({
    required SeasonLinkEntity seasonLink,
    required List<StandingEntity> finalSourceStandings,
  }) {
    if (seasonLink.status != SeasonLinkStatus.pending) {
      return [];
    }

    final topStandings = List<StandingEntity>.from(finalSourceStandings)
      ..sort((a, b) => a.rank.compareTo(b.rank));

    final countToPromote = seasonLink.promoteCount ?? 2;
    final eligible = topStandings.take(countToPromote).toList();
    final now = DateTime.now();

    return eligible.map((standing) {
      return PromotedEntrantResult(
        entrantId: standing.entrantId,
        sourceStageId: seasonLink.sourceStageId,
        targetStageId: seasonLink.targetStageId,
        sourceRank: standing.rank,
        promotedAt: now,
      );
    }).toList();
  }
}
