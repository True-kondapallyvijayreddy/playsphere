import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/event_repository_impl.dart';
import '../../domain/entities/event_entity.dart';
import '../../domain/repositories/event_repository.dart';

/// DI seam: presentation depends on [EventRepository] (interface),
/// this provider decides the concrete implementation.
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepositoryImpl();
});

/// Fetches the event list for a given organization. `family` keys the
/// cache per-orgId so switching organizations doesn't require manual
/// invalidation.
final eventListProvider =
    FutureProvider.family<List<EventEntity>, String>((ref, orgId) {
  final repo = ref.watch(eventRepositoryProvider);
  return repo.getEvents(orgId);
});

/// Fetches a single event by (orgId, eventId).
final eventDetailProvider = FutureProvider.family<EventEntity, (String, String)>(
  (ref, ids) {
    final repo = ref.watch(eventRepositoryProvider);
    return repo.getEvent(ids.$1, ids.$2);
  },
);
