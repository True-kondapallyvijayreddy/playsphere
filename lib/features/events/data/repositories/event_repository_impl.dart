import 'package:dio/dio.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/event_entity.dart';
import '../../domain/repositories/event_repository.dart';
import '../models/event_model.dart';

/// REST-backed implementation of [EventRepository]. Swap this out (or
/// add a sibling `EventRepositoryFirestoreImpl`) without touching any
/// presentation code, since callers only depend on the interface.
class EventRepositoryImpl implements EventRepository {
  EventRepositoryImpl({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  @override
  Future<List<EventEntity>> getEvents(String orgId) async {
    try {
      final res = await _dio.get('/orgs/$orgId/events');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      return data.map((e) => EventModel.fromJson(e).toEntity()).toList();
    } on DioException catch (_) {
      throw const NetworkException();
    }
  }

  @override
  Future<EventEntity> getEvent(String orgId, String eventId) async {
    try {
      final res = await _dio.get('/orgs/$orgId/events/$eventId');
      return EventModel.fromJson(res.data as Map<String, dynamic>).toEntity();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const NotFoundException();
      throw const NetworkException();
    }
  }

  @override
  Future<EventEntity> createEvent(EventEntity event) async {
    final body = EventModel.fromEntity(event).toJson();
    final res = await _dio.post('/orgs/${event.orgId}/events', data: body);
    return EventModel.fromJson(res.data as Map<String, dynamic>).toEntity();
  }

  @override
  Future<EventEntity> updateEvent(EventEntity event) async {
    final body = EventModel.fromEntity(event).toJson();
    final res = await _dio.put(
      '/orgs/${event.orgId}/events/${event.id}',
      data: body,
    );
    return EventModel.fromJson(res.data as Map<String, dynamic>).toEntity();
  }

  @override
  Future<void> deleteEvent(String orgId, String eventId) async {
    await _dio.delete('/orgs/$orgId/events/$eventId');
  }

  @override
  Future<EventEntity> transitionStage(
    String orgId,
    String eventId,
    String targetStage,
  ) async {
    final res = await _dio.post(
      '/orgs/$orgId/events/$eventId/transition',
      data: {'stage': targetStage},
    );
    return EventModel.fromJson(res.data as Map<String, dynamic>).toEntity();
  }
}
