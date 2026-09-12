import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/geo/geohash.dart';
import '../../domain/gov/age_group.dart';
import 'app_user.dart';
import 'enums.dart';
import 'firestore_codec.dart';
import 'geo.dart';

/// What somebody is hoping to find. Multi-select: a person who has just moved
/// usually wants a club AND people to practise with, and forcing them to pick
/// one makes them invisible to half the people who could help.
enum PlayerIntent {
  club('club', 'A club to join'),
  team('team', 'A team that needs players'),
  practice('practice', 'People to practise with'),
  coaching('coaching', 'Coaching'),
  officiating('officiating', 'Matches to officiate');

  const PlayerIntent(this.wire, this.label);

  final String wire;
  final String label;

  static PlayerIntent? fromWire(String? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }

  static List<PlayerIntent> setFrom(List<String> wires) =>
      [for (final w in wires) if (fromWire(w) != null) fromWire(w)!];

  static List<String> wiresOf(Iterable<PlayerIntent> intents) =>
      [for (final i in intents) i.wire];
}

/// A person who has asked to be findable, at `playerDirectory/{uid}`.
///
/// ## Why this is not a query over `users`
///
/// The product's whole answer to "I moved to a new city and know nobody" has
/// to be a search, and `users/{uid}` cannot serve one. `firestore.rules` will
/// only `list` that collection for documents that are already plainly visible
/// — and even where the rule would pass, a query over profiles means running
/// every discovery filter against the one document that also holds a birth
/// date, a phone number and an email address. A near-me feature does not need
/// any of those, so it should not be reading the document that has them.
///
/// So findability is a separate, opt-in, purpose-built document, exactly the
/// way `playerCodes` already is: small, public to signed-in users, and
/// containing only what its owner deliberately published. Nobody appears here
/// by being registered. They appear by choosing to.
///
/// ## Adults only, deliberately
///
/// A minor cannot create one of these — `firestore.rules` reads their date of
/// birth and refuses. A searchable, location-bearing directory of children is
/// not a feature this product is going to ship by accident, and the existing
/// guardian-consent path (`users/{minorUid}/guardianConsents/{granteeUid}`)
/// is the deliberate, per-grantee route that already exists for the cases
/// where a junior genuinely does need to be discoverable. Juniors new to a
/// place are served by the club half of discovery, which needs no listing.
///
/// ## Location is as coarse as the owner leaves it
///
/// [geo] carries district and state, and carries a point ONLY if its owner
/// tapped "use my current location" — the same opt-in the ground form uses.
/// Without a point there is no [geohash], the listing simply does not appear
/// in radius results, and it is still found by district. Nothing here ever
/// stores a village or an address.
class PlayerListing {
  const PlayerListing({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.playerCode,
    this.sportIds = const [],
    this.intents = const [],
    this.ageGroup,
    this.gender,
    this.geo = GeoLocation.empty,
    this.geohash,
    this.note,
    this.matchesPlayed = 0,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? playerCode;

  /// Sports this person wants to be found for. Seeded from the sports they
  /// have actually played and then editable, because the point of the
  /// directory is often the sport somebody is taking up in a new city rather
  /// than the one their record is in.
  final List<String> sportIds;

  final List<PlayerIntent> intents;

  /// The band, never the birth date. Recomputed on every save — see
  /// [refreshedFor] — and rendered as a band rather than a number so a
  /// listing that has sat untouched for a year is coarse rather than wrong.
  final AgeGroup? ageGroup;

  final Gender? gender;

  /// District and state only. See the class doc.
  final GeoLocation geo;

  /// Set only when [geo] carries a point. Precision 9, matching `grounds` —
  /// the search re-encodes at whatever precision the radius needs, so storing
  /// the finest is what keeps every radius answerable off one field.
  final String? geohash;

  /// A line or two in their own words. Bounded, for the same reason a
  /// membership application's note is.
  final String? note;

  static const maxNoteLength = 280;

  /// Their record, in one number, so a card can say "84 matches" without the
  /// directory carrying a copy of anybody's career.
  final int matchesPlayed;

  final DateTime? updatedAt;

  bool get hasPoint => geo.lat != null && geo.lng != null;

  /// A listing rebuilt from the profile it describes, keeping whatever the
  /// owner chose that the profile does not know about.
  ///
  /// The age band and the display name are refreshed from the profile every
  /// time rather than stored once: a directory that still calls somebody U-17
  /// two years on is worse than one that has no age at all.
  factory PlayerListing.refreshedFor(
    AppUser user, {
    required List<String> sportIds,
    required List<PlayerIntent> intents,
    required GeoLocation geo,
    String? note,
    int matchesPlayed = 0,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final lat = geo.lat;
    final lng = geo.lng;
    return PlayerListing(
      uid: user.uid,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      playerCode: user.playerCode,
      sportIds: sportIds,
      intents: intents,
      ageGroup: AgeGroup.fromDateOfBirth(user.dateOfBirth, referenceDate: at),
      gender: user.gender,
      // District and state survive; anything finer is dropped here rather
      // than at the call site, so no screen can publish a village by
      // forgetting to.
      geo: GeoLocation(
        state: geo.state,
        district: geo.district,
        lat: lat,
        lng: lng,
      ),
      geohash: lat == null || lng == null ? null : Geohash.encode(lat, lng),
      note: note,
      matchesPlayed: matchesPlayed,
      updatedAt: at,
    );
  }

  factory PlayerListing.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final band = Fs.strOrNull(d['ageGroup']);
    return PlayerListing(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      playerCode: Fs.strOrNull(d['playerCode']),
      sportIds: Fs.strList(d['sportIds']),
      intents: PlayerIntent.setFrom(Fs.strList(d['intents'])),
      ageGroup: band == null ? null : _bandFromWire(band),
      gender: d['gender'] == null ? null : Gender.fromWire(Fs.str(d['gender'])),
      geo: GeoLocation.fromDocData(d, legacyDistrictKey: null),
      geohash: Fs.strOrNull(d['geohash']),
      note: Fs.strOrNull(d['note']),
      matchesPlayed: Fs.integer(d['matchesPlayed']),
      updatedAt: Fs.dateOrNull(d['updatedAt']),
    );
  }

  /// Bands go to the wire as their enum name (`u17`), not their label
  /// (`U-17`): the label is display text and is allowed to change, the wire
  /// value is a stored key and is not.
  static AgeGroup? _bandFromWire(String w) {
    for (final b in AgeGroup.values) {
      if (b.name == w) return b;
    }
    return null;
  }

  /// The whole document. A listing is written whole every time — it is small,
  /// entirely owner-supplied, and a partial update would let a stale field
  /// survive an edit that was meant to remove it.
  ///
  /// `district` and `state` are also written FLAT, beside the nested `geo`
  /// map. Firestore can index and equality-filter a nested path fine, and the
  /// map is what [GeoLocation.fromDocData] reads back — the flat copies exist
  /// so the district query reads the same way the org and ground queries in
  /// this codebase already do, and so a composite index over them is one
  /// obvious pair of fields rather than two dotted paths.
  Map<String, Object?> toMap() => Fs.prune({
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'playerCode': playerCode,
        'sportIds': sportIds,
        'intents': PlayerIntent.wiresOf(intents),
        'ageGroup': ageGroup?.name,
        'gender': gender?.wire,
        'geo': geo.toMap(),
        'district': geo.district,
        'state': geo.state,
        'geohash': geohash,
        'note': note,
        'matchesPlayed': matchesPlayed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

/// One directory hit, with the distance that earned it its place when the
/// search was a radius one. Mirrors `GroundNearby`, for the same reason: the
/// distance is a property of the search, not of the listing.
class PlayerNearby {
  const PlayerNearby({required this.listing, this.distanceKm});

  final PlayerListing listing;

  /// Null for a district search, or for a hit with no published point.
  final double? distanceKm;

  String? get distanceLabel {
    final d = distanceKm;
    if (d == null) return null;
    if (d < 1) return '${(d * 1000).round()} m away';
    return '${d.toStringAsFixed(d < 10 ? 1 : 0)} km away';
  }
}
