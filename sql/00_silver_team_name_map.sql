-- ============================================================================
-- Silver helper: _team_name_map   |  PK: raw_name
-- ----------------------------------------------------------------------------
-- Canonical team-name mapping that fixes casing corruption (e.g. "SPAIN"->"Spain").
-- Canonical = the non-uppercase, most-frequent variant per case-insensitive name;
-- if a name exists only in uppercase (e.g. "ELBA ISLAND"), fall back to initcap.
-- Sourced from every team-name column across the Bronze tables so the same map
-- normalizes results, goalscorers and shootout winners consistently.
-- Rebuild (CREATE OR REPLACE): deterministic from Bronze, safe to rerun.
-- ============================================================================
CREATE OR REPLACE TABLE workshop_team_a_cba.silver._team_name_map AS
WITH all_names AS (
  SELECT trim(home_team) n FROM workshop_team_a_cba.bronze.results
  UNION ALL SELECT trim(away_team) FROM workshop_team_a_cba.bronze.results
  UNION ALL SELECT trim(home_team) FROM workshop_team_a_cba.bronze.goalscorers
  UNION ALL SELECT trim(away_team) FROM workshop_team_a_cba.bronze.goalscorers
  UNION ALL SELECT trim(team)      FROM workshop_team_a_cba.bronze.goalscorers
  UNION ALL SELECT trim(home_team) FROM workshop_team_a_cba.bronze.shootouts
  UNION ALL SELECT trim(away_team) FROM workshop_team_a_cba.bronze.shootouts
  UNION ALL SELECT trim(winner)    FROM workshop_team_a_cba.bronze.shootouts
),
freq AS (
  SELECT n, lower(n) AS lc, COUNT(*) AS c,
         CASE WHEN n = upper(n) AND n RLIKE '[A-Z]{2,}' THEN 1 ELSE 0 END AS is_upper
  FROM all_names
  WHERE n IS NOT NULL AND n <> ''
  GROUP BY n
),
ranked AS (
  -- prefer proper-case (is_upper=0), then most frequent, then alpha for determinism
  SELECT lc, n, is_upper,
         ROW_NUMBER() OVER (PARTITION BY lc ORDER BY is_upper ASC, c DESC, n ASC) AS rn
  FROM freq
),
canonical AS (
  SELECT lc,
         CASE WHEN is_upper = 1 THEN initcap(n) ELSE n END AS canonical_name
  FROM ranked WHERE rn = 1
)
SELECT f.n AS raw_name, c.canonical_name
FROM freq f
JOIN canonical c ON f.lc = c.lc;

COMMENT ON TABLE workshop_team_a_cba.silver._team_name_map IS 'Canonical team-name map fixing casing corruption. raw_name -> canonical_name. Built from all Bronze team-name columns.';
