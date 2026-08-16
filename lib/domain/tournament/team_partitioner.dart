import '../../core/models/competition.dart';
import '../../core/models/enums.dart';

/// A drafted or partitioned squad in the team builder.
class DraftSquad {
  DraftSquad({
    required this.name,
    List<Registration>? members,
    List<Registration>? reserves,
    this.bucketId,
  })  : members = members ?? [],
        reserves = reserves ?? [];

  String name;
  final String? bucketId;
  final List<Registration> members;
  final List<Registration> reserves;

  int get totalCount => members.length + reserves.length;
}

/// The result of running a team partitioning operation on a player pool.
class PartitionResult {
  const PartitionResult({
    required this.squads,
    this.unassigned = const [],
    this.waitlistOverflow = const [],
  });

  final List<DraftSquad> squads;
  final List<Registration> unassigned;
  final List<Registration> waitlistOverflow;

  int get totalAssigned => squads.fold(0, (sum, s) => sum + s.totalCount);
  bool get hasLeftovers => unassigned.isNotEmpty || waitlistOverflow.isNotEmpty;
}

/// Validation failure reason when gating draw generation.
class DrawReadinessReport {
  const DrawReadinessReport({
    required this.isReady,
    this.reasons = const [],
    this.unresolvedRegistrations = const [],
  });

  final bool isReady;
  final List<String> reasons;
  final List<Registration> unresolvedRegistrations;

  factory DrawReadinessReport.ready() => const DrawReadinessReport(isReady: true);

  factory DrawReadinessReport.blocked(List<String> reasons,
          [List<Registration> unresolved = const []]) =>
      DrawReadinessReport(
        isReady: false,
        reasons: reasons,
        unresolvedRegistrations: unresolved,
      );
}

/// High-precision mathematical and constraint-based team partitioning engine.
class TeamPartitioner {
  const TeamPartitioner();

  static const List<String> defaultSquadNames = [
    'Team Alpha',
    'Team Beta',
    'Team Gamma',
    'Team Delta',
    'Team Epsilon',
    'Team Zeta',
    'Team Eta',
    'Team Theta',
  ];

  /// Partitions a list of players into [teamCount] balanced squads.
  /// Handles exact division, odd remainders, and strategy selection.
  PartitionResult partition({
    required List<Registration> players,
    required int teamCount,
    int? targetSquadSize,
    RemainderStrategy remainderStrategy = RemainderStrategy.distributeEvenly,
    List<String>? customTeamNames,
  }) {
    if (teamCount < 2 || players.isEmpty) {
      return PartitionResult(
        squads: [
          for (var i = 0; i < (teamCount < 1 ? 2 : teamCount); i++)
            DraftSquad(name: _squadName(i, customTeamNames)),
        ],
        unassigned: List.of(players),
      );
    }

    final squads = [
      for (var i = 0; i < teamCount; i++)
        DraftSquad(name: _squadName(i, customTeamNames)),
    ];

    if (targetSquadSize != null && targetSquadSize > 0) {
      final totalCapacity = teamCount * targetSquadSize;
      final mainPool = players.take(totalCapacity).toList();
      final overflow = players.skip(totalCapacity).toList();

      for (var i = 0; i < mainPool.length; i++) {
        squads[i % teamCount].members.add(mainPool[i]);
      }

      if (remainderStrategy == RemainderStrategy.assignAsReserves) {
        for (var i = 0; i < overflow.length; i++) {
          squads[i % teamCount].reserves.add(overflow[i]);
        }
        return PartitionResult(squads: squads);
      } else if (remainderStrategy == RemainderStrategy.overflowWaitlist) {
        return PartitionResult(squads: squads, waitlistOverflow: overflow);
      } else {
        // Distribute remainder into squads anyway
        for (var i = 0; i < overflow.length; i++) {
          squads[i % teamCount].members.add(overflow[i]);
        }
        return PartitionResult(squads: squads);
      }
    }

    // No fixed target squad size -> distribute evenly
    final baseCount = players.length ~/ teamCount;
    final remainder = players.length % teamCount;

    if (remainder == 0 || remainderStrategy == RemainderStrategy.distributeEvenly) {
      for (var i = 0; i < players.length; i++) {
        squads[i % teamCount].members.add(players[i]);
      }
      return PartitionResult(squads: squads);
    } else if (remainderStrategy == RemainderStrategy.assignAsReserves) {
      final mainPoolCount = baseCount * teamCount;
      for (var i = 0; i < mainPoolCount; i++) {
        squads[i % teamCount].members.add(players[i]);
      }
      for (var i = mainPoolCount; i < players.length; i++) {
        squads[(i - mainPoolCount) % teamCount].reserves.add(players[i]);
      }
      return PartitionResult(squads: squads);
    } else {
      // overflowWaitlist
      final mainPoolCount = baseCount * teamCount;
      for (var i = 0; i < mainPoolCount; i++) {
        squads[i % teamCount].members.add(players[i]);
      }
      final overflow = players.sublist(mainPoolCount);
      return PartitionResult(squads: squads, waitlistOverflow: overflow);
    }
  }

  /// Partitions by organization bucket (House / Section / Grade).
  PartitionResult partitionByBuckets({
    required List<Registration> players,
    required List<String> bucketIds,
    required Map<String, String> bucketNames,
  }) {
    final squadsMap = <String, DraftSquad>{
      for (final id in bucketIds)
        id: DraftSquad(name: bucketNames[id] ?? id, bucketId: id),
    };
    final unassigned = <Registration>[];

    for (final p in players) {
      final bId = p.houseName;
      if (bId != null && squadsMap.containsKey(bId)) {
        squadsMap[bId]!.members.add(p);
      } else {
        unassigned.add(p);
      }
    }

    return PartitionResult(
      squads: squadsMap.values.toList(),
      unassigned: unassigned,
    );
  }

  /// Validates whether a competition is strictly ready to generate a draw.
  /// Enforces hard gates on entrant counts, unresolved pool players, and squad minimums.
  DrawReadinessReport validateDrawReadiness({
    required Competition competition,
    required List<Entrant> entrants,
    required List<Registration> confirmedRegistrations,
  }) {
    final reasons = <String>[];

    // A withdrawn entrant is not in the field, so it neither counts towards
    // the minimum nor has to field a full side.
    final field = entrants.where((e) => !e.withdrawn).toList();

    if (field.length < 2) {
      reasons.add('At least 2 confirmed entrants are required to generate a draw.');
    }

    // `Competition.teamSize` is players *per side* — the number the sport
    // needs on the field — so a squad below it cannot play its first match.
    if (competition.entrantType == EntrantType.team && competition.teamSize != null) {
      final minSquad = competition.teamSize!;
      for (final e in field) {
        if (e.memberUids.length < minSquad) {
          reasons.add(
            '${e.displayName} has only ${e.memberUids.length} players (minimum $minSquad required).',
          );
        }
      }
    }

    // Check for unresolved pool registrations
    final entrantUids = <String>{
      for (final e in field) ...[
        if (e.uid != null) e.uid!,
        ...e.memberUids,
      ],
    };

    final unresolved = confirmedRegistrations
        .where((r) => !entrantUids.contains(r.uid))
        .toList();

    if (unresolved.isNotEmpty) {
      reasons.add(
        '${unresolved.length} confirmed player${unresolved.length == 1 ? '' : 's'} remain in the draft pool unassigned to any squad.',
      );
    }

    if (reasons.isEmpty) {
      return DrawReadinessReport.ready();
    }
    return DrawReadinessReport.blocked(reasons, unresolved);
  }

  static String _squadName(int index, List<String>? customNames) {
    if (customNames != null && index < customNames.length) {
      return customNames[index];
    }
    if (index < defaultSquadNames.length) {
      return defaultSquadNames[index];
    }
    return 'Team ${index + 1}';
  }
}
