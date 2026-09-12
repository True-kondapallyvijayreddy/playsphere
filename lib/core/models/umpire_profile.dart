import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';
import 'geo.dart';

/// One registered match official / umpire across sports, at `umpires/{uid}`.
///
/// A person retains their single lifelong identity (`AppUser` at `users/{uid}`).
/// Registering as an official creates this profile without altering their player
/// identity or career stats — so a human can be a player on Saturday and an
/// official on Sunday.
class UmpireProfile {
  const UmpireProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.phone,
    this.sports = const [],
    this.badgeLevel = 'community',
    this.geo = GeoLocation.empty,
    this.matchesOfficiated = 0,
    this.isAvailable = true,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? phone;

  /// Sports this official is certified/registered to officiate (e.g. ['cricket', 'football']).
  final List<String> sports;

  /// Certification tier — e.g. 'community', 'district_certified', 'state_certified', 'association_certified'.
  final String badgeLevel;

  /// Where this official can actually turn up.
  ///
  /// The single most important filter in the directory after sport, and the
  /// reason is logistics rather than taste: a club in Nalgonda needing an
  /// umpire on Sunday cannot use a state-certified one in Adilabad, so a
  /// directory that can only be narrowed by sport hands them a list whose
  /// best entries are unusable. Copied from `AppUser.geo` at registration
  /// rather than re-asked — the account already knows, and a second address
  /// form is a second thing to keep true.
  ///
  /// District is what the filter matches on; see `Refs.umpires` and
  /// `UmpireRepository.watchUmpires`.
  final GeoLocation geo;

  /// How many matches this official has actually stood in.
  ///
  /// Written ONLY by `onMatchSettled` in `functions/index.js`, never by a
  /// client — the same discipline `GiveImpactStats` and
  /// `SponsorshipListing.sponsorsCount` are held to, and for a sharper reason
  /// here: this number is the entire evidence a stranger has that an official
  /// is experienced. A client that could set its own would be deciding how
  /// credible it looks.
  ///
  /// It sat at 0 forever before that trigger existed — registration wrote
  /// zero, nothing ever incremented it, and the directory sorted on a field
  /// that was zero for everybody.
  final int matchesOfficiated;
  final bool isAvailable;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool isCertifiedFor(String sportId) => sports.contains(sportId);

  factory UmpireProfile.fromMap(Map<String, dynamic> d) => UmpireProfile(
        uid: Fs.str(d['uid']),
        displayName: Fs.str(d['displayName'], 'Official'),
        photoUrl: Fs.strOrNull(d['photoUrl']),
        phone: Fs.strOrNull(d['phone']),
        sports: Fs.strList(d['sports']),
        badgeLevel: Fs.str(d['badgeLevel'], 'community'),
        geo: GeoLocation.fromDocData(d, legacyDistrictKey: null),
        matchesOfficiated: Fs.integer(d['matchesOfficiated']),
        isAvailable: Fs.boolean(d['isAvailable'], true),
        createdAt: Fs.dateOrNull(d['createdAt']),
        updatedAt: Fs.dateOrNull(d['updatedAt']),
      );

  /// What a client may write.
  ///
  /// [matchesOfficiated] is deliberately absent. It used to be included, which
  /// meant every re-save of this form wrote the count back from whatever the
  /// client last read — so an official editing their sports while a match was
  /// being settled would silently reset the counter the server had just
  /// moved. The server owns that field; see its doc above.
  Map<String, Object?> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'phone': phone,
        'sports': sports,
        'badgeLevel': badgeLevel,
        'geo': geo.toMap(),
        'districtKey': geo.district?.trim().toLowerCase(),
        'isAvailable': isAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  UmpireProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? phone,
    List<String>? sports,
    String? badgeLevel,
    GeoLocation? geo,
    int? matchesOfficiated,
    bool? isAvailable,
  }) =>
      UmpireProfile(
        uid: uid,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        phone: phone ?? this.phone,
        sports: sports ?? this.sports,
        badgeLevel: badgeLevel ?? this.badgeLevel,
        geo: geo ?? this.geo,
        matchesOfficiated: matchesOfficiated ?? this.matchesOfficiated,
        isAvailable: isAvailable ?? this.isAvailable,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
