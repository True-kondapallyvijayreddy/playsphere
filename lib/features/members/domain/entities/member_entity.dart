import 'package:equatable/equatable.dart';

import '../../../../core/constants/app_constants.dart';

/// Blueprint §6 - Member Module.
class MemberEntity extends Equatable {
  const MemberEntity({
    required this.id,
    required this.orgId,
    required this.fullName,
    required this.role,
    this.photoUrl,
    this.contactPhone,
    this.emergencyContact,
    this.medicalNotes,
    this.sports = const [],
    this.certifications = const [],
  });

  final String id;
  final String orgId;
  final String fullName;
  final UserRole role;
  final String? photoUrl;
  final String? contactPhone;
  final String? emergencyContact;
  final String? medicalNotes;
  final List<String> sports;
  final List<String> certifications;

  @override
  List<Object?> get props => [
        id,
        orgId,
        fullName,
        role,
        photoUrl,
        contactPhone,
        emergencyContact,
        medicalNotes,
        sports,
        certifications,
      ];
}
