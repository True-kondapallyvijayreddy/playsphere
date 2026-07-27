import 'package:equatable/equatable.dart';

enum MediaType { photo, video, streamLink }

/// Blueprint §14 - Media Module.
class MediaAssetEntity extends Equatable {
  const MediaAssetEntity({
    required this.id,
    required this.eventId,
    required this.type,
    required this.url,
    required this.uploadedAt,
    this.albumId,
    this.caption,
  });

  final String id;
  final String eventId;
  final MediaType type;
  final String url;
  final DateTime uploadedAt;
  final String? albumId;
  final String? caption;

  @override
  List<Object?> get props =>
      [id, eventId, type, url, uploadedAt, albumId, caption];
}
