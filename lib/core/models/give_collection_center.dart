import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// A physical PlaySphere Give drop-off point, at
/// `giveCollectionCenters/{centerId}`.
///
/// ## Curated like `products`, not self-listed like `grounds`
///
/// A ground is somebody else's business, self-registered and
/// self-maintained — PlaySphere just indexes it. A collection center is the
/// opposite: it is PlaySphere's own operation (or a formally onboarded
/// partner's), and a stranger being able to plant a fake one would let them
/// collect other people's donated equipment at an address PlaySphere's own
/// app vouches for. So this is server/console-written and world-readable,
/// the same trust shape as [ShopRepository]'s catalog — see
/// `firestore.rules` on `giveCollectionCenters`.
class GiveCollectionCenter {
  const GiveCollectionCenter({
    required this.id,
    required this.name,
    required this.city,
    this.address,
    this.contactPhone,
    this.latitude,
    this.longitude,
    this.acceptedCategories = const [],
    this.isActive = true,
    this.notes,
  });

  final String id;
  final String name;

  /// Same convention as `Ground.city`/`cityKey` — a flat, lowercase-matched
  /// city string, because donors search "collection centres in Hyderabad",
  /// never a mandal.
  final String city;

  final String? address;
  final String? contactPhone;
  final double? latitude;
  final double? longitude;

  /// Empty means "accepts everything" — the common case for a general
  /// center. A specialised one (a cricket academy's own drop-off) can narrow
  /// this so a donor isn't sent there with a pair of football boots.
  final List<EquipmentCategory> acceptedCategories;

  final bool isActive;
  final String? notes;

  String get cityKey => city.trim().toLowerCase();

  bool accepts(EquipmentCategory category) =>
      acceptedCategories.isEmpty || acceptedCategories.contains(category);

  factory GiveCollectionCenter.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return GiveCollectionCenter(
      id: doc.id,
      name: Fs.str(d['name'], 'PlaySphere Give Collection Centre'),
      city: Fs.str(d['city']),
      address: Fs.strOrNull(d['address']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      acceptedCategories: (d['acceptedCategories'] as List?)
              ?.whereType<String>()
              .map(EquipmentCategory.fromWire)
              .toList(growable: false) ??
          const [],
      isActive: Fs.boolean(d['isActive'], true),
      notes: Fs.strOrNull(d['notes']),
    );
  }

  Map<String, Object?> toMap() => Fs.prune({
        'name': name,
        'city': city,
        'cityKey': cityKey,
        'address': address,
        'contactPhone': contactPhone,
        'latitude': latitude,
        'longitude': longitude,
        'acceptedCategories':
            acceptedCategories.map((c) => c.wire).toList(growable: false),
        'isActive': isActive,
        'notes': notes,
      });
}
