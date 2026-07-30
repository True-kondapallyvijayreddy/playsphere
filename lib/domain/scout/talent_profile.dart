import '../../core/models/geo.dart';
import '../gov/age_group.dart' show AgeGroup;
import 'player_verification_tier.dart';

/// One player as a scout would see them in a search result: the flat set of
/// facts §6 Module C's talent-discovery filters actually operate on.
///
/// Deliberately *not* the same type as `AppUser` — a scout never needs (and
/// under §2.7 should frequently not be allowed) the full user document. This
/// is a purpose-built, reduced view, assembled by whatever layer already has
/// consent-check access to the underlying profile. `dateOfBirth` is kept
/// (rather than a precomputed age or `isMinor` flag) for the same §12.8
/// reason it is kept on `AppUser`: age must be derivable fresh at query
/// time, never read from a value that can go stale.
class TalentProfile {
  const TalentProfile({
    required this.uid,
    required this.dateOfBirth,
    required this.sportId,
    required this.geo,
    required this.ratingPercentile,
    required this.verificationTier,
    this.lastMatchAt,
  });

  final String uid;
  final DateTime dateOfBirth;
  final String sportId;
  final GeoLocation geo;

  /// This player's Sports OS Index / sport-specific rating percentile
  /// (0–100), as defined in CLAUDE.md §8.2. Kept as a plain percentile
  /// rather than a raw Glicko rating so filters read naturally ("top 10%")
  /// without this layer needing to know anything about Glicko-2 or RD.
  final double ratingPercentile;

  final PlayerVerificationTier verificationTier;

  /// When this player last played a match, if ever. Null for a profile with
  /// no match history yet. Drives the "recent form" filter — a rating
  /// percentile earned two years ago and never refreshed is a materially
  /// different signal to a scout than the same percentile earned last week.
  final DateTime? lastMatchAt;
}

/// A pure, composable set of scout search filters — §6 Module C's "sport,
/// age group, district/mandal, rating percentile, verified-only, recent
/// form", modelled as one value object.
///
/// This type intentionally has **no knowledge of consent**. It only ever
/// answers "does this profile match these sport/age/location/rating/
/// verification/recency criteria" — a question that is safe to answer for
/// any profile, adult or minor, because it never returns anything by
/// itself. The consent gate lives one layer up, in `TalentSearch.run`
/// (`talent_search.dart`), which is why that file — not this one — is where
/// "impossible to construct an unconsented result" is enforced. Keeping the
/// two concerns in separate types means a bug in filter logic (e.g. a typo
/// in a rating comparison) can never accidentally widen who becomes
/// visible; filters can only narrow an already-consent-checked set.
class TalentSearchFilters {
  const TalentSearchFilters({
    this.sportId,
    this.ageGroup,
    this.district,
    this.mandal,
    this.minRatingPercentile,
    this.minVerificationTier,
    this.activeWithin,
  });

  /// No filters applied — matches every candidate. Still subject to the
  /// consent gate in `TalentSearch.run`, which runs unconditionally.
  static const none = TalentSearchFilters();

  final String? sportId;

  /// Filters by Khelo India age band (`lib/domain/gov/age_group.dart`),
  /// reusing the exact same bands the government dashboards use rather than
  /// inventing a second, competing notion of "age group" for scouts.
  final AgeGroup? ageGroup;

  final String? district;
  final String? mandal;

  /// Only include players at or above this percentile (0–100).
  final double? minRatingPercentile;

  final PlayerVerificationTier? minVerificationTier;

  /// Only include players whose [TalentProfile.lastMatchAt] falls within
  /// this duration of the search instant. A player with no match history at
  /// all (`lastMatchAt == null`) never satisfies this filter, by design —
  /// "recent form" cannot be claimed for someone with no form on record.
  final Duration? activeWithin;

  /// Whether [profile] satisfies every filter set here, evaluated as of
  /// [now]. Age group is derived fresh from `profile.dateOfBirth` against
  /// [now] on every call (§12.8) — never cached on [TalentProfile] and never
  /// passed in separately, so a search run today and the same search run a
  /// year from now naturally reclassify anyone who aged out of a band, with
  /// no migration or backfill needed.
  bool matches(TalentProfile profile, DateTime now) {
    if (sportId != null && profile.sportId != sportId) return false;

    if (ageGroup != null) {
      final band = AgeGroup.fromDateOfBirth(profile.dateOfBirth, referenceDate: now);
      if (band != ageGroup) return false;
    }

    if (district != null && profile.geo.district != district) return false;
    if (mandal != null && profile.geo.mandal != mandal) return false;

    if (minRatingPercentile != null &&
        profile.ratingPercentile < minRatingPercentile!) {
      return false;
    }

    if (minVerificationTier != null &&
        !profile.verificationTier.atLeast(minVerificationTier!)) {
      return false;
    }

    if (activeWithin != null) {
      final lastMatchAt = profile.lastMatchAt;
      if (lastMatchAt == null) return false;
      if (now.difference(lastMatchAt) > activeWithin!) return false;
    }

    return true;
  }
}
