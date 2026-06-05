-- ============================================================================
-- Silver: silver_match_results   |  PK: match_id  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- One row per match (1930+). DQ fixes applied:
--   * casing fix via _team_name_map (e.g. "SPAIN"->"Spain") BEFORE dedup/former_names
--   * dedupe exact + casing-duplicate rows
--   * parse mixed date formats (yyyy-MM-dd + dd/MM/yyyy) -> 100% coverage
--   * non-numeric "NA" scores -> NULL (rows kept, incl. unplayed 2026 fixtures)
--   * neutral TRUE/FALSE strings -> boolean
--   * filter pre-1930
--   * team-name normalization via former_names (date-bounded)
--   * shootout enrichment from bronze.shootouts (also casing-normalized)
-- Rerunnable: DDL IF NOT EXISTS; load is MERGE on match_id with delete-on-miss.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.silver.silver_match_results (
  match_id          STRING  COMMENT 'PK. sha2(date|home_team|away_team|tournament|home_score|away_score, 256).',
  date              DATE    COMMENT 'Match date. Parsed from mixed yyyy-MM-dd and dd/MM/yyyy source formats.',
  home_team         STRING  COMMENT 'Home team, casing-fixed then normalized to current name via former_names.',
  away_team         STRING  COMMENT 'Away team, casing-fixed then normalized to current name via former_names.',
  home_score        INT     COMMENT 'Home goals. NULL where source had non-numeric "NA" or match unplayed.',
  away_score        INT     COMMENT 'Away goals. NULL where source had non-numeric "NA" or match unplayed.',
  tournament_clean  STRING  COMMENT 'Trimmed tournament name.',
  city              STRING  COMMENT 'Host city.',
  country           STRING  COMMENT 'Host country.',
  neutral           BOOLEAN COMMENT 'TRUE if played on neutral ground. Cast from source TRUE/FALSE strings.',
  result_home       STRING  COMMENT 'W/D/L from home perspective. NULL when scores are NULL.',
  result_away       STRING  COMMENT 'W/D/L from away perspective. NULL when scores are NULL.',
  is_world_cup      BOOLEAN COMMENT 'TRUE if tournament_clean = FIFA World Cup (excludes qualifiers).',
  had_shootout      BOOLEAN COMMENT 'TRUE if decided by penalty shootout (bronze.shootouts).',
  shootout_winner   STRING  COMMENT 'Shootout-winning team, normalized. NULL if no shootout.',
  year              INT     COMMENT 'Calendar year of the match.',
  decade            INT     COMMENT 'Decade bucket, e.g. 1990 for 1990-1999.'
)
USING DELTA
COMMENT 'Clean match results, one row per match (1930+). MERGE-upserted from bronze.results on match_id.';

MERGE INTO workshop_team_a_cba.silver.silver_match_results AS tgt
USING (
  WITH mapped AS (
    SELECT
      r.date,
      COALESCE(mh.canonical_name, trim(r.home_team)) AS home_team_c,
      COALESCE(ma.canonical_name, trim(r.away_team)) AS away_team_c,
      r.home_score, r.away_score, r.tournament, r.city, r.country, r.neutral
    FROM workshop_team_a_cba.bronze.results r
    LEFT JOIN workshop_team_a_cba.silver._team_name_map mh ON trim(r.home_team) = mh.raw_name
    LEFT JOIN workshop_team_a_cba.silver._team_name_map ma ON trim(r.away_team) = ma.raw_name
  ),
  dedup AS (
    -- collapses exact dupes AND casing-duplicate rows now that names are canonical
    SELECT DISTINCT date, home_team_c, away_team_c, home_score, away_score,
                    tournament, city, country, neutral
    FROM mapped
  ),
  parsed AS (
    SELECT
      COALESCE(try_to_date(date, 'yyyy-MM-dd'), try_to_date(date, 'dd/MM/yyyy')) AS date,
      home_team_c AS home_team_raw,
      away_team_c AS away_team_raw,
      try_cast(home_score AS INT) AS home_score,
      try_cast(away_score AS INT) AS away_score,
      trim(tournament) AS tournament_clean,
      trim(city) AS city,
      trim(country) AS country,
      CASE WHEN upper(trim(neutral)) = 'TRUE' THEN true
           WHEN upper(trim(neutral)) = 'FALSE' THEN false END AS neutral
    FROM dedup
  ),
  filtered AS (SELECT * FROM parsed WHERE year(date) >= 1930),
  -- casing-normalized shootouts for a clean join + winner
  shootouts_c AS (
    SELECT s.date,
           COALESCE(mh.canonical_name, trim(s.home_team)) AS home_team_c,
           COALESCE(ma.canonical_name, trim(s.away_team)) AS away_team_c,
           COALESCE(mw.canonical_name, trim(s.winner))    AS winner_c
    FROM workshop_team_a_cba.bronze.shootouts s
    LEFT JOIN workshop_team_a_cba.silver._team_name_map mh ON trim(s.home_team) = mh.raw_name
    LEFT JOIN workshop_team_a_cba.silver._team_name_map ma ON trim(s.away_team) = ma.raw_name
    LEFT JOIN workshop_team_a_cba.silver._team_name_map mw ON trim(s.winner)    = mw.raw_name
  ),
  with_shootout AS (
    SELECT f.*,
           CASE WHEN s.date IS NOT NULL THEN true ELSE false END AS had_shootout,
           s.winner_c AS shootout_winner_raw
    FROM filtered f
    LEFT JOIN shootouts_c s
      ON f.date = s.date AND f.home_team_raw = s.home_team_c AND f.away_team_raw = s.away_team_c
  ),
  norm AS (
    SELECT w.*,
           COALESCE(fh.current, w.home_team_raw)       AS home_team,
           COALESCE(fa.current, w.away_team_raw)       AS away_team,
           COALESCE(fw.current, w.shootout_winner_raw) AS shootout_winner
    FROM with_shootout w
    LEFT JOIN workshop_team_a_cba.bronze.former_names fh
      ON w.home_team_raw = fh.former AND w.date BETWEEN fh.start_date AND fh.end_date
    LEFT JOIN workshop_team_a_cba.bronze.former_names fa
      ON w.away_team_raw = fa.former AND w.date BETWEEN fa.start_date AND fa.end_date
    LEFT JOIN workshop_team_a_cba.bronze.former_names fw
      ON w.shootout_winner_raw = fw.former AND w.date BETWEEN fw.start_date AND fw.end_date
  )
  SELECT
    sha2(concat_ws('|', CAST(date AS STRING), home_team, away_team,
         tournament_clean, CAST(home_score AS STRING), CAST(away_score AS STRING)), 256) AS match_id,
    date, home_team, away_team, home_score, away_score, tournament_clean, city, country, neutral,
    CASE WHEN home_score > away_score THEN 'W' WHEN home_score = away_score THEN 'D'
         WHEN home_score < away_score THEN 'L' END AS result_home,
    CASE WHEN away_score > home_score THEN 'W' WHEN away_score = home_score THEN 'D'
         WHEN away_score < home_score THEN 'L' END AS result_away,
    (tournament_clean = 'FIFA World Cup') AS is_world_cup,
    had_shootout, shootout_winner,
    year(date) AS year,
    CAST(floor(year(date) / 10) * 10 AS INT) AS decade
  FROM norm
) AS src
ON tgt.match_id = src.match_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
