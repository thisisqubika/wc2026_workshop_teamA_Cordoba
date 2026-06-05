-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Silver Data Quality Checks — WC2026 (Team A)
-- MAGIC
-- MAGIC Recomputes every Silver DQ rule and **upserts** the outcomes into
-- MAGIC `workshop_team_a_cba.silver._dq_results` (PK = `table_name` + `rule`).
-- MAGIC
-- MAGIC Idempotent and rerunnable: each run refreshes `metric_value`, `passed`,
-- MAGIC and `checked_at` for existing rules and inserts any new ones.
-- MAGIC
-- MAGIC | criticality | meaning |
-- MAGIC |---|---|
-- MAGIC | `error` | must pass — a violation means the table is wrong |
-- MAGIC | `warn`  | should pass — investigate but not necessarily blocking |

-- COMMAND ----------

-- DBTITLE 1,Create the DQ results table (keyed by table_name + rule)
CREATE TABLE IF NOT EXISTS workshop_team_a_cba.silver._dq_results (
  table_name   STRING    COMMENT 'Silver table the rule was evaluated against.',
  rule         STRING    COMMENT 'Rule name. Part of the PK with table_name.',
  criticality  STRING    COMMENT 'error | warn.',
  metric_value BIGINT    COMMENT 'Observed metric (count or distinct-count) for the rule.',
  passed       BOOLEAN   COMMENT 'TRUE if the rule passed on this run.',
  checked_at   TIMESTAMP COMMENT 'When this rule was last evaluated.'
)
USING DELTA
COMMENT 'Silver DQ rule outcomes, one row per (table_name, rule). Upserted by silver_dq_checks notebook.';

-- COMMAND ----------

-- DBTITLE 1,Compute all checks and MERGE-upsert the outcomes
MERGE INTO workshop_team_a_cba.silver._dq_results AS tgt
USING (
  -- ---- silver_match_results ----
  SELECT 'silver_match_results' AS table_name, 'row_count_matches_source_1930plus_deduped' AS rule, 'error' AS criticality,
         CAST((SELECT COUNT(*) FROM workshop_team_a_cba.silver.silver_match_results) AS BIGINT) AS metric_value,
         (SELECT COUNT(*) FROM workshop_team_a_cba.silver.silver_match_results) =
         (SELECT COUNT(*) FROM (SELECT DISTINCT date,home_team,away_team,home_score,away_score,tournament,city,country,neutral
                                FROM workshop_team_a_cba.bronze.results) d
          WHERE year(COALESCE(try_to_date(date,'yyyy-MM-dd'),try_to_date(date,'dd/MM/yyyy')))>=1930) AS passed
  UNION ALL SELECT 'silver_match_results','match_id_unique','error',
         CAST(COUNT(DISTINCT match_id) AS BIGINT), COUNT(*)=COUNT(DISTINCT match_id)
         FROM workshop_team_a_cba.silver.silver_match_results
  UNION ALL SELECT 'silver_match_results','match_id_not_null','error',
         CAST(SUM(CASE WHEN match_id IS NULL THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN match_id IS NULL THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.silver.silver_match_results
  UNION ALL SELECT 'silver_match_results','no_pre_1930_rows','error',
         CAST(SUM(CASE WHEN year<1930 THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN year<1930 THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.silver.silver_match_results
  UNION ALL SELECT 'silver_match_results','result_in_domain_W_D_L','error',
         CAST(SUM(CASE WHEN result_home NOT IN ('W','D','L') THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN result_home NOT IN ('W','D','L') THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.silver.silver_match_results
  UNION ALL SELECT 'silver_match_results','result_consistent_with_score','warn',
         CAST(SUM(CASE WHEN home_score IS NOT NULL AND (
                   (home_score>away_score AND result_home<>'W') OR
                   (home_score=away_score AND result_home<>'D') OR
                   (home_score<away_score AND result_home<>'L')) THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN home_score IS NOT NULL AND (
                   (home_score>away_score AND result_home<>'W') OR
                   (home_score=away_score AND result_home<>'D') OR
                   (home_score<away_score AND result_home<>'L')) THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.silver.silver_match_results
  UNION ALL SELECT 'silver_match_results','neutral_not_null','warn',
         CAST(SUM(CASE WHEN neutral IS NULL THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN neutral IS NULL THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.silver.silver_match_results
  -- ---- silver_goalscorers ----
  UNION ALL SELECT 'silver_goalscorers','goal_id_unique','error',
         CAST(COUNT(DISTINCT goal_id) AS BIGINT), COUNT(*)=COUNT(DISTINCT goal_id)
         FROM workshop_team_a_cba.silver.silver_goalscorers
  UNION ALL SELECT 'silver_goalscorers','row_count_positive','error',
         CAST(COUNT(*) AS BIGINT), COUNT(*)>0 FROM workshop_team_a_cba.silver.silver_goalscorers
  UNION ALL SELECT 'silver_goalscorers','no_pre_1930_rows','error',
         CAST(SUM(CASE WHEN year<1930 THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN year<1930 THEN 1 ELSE 0 END)=0 FROM workshop_team_a_cba.silver.silver_goalscorers
  -- ---- silver_wc2026_fixture ----
  UNION ALL SELECT 'silver_wc2026_fixture','exactly_48_teams','error',
         CAST(COUNT(*) AS BIGINT), COUNT(*)=48 FROM workshop_team_a_cba.silver.silver_wc2026_fixture
  UNION ALL SELECT 'silver_wc2026_fixture','team_unique','error',
         CAST(COUNT(DISTINCT team) AS BIGINT), COUNT(*)=COUNT(DISTINCT team)
         FROM workshop_team_a_cba.silver.silver_wc2026_fixture
) AS src
ON tgt.table_name = src.table_name AND tgt.rule = src.rule
WHEN MATCHED THEN UPDATE SET
  tgt.criticality = src.criticality,
  tgt.metric_value = src.metric_value,
  tgt.passed = src.passed,
  tgt.checked_at = current_timestamp()
WHEN NOT MATCHED THEN INSERT
  (table_name, rule, criticality, metric_value, passed, checked_at)
  VALUES (src.table_name, src.rule, src.criticality, src.metric_value, src.passed, current_timestamp());

-- COMMAND ----------

-- DBTITLE 1,Review outcomes — failures first
SELECT table_name, rule, criticality, metric_value, passed, checked_at
FROM workshop_team_a_cba.silver._dq_results
ORDER BY passed ASC, criticality DESC, table_name, rule;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Gate
-- MAGIC If any `error`-criticality row has `passed = false`, the Silver build is
-- MAGIC **not** safe to promote to Gold. The query below returns those rows; an
-- MAGIC empty result means all hard checks passed.

-- COMMAND ----------

SELECT * FROM workshop_team_a_cba.silver._dq_results
WHERE criticality = 'error' AND passed = false;
