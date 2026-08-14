-- The government dashboard's rollup: clubs, members, events and matches per
-- district.
--
-- ## What this replaces
--
-- `computeGovAggregates` (functions/gov.js) computes the same four numbers by
-- reading every org, every competition and every completed fixture in the
-- database on each run. That is three unbounded collection scans in one
-- 300-second function, and it is the thing that stops working first as the
-- product grows — not because the maths is hard but because the read is.
--
-- Here the same answer is a partition-pruned aggregate the warehouse is built
-- to do. `syncGovAggregates` in functions/analytics.js runs this and writes
-- the rows into Firestore for the app to read; the Firestore scan stays as
-- the fallback for a project whose warehouse is not provisioned yet.
--
-- ## Deleted clubs
--
-- Excluded from every count, including historic ones. A district's "clubs"
-- figure is a statement about what exists now, and a dashboard that counts
-- deleted clubs to make a district look busier is worse than no dashboard.

CREATE OR REPLACE VIEW `playsphere_analytics.participation_by_district` AS
WITH clubs AS (
  SELECT
    state,
    district,
    COUNT(*)                        AS club_count,
    SUM(COALESCE(member_count, 0))  AS member_count
  FROM `playsphere_analytics.dim_org`
  WHERE NOT is_deleted
  GROUP BY state, district
),
events AS (
  SELECT
    o.state,
    o.district,
    COUNT(DISTINCT c.document_id) AS competition_count
  FROM `playsphere_analytics.competitions_raw_latest` c
  JOIN `playsphere_analytics.dim_org` o
    ON o.org_id = JSON_VALUE(c.path_params, '$.orgId')
  WHERE c.operation != 'DELETE' AND NOT o.is_deleted
  GROUP BY o.state, o.district
),
matches AS (
  SELECT
    state,
    district,
    COUNT(*) AS completed_match_count,
    COUNT(DISTINCT sport_id) AS sports_played
  FROM `playsphere_analytics.fact_match`
  WHERE state IS NOT NULL
  GROUP BY state, district
)
SELECT
  clubs.state,
  clubs.district,
  clubs.club_count,
  clubs.member_count,
  COALESCE(events.competition_count, 0)     AS competition_count,
  COALESCE(matches.completed_match_count, 0) AS completed_match_count,
  COALESCE(matches.sports_played, 0)         AS sports_played
FROM clubs
LEFT JOIN events
  ON events.state = clubs.state AND events.district = clubs.district
LEFT JOIN matches
  ON matches.state = clubs.state AND matches.district = clubs.district;
