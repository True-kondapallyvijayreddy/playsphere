import 'package:cloud_firestore/cloud_firestore.dart';

import 'billing.dart';
import 'enums.dart';
import 'firestore_codec.dart';
import 'geo.dart';
import 'glicko_badge.dart';

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
    this.geo = GeoLocation.empty,
    this.orgIds = const [],
    this.pendingOrgIds = const [],
    this.playerCode,
    this.plan = MemberPlan.free,
    this.planState = PlanState.none,
    this.custodianUid,
    this.claimedAt,
    this.glicko,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String email;

  /// The player's public identifier — `PSOS-4K7M2`.
  ///
  /// A uid is 28 characters of base64 and cannot be read down a phone line or
  /// written on a team sheet. This is the thing a player actually tells
  /// somebody: a captain filling in a squad types it, and the person is added
  /// to the match with their real account attached, so the runs they score
  /// land on their own career record rather than on a namesake guest.
  ///
  /// Null only for accounts created before codes existed — see
  /// [PlayerCode.generate] and the backfill in `UserRepository.ensureCode`.
  /// Nothing may depend on it being present.
  final String? playerCode;

  /// Drives age-category eligibility and every minor-safety rule. Write-once:
  /// `firestore.rules` rejects any update that changes it, because a
  /// self-editable birth date makes every junior result contestable.
  final DateTime dateOfBirth;

  final Gender gender;
  final String? photoUrl;
  final String? phone;
  final ProfileVisibility profileVisibility;

  /// State → district → mandal → village, feeding the gov aggregates in
  /// `lib/domain/gov/`. No AppUser document had any location field before
  /// this, so there is no legacy shape to fall back to here — unlike
  /// [Organization.geo], a missing `geo` map just means "not captured yet".
  final GeoLocation geo;

  /// The clubs this person is an ACTIVE member of, most-recently-joined
  /// first. A mirror of their memberships, not the record of them — the
  /// records live at `orgs/{orgId}/members/{uid}` and stay authoritative.
  ///
  /// It exists because `firestore.rules` has to answer "do these two people
  /// share a club" to honour [ProfileVisibility.community], and rules cannot
  /// run a query. The rule checks the CALLER's real membership document
  /// against the first few entries here, so a padded list grants a stranger
  /// nothing — see the sharesActiveOrgWith() comment in firestore.rules.
  /// Kept in step by `UserRepository.mirrorOrgIds`.
  final List<String> orgIds;

  /// The clubs this person has an OUTSTANDING application to, most-recently-
  /// applied first. The same kind of mirror as [orgIds], for the same kind of
  /// reason, but pointing the other way.
  ///
  /// It exists so `firestore.rules` can let the admins of a club read the
  /// profile of somebody who has asked to join it — a decision they were
  /// previously asked to make on a name and a photo alone. Rules cannot run a
  /// query, so without this there is no path from the applicant's document to
  /// the club whose admins are entitled to read it.
  ///
  /// A padded list grants nothing. The rule checks TWO facts per entry: that
  /// the caller is an owner or admin of that club, and that this person's
  /// membership row in it is still `pending`. So naming a club you never
  /// applied to grants its admins nothing, and the grant lapses on its own the
  /// moment the application is decided — which matters, because the approver
  /// cannot write this list to clean it up. Only the first few entries are
  /// checked (see the rule), so freshest must come first.
  ///
  /// Kept in step by `UserRepository.mirrorPendingOrgIds`.
  final List<String> pendingOrgIds;

  /// Google Sign-In gives us a name, an email and a photo — but never a birth
  /// date. Until the user supplies one we cannot judge age eligibility or
  /// apply minor protections, so the app routes them to a completion screen
  /// and refuses to let them register for anything.
  final bool profileComplete;

  /// Free or Premium. See [MemberPlan] — nothing needed to take part in sport
  /// is ever behind this.
  final MemberPlan plan;

  /// When Premium was activated and when it lapses.
  final PlanState planState;

  /// The guardian's uid, for a profile a guardian created on behalf of a
  /// child with no device or Google account of their own yet.
  ///
  /// Deliberately distinct from [GuardianConsent]'s guardian/minor
  /// relationship (see `lib/core/models/guardian_consent.dart`), which
  /// exists for a completely different purpose — scout-visibility consent —
  /// and stays self-declared and optional even for an adult-created account.
  /// This field, by contrast, is set exactly once, server-side, by the
  /// `createManagedChildProfile` Cloud Function at the moment the profile is
  /// created, and `firestore.rules` refuses any client write that changes
  /// it. It is never null-to-non-null on an existing document, and never
  /// edited afterward by anyone, guardian included.
  final String? custodianUid;

  /// Null while this profile is guardian-managed and has no login of its
  /// own. Set exactly once — by the CHILD's own newly-linked session, never
  /// by the guardian — the moment they finish linking their own Google
  /// account via a claim code. See [isManaged].
  final DateTime? claimedAt;

  /// This person's competitive standing across every sport they play, or null
  /// if they have not played a rated match.
  ///
  /// Server-written and frozen against client writes — see [GlickoBadge]. It
  /// is here, on the document every screen already loads, precisely so that a
  /// standing can appear beside a name anywhere a name appears, which is the
  /// whole point of treating it as identity rather than as a statistic.
  final GlickoBadge? glicko;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True while a profile has a custodian and has not yet been claimed by
  /// the child themselves. A claimed profile keeps [custodianUid] — the
  /// guardian retains read access — but [isManaged] goes false, because the
  /// guardian can no longer write to it.
  bool get isManaged => custodianUid != null && claimedAt == null;

  /// Whether this player's Premium entitlement is live at [asOf].
  ///
  /// Everything that reads an entitlement takes the instant rather than
  /// calling `DateTime.now()` itself, so a screen cannot render half of
  /// itself as Premium and half as free across a midnight expiry.
  bool hasPremiumAt(DateTime asOf) =>
      plan.rank >= MemberPlan.premium.rank && planState.isActiveAt(asOf);

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
      geo: GeoLocation.fromDocData(d, legacyDistrictKey: null),
      orgIds: Fs.strList(d['orgIds']),
      pendingOrgIds: Fs.strList(d['pendingOrgIds']),
      playerCode: Fs.strOrNull(d['playerCode']),
      plan: MemberPlan.fromWire(Fs.str(d['plan'])),
      planState: PlanState.fromDocData(
        d,
        activatedKey: 'planActivatedAt',
        validUntilKey: 'planValidUntil',
        lastPaymentKey: 'planPaymentId',
      ),
      custodianUid: Fs.strOrNull(d['custodianUid']),
      claimedAt: Fs.dateOrNull(d['claimedAt']),
      glicko: GlickoBadge.fromMap(d['glicko']),
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
        'geo': geo.toMap(),
        'orgIds': orgIds,
        'pendingOrgIds': pendingOrgIds,
        'playerCode': playerCode,
        'plan': plan.wire,
        'isMinor': isMinor,
        // Explicit null on an ordinary self-signup, same as [photoUrl] and
        // [phone] above — a managed child's document gets a real value here
        // instead, but only ever via `createManagedChildProfile` (Admin
        // SDK), never through this method.
        'custodianUid': custodianUid,
        'claimedAt': claimedAt == null ? null : Fs.ts(claimedAt!),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Update payload. Omits `dateOfBirth` and `createdAt` entirely — rules
  /// reject any write that changes them, so including them would turn every
  /// profile edit into a permission error.
  ///
  /// Omits `orgIds` and `pendingOrgIds` for a different reason: both are
  /// mirrors of the membership documents, maintained by
  /// [UserRepository.mirrorOrgIds] and [UserRepository.mirrorPendingOrgIds]
  /// from the live memberships stream. Writing it from an edit form would let a screen that
  /// never loaded the memberships blank it — and blanking it silently makes
  /// the profile unreadable to every club-mate.
  ///
  /// And omits `plan` for a third reason: a profile edit form must not be
  /// able to grant its own author Premium. That field is written only by
  /// `BillingRepository`, next to the ledger row that paid for it, with
  /// `firestore.rules` enforcing the same split independently.
  Map<String, Object?> toUpdate() => {
        'uid': uid,
        'displayName': displayName,
        'gender': gender.wire,
        'photoUrl': photoUrl,
        'phone': phone,
        'profileVisibility': profileVisibility.wire,
        'profileComplete': profileComplete,
        'geo': geo.toMap(),
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
    GeoLocation? geo,
    List<String>? orgIds,
    List<String>? pendingOrgIds,
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
      geo: geo ?? this.geo,
      orgIds: orgIds ?? this.orgIds,
      pendingOrgIds: pendingOrgIds ?? this.pendingOrgIds,
      // Not a copyWith parameter. A player code is claimed once, against a
      // reservation document that makes it unique, and is never edited — an
      // editable code would let two people trade identities, and every match
      // either had ever played would follow.
      playerCode: playerCode,
      // Not copyWith parameters either, and for the same reason the update
      // payload omits them: an entitlement is granted by a payment, never by
      // a screen holding a modified copy of the profile.
      plan: plan,
      planState: planState,
      // Not copyWith parameters. custodianUid is set once, server-side, at
      // creation; claimedAt is set once, by the child's own session, on
      // claim. Neither is ever the product of a profile-edit form.
      custodianUid: custodianUid,
      claimedAt: claimedAt,
      // Not a copyWith parameter, for the sharpest version of that same
      // reason: this one is a statement about how good somebody is, and the
      // only thing entitled to make it is the result of a match.
      glicko: glicko,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
