import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One playing area inside a [Venue] — court 3 of a badminton hall, pitch 2
/// of a ground, table 5 of a table-tennis room.
///
/// ## Why this needs an id of its own
///
/// A court used to be a string typed into a text field, once per competition.
/// That is survivable for a single draw and impossible for a tournament: the
/// U-13 event's "Court 1" and the senior event's "Court 1" were unrelated
/// pieces of text, so nothing could tell that the two draws were competing for
/// the same physical court — which is precisely the contention that makes a
/// tournament day overrun. A stable id makes them the same court to every
/// event that uses it, and survives the court being renamed.
class Court {
  const Court({
    required this.id,
    required this.name,
    this.isIndoor = true,
    this.surface,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final bool isIndoor;

  /// "Wooden", "Synthetic", "Clay", "Turf" — free text, because the
  /// vocabulary differs by sport and no fixed list would survive contact with
  /// a village ground.
  final String? surface;

  /// A court that exists but cannot be used today — a broken net, a booked
  /// half of the hall. Kept rather than deleted so fixtures already scheduled
  /// on it still resolve to a name.
  final bool isAvailable;

  static Court fromMap(Map<String, dynamic> m) => Court(
        id: Fs.str(m['id']),
        name: Fs.str(m['name'], 'Court'),
        isIndoor: Fs.boolean(m['isIndoor'], true),
        surface: Fs.strOrNull(m['surface']),
        isAvailable: Fs.boolean(m['isAvailable'], true),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'isIndoor': isIndoor,
        'surface': surface,
        'isAvailable': isAvailable,
      };

  static List<Court> listFrom(Object? v) => v is List
      ? v
          .whereType<Map>()
          .map((m) => Court.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false)
      : const [];

  static List<Map<String, Object?>> listTo(List<Court> courts) =>
      [for (final c in courts) c.toMap()];

  Court copyWith({
    String? name,
    bool? isIndoor,
    String? surface,
    bool? isAvailable,
  }) =>
      Court(
        id: id,
        name: name ?? this.name,
        isIndoor: isIndoor ?? this.isIndoor,
        surface: surface ?? this.surface,
        isAvailable: isAvailable ?? this.isAvailable,
      );
}

/// A place matches are played, at `orgs/{orgId}/venues/{venueId}`.
///
/// ## Why a venue is an entity and not a string
///
/// `Competition.venue`, `Fixture.venue` and `Challenge.venue` were all free
/// text. That is enough to print on a card and not enough for anything else:
/// it cannot say how many courts a hall has, when it opens, or whether two
/// events are booked into the same room at the same hour. A tournament is
/// fundamentally a resource-allocation problem — fifteen events, six courts,
/// one day — and it cannot even be posed against a string.
///
/// Defining venues up front, once per club, is also the smaller amount of
/// work for the organizer: a club plays at the same two or three places all
/// season, and re-typing the court list into every event is how the court
/// list ends up inconsistent between events.
///
/// The hours live here rather than on the competition because they are a fact
/// about the building — a school hall that closes at 6pm closes at 6pm for
/// every event running in it.
class Venue {
  const Venue({
    required this.id,
    required this.orgId,
    required this.name,
    this.address,
    this.city,
    this.district,
    this.latitude,
    this.longitude,
    this.courts = const [],
    this.openHour = 6,
    this.closeHour = 22,
    this.notes,
    this.isArchived = false,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String name;

  final String? address;
  final String? city;

  /// Kept alongside [city] because the government reporting layer aggregates
  /// mandal → district → state, and a venue is where participation physically
  /// happened.
  final String? district;

  final double? latitude;
  final double? longitude;

  final List<Court> courts;

  /// When the building opens and closes, in local hours. The scheduler will
  /// not place a match outside this window.
  final int openHour;
  final int closeHour;

  final String? notes;

  /// Retired rather than deleted, so historic fixtures still name a real
  /// place. A venue that has hosted a match is part of the record.
  final bool isArchived;

  final String? createdBy;
  final DateTime? createdAt;

  /// Courts that can actually take a match today.
  List<Court> get usableCourts =>
      [for (final c in courts) if (c.isAvailable) c];

  /// How many matches this venue can run at once.
  int get capacity => usableCourts.length;

  /// How many matches of [matchMinutes] (plus changeover) one court can take
  /// in a day here. The number an organizer needs before they know whether a
  /// 38-entrant draw fits between breakfast and dark.
  int slotsPerCourtPerDay(int slotMinutes) {
    if (slotMinutes <= 0) return 0;
    return ((closeHour - openHour) * 60) ~/ slotMinutes;
  }

  bool get hasLocation => latitude != null && longitude != null;

  factory Venue.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Venue(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      name: Fs.str(d['name'], 'Venue'),
      address: Fs.strOrNull(d['address']),
      city: Fs.strOrNull(d['city']),
      district: Fs.strOrNull(d['district']),
      latitude: d['latitude'] == null ? null : Fs.decimal(d['latitude']),
      longitude: d['longitude'] == null ? null : Fs.decimal(d['longitude']),
      courts: Court.listFrom(d['courts']),
      openHour: Fs.integer(d['openHour'], 6),
      closeHour: Fs.integer(d['closeHour'], 22),
      notes: Fs.strOrNull(d['notes']),
      isArchived: Fs.boolean(d['isArchived']),
      createdBy: Fs.strOrNull(d['createdBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'address': address,
        'city': city,
        'district': district,
        'latitude': latitude,
        'longitude': longitude,
        'courts': Court.listTo(courts),
        'openHour': openHour,
        'closeHour': closeHour,
        'notes': notes,
        'isArchived': false,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, Object?> toUpdate() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'address': address,
        'city': city,
        'district': district,
        'latitude': latitude,
        'longitude': longitude,
        'courts': Court.listTo(courts),
        'openHour': openHour,
        'closeHour': closeHour,
        'notes': notes,
        'isArchived': isArchived,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// The same venue under a different document id.
  ///
  /// Exists for exactly one flow, and [copyWith] deliberately cannot do it:
  /// changing a saved venue's id would orphan every fixture, plan and event
  /// pointing at the old one. A ground typed into the season create form has
  /// no id until the form is submitted, and the form needs a local key to
  /// hang a plan and a category restriction on in the meantime — so the
  /// rekey is a separate, obviously-named method, used only on a venue that
  /// has never been written.
  Venue withId(String id) => Venue(
        id: id,
        orgId: orgId,
        name: name,
        address: address,
        city: city,
        district: district,
        latitude: latitude,
        longitude: longitude,
        courts: courts,
        openHour: openHour,
        closeHour: closeHour,
        notes: notes,
        isArchived: isArchived,
        createdBy: createdBy,
        createdAt: createdAt,
      );

  Venue copyWith({
    String? name,
    String? address,
    String? city,
    String? district,
    double? latitude,
    double? longitude,
    List<Court>? courts,
    int? openHour,
    int? closeHour,
    String? notes,
    bool? isArchived,
  }) =>
      Venue(
        id: id,
        orgId: orgId,
        name: name ?? this.name,
        address: address ?? this.address,
        city: city ?? this.city,
        district: district ?? this.district,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        courts: courts ?? this.courts,
        openHour: openHour ?? this.openHour,
        closeHour: closeHour ?? this.closeHour,
        notes: notes ?? this.notes,
        isArchived: isArchived ?? this.isArchived,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
