import '../../core/models/guardian_consent.dart';
import '../consent/consent_decision.dart';
import '../consent/consent_policy.dart';
import 'talent_profile.dart';

/// A [TalentProfile] that has already been proven safe to show a scout, at
/// the instant it was produced.
///
/// # Why this type exists — making the unsafe query unrepresentable
///
/// The brief for this module was: *it must be impossible to construct a
/// query that returns an unconsented minor, enforced in the type/API design
/// — not merely by remembering to check.* A runtime check achieves that only
/// until someone adds a second code path that forgets to call it. A type
/// achieves it structurally, so here is how:
///
/// 1. [VettedCandidate]'s only constructor, [VettedCandidate._], is private
///    to this library file. No code outside `talent_search.dart` can write
///    `VettedCandidate(...)` — the language itself rejects it, not a
///    reviewer.
/// 2. The only two functions in this file that call that private
///    constructor are [TalentSearch.run] and [TalentSearch.vetOne], and
///    both of them call [ConsentPolicy.evaluate] first and only construct a
///    [VettedCandidate] when the decision is `allowed`. There is no third
///    path.
/// 3. Every downstream operation this module offers on a candidate — adding
///    to a watchlist, a shortlist, a trial invite (see
///    `scout_access_ops.dart`) — takes a [VettedCandidate], never a raw
///    [TalentProfile] or a bare uid. A caller who only has a uid cannot
///    shortlist it; they must go through [TalentSearch] first, which is the
///    only place that can mint the proof object those functions require.
///
/// Put differently: there is no line of application code, anywhere in this
/// codebase, that type-checks and also skips the consent check — the two
/// are the same code path. (The one thing this cannot protect against is
/// someone hand-rolling Firestore queries outside this Dart code entirely —
/// that is exactly why `guardian_consent.dart`'s file doc insists the real
/// boundary is server-side security rules, not this file.)
class VettedCandidate {
  const VettedCandidate._({
    required this.profile,
    required this.consentRecordId,
  });

  final TalentProfile profile;

  /// The [GuardianConsent.id] that justified showing this candidate, or
  /// `null` for an adult (who needed no consent record at all — see
  /// `ConsentPolicy.evaluate`). Kept so any later action taken on this
  /// candidate (shortlisting, inviting to trial) can record, alongside
  /// itself, *which* consent grant authorized the scout to even see this
  /// player in the first place — the audit trail §2.7 requires.
  final String? consentRecordId;
}

/// The pure filter/query builder for scout talent search (§6 Module C).
///
/// [run] is the only entry point that produces search results. It always
/// runs every candidate through [ConsentPolicy] for
/// [ConsentScope.talentVisibility] *before* applying [TalentSearchFilters] —
/// filtering happens strictly inside the already-consented set, so no
/// combination of filter values can widen who becomes visible. An
/// unconsented minor is not "filtered out"; they are never turned into a
/// [VettedCandidate] to begin with, which is what makes them structurally
/// absent rather than merely hidden.
class TalentSearch {
  const TalentSearch({this.consentPolicy = const ConsentPolicy()});

  final ConsentPolicy consentPolicy;

  /// Runs [filters] over [candidates], gating every minor through
  /// [ConsentPolicy] first.
  ///
  /// [consentsByUserId] should map each candidate's uid to every
  /// [GuardianConsent] record on file for them (any scope, any status) —
  /// the same shape [ConsentPolicy.evaluate] expects. A uid with no entry is
  /// treated as having zero consent records, which for a minor means denial
  /// with [ConsentDenialReason.noConsentForScope] — the safe default for
  /// "we don't know" is "not visible", never "visible".
  List<VettedCandidate> run({
    required Iterable<TalentProfile> candidates,
    required TalentSearchFilters filters,
    required Map<String, List<GuardianConsent>> consentsByUserId,
    required DateTime now,
  }) {
    final results = <VettedCandidate>[];
    for (final profile in candidates) {
      final vetted = vetOne(
        profile: profile,
        consentsForSubject: consentsByUserId[profile.uid] ?? const [],
        now: now,
      );
      if (vetted == null) continue; // not consented — never enters the pool
      if (!filters.matches(vetted.profile, now)) continue;
      results.add(vetted);
    }
    // Highest-rated first — the ordering a scout scanning results actually
    // wants; ties broken by uid for a deterministic, testable order.
    results.sort((a, b) {
      final byRating =
          b.profile.ratingPercentile.compareTo(a.profile.ratingPercentile);
      return byRating != 0 ? byRating : a.profile.uid.compareTo(b.profile.uid);
    });
    return results;
  }

  /// Runs the consent gate for a single [profile], returning `null` (never
  /// a [VettedCandidate]) when it is not currently visible.
  ///
  /// This is the method to call outside of a full search — e.g. re-checking
  /// one player before letting a scout act on a stale shortlist entry (see
  /// `scout_access_ops.dart`), where consent may have been granted, expired
  /// or revoked since the entry was added.
  VettedCandidate? vetOne({
    required TalentProfile profile,
    required List<GuardianConsent> consentsForSubject,
    required DateTime now,
  }) {
    final decision = consentPolicy.mayAppearInSearch(
      subjectUserId: profile.uid,
      subjectDateOfBirth: profile.dateOfBirth,
      consentsForSubject: consentsForSubject,
      now: now,
    );
    if (!decision.allowed) return null;
    return VettedCandidate._(
      profile: profile,
      consentRecordId: decision.matchedConsent?.id,
    );
  }
}
