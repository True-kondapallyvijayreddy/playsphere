import '../phase2_season_competition.dart';
import '../phase4_fixtures_scoring.dart';

/// Idempotent standings calculation engine (§4.4).
class StandingsCalculatorService {
  const StandingsCalculatorService();

  List<StandingEntity> computeStandings({
    required String stageId,
    required List<String> entrantIds,
    required List<FixtureEntity> completedFixtures,
    required PointsConfigEntity pointsConfig,
    Map<String, Map<String, double>>? matchScores,
  }) {
    final Map<String, int> playedMap = {for (final id in entrantIds) id: 0};
    final Map<String, int> winsMap = {for (final id in entrantIds) id: 0};
    final Map<String, int> drawsMap = {for (final id in entrantIds) id: 0};
    final Map<String, int> lossesMap = {for (final id in entrantIds) id: 0};
    final Map<String, double> pointsMap = {for (final id in entrantIds) id: 0.0};
    final Map<String, double> scoreForMap = {for (final id in entrantIds) id: 0.0};
    final Map<String, double> scoreAgainstMap = {for (final id in entrantIds) id: 0.0};

    for (final fixture in completedFixtures) {
      if (fixture.stageId != stageId) continue;

      final eA = fixture.entrantAId;
      final eB = fixture.entrantBId;

      if (!playedMap.containsKey(eA)) playedMap[eA] = 0;
      if (!playedMap.containsKey(eB)) playedMap[eB] = 0;

      playedMap[eA] = (playedMap[eA] ?? 0) + 1;
      playedMap[eB] = (playedMap[eB] ?? 0) + 1;

      if (fixture.isDraw) {
        drawsMap[eA] = (drawsMap[eA] ?? 0) + 1;
        drawsMap[eB] = (drawsMap[eB] ?? 0) + 1;
        pointsMap[eA] = (pointsMap[eA] ?? 0) + pointsConfig.drawPoints;
        pointsMap[eB] = (pointsMap[eB] ?? 0) + pointsConfig.drawPoints;
      } else if (fixture.resultEntrantId == eA) {
        winsMap[eA] = (winsMap[eA] ?? 0) + 1;
        lossesMap[eB] = (lossesMap[eB] ?? 0) + 1;
        pointsMap[eA] = (pointsMap[eA] ?? 0) + pointsConfig.winPoints;
        pointsMap[eB] = (pointsMap[eB] ?? 0) + pointsConfig.lossPoints;
      } else if (fixture.resultEntrantId == eB) {
        winsMap[eB] = (winsMap[eB] ?? 0) + 1;
        lossesMap[eA] = (lossesMap[eA] ?? 0) + 1;
        pointsMap[eB] = (pointsMap[eB] ?? 0) + pointsConfig.winPoints;
        pointsMap[eA] = (pointsMap[eA] ?? 0) + pointsConfig.lossPoints;
      }

      if (matchScores != null && matchScores.containsKey(fixture.id)) {
        final scores = matchScores[fixture.id]!;
        final sA = scores[eA] ?? 0.0;
        final sB = scores[eB] ?? 0.0;

        scoreForMap[eA] = (scoreForMap[eA] ?? 0.0) + sA;
        scoreAgainstMap[eA] = (scoreAgainstMap[eA] ?? 0.0) + sB;

        scoreForMap[eB] = (scoreForMap[eB] ?? 0.0) + sB;
        scoreAgainstMap[eB] = (scoreAgainstMap[eB] ?? 0.0) + sA;
      }
    }

    final rawList = entrantIds.map((entrantId) {
      final sf = scoreForMap[entrantId] ?? 0.0;
      final sa = scoreAgainstMap[entrantId] ?? 0.0;
      final diff = sf - sa;

      return {
        'entrantId': entrantId,
        'played': playedMap[entrantId] ?? 0,
        'wins': winsMap[entrantId] ?? 0,
        'draws': drawsMap[entrantId] ?? 0,
        'losses': lossesMap[entrantId] ?? 0,
        'points': pointsMap[entrantId] ?? 0.0,
        'diff': diff,
      };
    }).toList();

    rawList.sort((a, b) {
      final pComp = (b['points'] as double).compareTo(a['points'] as double);
      if (pComp != 0) return pComp;

      final diffComp = (b['diff'] as double).compareTo(a['diff'] as double);
      if (diffComp != 0) return diffComp;

      return (b['wins'] as int).compareTo(a['wins'] as int);
    });

    return List.generate(rawList.length, (index) {
      final item = rawList[index];
      final entrantId = item['entrantId'] as String;

      return StandingEntity(
        id: 'standing-$stageId-$entrantId',
        stageId: stageId,
        entrantId: entrantId,
        played: item['played'] as int,
        wins: item['wins'] as int,
        draws: item['draws'] as int,
        losses: item['losses'] as int,
        points: item['points'] as double,
        tiebreakValues: {'score_diff': item['diff']},
        rank: index + 1,
      );
    });
  }
}
