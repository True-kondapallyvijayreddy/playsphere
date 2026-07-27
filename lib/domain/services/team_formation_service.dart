import 'dart:math' as math;

import '../enums.dart';
import '../phase2_season_competition.dart';
import '../phase3_team_formation.dart';

class RegistrantWithRating {
  const RegistrantWithRating({
    required this.registration,
    required this.playerProfileId,
    required this.displayName,
    required this.rating,
    this.membershipTag,
  });

  final RegistrationEntity registration;
  final String playerProfileId;
  final String displayName;
  final double rating;
  final String? membershipTag;
}

class FormedTeamResult {
  const FormedTeamResult({
    required this.team,
    required this.memberProfileIds,
    required this.averageRating,
  });

  final TeamEntity team;
  final List<String> memberProfileIds;
  final double averageRating;
}

/// Pluggable strategy engine for forming teams from registrants (§3.3).
class PlaySphereTeamFormationEngine {
  const PlaySphereTeamFormationEngine();

  List<FormedTeamResult> formTeams({
    required SportCompetitionEntity competition,
    required TeamFormationStrategyType strategyType,
    required List<RegistrantWithRating> registrants,
    int teamCount = 4,
    int randomSeed = 42,
  }) {
    if (registrants.isEmpty) return [];

    switch (strategyType) {
      case TeamFormationStrategyType.random:
        return _formRandomTeams(competition, registrants, teamCount, randomSeed);
      case TeamFormationStrategyType.aiBalanced:
        return _formAIBalancedTeams(competition, registrants, teamCount);
      case TeamFormationStrategyType.houseWise:
      case TeamFormationStrategyType.departmentWise:
        return _formTagBasedTeams(competition, registrants);
      case TeamFormationStrategyType.manual:
      default:
        return _formRandomTeams(competition, registrants, teamCount, randomSeed);
    }
  }

  List<FormedTeamResult> _formRandomTeams(
    SportCompetitionEntity competition,
    List<RegistrantWithRating> registrants,
    int teamCount,
    int seed,
  ) {
    final list = List<RegistrantWithRating>.from(registrants);
    list.shuffle(math.Random(seed));

    final count = math.max(1, teamCount);
    final buckets = List<List<RegistrantWithRating>>.generate(count, (_) => []);

    for (var i = 0; i < list.length; i++) {
      buckets[i % count].add(list[i]);
    }

    return List.generate(count, (index) {
      final members = buckets[index];
      final avgRating = members.isEmpty
          ? 1200.0
          : members.map((m) => m.rating).reduce((a, b) => a + b) / members.length;
      final teamName = 'Team ${String.fromCharCode(65 + index)}';

      return FormedTeamResult(
        team: TeamEntity(
          id: 'team-${competition.id}-$index',
          orgId: competition.seasonId,
          teamKind: TeamKind.adHoc,
          name: teamName,
          isActive: true,
        ),
        memberProfileIds: members.map((m) => m.playerProfileId).toList(),
        averageRating: double.parse(avgRating.toStringAsFixed(1)),
      );
    });
  }

  /// AI-balanced team formation via greedy snake draft on per-sport ELO rating.
  List<FormedTeamResult> _formAIBalancedTeams(
    SportCompetitionEntity competition,
    List<RegistrantWithRating> registrants,
    int teamCount,
  ) {
    final sorted = List<RegistrantWithRating>.from(registrants)
      ..sort((a, b) => b.rating.compareTo(a.rating));

    final count = math.max(1, teamCount);
    final buckets = List<List<RegistrantWithRating>>.generate(count, (_) => []);

    // Snake draft distribution: 0..count-1, count-1..0
    for (var i = 0; i < sorted.length; i++) {
      final round = i ~/ count;
      final isEvenRound = round % 2 == 0;
      final bucketIndex = isEvenRound ? (i % count) : (count - 1 - (i % count));
      buckets[bucketIndex].add(sorted[i]);
    }

    return List.generate(count, (index) {
      final members = buckets[index];
      final avgRating = members.isEmpty
          ? 1200.0
          : members.map((m) => m.rating).reduce((a, b) => a + b) / members.length;
      final teamName = 'Strikers ${String.fromCharCode(65 + index)}';

      return FormedTeamResult(
        team: TeamEntity(
          id: 'ai-team-${competition.id}-$index',
          orgId: competition.seasonId,
          teamKind: TeamKind.adHoc,
          name: teamName,
          isActive: true,
        ),
        memberProfileIds: members.map((m) => m.playerProfileId).toList(),
        averageRating: double.parse(avgRating.toStringAsFixed(1)),
      );
    });
  }

  List<FormedTeamResult> _formTagBasedTeams(
    SportCompetitionEntity competition,
    List<RegistrantWithRating> registrants,
  ) {
    final Map<String, List<RegistrantWithRating>> tagMap = {};

    for (final reg in registrants) {
      final tag = reg.membershipTag ?? 'Unassigned';
      tagMap.putIfAbsent(tag, () => []).add(reg);
    }

    final results = <FormedTeamResult>[];
    var index = 0;

    tagMap.forEach((tag, members) {
      final avgRating = members.isEmpty
          ? 1200.0
          : members.map((m) => m.rating).reduce((a, b) => a + b) / members.length;

      results.add(
        FormedTeamResult(
          team: TeamEntity(
            id: 'tag-team-${competition.id}-$index',
            orgId: competition.seasonId,
            teamKind: TeamKind.adHoc,
            name: '$tag Unit',
            isActive: true,
          ),
          memberProfileIds: members.map((m) => m.playerProfileId).toList(),
          averageRating: double.parse(avgRating.toStringAsFixed(1)),
        ),
      );
      index++;
    });

    return results;
  }
}
