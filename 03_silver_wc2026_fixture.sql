-- ============================================================================
-- Silver: silver_wc2026_fixture   |  PK: team  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- WC2026 qualified teams (48) with correct types. Source already clean —
-- light trim/type pass. Upserted on team.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.silver.silver_wc2026_fixture (
  team          STRING  COMMENT 'PK. Qualified national team (matches dim_team_stats.team).',
  group_name    STRING  COMMENT 'WC2026 group letter.',
  confederation STRING  COMMENT 'FIFA confederation (UEFA, CONMEBOL, ...).',
  fifa_ranking  INT     COMMENT 'FIFA ranking at qualification.',
  is_host       BOOLEAN COMMENT 'TRUE if a tournament host nation.'
)
USING DELTA
COMMENT 'WC2026 qualified teams (48), typed. MERGE-upserted from bronze.wc2026_fixture on team.';

MERGE INTO workshop_team_a_cba.silver.silver_wc2026_fixture AS tgt
USING (
  SELECT
    trim(team)                AS team,
    trim(`group`)             AS group_name,
    trim(confederation)       AS confederation,
    CAST(fifa_ranking AS INT) AS fifa_ranking,
    is_host
  FROM workshop_team_a_cba.bronze.wc2026_fixture
) AS src
ON tgt.team = src.team
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
