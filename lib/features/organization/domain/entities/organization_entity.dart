import 'package:equatable/equatable.dart';

/// Blueprint §5 - Organization Module.
class OrganizationEntity extends Equatable {
  const OrganizationEntity({
    required this.id,
    required this.name,
    required this.timezone,
    this.logoUrl,
    this.themeColorHex,
    this.address,
    this.contactEmail,
  });

  final String id;
  final String name;
  final String timezone;
  final String? logoUrl;
  final String? themeColorHex;
  final String? address;
  final String? contactEmail;

  @override
  List<Object?> get props =>
      [id, name, timezone, logoUrl, themeColorHex, address, contactEmail];
}
