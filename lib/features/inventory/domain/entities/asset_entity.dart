import 'package:equatable/equatable.dart';

enum AssetAvailability { available, inUse, maintenance, retired }

/// Blueprint §17 - Inventory (equipment, chairs, sound systems,
/// medical kits, medals, trophies, ...).
class AssetEntity extends Equatable {
  const AssetEntity({
    required this.id,
    required this.orgId,
    required this.name,
    required this.category,
    required this.availability,
    this.assignedEventId,
    this.lastMaintainedAt,
  });

  final String id;
  final String orgId;
  final String name;
  final String category;
  final AssetAvailability availability;
  final String? assignedEventId;
  final DateTime? lastMaintainedAt;

  @override
  List<Object?> get props => [
        id,
        orgId,
        name,
        category,
        availability,
        assignedEventId,
        lastMaintainedAt,
      ];
}
