import 'package:equatable/equatable.dart';

import '../../../../core/constants/app_constants.dart';

/// Blueprint §11 - Fixture Engine.
class FixtureEntity extends Equatable {
  const FixtureEntity({
    required this.id,
    required this.eventId,
    required this.format,
    required this.round,
    required this.teamAId,
    required this.teamBId,
    required this.scheduledAt,
    required this.venue,
    this.winnerTeamId,
  });

  final String id;
  final String eventId;
  final FixtureFormat format;
  final int round;
  final String teamAId;
  final String teamBId;
  final DateTime scheduledAt;
  final String venue;
  final String? winnerTeamId;

  @override
  List<Object?> get props => [
        id,
        eventId,
        format,
        round,
        teamAId,
        teamBId,
        scheduledAt,
        venue,
        winnerTeamId,
      ];
}
