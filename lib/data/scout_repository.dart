import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../domain/rating/cross_sport_index.dart';
import '../domain/rating/glicko2.dart';
import '../domain/scout/player_verification_tier.dart';
import '../domain/scout/talent_profile.dart';

/// One candidate as a scout's results list actually needs to render it:
/// [TalentProfile] (the consent-safe reduced view) plus the display name and
/// photo a search result reasonably shows once the read has already cleared
/// every privacy gate below. Kept out of `TalentProfile` itself deliberately
/// — see that class's doc on why it stays a minimal, purpose-built shape.
class ScoutSearchResult {
  const ScoutSearchResult({
    required this.profile,
    required this.displayName,
    this.photoUrl,
  });

  final TalentProfile profile;
  final String displayName;
  final String? photoUrl;
}

/// Talent search, wired to real data for the first time.
///
/// ## Where the actual safety boundary is
///
/// `lib/domain/scout/talent_search.dart` documents a `TalentSearch`/
/// `ConsentPolicy`/`GuardianConsent` pipeline built against a *time-bounded,
/// per-scope* consent record (`grantedAt`/`expiresAt`/`verificationMethod`).
/// The consent record `firestore.rules` actually enforces today, at
/// `users/{minorUid}/guardianConsents/{granteeUid}`, is a simpler,
/// already-shipped shape: one document per (minor, scout) pair, a
/// `consentedTo` list of scope strings, and a bare `revoked` flag — no
/// expiry field exists there at all. The two were never reconciled.
///
/// Rather than force real Firestore data through a Dart type whose
/// constructor invariants (a maximum validity window, a verification method)
/// the real record cannot honestly supply, this repository relies on the
/// boundary that is actually deployed: `firestore.rules` on `/users/{userId}`
/// already refuses to serve a minor's document to anyone except a scout
/// holding an unrevoked `guardianConsents` record naming them specifically.
/// A [TalentProfile] is only ever constructed here from a document read that
/// has *already* cleared that rule — so by the time [searchCandidates]
/// builds one, consent (for a minor) or public/community visibility (for an
/// adult) is a proven fact, not a client-side claim. [TalentSearchFilters]
/// (sport/age/geo/rating/verification/recency) is applied on top of that
/// already-safe set, exactly as its own doc describes.
///
/// ## Verification tier — not computed yet
///
/// Every candidate here reports [PlayerVerificationTier.self]. Nothing in
/// the product yet derives `scorer_verified` (a scorer who is not the player
/// vouching for a result) or `association_verified` (a sports body attesting
/// one) — `player_verification_tier.dart`'s schema anticipates both, but no
/// Cloud Function computes them. A search filtered to verified-only will
/// therefore honestly return nothing today rather than a fabricated signal.
///
/// ## Rating percentile — a sample, not the true population
///
/// [SportPopulation] should ideally be the *entire* rated population for a
/// sport. Computing and maintaining that continuously is a materialized-view
/// job of its own (mirroring how `docs/IMPLEMENTATION_STATUS.md` treats
/// BigQuery rollups as separate infrastructure from an on-demand Firestore
/// read). Until that job exists, this repository builds the population from
/// whichever candidates the search itself fetched — an honest, if smaller,
/// sample, never a fabricated global figure.
class ScoutRepository {
  const ScoutRepository();

  /// Searches for players in [sportId], applying [filters] to the set of
  /// candidates this reader is actually allowed to see.
  ///
  /// [limit] bounds how many `career_stats` rows are considered before
  /// filtering — the result list is usually smaller once filters and
  /// per-document consent gates are applied.
  Future<List<ScoutSearchResult>> searchCandidates({
    required String sportId,
    TalentSearchFilters filters = TalentSearchFilters.none,
    int limit = 60,
  }) async {
    final now = DateTime.now();

    QuerySnapshot<Map<String, dynamic>> statsSnap;
    try {
      statsSnap = await Refs.careerStatsGroup
          .where('sportId', isEqualTo: sportId)
          .orderBy('lastPlayedAt', descending: true)
          .limit(limit)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return const [];
      rethrow;
    }

    final lastPlayedByUid = <String, DateTime?>{};
    for (final doc in statsSnap.docs) {
      final uid = doc.data()['uid'] as String?;
      if (uid == null) continue;
      final ts = doc.data()['lastPlayedAt'];
      lastPlayedByUid[uid] = ts is Timestamp ? ts.toDate() : null;
    }

    final candidates = <(AppUser, Rating, DateTime?)>[];
    for (final uid in lastPlayedByUid.keys) {
      // Tolerant per-document read: a permission-denied here means exactly
      // what it means at `/users/{userId}` in `firestore.rules` — a minor
      // with no consent record for this reader, or an adult who kept their
      // profile private. Either way, "not visible" — never an error the
      // search itself should surface.
      final AppUser user;
      try {
        final userDoc = await Refs.user(uid).get();
        if (!userDoc.exists) continue;
        user = AppUser.fromDoc(userDoc);
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') continue;
        rethrow;
      }

      Rating rating = const Rating();
      try {
        final ratingDoc = await Refs.userRating(uid, sportId).get();
        if (ratingDoc.exists) {
          final d = ratingDoc.data()!;
          rating = Rating(
            rating: (d['rating'] as num?)?.toDouble() ?? Rating.defaultRating,
            deviation:
                (d['deviation'] as num?)?.toDouble() ?? Rating.defaultDeviation,
            volatility: (d['volatility'] as num?)?.toDouble() ??
                Rating.defaultVolatility,
            gamesPlayed: (d['gamesPlayed'] as num?)?.toInt() ?? 0,
          );
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }

      candidates.add((user, rating, lastPlayedByUid[uid]));
    }

    // The population this batch's percentiles are computed against — see
    // the class doc on why this is a sample, not the true global figure.
    final population = SportPopulation(
      sportId: sportId,
      ratings: [for (final (_, rating, _) in candidates) rating.rating],
    );

    final results = <ScoutSearchResult>[];
    for (final (user, rating, lastPlayedAt) in candidates) {
      final profile = TalentProfile(
        uid: user.uid,
        dateOfBirth: user.dateOfBirth,
        sportId: sportId,
        geo: user.geo,
        ratingPercentile: population.percentileOf(rating.rating),
        verificationTier: PlayerVerificationTier.self,
        lastMatchAt: lastPlayedAt,
      );
      if (!filters.matches(profile, now)) continue;
      results.add(ScoutSearchResult(
        profile: profile,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      ));
    }

    results.sort(
      (a, b) => b.profile.ratingPercentile.compareTo(a.profile.ratingPercentile),
    );
    return results;
  }
}
