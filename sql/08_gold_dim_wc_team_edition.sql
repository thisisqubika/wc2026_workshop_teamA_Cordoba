-- ============================================================================
-- Gold: dim_wc_team_edition   |  PK: (team, wc_year)  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- One row per team per World Cup edition — how each team performed in each WC
-- it played. Enables Team B to build "progression / consistency over editions"
-- views without inferring rounds (rounds are NOT in the source data).
-- Computed from fct_wc_only over PLAYED matches, both home & away perspectives.
-- NOTE: source data is incomplete per edition and has no round labels, so this
-- table intentionally does NOT claim finishes/champions — only per-edition
-- match performance.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.gold.dim_wc_team_edition (
  team             STRING COMMENT 'Team (current, canonical name). Part of PK.',
  wc_year          INT    COMMENT 'World Cup edition year. Part of PK.',
  matches_played   BIGINT COMMENT 'Matches played by the team that edition (result known).',
  wins             BIGINT COMMENT 'Wins that edition.',
  draws            BIGINT COMMENT 'Draws that edition.',
  losses           BIGINT COMMENT 'Losses that edition.',
  goals_for        BIGINT COMMENT 'Goals scored that edition.',
  goals_against    BIGINT COMMENT 'Goals conceded that edition.',
  goal_difference  BIGINT COMMENT 'goals_for - goals_against that edition.'
)
USING DELTA
COMMENT 'Per-team, per-World-Cup-edition match performance (Gold). MERGE on (team, wc_year). No round/finish data — source lacks it.';

MERGE INTO workshop_team_a_cba.gold.dim_wc_team_edition AS tgt
USING (
  WITH team_match AS (
    SELECT home_team AS team, year AS wc_year,
           home_score AS gf, away_score AS ga, result_home AS result
    FROM workshop_team_a_cba.gold.fct_wc_only WHERE result_home IS NOT NULL
    UNION ALL
    SELECT away_team AS team, year AS wc_year,
           away_score AS gf, home_score AS ga, result_away AS result
    FROM workshop_team_a_cba.gold.fct_wc_only WHERE result_away IS NOT NULL
  )
  SELECT
    team, wc_year,
    COUNT(*)                                      AS matches_played,
    SUM(CASE WHEN result='W' THEN 1 ELSE 0 END)  AS wins,
    SUM(CASE WHEN result='D' THEN 1 ELSE 0 END)  AS draws,
    SUM(CASE WHEN result='L' THEN 1 ELSE 0 END)  AS losses,
    CAST(SUM(gf) AS BIGINT)                       AS goals_for,
    CAST(SUM(ga) AS BIGINT)                       AS goals_against,
    CAST(SUM(gf) - SUM(ga) AS BIGINT)            AS goal_difference
  FROM team_match
  GROUP BY team, wc_year
) AS src
ON tgt.team = src.team AND tgt.wc_year = src.wc_year
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
