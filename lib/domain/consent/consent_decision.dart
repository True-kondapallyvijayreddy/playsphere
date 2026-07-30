import '../../core/models/guardian_consent.dart';

/// Why [ConsentPolicy] said no.
///
/// A bare `false` tells a scout-facing screen nothing it can act on or
/// explain to a scout who is wondering why a promising player they heard
/// about locally never turns up in search. Each value here maps to a
/// distinct, honest sentence the UI can show — see [ConsentDenialReason.explain].
enum ConsentDenialReason {
  /// No [GuardianConsent] record exists for the exact [ConsentScope] asked
  /// about — for this minor, from any guardian, ever. This is also the
  /// reason returned when consent exists for a *different* scope: a record
  /// covering [ConsentScope.talentVisibility] says nothing about
  /// [ConsentScope.contactByScouts], so asking about contact with only a
  /// visibility grant on file lands here, not in [consentExpired] or
  /// [consentRevoked].
  noConsentForScope,

  /// A record for this exact scope exists and was once active, but
  /// [GuardianConsent.expiresAt] has passed as of the instant being
  /// evaluated.
  consentExpired,

  /// A record for this exact scope exists but its guardian revoked it.
  /// Revocation always wins over expiry when both could apply, because a
  /// guardian who actively said "stop" is the actor whose intent (2.7) the
  /// caller most needs to know.
  consentRevoked;

  /// A short, non-localized explanation suitable for logs and as a fallback.
  /// User-facing surfaces must run this through the app's i18n layer
  /// (CLAUDE.md §12.7) rather than showing this string directly — it exists
  /// so a denial is never just a silent, unexplained absence.
  String explain() => switch (this) {
        ConsentDenialReason.noConsentForScope =>
          'No guardian consent on file for this purpose.',
        ConsentDenialReason.consentExpired =>
          'Guardian consent for this purpose has expired.',
        ConsentDenialReason.consentRevoked =>
          'Guardian consent for this purpose was revoked.',
      };
}

/// The result of asking [ConsentPolicy] "may this happen, right now?".
///
/// Carries a reason on denial (see [ConsentDenialReason]) and, on approval
/// for a minor, the specific [GuardianConsent] record that justified it —
/// so a caller that goes on to act on this decision (e.g. adding the player
/// to a scout's shortlist) can store which consent record it relied on,
/// which is what makes that downstream action auditable too.
class ConsentDecision {
  const ConsentDecision._({
    required this.allowed,
    this.reason,
    this.matchedConsent,
  });

  /// Always allowed, with no consent record attached — used for adults, who
  /// are entirely outside this policy's jurisdiction (see
  /// `ConsentPolicy.evaluate`).
  const ConsentDecision.allowedForAdult() : this._(allowed: true);

  /// Allowed for a minor on the strength of [consent], which was checked and
  /// found active at the evaluated instant.
  const ConsentDecision.allowedForMinor(GuardianConsent consent)
      : this._(allowed: true, matchedConsent: consent);

  const ConsentDecision.denied(ConsentDenialReason reason)
      : this._(allowed: false, reason: reason);

  final bool allowed;

  /// Non-null exactly when [allowed] is false.
  final ConsentDenialReason? reason;

  /// Non-null only when [allowed] is true *and* the subject is a minor —
  /// the record that authorized this decision. Null for adults (no consent
  /// record ever applies to them) and null on any denial.
  final GuardianConsent? matchedConsent;

  @override
  String toString() => allowed
      ? 'ConsentDecision.allowed(consent: ${matchedConsent?.id})'
      : 'ConsentDecision.denied(${reason?.name})';
}
