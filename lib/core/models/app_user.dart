import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// A person, globally — one document per real human, at `users/{uid}`.
///
/// Deliberately separate from any organization. A player who moves from a
/// school team to a district academy keeps this identity and therefore keeps
/// their results, rating and achievements. Tying identity to an org is what
/// makes sports records non-portable, and it is the mistake that forces
/// athletes to rebuild their history every time they move.
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.dateOfBirth,
    required this.gender,
    this.photoUrl,
    this.phone,
    this.profileVisibility = ProfileVisibility.community,
    this.profileComplete = false,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String email;

  /// Drives age-category eligibility and every minor-safety rule. Write-once:
  /// `firestore.rules` rejects any update that changes it, because a
  /// self-editable birth date makes every junior result contestable.
  final DateTime dateOfBirth;

  final Gender gender;
  final String? photoUrl;
  final String? phone;
  final ProfileVisibility profileVisibility;

  /// Google Sign-In gives us a name, an email and a photo — but never a birth
  /// date. Until the user supplies one we cannot judge age eligibility or
  /// apply minor protections, so the app routes them to a completion screen
  /// and refuses to let them register for anything.
  final bool profileComplete;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Evaluated against the current instant for safety decisions (visibility,
  /// guardian consent). Note this is intentionally different from
  /// [ageOnDate], which pins to a competition's cut-off date for eligibility.
  bool get isMinor => ageOnDate(dateOfBirth, DateTime.now()) < 18;

  int ageAt(DateTime referenceDate) => ageOnDate(dateOfBirth, referenceDate);

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AppUser(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      email: Fs.str(d['email']),
      // A missing birth date would silently make everyone an adult, so it
      // falls back to "today", which reads as age 0 and fails every adult
      // check rather than passing it.
      dateOfBirth: Fs.date(d['dateOfBirth'], DateTime.now()),
      gender: Gender.fromWire(Fs.str(d['gender'])),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      phone: Fs.strOrNull(d['phone']),
      profileVisibility:
          ProfileVisibility.fromWire(Fs.str(d['profileVisibility'])),
      profileComplete: Fs.boolean(d['profileComplete']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      updatedAt: Fs.dateOrNull(d['updatedAt']),
    );
  }

  /// Payload for the first write. `isMinor` is denormalized because security
  /// rules cannot compute an age from a timestamp — the rule that stops a
  /// minor's profile being world-readable has to read a plain boolean.
  Map<String, Object?> toCreate() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'dateOfBirth': Fs.ts(dateOfBirth),
        'gender': gender.wire,
        'photoUrl': photoUrl,
        'phone': phone,
        'profileVisibility': profileVisibility.wire,
        'profileComplete': profileComplete,
        'isMinor': isMinor,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Update payload. Omits `dateOfBirth` and `createdAt` entirely — rules
  /// reject any write that changes them, so including them would turn every
  /// profile edit into a permission error.
  Map<String, Object?> toUpdate() => {
        'uid': uid,
        'displayName': displayName,
        'gender': gender.wire,
        'photoUrl': photoUrl,
        'phone': phone,
        'profileVisibility': profileVisibility.wire,
        'profileComplete': profileComplete,
        'isMinor': isMinor,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  AppUser copyWith({
    String? displayName,
    Gender? gender,
    String? photoUrl,
    String? phone,
    DateTime? dateOfBirth,
    ProfileVisibility? profileVisibility,
    bool? profileComplete,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone ?? this.phone,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      profileComplete: profileComplete ?? this.profileComplete,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
