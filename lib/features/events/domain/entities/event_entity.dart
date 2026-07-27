import 'package:equatable/equatable.dart';

import '../../../../core/constants/app_constants.dart';

/// Pure domain representation of an Event, independent of any
/// JSON/DB shape. Mirrors the configurable fields from Blueprint §7.
class EventEntity extends Equatable {
  const EventEntity({
    required this.id,
    required this.orgId,
    required this.name,
    required this.category,
    required this.stage,
    required this.venue,
    required this.startDate,
    required this.endDate,
    required this.isTeamEvent,
    this.description,
    this.capacity,
    this.registrationFeeCents,
  });

  final String id;
  final String orgId;
  final String name;
  final EventCategory category;
  final EventStage stage;
  final String venue;
  final DateTime startDate;
  final DateTime endDate;
  final bool isTeamEvent;
  final String? description;
  final int? capacity;
  final int? registrationFeeCents;

  @override
  List<Object?> get props => [
        id,
        orgId,
        name,
        category,
        stage,
        venue,
        startDate,
        endDate,
        isTeamEvent,
        description,
        capacity,
        registrationFeeCents,
      ];
}
