import 'package:equatable/equatable.dart';

/// PHASE 8 — Talent Graph & Career Page (Discovery Layer)
///
/// Turn already-captured data into a search surface for
/// scouts/academies and a shareable page for players. See spec §8.

// ---------------------------------------------------------------------------
// 8.1 Career page — generated view, not a new writable object.
// ---------------------------------------------------------------------------

/// Purpose: read-model composed at render time from PlayerProfile +
/// all RatingHistoryEntry (for the rating-over-time chart) + all
/// visible Achievement rows + linked MediaAlbum photos where the
/// player was tagged. Published at
/// playsphere.app/p/{career_page_slug} once
/// PlayerProfile.careerPageSlug is set (auto-generate on first
/// sanctioned-tier achievement, or manually by the player/guardian).
///
/// This is intentionally NOT persisted as its own table — it is a
/// query composition. Modeled here only as the shape a
/// repository/view-layer should assemble.
class CareerPageView extends Equatable {
  const CareerPageView({
    required this.playerProfileId,
    required this.careerPageSlug,
    required this.ratingHistoryPointsBySport,
    required this.visibleAchievementIds,
    required this.taggedMediaAssetIds,
  });

  final String playerProfileId;
  final String careerPageSlug;

  /// sportId -> ordered list of (fixtureId?, ratingAfter, at) points
  /// for the rating-over-time chart. Kept as a loose map here since
  /// the concrete point shape belongs to RatingHistoryEntryEntity
  /// (Phase 5).
  final Map<String, List<Map<String, dynamic>>> ratingHistoryPointsBySport;
  final List<String> visibleAchievementIds;
  final List<String> taggedMediaAssetIds;

  // TODO(business-rules, enforce in the view/query layer — none
  // implemented yet):
  //  - Must respect visibility at render time — filter Achievement
  //    rows by visibilityOverride (or inherited default) resolved
  //    against the viewer's identity:
  //      anonymous viewer   -> only `statewide`-visible items
  //      org-mate           -> `community` + `statewide`
  //      self/guardian      -> everything
  //  - Apply the Phase 6 minor-lock rule before any of the above.

  @override
  List<Object?> get props => [
        playerProfileId,
        careerPageSlug,
        ratingHistoryPointsBySport,
        visibleAchievementIds,
        taggedMediaAssetIds,
      ];
}

// ---------------------------------------------------------------------------
// 8.2 TalentSearchIndex
// ---------------------------------------------------------------------------

/// Purpose: a denormalized, queryable index (Elasticsearch/Postgres
/// full-text + filters — implementation detail, not a
/// source-of-truth table) rebuilt from PlayerProfile + RatingRecord +
/// Achievement, filterable by sport, age category (derived from
/// dateOfBirth), region (derived from org hierarchy), and rating
/// trend (slope of recent RatingHistoryEntry points).
class TalentSearchIndexEntry extends Equatable {
  const TalentSearchIndexEntry({
    required this.playerProfileId,
    required this.sportId,
    required this.ageCategory,
    required this.regionOrgId,
    required this.currentRating,
    required this.ratingTrendSlope,
    required this.indexedVisibilityFloor,
  });

  final String playerProfileId;
  final String sportId;

  /// derived from User.dateOfBirth at index-build time, e.g. "U16".
  final String ageCategory;

  /// derived from org hierarchy (which org tier this player rolls up
  /// to for region filtering).
  final String regionOrgId;
  final double currentRating;

  /// slope of recent RatingHistoryEntry points.
  final double ratingTrendSlope;

  /// The minimum resolved visibility this indexed row represents.
  /// Documents the invariant below; not itself a query filter value
  /// a caller sets.
  final String indexedVisibilityFloor;

  // TODO(business-rules, enforce in the index-build job — not
  // implemented yet):
  //  - Only index rows where resolved visibility >= `statewide` — the
  //    index must never contain data the visibility engine wouldn't
  //    otherwise show that viewer class.

  @override
  List<Object?> get props => [
        playerProfileId,
        sportId,
        ageCategory,
        regionOrgId,
        currentRating,
        ratingTrendSlope,
        indexedVisibilityFloor,
      ];
}
