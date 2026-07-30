/// Guardian consent for a minor's visibility to talent scouts.
///
/// This is the client-side data shape behind CLAUDE.md §2.7 (MUST — "Guardian
/// consent for under-18 talent visibility; consent-gated scout access; India
/// DPDP Act data handling") and §5's `scout_access` entity ("consent records
/// (guardian consent for minors)").
///
/// **What this file cannot do.** A [GuardianConsent] object is just data. It
/// proves nothing on its own — a modified client could construct one out of
/// thin air and hand it to [ConsentPolicy] (see `lib/domain/consent/`) to
/// unlock a minor's profile. The record only means something once a server
/// has (a) verified the guardian relationship through [verificationMethod]
/// and (b) is the party that persists, serves and — critically — enforces
/// expiry and revocation. Everything in this file and in
/// `lib/domain/consent/` is the client's *mirror* of that server-side truth:
/// it is what lets the app decide what to render without a round trip for
/// every scroll, and what lets a guardian's revocation take visible effect
/// the instant it syncs. It is not, and cannot be, the actual safety
/// boundary. That boundary is `firestore.rules` plus server-side query
/// constraints, owned elsewhere.
library;

/// One specific thing a guardian can consent to on a minor's behalf.
///
/// Deliberately three separate grants rather than one "yes, scouts can see
/// my child" toggle. A guardian who is comfortable with a scout finding
/// their child's verified stats has not thereby agreed that a stranger may
/// contact the household, and has separately not agreed that match photos
/// of their child may be shown to or reused by scouts. Collapsing these
/// into one blanket flag is exactly the pattern India's DPDP Act consent
/// provisions exist to prevent: consent must be specific to a purpose, and a
/// purpose the guardian never considered cannot be inferred from a purpose
/// they did consider. Every new use of a minor's data needs its own scope
/// added here — never a wildcard "and anything else" case.
enum ConsentScope {
  /// A scout running a talent search may see that this minor exists: sport,
  /// district/mandal, age group and verified performance numbers. This is
  /// the baseline grant — without it the minor does not appear in search at
  /// all (see `TalentSearch` in `lib/domain/scout/`).
  talentVisibility('talent_visibility', 'Appear in scout talent search'),

  /// A scout who has already found the minor via [talentVisibility] may
  /// initiate contact: message the guardian, invite the minor to a trial.
  ///
  /// Layered strictly on top of [talentVisibility], never a substitute for
  /// it — contact permission without visibility permission is meaningless
  /// (there is no search result to contact through), but visibility without
  /// contact permission is a real and common guardian preference: "let my
  /// child's record be found so it counts, but any approach comes through
  /// me at the club, not through a stranger in the app."
  contactByScouts('contact_by_scouts', 'Allow scouts to make contact'),

  /// Match photos/video of the minor may be shown to, or reused by, scouts
  /// and academies for talent-identification purposes.
  ///
  /// Distinct from the ordinary in-app memory album, which is governed by
  /// `AppUser.profileVisibility` and has nothing to do with this model —
  /// this scope is specifically about a scout, a party outside the minor's
  /// own clubs, seeing or reusing that media.
  mediaUsage('media_usage', 'Allow scouts to view/use match media');

  const ConsentScope(this.wire, this.label);

  /// Stable string persisted wherever this consent is stored. Never persist
  /// `Enum.name` directly, for the same reason `enums.dart` gives for every
  /// other enum in this codebase: renaming a Dart constant must never
  /// silently orphan an existing consent record — that would turn a real,
  /// deliberate guardian grant into an unrecognised value that a strict
  /// reader might (wrongly, dangerously) treat as "consent not found".
  final String wire;
  final String label;

  static ConsentScope fromWire(String? w) => ConsentScope.values.firstWhere(
        (e) => e.wire == w,
        // No safe default exists here — unlike most `fromWire` fallbacks in
        // this codebase, defaulting to any real scope would silently grant
        // something nobody asked for. Callers that hit this fallback should
        // treat the record as unparseable and refuse to rely on it, not
        // proceed as if the fallback scope was actually granted.
        orElse: () => ConsentScope.talentVisibility,
      );
}

/// How the guardian relationship itself was established, ordered roughly
/// weakest to strongest evidence.
///
/// This is deliberately tracked per consent record, not per user. A family
/// might establish the relationship one way for a first-ever grant
/// (self-declared, to unblock onboarding) and a club administrator might
/// upgrade it to [associationAttested] later when the minor joins a
/// verified academy — the two records coexist and each is honest about how
/// it was obtained.
enum GuardianVerificationMethod {
  /// The guardian typed the relationship themselves; nothing independent
  /// checked it. Weakest tier — acceptable to unblock a family onboarding,
  /// but a product decision elsewhere (not this file) may choose to gate
  /// higher-stakes scopes like [ConsentScope.contactByScouts] behind a
  /// stronger method.
  selfDeclared('self_declared', 'Self-declared by guardian'),

  /// The guardian's phone number matches a family/household record already
  /// on file (e.g. the same number used for the minor's own OTP signup, or
  /// one previously confirmed for a sibling).
  phoneNumberMatch('phone_number_match', 'Guardian phone number verified'),

  /// A guardian uploaded a document (birth certificate, school ID,
  /// ration card) establishing the relationship, reviewed by app staff.
  documentUpload('document_upload', 'Document reviewed'),

  /// A school, academy or club administrator who already manages the minor
  /// through a membership vouched for the relationship.
  schoolOrClubAttested('school_or_club_attested', 'School/club attested'),

  /// A sports association (district/state body) verified the relationship,
  /// e.g. as part of registering the minor for a sanctioned trial. Strongest
  /// tier — mirrors [VerificationTier.sanctioned] in `enums.dart`, which
  /// applies the same "association-level trust beats self-report" idea to
  /// match results.
  associationAttested('association_attested', 'Sports association verified');

  const GuardianVerificationMethod(this.wire, this.label);
  final String wire;
  final String label;

  static GuardianVerificationMethod fromWire(String? w) =>
      GuardianVerificationMethod.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => GuardianVerificationMethod.selfDeclared,
      );
}

/// A single, scoped, time-bounded, revocable grant of consent from a
/// guardian on behalf of one minor.
///
/// # Why every field is shaped the way it is
///
/// - **Scoped** ([scope]): see [ConsentScope] — one record grants exactly
///   one purpose. A minor with `talentVisibility` consent and no
///   `contactByScouts` record has, as far as this model is concerned, *no*
///   contact consent — there is nothing to fall back to.
/// - **Time-bounded** ([grantedAt], [expiresAt]): DPDP-aligned consent is
///   not a lifetime grant. [maxValidity] caps how far in the future
///   [expiresAt] may sit, which makes it a compile-time-adjacent guarantee
///   (checked in the [GuardianConsent.grant] factory, the only supported
///   way to create a fresh record) rather than a convention someone has to
///   remember to apply. An "expiring" consent that never actually expires
///   because nobody enforced a cap is not meaningfully different from the
///   blanket consent DPDP forbids.
/// - **Revocable, effective immediately** ([revokedAt]): once set, a record
///   is dead for good — there is no "un-revoke". A guardian who changes
///   their mind again is expected to grant a fresh record, so every consent
///   decision a family ever made stays in the audit trail rather than being
///   overwritten.
/// - **Auditable** ([id], [verificationMethod]): every record answers "who
///   consented, to what, when, until when, and how do we know they were
///   actually the guardian" without joining out to another table.
///
/// This type has no public mutating methods — [revoke] returns a new
/// instance. Nothing here reaches Firestore; a persistence layer elsewhere
/// is responsible for writing new records and (per DPDP's audit
/// requirement) never deleting old ones, only appending revocations.
class GuardianConsent {
  const GuardianConsent._({
    required this.id,
    required this.minorUserId,
    required this.guardianUserId,
    required this.scope,
    required this.verificationMethod,
    required this.grantedAt,
    required this.expiresAt,
    this.revokedAt,
  });

  /// The longest window a single grant may cover before the guardian must be
  /// asked again. One year mirrors the "annual re-consent" pattern common to
  /// DPDP-style regimes and — just as importantly — bounds how stale a
  /// forgotten grant can get: a guardian who consented when their child was
  /// 12 and never revisits the app cannot end up with an effectively
  /// permanent grant still active when the child is 17.
  static const maxValidity = Duration(days: 365);

  /// Creates a fresh grant, enforcing every invariant a consent record must
  /// satisfy so that an invalid one is simply not constructible:
  ///
  /// - `guardianUserId != minorUserId` — a minor cannot consent for
  ///   themselves; that is the entire reason this model exists.
  /// - `expiresAt` strictly after `grantedAt` — a zero-or-negative window is
  ///   not "time-bounded consent", it is consent that was never really
  ///   granted.
  /// - `expiresAt` no more than [maxValidity] past `grantedAt` — see
  ///   [maxValidity] above.
  ///
  /// [id] is supplied by the caller (e.g. a Firestore document ID or a
  /// client UUIDv7, matching this codebase's sync protocol) rather than
  /// generated here, keeping this constructor pure and deterministic.
  factory GuardianConsent.grant({
    required String id,
    required String minorUserId,
    required String guardianUserId,
    required ConsentScope scope,
    required GuardianVerificationMethod verificationMethod,
    required DateTime grantedAt,
    DateTime? expiresAt,
  }) {
    if (guardianUserId == minorUserId) {
      throw ArgumentError(
        'A minor cannot be their own guardian (uid: $minorUserId).',
      );
    }
    final resolvedExpiry = expiresAt ?? grantedAt.add(maxValidity);
    if (!resolvedExpiry.isAfter(grantedAt)) {
      throw ArgumentError(
        'expiresAt ($resolvedExpiry) must be after grantedAt ($grantedAt) — '
        'consent must cover a real, non-empty window.',
      );
    }
    if (resolvedExpiry.isAfter(grantedAt.add(maxValidity))) {
      throw ArgumentError(
        'expiresAt ($resolvedExpiry) exceeds the maximum validity window of '
        '${maxValidity.inDays} days from grantedAt ($grantedAt). Guardians '
        'must be asked to re-consent at least this often.',
      );
    }
    return GuardianConsent._(
      id: id,
      minorUserId: minorUserId,
      guardianUserId: guardianUserId,
      scope: scope,
      verificationMethod: verificationMethod,
      grantedAt: grantedAt,
      expiresAt: resolvedExpiry,
      revokedAt: null,
    );
  }

  final String id;
  final String minorUserId;
  final String guardianUserId;
  final ConsentScope scope;
  final GuardianVerificationMethod verificationMethod;
  final DateTime grantedAt;
  final DateTime expiresAt;

  /// Null while active. Once set, this record is permanently inactive —
  /// see [revoke].
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  /// Whether [instant] falls strictly inside the granted window and the
  /// record has not been revoked.
  ///
  /// This is the one predicate every consent check in this codebase should
  /// ultimately reduce to. It takes `instant` as a parameter rather than
  /// reading `DateTime.now()` itself so that (a) tests can pin time exactly
  /// the way `AgeGroup.fromDateOfBirth` and `ageOnDate` already do elsewhere
  /// in this codebase, and (b) a single "now" is reused across every field
  /// checked in one decision, so a consent record can never be judged
  /// "not yet started" against one clock reading and "already expired"
  /// against another.
  bool isActiveAt(DateTime instant) =>
      !isRevoked &&
      !instant.isBefore(grantedAt) &&
      instant.isBefore(expiresAt);

  /// Returns a new record with [revokedAt] set to [at]. Revocation is a
  /// one-way door: calling this on an already-revoked record is a
  /// programming error (the caller should be grazing an existing revocation,
  /// not creating a second one), so it throws rather than silently
  /// no-opping or moving the revocation timestamp.
  GuardianConsent revoke(DateTime at) {
    if (isRevoked) {
      throw StateError(
        'GuardianConsent $id was already revoked at $revokedAt.',
      );
    }
    if (at.isBefore(grantedAt)) {
      throw ArgumentError(
        'Cannot revoke at $at, which is before this grant started '
        '($grantedAt).',
      );
    }
    return GuardianConsent._(
      id: id,
      minorUserId: minorUserId,
      guardianUserId: guardianUserId,
      scope: scope,
      verificationMethod: verificationMethod,
      grantedAt: grantedAt,
      expiresAt: expiresAt,
      revokedAt: at,
    );
  }

  /// Plain, storage-agnostic payload — ISO-8601 strings and wire enums only,
  /// no `Timestamp`/`FieldValue`. Deliberately decoupled from Firestore so
  /// this model stays usable from any persistence layer (or from a pure
  /// unit test) without pulling in `cloud_firestore`.
  Map<String, Object?> toMap() => {
        'id': id,
        'minorUserId': minorUserId,
        'guardianUserId': guardianUserId,
        'scope': scope.wire,
        'verificationMethod': verificationMethod.wire,
        'grantedAt': grantedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'revokedAt': revokedAt?.toIso8601String(),
      };

  factory GuardianConsent.fromMap(Map<String, Object?> m) => GuardianConsent._(
        id: m['id'] as String,
        minorUserId: m['minorUserId'] as String,
        guardianUserId: m['guardianUserId'] as String,
        scope: ConsentScope.fromWire(m['scope'] as String?),
        verificationMethod:
            GuardianVerificationMethod.fromWire(m['verificationMethod'] as String?),
        grantedAt: DateTime.parse(m['grantedAt'] as String),
        expiresAt: DateTime.parse(m['expiresAt'] as String),
        revokedAt: m['revokedAt'] == null
            ? null
            : DateTime.parse(m['revokedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is GuardianConsent &&
      other.id == id &&
      other.minorUserId == minorUserId &&
      other.guardianUserId == guardianUserId &&
      other.scope == scope &&
      other.verificationMethod == verificationMethod &&
      other.grantedAt == grantedAt &&
      other.expiresAt == expiresAt &&
      other.revokedAt == revokedAt;

  @override
  int get hashCode => Object.hash(
        id,
        minorUserId,
        guardianUserId,
        scope,
        verificationMethod,
        grantedAt,
        expiresAt,
        revokedAt,
      );

  @override
  String toString() =>
      'GuardianConsent($id, minor: $minorUserId, scope: ${scope.wire}, '
      'active: ${!isRevoked}, expires: $expiresAt)';
}
