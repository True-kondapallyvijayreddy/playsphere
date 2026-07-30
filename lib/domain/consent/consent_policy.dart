import '../../core/models/firestore_codec.dart' show ageOnDate;
import '../../core/models/guardian_consent.dart';
import 'consent_decision.dart';

/// Answers exactly one question, for exactly one purpose, at exactly one
/// instant: **may this scout see this minor's profile, for this purpose,
/// right now?**
///
/// This is the single choke point CLAUDE.md §2.7 and §12.8 describe.
/// Everything else in `lib/domain/scout/` calls through here rather than
/// re-implementing any part of this logic, so there is exactly one place
/// that can get a minor-safety rule wrong.
///
/// # Age is derived, never stored (§12.8)
///
/// [evaluate] takes a raw `dateOfBirth` and a `now`, and computes age at the
/// instant of the call via [ageOnDate] — the exact function
/// `AppUser.isMinor` and `AgeGroup.fromDateOfBirth` already use elsewhere in
/// this codebase. It never accepts a pre-computed `isMinor` boolean. A
/// stored flag goes stale in both directions the moment it is out of sync
/// with the calendar: a 17-year-old who turned 18 yesterday would stay
/// gated behind consent that no longer applies to them (annoying, but
/// safe), while a stale flag that read "adult" a day early would expose a
/// still-minor player with zero consent check at all (the actual failure
/// this rule exists to prevent). Recomputing from `dateOfBirth` on every
/// call makes that second failure mode structurally impossible — there is
/// no boolean left to go stale.
///
/// # What this class is honest about
///
/// This is client-side, in-memory policy logic. It is exactly as trustworthy
/// as the [GuardianConsent] records handed to it. A compromised client could
/// call [evaluate] with fabricated consent objects and get `allowed: true`
/// back — this class has no way to know a record is fake. The real
/// boundary, as `guardian_consent.dart`'s file doc says, is server-side:
/// this policy's job is to be the *correct* logic to run wherever
/// enforcement actually happens (client for UX, server for safety), not to
/// be the enforcement itself.
class ConsentPolicy {
  const ConsentPolicy();

  /// The age (inclusive) at which a person stops being subject to this
  /// policy altogether. Matches `AppUser.isMinor`'s `< 18` cutoff exactly —
  /// kept as a named constant here rather than a bare literal so the two
  /// call sites cannot silently drift apart.
  static const adultAge = 18;

  /// Evaluates one consent question.
  ///
  /// - [subjectDateOfBirth]: the minor/adult whose profile is being asked
  ///   about. Age is derived from this against [now], never read from a
  ///   stored flag (see class doc).
  /// - [purpose]: the exact [ConsentScope] being asked about. A grant for a
  ///   different scope never satisfies this — see
  ///   [ConsentDenialReason.noConsentForScope].
  /// - [consentsForSubject]: every [GuardianConsent] record on file for this
  ///   subject, from any guardian, any scope, any point in time (active,
  ///   expired, revoked — all of it). The caller does not need to
  ///   pre-filter; this method does, defensively, by [purpose] itself so a
  ///   caller that accidentally hands over a mixed bag for several users
  ///   cannot cause a cross-subject leak (any record for a different
  ///   `minorUserId` is ignored).
  /// - [subjectUserId]: the subject's own uid, used as the defensive filter
  ///   described above.
  /// - [now]: the instant to evaluate against. Passed explicitly, exactly
  ///   like [ageOnDate] and `AgeGroup.fromDateOfBirth` elsewhere in this
  ///   codebase, so tests can pin time and so one call never mixes two
  ///   different clock readings across its own age check and consent-window
  ///   check.
  ConsentDecision evaluate({
    required String subjectUserId,
    required DateTime subjectDateOfBirth,
    required ConsentScope purpose,
    required List<GuardianConsent> consentsForSubject,
    required DateTime now,
  }) {
    final age = ageOnDate(subjectDateOfBirth, now);
    if (age >= adultAge) {
      // Adults are entirely outside this policy. Guardian consent is a
      // minor-safety mechanism, not a general privacy control — an adult's
      // visibility is governed by `AppUser.profileVisibility` elsewhere,
      // which this policy neither knows about nor should.
      return const ConsentDecision.allowedForAdult();
    }

    // Defensive filter: only records for this exact subject and this exact
    // purpose can possibly authorize this decision. A record for a sibling,
    // or for a different `ConsentScope`, is inert here no matter how recent
    // or how strongly verified it is.
    final candidates = consentsForSubject
        .where((c) => c.minorUserId == subjectUserId && c.scope == purpose)
        .toList();

    if (candidates.isEmpty) {
      return const ConsentDecision.denied(ConsentDenialReason.noConsentForScope);
    }

    // Guardians may grant, let lapse, and grant again — a family that
    // re-consents after an old grant expired should not be punished by an
    // evaluator that only ever looks at the first record it finds. Consider
    // the most recently granted record as the one representing the family's
    // current intent.
    candidates.sort((a, b) => b.grantedAt.compareTo(a.grantedAt));
    final mostRecent = candidates.first;

    if (mostRecent.isActiveAt(now)) {
      return ConsentDecision.allowedForMinor(mostRecent);
    }

    // Revocation is a deliberate guardian act ("stop"); expiry is just time
    // passing. When the most recent record is both revoked and expired,
    // report the revocation — it is the more informative, more actionable
    // fact for whoever reads this decision.
    if (mostRecent.isRevoked) {
      return const ConsentDecision.denied(ConsentDenialReason.consentRevoked);
    }
    return const ConsentDecision.denied(ConsentDenialReason.consentExpired);
  }

  /// Convenience wrapper for the most common question: may this minor
  /// appear in scout talent search at all? Equivalent to calling [evaluate]
  /// with `purpose: ConsentScope.talentVisibility`.
  ConsentDecision mayAppearInSearch({
    required String subjectUserId,
    required DateTime subjectDateOfBirth,
    required List<GuardianConsent> consentsForSubject,
    required DateTime now,
  }) =>
      evaluate(
        subjectUserId: subjectUserId,
        subjectDateOfBirth: subjectDateOfBirth,
        purpose: ConsentScope.talentVisibility,
        consentsForSubject: consentsForSubject,
        now: now,
      );

  /// May a scout contact this subject (message the guardian, invite to a
  /// trial)? Equivalent to [evaluate] with `purpose:
  /// ConsentScope.contactByScouts`. Note this says nothing about whether the
  /// subject is even visible in search — callers normally check
  /// [mayAppearInSearch] first, since a subject who fails that check should
  /// never reach a "contact" affordance in the UI in the first place.
  ConsentDecision mayContact({
    required String subjectUserId,
    required DateTime subjectDateOfBirth,
    required List<GuardianConsent> consentsForSubject,
    required DateTime now,
  }) =>
      evaluate(
        subjectUserId: subjectUserId,
        subjectDateOfBirth: subjectDateOfBirth,
        purpose: ConsentScope.contactByScouts,
        consentsForSubject: consentsForSubject,
        now: now,
      );

  /// May a scout view/reuse match media of this subject? Equivalent to
  /// [evaluate] with `purpose: ConsentScope.mediaUsage`.
  ConsentDecision mayUseMedia({
    required String subjectUserId,
    required DateTime subjectDateOfBirth,
    required List<GuardianConsent> consentsForSubject,
    required DateTime now,
  }) =>
      evaluate(
        subjectUserId: subjectUserId,
        subjectDateOfBirth: subjectDateOfBirth,
        purpose: ConsentScope.mediaUsage,
        consentsForSubject: consentsForSubject,
        now: now,
      );
}
