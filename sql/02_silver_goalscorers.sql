-- ============================================================================
-- Silver: silver_goalscorers   |  PK: goal_id  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- Clean goal events (1930+). Casing fix via _team_name_map, then team-name
-- normalization via former_names (date-bounded); minute typed to INT.
-- goal_id is a deterministic surrogate over all business columns.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.silver.silver_goalscorers (
  goal_id    STRING  COMMENT 'PK. sha2 over date|home_team|away_team|team|scorer|minute|own_goal|penalty.',
  date       DATE     COMMENT 'Match date of the goal.',
  home_team  STRING   COMMENT 'Home team, casing-fixed + normalized via former_names.',
  away_team  STRING   COMMENT 'Away team, casing-fixed + normalized via former_names.',
  team       STRING   COMMENT 'Team that scored, casing-fixed + normalized via former_names.',
  scorer     STRING   COMMENT 'Player who scored.',
  minute     INT      COMMENT 'Minute of the goal. NULL where source was non-numeric.',
  own_goal   BOOLEAN  COMMENT 'TRUE if own goal.',
  penalty    BOOLEAN  COMMENT 'TRUE if scored from a penalty.',
  year       INT      COMMENT 'Calendar year of the goal.'
)
USING DELTA
COMMENT 'Clean individual goal events (1930+). MERGE-upserted from bronze.goalscorers on goal_id.';

MERGE INTO workshop_team_a_cba.silver.silver_goalscorers AS tgt
USING (
  WITH mapped AS (
    SELECT
      g.date,
      COALESCE(mh.canonical_name, trim(g.home_team)) AS home_team_c,
      COALESCE(ma.canonical_name, trim(g.away_team)) AS away_team_c,
      COALESCE(mt.canonical_name, trim(g.team))      AS team_c,
      g.scorer, g.minute, g.own_goal, g.penalty
    FROM workshop_team_a_cba.bronze.goalscorers g
    LEFT JOIN workshop_team_a_cba.silver._team_name_map mh ON trim(g.home_team) = mh.raw_name
    LEFT JOIN workshop_team_a_cba.silver._team_name_map ma ON trim(g.away_team) = ma.raw_name
    LEFT JOIN workshop_team_a_cba.silver._team_name_map mt ON trim(g.team)      = mt.raw_name
    WHERE year(g.date) >= 1930
  ),
  dedup AS (
    SELECT DISTINCT date, home_team_c, away_team_c, team_c, scorer, minute, own_goal, penalty FROM mapped
  ),
  norm AS (
    SELECT
      d.date,
      COALESCE(fh.current, d.home_team_c) AS home_team,
      COALESCE(fa.current, d.away_team_c) AS away_team,
      COALESCE(ft.current, d.team_c)      AS team,
      trim(d.scorer)            AS scorer,
      try_cast(d.minute AS INT) AS minute,
      d.own_goal, d.penalty,
      year(d.date)              AS year
    FROM dedup d
    LEFT JOIN workshop_team_a_cba.bronze.former_names fh
      ON d.home_team_c = fh.former AND d.date BETWEEN fh.start_date AND fh.end_date
    LEFT JOIN workshop_team_a_cba.bronze.former_names fa
      ON d.away_team_c = fa.former AND d.date BETWEEN fa.start_date AND fa.end_date
    LEFT JOIN workshop_team_a_cba.bronze.former_names ft
      ON d.team_c = ft.former AND d.date BETWEEN ft.start_date AND ft.end_date
  )
  SELECT
    sha2(concat_ws('|', CAST(date AS STRING), home_team, away_team, team, scorer,
         COALESCE(CAST(minute AS STRING), 'NA'), CAST(own_goal AS STRING), CAST(penalty AS STRING)), 256) AS goal_id,
    date, home_team, away_team, team, scorer, minute, own_goal, penalty, year
  FROM norm
) AS src
ON tgt.goal_id = src.goal_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
