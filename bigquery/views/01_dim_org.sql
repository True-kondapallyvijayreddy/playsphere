-- Clubs, one row each, with the geography every other model joins on.
--
-- Built on `orgs_raw_latest` (the extension's current-state view) rather than
-- the changelog: an org's district is a fact about it now, not a time series.
--
-- ## Why the geography is coalesced twice over
--
-- `GeoLocation` (lib/core/models/geo.dart) is the current shape and a flat
-- `district` string is the legacy one, kept in parallel rather than migrated.
-- Rows written before `geo` existed only have the flat field, so a model that
-- reads one or the other loses a chunk of the country. Everything lands in
-- 'unspecified' rather than NULL so a GROUP BY does not silently drop it —
-- an org with no district is a data-quality fact worth being able to count.

CREATE OR REPLACE VIEW `playsphere_analytics.dim_org` AS
SELECT
  document_id AS org_id,
  JSON_VALUE(data, '$.name')       AS org_name,
  JSON_VALUE(data, '$.visibility') AS visibility,
  JSON_VALUE(data, '$.type')       AS org_type,
  COALESCE(
    NULLIF(LOWER(TRIM(JSON_VALUE(data, '$.geo.state'))), ''),
    NULLIF(LOWER(TRIM(JSON_VALUE(data, '$.state'))), ''),
    'unspecified'
  ) AS state,
  COALESCE(
    NULLIF(LOWER(TRIM(JSON_VALUE(data, '$.geo.district'))), ''),
    NULLIF(LOWER(TRIM(JSON_VALUE(data, '$.district'))), ''),
    'unspecified'
  ) AS district,
  NULLIF(LOWER(TRIM(JSON_VALUE(data, '$.geo.mandal'))), '')  AS mandal,
  NULLIF(LOWER(TRIM(JSON_VALUE(data, '$.geo.village'))), '') AS village,
  CAST(JSON_VALUE(data, '$.memberCount') AS INT64) AS member_count,
  JSON_VALUE(data, '$.deletedAt') IS NOT NULL      AS is_deleted
FROM `playsphere_analytics.orgs_raw_latest`
WHERE operation != 'DELETE';
