-- Every player's rating movement, over any window, from the full history.
--
-- ## Why this is strictly better than the trail it mirrors
--
-- The rating document carries a bounded `trail` of the last 24 snapshots
-- (see `onMatchSettled`), because an array that grows for a whole career
-- would become the largest thing in a document that is re-read on every
-- match. That bound is right for Firestore and it is a real limit: a player
-- in a daily league fills 24 snapshots in three weeks, so a 90-day trend
-- computed from the trail silently measures three weeks instead.
--
-- The changelog has no such bound. Every rating write ever made is a row
-- here, so this view answers the same question with the whole history — and
-- can answer it for windows the trail could never reach, like "improvement
-- across a season" or "how did this cohort develop over two years".
--
-- `functions/talent.js` reads the trail today and this view once the
-- warehouse is populated. Both produce the same shape; this one is simply
-- not lying about the window when a player is very active.

CREATE OR REPLACE VIEW `playsphere_analytics.player_rating_history` AS
SELECT
  JSON_VALUE(path_params, '$.uid') AS uid,
  document_id                      AS rating_key,
  -- Chess is rated per time control (`chess_blitz`), everything else rates as
  -- itself. Boards are per sport, so the control is trimmed back off.
  SPLIT(document_id, '_')[OFFSET(0)] AS sport_id,
  CAST(JSON_VALUE(data, '$.rating')      AS FLOAT64) AS rating,
  CAST(JSON_VALUE(data, '$.deviation')   AS FLOAT64) AS deviation,
  CAST(JSON_VALUE(data, '$.gamesPlayed') AS INT64)   AS games_played,
  timestamp AS recorded_at
FROM `playsphere_analytics.ratings_raw_changelog`
WHERE operation != 'DELETE'
  AND JSON_VALUE(data, '$.rating') IS NOT NULL;

-- The 90-day trend, in the exact shape `RisingSignal` produces.
--
-- ## The baseline must come from before the window
--
-- `baseline_rating` is the last reading taken *before* the window opened, via
-- LAST_VALUE over the preceding rows — not the first reading inside it.
-- Anchoring inside would discard the gain from the window's first match,
-- which for a player with four results in ninety days throws away a quarter
-- of the signal. `lib/domain/scout/talent_trend.dart` makes the same choice
-- and `test/talent_trend_test.dart` pins it.
--
-- The score formula (`delta * matches / (matches + 3)`) and the eligibility
-- floor (3 matches, positive delta) mirror `RisingSignal` exactly. See that
-- class for why the score is built on the *change* and never on the level:
-- ranking by rating just reproduces the leaderboard that already exists.
CREATE OR REPLACE VIEW `playsphere_analytics.player_rating_trend_90d` AS
WITH windowed AS (
  SELECT
    uid,
    sport_id,
    rating,
    deviation,
    recorded_at,
    recorded_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
      AS in_window,
    LAST_VALUE(
      IF(recorded_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY),
         rating, NULL)
      IGNORE NULLS
    ) OVER (
      PARTITION BY uid, sport_id
      ORDER BY recorded_at
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS baseline_rating
  FROM `playsphere_analytics.player_rating_history`
),
latest AS (
  SELECT
    uid,
    sport_id,
    ARRAY_AGG(rating     ORDER BY recorded_at DESC LIMIT 1)[OFFSET(0)] AS current_rating,
    ARRAY_AGG(deviation  ORDER BY recorded_at DESC LIMIT 1)[OFFSET(0)] AS current_deviation,
    ARRAY_AGG(baseline_rating ORDER BY recorded_at DESC LIMIT 1)[OFFSET(0)] AS baseline_rating,
    -- The oldest reading held, used only when the player has no history at
    -- all before the window — the honest fallback baseline.
    ARRAY_AGG(rating ORDER BY recorded_at ASC LIMIT 1)[OFFSET(0)] AS first_rating,
    COUNTIF(in_window) AS readings_in_window,
    MAX(recorded_at)   AS last_played_at
  FROM windowed
  GROUP BY uid, sport_id
)
SELECT
  uid,
  sport_id,
  current_rating,
  current_deviation,
  COALESCE(baseline_rating, first_rating) AS baseline_rating,
  baseline_rating IS NULL                 AS truncated_span,
  -- With no pre-window baseline the first reading IS the baseline, so it must
  -- not also count as one of the matches that moved away from it.
  IF(baseline_rating IS NULL, readings_in_window - 1, readings_in_window)
    AS matches_in_window,
  current_rating - COALESCE(baseline_rating, first_rating) AS rating_delta,
  current_deviation > 110 AS provisional,
  last_played_at
FROM latest;
