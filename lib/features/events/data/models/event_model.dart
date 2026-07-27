import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/event_entity.dart';

/// Data-layer model responsible for JSON <-> [EventEntity] conversion.
/// Kept separate from the domain entity so API/DB shape changes never
/// leak into business logic or UI.
class EventModel {
  const EventModel({
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
  final String category;
  final String stage;
  final String venue;
  final DateTime startDate;
  final DateTime endDate;
  final bool isTeamEvent;
  final String? description;
  final int? capacity;
  final int? registrationFeeCents;

  factory EventModel.fromJson(Map<String, dynamic> json) => EventModel(
        id: json['id'] as String,
        orgId: json['org_id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        stage: json['stage'] as String,
        venue: json['venue'] as String,
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        isTeamEvent: json['is_team_event'] as bool,
        description: json['description'] as String?,
        capacity: json['capacity'] as int?,
        registrationFeeCents: json['registration_fee_cents'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'org_id': orgId,
        'name': name,
        'category': category,
        'stage': stage,
        'venue': venue,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'is_team_event': isTeamEvent,
        'description': description,
        'capacity': capacity,
        'registration_fee_cents': registrationFeeCents,
      };

  EventEntity toEntity() => EventEntity(
        id: id,
        orgId: orgId,
        name: name,
        category: EventCategory.values.byName(category),
        stage: EventStage.values.byName(stage),
        venue: venue,
        startDate: startDate,
        endDate: endDate,
        isTeamEvent: isTeamEvent,
        description: description,
        capacity: capacity,
        registrationFeeCents: registrationFeeCents,
      );

  factory EventModel.fromEntity(EventEntity entity) => EventModel(
        id: entity.id,
        orgId: entity.orgId,
        name: entity.name,
        category: entity.category.name,
        stage: entity.stage.name,
        venue: entity.venue,
        startDate: entity.startDate,
        endDate: entity.endDate,
        isTeamEvent: entity.isTeamEvent,
        description: entity.description,
        capacity: entity.capacity,
        registrationFeeCents: entity.registrationFeeCents,
      );
}
