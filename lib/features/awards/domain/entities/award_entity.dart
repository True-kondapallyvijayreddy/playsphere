import 'package:equatable/equatable.dart';

enum AwardType { winner, runnerUp, thirdPlace, participation, bestPlayer, fairPlay, volunteer }

/// Blueprint §15 - Awards & certificate generation.
class AwardEntity extends Equatable {
  const AwardEntity({
    required this.id,
    required this.eventId,
    required this.recipientId,
    required this.type,
    this.certificateUrl,
    this.qrVerificationCode,
  });

  final String id;
  final String eventId;
  final String recipientId;
  final AwardType type;
  final String? certificateUrl;
  final String? qrVerificationCode;

  @override
  List<Object?> get props =>
      [id, eventId, recipientId, type, certificateUrl, qrVerificationCode];
}
