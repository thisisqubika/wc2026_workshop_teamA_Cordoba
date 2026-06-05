-- ============================================================================
-- Silver: silver_goalscorers   |  PK: goal_id  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- Clean goal events (1930+). Team names normalized via former_names
-- (date-bounded); minute typed to INT. goal_id is a deterministic surrogate
-- over all business columns (rows are DISTINCT, so the hash is unique).
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.silver.silver_goalscorers (
  goal_id    STRING  COMMENT 'PK. sha2 over date|home_team|away_team|team|scorer|minute|own_goal|penalty.',
  date       DATE     COMMENT 'Match date of the goal.',
  home_team  STRING   COMMENT 'Home team, normalized via former_names.',
  away_team  STRING   COMMENT 'Away team, normalized via former_names.',
  team       STRING   COMMENT 'Team that scored, normalized via former_names.',
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
  WITH base AS (
    SELECT DISTINCT date, home_team, away_team, team, scorer, minute, own_goal, penalty
    FROM workshop_team_a_cba.bronze.goalscorers
    WHERE year(date) >= 1930
  ),
  norm AS (
    SELECT
      b.date,
      COALESCE(fh.current, trim(b.home_team)) AS home_team,
      COALESCE(fa.current, trim(b.away_team)) AS away_team,
      COALESCE(ft.current, trim(b.team))      AS team,
      trim(b.scorer)            AS scorer,
      try_cast(b.minute AS INT) AS minute,
      b.own_goal, b.penalty,
      year(b.date)              AS year
    FROM base b
    LEFT JOIN workshop_team_a_cba.bronze.former_names fh
      ON trim(b.home_team) = fh.former AND b.date BETWEEN fh.start_date AND fh.end_date
    LEFT JOIN workshop_team_a_cba.bronze.former_names fa
      ON trim(b.away_team) = fa.former AND b.date BETWEEN fa.start_date AND fa.end_date
    LEFT JOIN workshop_team_a_cba.bronze.former_names ft
      ON trim(b.team) = ft.former AND b.date BETWEEN ft.start_date AND ft.end_date
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
