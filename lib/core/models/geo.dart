import 'firestore_codec.dart';

/// The four rungs of the Telangana Sports Policy reporting ladder, coarsest
/// last-but-one and finest last. Order matters: [GovAggregate] rollups and
/// [GeoLocation.rollUpTo] both index into this list, so re-ordering it would
/// silently swap what "district-level" means for every dashboard query.
enum GeoLevel {
  state,
  district,
  mandal,
  village;

  /// The level directly containing this one, or null for [state] — a state
  /// has no parent to roll up into.
  GeoLevel? get parent {
    final i = GeoLevel.values.indexOf(this);
    return i == 0 ? null : GeoLevel.values[i - 1];
  }
}

/// A place in the state → district → mandal → village hierarchy that every
/// government dashboard in §6 Module D pivots on.
///
/// Before this type existed, location lived as disconnected flat strings
/// (`Organization.district`, `Organization.city`, `LookingForPost.mandal`)
/// with no shared shape and no mandal on users at all — so a village's
/// participation numbers had nothing to roll up into and a state dashboard
/// could never be built from what the app actually stored. This is the one
/// place location is parsed, validated and rolled up, so every consumer
/// (profile screens, gov aggregates, exports) agrees on what "Warangal
/// district" means.
///
/// Deliberately a plain value type with no Firestore document of its own —
/// it is always embedded as a `geo` map inside a `users/{uid}` or
/// `orgs/{orgId}` document, never stored standalone.
class GeoLocation {
  const GeoLocation({
    this.state,
    this.district,
    this.mandal,
    this.village,
    this.pincode,
    this.lat,
    this.lng,
  });

  /// No location captured at all. The common case for a brand-new profile
  /// that has not been through location onboarding yet — callers must treat
  /// this the same as "unknown", never as a specific place.
  static const empty = GeoLocation();

  final String? state;
  final String? district;
  final String? mandal;
  final String? village;

  /// PIN code, kept separate from the named hierarchy because it does not
  /// map 1:1 onto mandal boundaries and is only ever used for delivery-style
  /// lookups (nearest venue), never for gov rollups.
  final String? pincode;

  final double? lat;
  final double? lng;

  bool get isEmpty =>
      state == null &&
      district == null &&
      mandal == null &&
      village == null &&
      pincode == null &&
      lat == null &&
      lng == null;

  bool get isNotEmpty => !isEmpty;

  /// The name at [level], or null if this location was never captured that
  /// granularly (e.g. a user who only ever picked a district has no mandal
  /// to report). Callers must treat null as "cannot place this row at this
  /// level" and exclude it from that level's rollup rather than guessing —
  /// a guessed mandal is worse than an honestly-smaller sample.
  String? rollUpTo(GeoLevel level) => switch (level) {
        GeoLevel.state => state,
        GeoLevel.district => district,
        GeoLevel.mandal => mandal,
        GeoLevel.village => village,
      };

  factory GeoLocation.fromMap(Map<String, dynamic> m) => GeoLocation(
        state: Fs.strOrNull(m['state']),
        district: Fs.strOrNull(m['district']),
        mandal: Fs.strOrNull(m['mandal']),
        village: Fs.strOrNull(m['village']),
        pincode: Fs.strOrNull(m['pincode']),
        lat: _numOrNull(m['lat']),
        lng: _numOrNull(m['lng']),
      );

  static double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

  /// Reads location off a parent document, preferring the nested `geo` map
  /// this type introduced but falling back to whatever flat fields the
  /// document was written with before it existed.
  ///
  /// This is the backward-compatibility seam: every `users/{uid}` and
  /// `orgs/{orgId}` document written before this change has no `geo` field
  /// at all, and `orgs/{orgId}` documents additionally carry legacy flat
  /// `district`/`city` strings that predate the hierarchy. Without this
  /// fallback, deploying this model would make every existing org's location
  /// vanish from the app the instant it shipped — the fallback is what lets
  /// old documents keep rendering correctly until they are next saved (at
  /// which point [toMap] writes the nested `geo` map going forward).
  ///
  /// [legacyVillageKey] maps a legacy flat field onto [village] rather than
  /// [mandal] deliberately: at the time those flat fields were the *only*
  /// location data available, `city`/locality was the most granular thing a
  /// club recorded — closer in spirit to a village/town than to a mandal
  /// (an administrative unit nobody was asked to pick). It is a best-effort
  /// placement, not a claim of accuracy; it disappears the moment the
  /// document is re-saved with real hierarchy data.
  factory GeoLocation.fromDocData(
    Map<String, dynamic> d, {
    String field = 'geo',
    String? legacyDistrictKey = 'district',
    String? legacyVillageKey,
  }) {
    final nested = Fs.map(d[field]);
    if (nested.isNotEmpty) return GeoLocation.fromMap(nested);

    final legacyDistrict =
        legacyDistrictKey == null ? null : Fs.strOrNull(d[legacyDistrictKey]);
    final legacyVillage =
        legacyVillageKey == null ? null : Fs.strOrNull(d[legacyVillageKey]);
    if (legacyDistrict == null && legacyVillage == null) return empty;
    return GeoLocation(district: legacyDistrict, village: legacyVillage);
  }

  /// Payload for the nested `geo` map. Pruned of nulls so a partially-filled
  /// location (state + district only) does not write explicit nulls that
  /// would clobber sibling fields set by a concurrent writer.
  Map<String, Object?> toMap() => Fs.prune({
        'state': state,
        'district': district,
        'mandal': mandal,
        'village': village,
        'pincode': pincode,
        'lat': lat,
        'lng': lng,
      });

  GeoLocation copyWith({
    String? state,
    String? district,
    String? mandal,
    String? village,
    String? pincode,
    double? lat,
    double? lng,
  }) =>
      GeoLocation(
        state: state ?? this.state,
        district: district ?? this.district,
        mandal: mandal ?? this.mandal,
        village: village ?? this.village,
        pincode: pincode ?? this.pincode,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );

  @override
  bool operator ==(Object other) =>
      other is GeoLocation &&
      other.state == state &&
      other.district == district &&
      other.mandal == mandal &&
      other.village == village &&
      other.pincode == pincode &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode =>
      Object.hash(state, district, mandal, village, pincode, lat, lng);

  @override
  String toString() =>
      'GeoLocation(state: $state, district: $district, mandal: $mandal, '
      'village: $village)';
}
