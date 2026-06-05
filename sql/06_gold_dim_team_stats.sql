-- ============================================================================
-- Gold: dim_team_stats   |  PK: team  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- One row per team — cumulative historical statistics over PLAYED matches only
-- (result IS NOT NULL), computed from both home and away perspectives. Unplayed
-- future fixtures (e.g. WC2026 schedule) and NA-score rows are excluded so the
-- stats reflect real history. Designed for a tournament simulator / ranking:
--   * strength: win_pct, avg_goals_for/against (attack/defense rates)
--   * comparability: matches_played, goal_difference
--   * defense: clean_sheets, clean_sheet_pct
--   * form: recent_win_pct_last20 (last 20 played matches by date)
--   * World Cup pedigree: wc_appearances, wc_matches_played, wc_wins,
--     wc_win_pct, wc goals, wc_goal_difference.
-- NOTE: WC "best finish"/champions are NOT included — source data is incomplete
-- per edition and has no round labels (see dim_wc_team_edition).
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.gold.dim_team_stats (
  team                STRING COMMENT 'PK. National team (current, canonical name).',
  matches_played      BIGINT COMMENT 'Played match appearances (home + away, result known).',
  wins                BIGINT COMMENT 'Total wins.',
  draws               BIGINT COMMENT 'Total draws.',
  losses              BIGINT COMMENT 'Total losses.',
  win_pct             DOUBLE COMMENT 'wins / matches_played (0-1).',
  goals_for           BIGINT COMMENT 'Total goals scored.',
  goals_against       BIGINT COMMENT 'Total goals conceded.',
  goal_difference     BIGINT COMMENT 'goals_for - goals_against.',
  avg_goals_for       DOUBLE COMMENT 'Attack rate: goals_for / matches_played.',
  avg_goals_against   DOUBLE COMMENT 'Defense rate: goals_against / matches_played.',
  clean_sheets        BIGINT COMMENT 'Played matches with 0 goals conceded.',
  clean_sheet_pct     DOUBLE COMMENT 'clean_sheets / matches_played (0-1).',
  recent_win_pct_last20 DOUBLE COMMENT 'Form: win rate over the team''s last 20 played matches by date (0-1).',
  first_match         DATE   COMMENT 'Earliest played match date (1930+).',
  last_match          DATE   COMMENT 'Most recent played match date.',
  wc_appearances      BIGINT COMMENT 'Distinct World Cup editions (years) the team actually played.',
  wc_matches_played   BIGINT COMMENT 'Total World Cup matches played.',
  wc_wins             BIGINT COMMENT 'World Cup matches won.',
  wc_win_pct          DOUBLE COMMENT 'wc_wins / wc_matches_played (0-1). NULL if none.',
  wc_goals_for        BIGINT COMMENT 'World Cup goals scored.',
  wc_goals_against    BIGINT COMMENT 'World Cup goals conceded.',
  wc_goal_difference  BIGINT COMMENT 'wc_goals_for - wc_goals_against.'
)
USING DELTA
COMMENT 'One row per team: cumulative historical + World Cup stats over played matches (Gold). MERGE on team.';

MERGE INTO workshop_team_a_cba.gold.dim_team_stats AS tgt
USING (
  WITH team_match AS (
    SELECT home_team AS team, date, year, is_world_cup,
           home_score AS gf, away_score AS ga, result_home AS result
    FROM workshop_team_a_cba.silver.silver_match_results
    WHERE result_home IS NOT NULL          -- played matches only
    UNION ALL
    SELECT away_team AS team, date, year, is_world_cup,
           away_score AS gf, home_score AS ga, result_away AS result
    FROM workshop_team_a_cba.silver.silver_match_results
    WHERE result_away IS NOT NULL
  ),
  recent AS (
    SELECT team, result,
           ROW_NUMBER() OVER (PARTITION BY team ORDER BY date DESC) AS rn
    FROM team_match
  ),
  recent_form AS (
    SELECT team,
           ROUND(SUM(CASE WHEN result='W' THEN 1 ELSE 0 END) / COUNT(*), 4) AS recent_win_pct_last20
    FROM recent WHERE rn <= 20 GROUP BY team
  ),
  base AS (
    SELECT
      team,
      COUNT(*)                                                  AS matches_played,
      SUM(CASE WHEN result='W' THEN 1 ELSE 0 END)             AS wins,
      SUM(CASE WHEN result='D' THEN 1 ELSE 0 END)             AS draws,
      SUM(CASE WHEN result='L' THEN 1 ELSE 0 END)             AS losses,
      ROUND(SUM(CASE WHEN result='W' THEN 1 ELSE 0 END) / COUNT(*), 4) AS win_pct,
      CAST(SUM(gf) AS BIGINT)                                  AS goals_for,
      CAST(SUM(ga) AS BIGINT)                                  AS goals_against,
      CAST(SUM(gf) - SUM(ga) AS BIGINT)                       AS goal_difference,
      ROUND(SUM(gf) / COUNT(*), 4)                            AS avg_goals_for,
      ROUND(SUM(ga) / COUNT(*), 4)                            AS avg_goals_against,
      SUM(CASE WHEN ga = 0 THEN 1 ELSE 0 END)                AS clean_sheets,
      ROUND(SUM(CASE WHEN ga = 0 THEN 1 ELSE 0 END) / COUNT(*), 4) AS clean_sheet_pct,
      MIN(date)                                                AS first_match,
      MAX(date)                                                AS last_match,
      COUNT(DISTINCT CASE WHEN is_world_cup THEN year END)     AS wc_appearances,
      SUM(CASE WHEN is_world_cup THEN 1 ELSE 0 END)           AS wc_matches_played,
      SUM(CASE WHEN is_world_cup AND result='W' THEN 1 ELSE 0 END) AS wc_wins,
      ROUND(SUM(CASE WHEN is_world_cup AND result='W' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN is_world_cup THEN 1 ELSE 0 END),0), 4) AS wc_win_pct,
      CAST(SUM(CASE WHEN is_world_cup THEN gf ELSE 0 END) AS BIGINT) AS wc_goals_for,
      CAST(SUM(CASE WHEN is_world_cup THEN ga ELSE 0 END) AS BIGINT) AS wc_goals_against,
      CAST(SUM(CASE WHEN is_world_cup THEN gf ELSE 0 END)
         - SUM(CASE WHEN is_world_cup THEN ga ELSE 0 END) AS BIGINT) AS wc_goal_difference
    FROM team_match
    GROUP BY team
  )
  SELECT
    b.team, b.matches_played, b.wins, b.draws, b.losses, b.win_pct,
    b.goals_for, b.goals_against, b.goal_difference, b.avg_goals_for, b.avg_goals_against,
    b.clean_sheets, b.clean_sheet_pct, rf.recent_win_pct_last20,
    b.first_match, b.last_match,
    b.wc_appearances, b.wc_matches_played, b.wc_wins, b.wc_win_pct,
    b.wc_goals_for, b.wc_goals_against, b.wc_goal_difference
  FROM base b
  LEFT JOIN recent_form rf ON b.team = rf.team
) AS src
ON tgt.team = src.team
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
