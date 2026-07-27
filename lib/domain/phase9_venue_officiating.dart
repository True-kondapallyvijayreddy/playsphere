import 'package:equatable/equatable.dart';

import 'enums.dart';

/// PHASE 9 — Venue & Officiating Marketplace *(design sketch only —
/// not build-ready per spec)*.
///
/// Minimum viable objects to unblock Phase 4's Fixture.venueId and
/// Fixture.officiatedByUserId at scale. Do not start building real
/// logic against these until Phase 4 is stable in production — see
/// spec §Phase 9 note. Modeled here purely to reserve the shape.

class VenueEntity extends Equatable {
  const VenueEntity({
    required this.id,
    required this.orgId,
    required this.name,
    required this.address,
    required this.geoLat,
    required this.geoLng,
    required this.sportIdsSupported,
    required this.bookingUnit,
    required this.capacity,
  });

  final String id;

  /// owner org.
  final String orgId;
  final String name;
  final String address;
  final double geoLat;
  final double geoLng;
  final List<String> sportIdsSupported;
  final BookingUnit bookingUnit;
  final int capacity;

  @override
  List<Object?> get props => [
        id,
        orgId,
        name,
        address,
        geoLat,
        geoLng,
        sportIdsSupported,
        bookingUnit,
        capacity,
      ];
}

class VenueBookingEntity extends Equatable {
  const VenueBookingEntity({
    required this.id,
    required this.venueId,
    required this.fixtureId,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  final String id;
  final String venueId;
  final String fixtureId;
  final DateTime startTime;
  final DateTime endTime;
  final VenueBookingStatus status;

  // TODO(business-rules, enforce in service layer — none implemented
  // yet): needs a conflict-check constraint — no two `confirmed`
  // bookings may overlap on the same venue.

  @override
  List<Object?> get props =>
      [id, venueId, fixtureId, startTime, endTime, status];
}

class OfficialRegistryEntity extends Equatable {
  const OfficialRegistryEntity({
    required this.id,
    required this.userId,
    required this.sportId,
    required this.certificationLevel,
    required this.certifyingBody,
    required this.status,
    this.certificateDocUrl,
  });

  final String id;
  final String userId;
  final String sportId;
  final String certificationLevel;
  final String certifyingBody;
  final String? certificateDocUrl;
  final OfficialCertificationStatus status;

  @override
  List<Object?> get props => [
        id,
        userId,
        sportId,
        certificationLevel,
        certifyingBody,
        certificateDocUrl,
        status,
      ];
}

class OfficialAssignmentEntity extends Equatable {
  const OfficialAssignmentEntity({
    required this.id,
    required this.fixtureId,
    required this.officialUserId,
    required this.role,
    required this.status,
  });

  final String id;
  final String fixtureId;
  final String officialUserId;
  final OfficialAssignmentRole role;
  final OfficialAssignmentStatus status;

  @override
  List<Object?> get props =>
      [id, fixtureId, officialUserId, role, status];
}
