import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

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
        matchesOfficiated: Fs.integer(d['matchesOfficiated']),
        isAvailable: Fs.boolean(d['isAvailable'], true),
        createdAt: Fs.dateOrNull(d['createdAt']),
        updatedAt: Fs.dateOrNull(d['updatedAt']),
      );

  Map<String, Object?> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'phone': phone,
        'sports': sports,
        'badgeLevel': badgeLevel,
        'matchesOfficiated': matchesOfficiated,
        'isAvailable': isAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  UmpireProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? phone,
    List<String>? sports,
    String? badgeLevel,
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
        matchesOfficiated: matchesOfficiated ?? this.matchesOfficiated,
        isAvailable: isAvailable ?? this.isAvailable,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
