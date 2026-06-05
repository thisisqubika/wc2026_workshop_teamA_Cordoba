-- ============================================================================
-- Gold: fct_match_results   |  PK: match_id  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- Silver promoted to Gold — the clean match fact table consumed by Teams B/C.
-- Same grain as silver_match_results (one row per match). MERGE on match_id.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.gold.fct_match_results (
  match_id         STRING  COMMENT 'PK. Inherited from silver_match_results.',
  date             DATE    COMMENT 'Match date.',
  home_team        STRING  COMMENT 'Home team (current name).',
  away_team        STRING  COMMENT 'Away team (current name).',
  home_score       INT     COMMENT 'Home goals. NULL if unknown.',
  away_score       INT     COMMENT 'Away goals. NULL if unknown.',
  tournament_clean STRING  COMMENT 'Tournament name.',
  city             STRING  COMMENT 'Host city.',
  country          STRING  COMMENT 'Host country.',
  neutral          BOOLEAN COMMENT 'TRUE if neutral ground.',
  result_home      STRING  COMMENT 'W/D/L home perspective.',
  result_away      STRING  COMMENT 'W/D/L away perspective.',
  is_world_cup     BOOLEAN COMMENT 'TRUE if FIFA World Cup match.',
  had_shootout     BOOLEAN COMMENT 'TRUE if decided by shootout.',
  shootout_winner  STRING  COMMENT 'Shootout winner. NULL if none.',
  year             INT     COMMENT 'Match year.',
  decade           INT     COMMENT 'Decade bucket.'
)
USING DELTA
COMMENT 'Clean match fact table (Gold). MERGE-promoted from silver_match_results on match_id.';

MERGE INTO workshop_team_a_cba.gold.fct_match_results AS tgt
USING (SELECT * FROM workshop_team_a_cba.silver.silver_match_results) AS src
ON tgt.match_id = src.match_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
