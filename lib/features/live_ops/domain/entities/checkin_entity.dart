import 'package:equatable/equatable.dart';

/// Blueprint §12 - Live Operations (QR check-in / attendance).
class CheckinEntity extends Equatable {
  const CheckinEntity({
    required this.id,
    required this.eventId,
    required this.memberId,
    required this.checkedInAt,
  });

  final String id;
  final String eventId;
  final String memberId;
  final DateTime checkedInAt;

  @override
  List<Object?> get props => [id, eventId, memberId, checkedInAt];
}
