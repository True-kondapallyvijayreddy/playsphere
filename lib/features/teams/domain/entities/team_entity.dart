import 'package:equatable/equatable.dart';

import '../../../../core/constants/app_constants.dart';

/// Blueprint §10 - Team Management.
class TeamEntity extends Equatable {
  const TeamEntity({
    required this.id,
    required this.eventId,
    required this.name,
    required this.formationMethod,
    required this.memberIds,
    this.captainId,
  });

  final String id;
  final String eventId;
  final String name;
  final TeamFormationMethod formationMethod;
  final List<String> memberIds;
  final String? captainId;

  @override
  List<Object?> get props =>
      [id, eventId, name, formationMethod, memberIds, captainId];
}
