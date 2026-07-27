import 'package:equatable/equatable.dart';

enum NotificationChannel { push, email, sms, whatsapp, inApp }

/// Blueprint §18 - Notification Engine.
class NotificationEntity extends Equatable {
  const NotificationEntity({
    required this.id,
    required this.orgId,
    required this.templateKey, // e.g. 'registration_approved', 'fixture_reminder'
    required this.channels,
    required this.recipientId,
    required this.createdAt,
    this.sentAt,
  });

  final String id;
  final String orgId;
  final String templateKey;
  final List<NotificationChannel> channels;
  final String recipientId;
  final DateTime createdAt;
  final DateTime? sentAt;

  @override
  List<Object?> get props =>
      [id, orgId, templateKey, channels, recipientId, createdAt, sentAt];
}
