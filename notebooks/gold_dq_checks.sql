-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Gold Data Quality Checks — WC2026 (Team A)
-- MAGIC
-- MAGIC Recomputes Gold DQ rules and **upserts** outcomes into
-- MAGIC `workshop_team_a_cba.gold._dq_results` (PK = `table_name` + `rule`).
-- MAGIC Includes cross-layer reconciliation against Silver.
-- MAGIC Idempotent / rerunnable.

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.gold._dq_results (
  table_name   STRING    COMMENT 'Gold table the rule was evaluated against.',
  rule         STRING    COMMENT 'Rule name. Part of the PK with table_name.',
  criticality  STRING    COMMENT 'error | warn.',
  metric_value BIGINT    COMMENT 'Observed metric for the rule.',
  passed       BOOLEAN   COMMENT 'TRUE if the rule passed on this run.',
  checked_at   TIMESTAMP COMMENT 'When this rule was last evaluated.'
)
USING DELTA
COMMENT 'Gold DQ rule outcomes, one row per (table_name, rule). Upserted by gold_dq_checks notebook.';

-- COMMAND ----------

MERGE INTO workshop_team_a_cba.gold._dq_results AS tgt
USING (
  -- fct_match_results faithfully promotes silver (same grain/count)
  SELECT 'fct_match_results' AS table_name, 'row_count_equals_silver' AS rule, 'error' AS criticality,
         CAST((SELECT COUNT(*) FROM workshop_team_a_cba.gold.fct_match_results) AS BIGINT) AS metric_value,
         (SELECT COUNT(*) FROM workshop_team_a_cba.gold.fct_match_results)
         = (SELECT COUNT(*) FROM workshop_team_a_cba.silver.silver_match_results) AS passed
  UNION ALL SELECT 'fct_match_results','match_id_unique','error',
         CAST(COUNT(DISTINCT match_id) AS BIGINT), COUNT(*)=COUNT(DISTINCT match_id)
         FROM workshop_team_a_cba.gold.fct_match_results
  -- fct_wc_only: only world cup, count matches silver WC count
  UNION ALL SELECT 'fct_wc_only','all_is_world_cup','error',
         CAST(SUM(CASE WHEN NOT is_world_cup THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN NOT is_world_cup THEN 1 ELSE 0 END)=0 FROM workshop_team_a_cba.gold.fct_wc_only
  UNION ALL SELECT 'fct_wc_only','row_count_equals_silver_wc','error',
         CAST((SELECT COUNT(*) FROM workshop_team_a_cba.gold.fct_wc_only) AS BIGINT),
         (SELECT COUNT(*) FROM workshop_team_a_cba.gold.fct_wc_only)
         = (SELECT COUNT(*) FROM workshop_team_a_cba.silver.silver_match_results WHERE is_world_cup) AS passed
  -- dim_team_stats integrity
  UNION ALL SELECT 'dim_team_stats','team_unique','error',
         CAST(COUNT(DISTINCT team) AS BIGINT), COUNT(*)=COUNT(DISTINCT team)
         FROM workshop_team_a_cba.gold.dim_team_stats
  UNION ALL SELECT 'dim_team_stats','wdl_sums_to_matches_played','error',
         CAST(SUM(CASE WHEN wins+draws+losses <> matches_played THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN wins+draws+losses <> matches_played THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.gold.dim_team_stats
  UNION ALL SELECT 'dim_team_stats','no_negative_goals','error',
         CAST(SUM(CASE WHEN goals_for<0 OR goals_against<0 THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN goals_for<0 OR goals_against<0 THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.gold.dim_team_stats
  -- cross-layer reconciliation: total goals_for == total goals across played matches
  UNION ALL SELECT 'dim_team_stats','goals_reconcile_with_silver','error',
         CAST((SELECT SUM(goals_for) FROM workshop_team_a_cba.gold.dim_team_stats) AS BIGINT),
         (SELECT SUM(goals_for) FROM workshop_team_a_cba.gold.dim_team_stats)
         = (SELECT SUM(CASE WHEN result_home IS NOT NULL THEN home_score ELSE 0 END)
                 + SUM(CASE WHEN result_away IS NOT NULL THEN away_score ELSE 0 END)
            FROM workshop_team_a_cba.silver.silver_match_results) AS passed
  -- fct_wc2026_participants
  UNION ALL SELECT 'fct_wc2026_participants','exactly_48','error',
         CAST(COUNT(*) AS BIGINT), COUNT(*)=48 FROM workshop_team_a_cba.gold.fct_wc2026_participants
  UNION ALL SELECT 'fct_wc2026_participants','team_unique','error',
         CAST(COUNT(DISTINCT team) AS BIGINT), COUNT(*)=COUNT(DISTINCT team)
         FROM workshop_team_a_cba.gold.fct_wc2026_participants
  UNION ALL SELECT 'fct_wc2026_participants','all_have_history','warn',
         CAST(SUM(CASE WHEN NOT has_history THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN NOT has_history THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.gold.fct_wc2026_participants
  -- dim_team_stats new columns
  UNION ALL SELECT 'dim_team_stats','clean_sheets_not_exceed_matches','error',
         CAST(SUM(CASE WHEN clean_sheets > matches_played THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN clean_sheets > matches_played THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.gold.dim_team_stats
  UNION ALL SELECT 'dim_team_stats','recent_form_in_range','error',
         CAST(SUM(CASE WHEN recent_win_pct_last20 < 0 OR recent_win_pct_last20 > 1 THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN recent_win_pct_last20 < 0 OR recent_win_pct_last20 > 1 THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.gold.dim_team_stats
  -- dim_wc_team_edition
  UNION ALL SELECT 'dim_wc_team_edition','pk_unique','error',
         CAST(COUNT(*) AS BIGINT), COUNT(*)=COUNT(DISTINCT concat_ws('|', team, CAST(wc_year AS STRING)))
         FROM workshop_team_a_cba.gold.dim_wc_team_edition
  UNION ALL SELECT 'dim_wc_team_edition','wdl_sums_to_matches_played','error',
         CAST(SUM(CASE WHEN wins+draws+losses <> matches_played THEN 1 ELSE 0 END) AS BIGINT),
         SUM(CASE WHEN wins+draws+losses <> matches_played THEN 1 ELSE 0 END)=0
         FROM workshop_team_a_cba.gold.dim_wc_team_edition
  UNION ALL SELECT 'dim_wc_team_edition','reconciles_with_dim_team_stats_wc_matches','error',
         CAST((SELECT SUM(matches_played) FROM workshop_team_a_cba.gold.dim_wc_team_edition) AS BIGINT),
         (SELECT SUM(matches_played) FROM workshop_team_a_cba.gold.dim_wc_team_edition)
         = (SELECT SUM(wc_matches_played) FROM workshop_team_a_cba.gold.dim_team_stats) AS passed
) AS src
ON tgt.table_name = src.table_name AND tgt.rule = src.rule
WHEN MATCHED THEN UPDATE SET
  tgt.criticality=src.criticality, tgt.metric_value=src.metric_value,
  tgt.passed=src.passed, tgt.checked_at=current_timestamp()
WHEN NOT MATCHED THEN INSERT
  (table_name, rule, criticality, metric_value, passed, checked_at)
  VALUES (src.table_name, src.rule, src.criticality, src.metric_value, src.passed, current_timestamp());

-- COMMAND ----------

SELECT table_name, rule, criticality, metric_value, passed, checked_at
FROM workshop_team_a_cba.gold._dq_results
ORDER BY passed ASC, criticality DESC, table_name, rule;

-- COMMAND ----------

SELECT * FROM workshop_team_a_cba.gold._dq_results WHERE criticality='error' AND passed=false;
