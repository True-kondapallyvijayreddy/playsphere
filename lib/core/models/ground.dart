import 'package:cloud_firestore/cloud_firestore.dart';

import 'billing.dart';
import 'firestore_codec.dart';

/// A ground somebody rents out by the hour, at `grounds/{groundId}`.
///
/// ## Why this is not a [Venue]
///
/// The two look alike and are opposites. A `Venue` is a club's own hall,
/// declared once so the club's own draws can be allocated against its courts;
/// it lives at `orgs/{orgId}/venues/{venueId}` and means nothing outside that
/// club. A ground is a business, owned by someone who is not a member of any
/// club, rented to whoever books it first.
///
/// Nesting a ground under an org would make the only question that matters —
/// "what cricket grounds near Hyderabad are free on Sunday evening?" —
/// unanswerable without reading every club in the country, and would make the
/// ground's owner a member of a club they have no relationship with.
///
/// A club that books a ground for an event still gets its scheduling handled
/// through its own `Venue` record; the two connect through [GroundBooking],
/// which is the receipt, not the resource.
class Ground {
  const Ground({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.city,
    this.address,
    this.district,
    this.latitude,
    this.longitude,
    this.sportIds = const [],
    this.hourlyRatePaise = 0,
    this.openHour = 6,
    this.closeHour = 22,
    this.facilities = const [],
    this.surface,
    this.isIndoor = false,
    this.capacity,
    this.contactPhone,
    this.photoUrl,
    this.notes,
    this.isActive = true,
    this.isVerified = false,
    this.bookingCount = 0,
    this.createdAt,
  });

  final String id;

  /// The person who takes the money and controls the calendar.
  ///
  /// A single uid, not a list. Co-owners are a real thing and deliberately
  /// not modelled yet: the security rule for "may edit this ground" is the
  /// one guarding somebody's income, and a one-line owner check is a rule
  /// that can be read and trusted. Adding managers later is a strictly easier
  /// change than un-shipping a permissive rule.
  final String ownerUid;

  final String name;

  /// Required, unlike on a venue.
  ///
  /// A ground nobody can find is a ground nobody books, and city is the level
  /// people actually search at — "grounds in Warangal", never "grounds within
  /// 4.7km". Stored lowercased in [cityKey] for querying, and verbatim here
  /// for display.
  final String city;

  final String? address;
  final String? district;

  /// Present for the map pin and for distance sorting once that exists. The
  /// search deliberately does not depend on them: a ground owner filling in a
  /// form on a phone will type a city name and will not drop a map pin, and a
  /// listing that cannot be found until someone geocodes it is a listing that
  /// never goes live.
  final double? latitude;
  final double? longitude;

  /// Which sports can actually be played here. Drives the search filter, so
  /// an empty list means the ground appears for every sport — correct for a
  /// bare multi-purpose maidan, wrong for a badminton hall, which is why the
  /// registration form asks.
  final List<String> sportIds;

  /// Price per hour in paise. Zero means the owner has listed it free, which
  /// happens with school and panchayat grounds and is a legitimate listing
  /// rather than a missing field.
  final int hourlyRatePaise;

  /// When the gates open and shut, in local hours. A booking outside this
  /// window is rejected before it is ever offered — see [isWithinHours].
  final int openHour;
  final int closeHour;

  /// "Floodlights", "Parking", "Changing rooms", "Drinking water". Free text
  /// for the same reason `Court.surface` is: the useful list differs between
  /// a turf in Hyderabad and a village ground, and a fixed enum would need a
  /// release to add "Sight screen".
  final List<String> facilities;

  final String? surface;
  final bool isIndoor;
  final int? capacity;
  final String? contactPhone;
  final String? photoUrl;
  final String? notes;

  /// Owner-controlled. An owner going away for a month switches this off
  /// rather than deleting the ground, so the bookings already taken against
  /// it still resolve to a real place.
  final bool isActive;

  /// Set by PlaySphere, never by the owner — the client cannot write it and
  /// `firestore.rules` enforces that. An owner who could tick their own
  /// "verified" box makes the badge worthless.
  final bool isVerified;

  final int bookingCount;
  final DateTime? createdAt;

  /// The lowercased city, for equality queries. Firestore has no
  /// case-insensitive matching, so "Hyderabad" and "hyderabad" are different
  /// documents to a `where` clause unless one canonical form is stored.
  String get cityKey => city.trim().toLowerCase();

  bool get isFree => hourlyRatePaise == 0;

  String get rateLabel =>
      isFree ? 'Free' : '${Pricing.formatPaise(hourlyRatePaise)}/hour';

  bool servesSport(String sportId) =>
      sportIds.isEmpty || sportIds.contains(sportId);

  /// Whether a slot falls inside the ground's opening hours.
  ///
  /// [endHour] is exclusive, so a ground closing at 22 can be booked 21–22.
  bool isWithinHours(int startHour, int endHour) =>
      startHour >= openHour && endHour <= closeHour && startHour < endHour;

  /// What a slot of [hours] costs here.
  int priceForPaise(int hours) => hourlyRatePaise * hours;

  factory Ground.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Ground(
      id: doc.id,
      ownerUid: Fs.str(d['ownerUid']),
      name: Fs.str(d['name'], 'Ground'),
      city: Fs.str(d['city']),
      address: Fs.strOrNull(d['address']),
      district: Fs.strOrNull(d['district']),
      latitude: d['latitude'] is num ? (d['latitude'] as num).toDouble() : null,
      longitude:
          d['longitude'] is num ? (d['longitude'] as num).toDouble() : null,
      sportIds: Fs.strList(d['sportIds']),
      hourlyRatePaise: Fs.integer(d['hourlyRatePaise']),
      openHour: Fs.integer(d['openHour'], 6),
      closeHour: Fs.integer(d['closeHour'], 22),
      facilities: Fs.strList(d['facilities']),
      surface: Fs.strOrNull(d['surface']),
      isIndoor: Fs.boolean(d['isIndoor']),
      capacity: Fs.intOrNull(d['capacity']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      notes: Fs.strOrNull(d['notes']),
      isActive: Fs.boolean(d['isActive'], true),
      isVerified: Fs.boolean(d['isVerified']),
      bookingCount: Fs.integer(d['bookingCount']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        ...toUpdate(),
        'ownerUid': ownerUid,
        // Never from the client. Listed explicitly rather than simply omitted
        // so the intent survives someone later "tidying up" the create map.
        'isVerified': false,
        'bookingCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Everything the owner may edit. Excludes [ownerUid], [isVerified] and
  /// [bookingCount] — one is identity, one is PlaySphere's judgement, and one
  /// is a counter the booking transaction maintains.
  Map<String, Object?> toUpdate() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'city': city.trim(),
        'cityKey': cityKey,
        'address': address,
        'district': district,
        'latitude': latitude,
        'longitude': longitude,
        'sportIds': sportIds,
        'hourlyRatePaise': hourlyRatePaise,
        'openHour': openHour,
        'closeHour': closeHour,
        'facilities': facilities,
        'surface': surface,
        'isIndoor': isIndoor,
        'capacity': capacity,
        'contactPhone': contactPhone,
        'photoUrl': photoUrl,
        'notes': notes,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Ground copyWith({
    String? name,
    String? city,
    String? address,
    String? district,
    List<String>? sportIds,
    int? hourlyRatePaise,
    int? openHour,
    int? closeHour,
    List<String>? facilities,
    String? surface,
    bool? isIndoor,
    int? capacity,
    String? contactPhone,
    String? notes,
    bool? isActive,
  }) =>
      Ground(
        id: id,
        ownerUid: ownerUid,
        name: name ?? this.name,
        city: city ?? this.city,
        address: address ?? this.address,
        district: district ?? this.district,
        latitude: latitude,
        longitude: longitude,
        sportIds: sportIds ?? this.sportIds,
        hourlyRatePaise: hourlyRatePaise ?? this.hourlyRatePaise,
        openHour: openHour ?? this.openHour,
        closeHour: closeHour ?? this.closeHour,
        facilities: facilities ?? this.facilities,
        surface: surface ?? this.surface,
        isIndoor: isIndoor ?? this.isIndoor,
        capacity: capacity ?? this.capacity,
        contactPhone: contactPhone ?? this.contactPhone,
        photoUrl: photoUrl,
        notes: notes ?? this.notes,
        isActive: isActive ?? this.isActive,
        isVerified: isVerified,
        bookingCount: bookingCount,
        createdAt: createdAt,
      );
}

/// One hour-range held on one ground, at `grounds/{groundId}/bookings/{id}`.
///
/// ## Why the slot is stored as a day plus two integer hours
///
/// The obvious modelling is two timestamps. It makes the double-booking check
/// far harder than it needs to be: Firestore cannot express "overlaps" as a
/// query, so an interval search becomes a range read plus client-side
/// filtering, and the transaction has to reason about instants in a timezone
/// nobody agreed on.
///
/// A ground is booked in whole hours on a named day — that is how the owner
/// thinks and how the money is charged. So the day is a plain `yyyy-MM-dd`
/// key and the slot is `[startHour, endHour)` in the ground's local time. The
/// conflict check becomes "read this ground's bookings for this dayKey, and
/// see whether any of them overlaps", which is one small indexed query the
/// booking transaction can afford.
class GroundBooking {
  const GroundBooking({
    required this.id,
    required this.groundId,
    required this.groundName,
    required this.dayKey,
    required this.startHour,
    required this.endHour,
    required this.bookedByUid,
    required this.bookedByName,
    required this.status,
    this.bookedForOrgId,
    this.competitionId,
    this.sportId,
    this.amountPaise = 0,
    this.paymentId,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String groundId;

  /// Denormalized so "my bookings" can be rendered from the collectionGroup
  /// query alone. Resolving each ground would be one extra read per row, on a
  /// screen whose whole job is to list rows.
  final String groundName;

  /// `yyyy-MM-dd` in the ground's local time. See the class comment.
  final String dayKey;

  /// Half-open: `[startHour, endHour)`. A 18–20 booking occupies 18 and 19,
  /// so another 20–22 booking does not conflict with it.
  final int startHour;
  final int endHour;

  final String bookedByUid;
  final String bookedByName;

  /// The club the ground was booked for, when it was booked from an event.
  final String? bookedForOrgId;

  /// The competition this was booked for, so cancelling the event can find
  /// the booking it should release.
  final String? competitionId;

  final String? sportId;
  final int amountPaise;

  /// The `payments/{id}` row, when money changed hands.
  final String? paymentId;

  final String? notes;
  final GroundBookingStatus status;
  final DateTime? createdAt;

  int get hours => endHour - startHour;

  /// Whether this booking occupies any hour that [other] also would.
  ///
  /// Half-open intervals overlap exactly when each starts before the other
  /// ends. Written as a plain function so the rule is testable without
  /// Firestore — the double-booking check is the one piece of this feature
  /// that must not be got wrong, because getting it wrong means two teams
  /// turning up to the same pitch.
  bool overlaps(int otherStart, int otherEnd) =>
      startHour < otherEnd && otherStart < endHour;

  /// Only a live booking blocks a slot. A cancelled one stays in the
  /// collection as a record and must not hold the hour hostage.
  bool get holdsSlot => status == GroundBookingStatus.confirmed;

  factory GroundBooking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return GroundBooking(
      id: doc.id,
      groundId: Fs.str(d['groundId']),
      groundName: Fs.str(d['groundName'], 'Ground'),
      dayKey: Fs.str(d['dayKey']),
      startHour: Fs.integer(d['startHour']),
      endHour: Fs.integer(d['endHour']),
      bookedByUid: Fs.str(d['bookedByUid']),
      bookedByName: Fs.str(d['bookedByName'], 'Someone'),
      bookedForOrgId: Fs.strOrNull(d['bookedForOrgId']),
      competitionId: Fs.strOrNull(d['competitionId']),
      sportId: Fs.strOrNull(d['sportId']),
      amountPaise: Fs.integer(d['amountPaise']),
      paymentId: Fs.strOrNull(d['paymentId']),
      notes: Fs.strOrNull(d['notes']),
      status: GroundBookingStatus.fromWire(Fs.str(d['status'])),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'groundId': groundId,
        'groundName': groundName,
        'dayKey': dayKey,
        'startHour': startHour,
        'endHour': endHour,
        'startsAt': Fs.ts(startsAt),
        'bookedByUid': bookedByUid,
        'bookedByName': bookedByName,
        'bookedForOrgId': bookedForOrgId,
        'competitionId': competitionId,
        'sportId': sportId,
        'amountPaise': amountPaise,
        'paymentId': paymentId,
        'notes': notes,
        'status': status.wire,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// The instant the slot begins, derived from [dayKey] and [startHour].
  ///
  /// Written alongside the parts rather than instead of them: the parts are
  /// what the conflict check queries, and this is what "my bookings, soonest
  /// first" orders by. Neither can do the other's job.
  DateTime get startsAt {
    final parts = dayKey.split('-');
    if (parts.length != 3) return DateTime.now();
    return DateTime(
      int.tryParse(parts[0]) ?? 1970,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
      startHour,
    );
  }

  /// `yyyy-MM-dd` for a date. The one place this format is produced, so the
  /// key a booking is written under and the key a search reads by cannot
  /// drift apart.
  static String dayKeyOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

enum GroundBookingStatus {
  /// The slot is held. The only status that blocks anyone else.
  confirmed('confirmed', 'Confirmed'),

  /// Released by the person who booked it, or by the owner.
  cancelled('cancelled', 'Cancelled'),

  /// The slot has passed. Set by the owner's screen when they settle up, and
  /// kept distinct from [confirmed] so "what is coming up" is a query rather
  /// than a date comparison over every booking ever made.
  completed('completed', 'Completed');

  const GroundBookingStatus(this.wire, this.label);
  final String wire;
  final String label;

  static GroundBookingStatus fromWire(String? w) =>
      GroundBookingStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => GroundBookingStatus.confirmed,
      );
}

/// Which hours of one day on one ground are already taken.
///
/// Built from the day's bookings once, then asked about each candidate slot,
/// rather than re-scanning the list per slot. The search screen offers every
/// hour the ground is open, so this gets asked sixteen times a ground.
class DayAvailability {
  DayAvailability(this.ground, Iterable<GroundBooking> bookings)
      : _taken = {
          for (final b in bookings)
            if (b.holdsSlot)
              for (var h = b.startHour; h < b.endHour; h++) h,
        };

  final Ground ground;
  final Set<int> _taken;

  /// Whether `[startHour, endHour)` can be booked.
  ///
  /// Checks the opening hours as well as the clashes, because a slot outside
  /// them is unbookable for a reason the person needs told differently —
  /// "the ground is shut then", not "somebody else has it".
  bool isFree(int startHour, int endHour) {
    if (!ground.isWithinHours(startHour, endHour)) return false;
    for (var h = startHour; h < endHour; h++) {
      if (_taken.contains(h)) return false;
    }
    return true;
  }

  bool isHourTaken(int hour) => _taken.contains(hour);

  /// Every start hour at which a slot of [hours] would fit.
  ///
  /// What the booking sheet renders. Returning the whole set at once means
  /// the person sees their options rather than discovering one at a time that
  /// the time they wanted is gone.
  List<int> startsFitting(int hours) => [
        for (var h = ground.openHour; h + hours <= ground.closeHour; h++)
          if (isFree(h, h + hours)) h,
      ];
}
