-- ============================================================================
-- Gold: fct_wc_only   |  PK: match_id  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- World Cup matches only (is_world_cup = true). Same grain/columns as
-- fct_match_results; a convenience fact for WC-specific analytics.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.gold.fct_wc_only (
  match_id         STRING  COMMENT 'PK. FIFA World Cup match.',
  date             DATE    COMMENT 'Match date.',
  home_team        STRING  COMMENT 'Home team (current name).',
  away_team        STRING  COMMENT 'Away team (current name).',
  home_score       INT     COMMENT 'Home goals.',
  away_score       INT     COMMENT 'Away goals.',
  tournament_clean STRING  COMMENT 'Tournament name (FIFA World Cup).',
  city             STRING  COMMENT 'Host city.',
  country          STRING  COMMENT 'Host country.',
  neutral          BOOLEAN COMMENT 'TRUE if neutral ground.',
  result_home      STRING  COMMENT 'W/D/L home perspective.',
  result_away      STRING  COMMENT 'W/D/L away perspective.',
  is_world_cup     BOOLEAN COMMENT 'Always TRUE in this table.',
  had_shootout     BOOLEAN COMMENT 'TRUE if decided by shootout.',
  shootout_winner  STRING  COMMENT 'Shootout winner. NULL if none.',
  year             INT     COMMENT 'Tournament year.',
  decade           INT     COMMENT 'Decade bucket.'
)
USING DELTA
COMMENT 'World Cup matches only (Gold). MERGE-filtered from silver_match_results where is_world_cup.';

MERGE INTO workshop_team_a_cba.gold.fct_wc_only AS tgt
USING (SELECT * FROM workshop_team_a_cba.silver.silver_match_results WHERE is_world_cup) AS src
ON tgt.match_id = src.match_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
