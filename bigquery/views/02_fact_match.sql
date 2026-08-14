-- One row per completed match, attributed to the district that hosted it.
--
-- ## Why this reads the changelog and not the latest view
--
-- A fixture is rewritten on every scoring action, so `fixtures_raw_latest`
-- holds only its final state. That is enough for "who won", which is all this
-- model needs — but the *time* a match completed is not reliably on the
-- document (`completedAt` was added later than some of the data), so the
-- changelog's own `timestamp` on the write that first set
-- `status = 'completed'` is the more trustworthy clock. Taking the earliest
-- such write also makes the model immune to a fixture being reopened and
-- re-completed: the match happened once.
--
-- ## `orgId` comes from the wildcard column
--
-- Fixtures are nested three levels down. The extension is configured with
-- WILDCARD_IDS=true, which adds a `path_params` JSON column carrying the
-- `{orgId}` and `{compId}` captured from the collection path — without it a
-- match could not be attributed to a club at all.

CREATE OR REPLACE VIEW `playsphere_analytics.fact_match` AS
WITH completed AS (
  SELECT
    document_id AS fixture_id,
    JSON_VALUE(path_params, '$.orgId')  AS org_id,
    JSON_VALUE(path_params, '$.compId') AS comp_id,
    JSON_VALUE(data, '$.sportId')       AS sport_id,
    JSON_VALUE(data, '$.entrantAId')    AS entrant_a_id,
    JSON_VALUE(data, '$.entrantBId')    AS entrant_b_id,
    JSON_VALUE(data, '$.winnerEntrantId') AS winner_entrant_id,
    COALESCE(CAST(JSON_VALUE(data, '$.isDraw') AS BOOL), FALSE) AS is_draw,
    COALESCE(JSON_VALUE(data, '$.resultType'), 'normal')        AS result_type,
    timestamp AS completed_at,
    ROW_NUMBER() OVER (
      PARTITION BY document_name ORDER BY timestamp ASC
    ) AS completion_seq
  FROM `playsphere_analytics.fixtures_raw_changelog`
  WHERE operation != 'DELETE'
    AND JSON_VALUE(data, '$.status') = 'completed'
)
SELECT
  c.fixture_id,
  c.org_id,
  c.comp_id,
  c.sport_id,
  c.entrant_a_id,
  c.entrant_b_id,
  c.winner_entrant_id,
  c.is_draw,
  c.result_type,
  c.completed_at,
  DATE(c.completed_at) AS completed_date,
  o.state,
  o.district,
  -- An inter-club result: both entrant ids resolve to real clubs. A club's
  -- internal match has both sides inside one club and tells you nothing about
  -- how that club fares against others — see `loadTeamCandidates` in
  -- functions/talent.js, which applies the same test.
  (a.org_id IS NOT NULL AND b.org_id IS NOT NULL
     AND c.entrant_a_id != c.entrant_b_id) AS is_inter_club
FROM completed c
LEFT JOIN `playsphere_analytics.dim_org` o ON o.org_id = c.org_id
LEFT JOIN `playsphere_analytics.dim_org` a ON a.org_id = c.entrant_a_id
LEFT JOIN `playsphere_analytics.dim_org` b ON b.org_id = c.entrant_b_id
WHERE c.completion_seq = 1;
