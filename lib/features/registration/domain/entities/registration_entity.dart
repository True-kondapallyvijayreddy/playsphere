import 'package:equatable/equatable.dart';

enum RegistrationStatus { pending, approved, waitlisted, rejected, refunded }

/// Blueprint §9 - Registration Module.
class RegistrationEntity extends Equatable {
  const RegistrationEntity({
    required this.id,
    required this.eventId,
    required this.memberId,
    required this.status,
    required this.registeredAt,
    this.teamId,
    this.couponCode,
    this.amountPaidCents,
  });

  final String id;
  final String eventId;
  final String memberId;
  final RegistrationStatus status;
  final DateTime registeredAt;
  final String? teamId;
  final String? couponCode;
  final int? amountPaidCents;

  @override
  List<Object?> get props => [
        id,
        eventId,
        memberId,
        status,
        registeredAt,
        teamId,
        couponCode,
        amountPaidCents,
      ];
}
