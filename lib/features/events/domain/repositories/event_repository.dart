import '../entities/event_entity.dart';

/// Domain-facing contract for event data access. Presentation code
/// (state notifiers/controllers) depends on this abstraction, not on
/// the concrete Dio/Firestore implementation, so the data source can
/// be swapped or mocked in tests.
abstract class EventRepository {
  Future<List<EventEntity>> getEvents(String orgId);

  Future<EventEntity> getEvent(String orgId, String eventId);

  Future<EventEntity> createEvent(EventEntity event);

  Future<EventEntity> updateEvent(EventEntity event);

  Future<void> deleteEvent(String orgId, String eventId);

  /// Advances an event through its lifecycle
  /// (Draft -> Published -> ... -> Archive, Blueprint §7).
  Future<EventEntity> transitionStage(
    String orgId,
    String eventId,
    String targetStage,
  );
}
