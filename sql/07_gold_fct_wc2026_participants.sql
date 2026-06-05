-- ============================================================================
-- Gold: fct_wc2026_participants   |  PK: team  |  Idempotent MERGE upsert
-- ----------------------------------------------------------------------------
-- The 48 WC2026 qualified teams joined to their historical stats from
-- dim_team_stats. LEFT JOIN so all 48 survive even if a team has no history
-- under its current name (those stats land NULL — flagged by has_history).
-- ============================================================================

CREATE TABLE IF NOT EXISTS workshop_team_a_cba.gold.fct_wc2026_participants (
  team              STRING  COMMENT 'PK. WC2026 qualified team.',
  group_name        STRING  COMMENT 'WC2026 group letter.',
  confederation     STRING  COMMENT 'FIFA confederation.',
  fifa_ranking      INT     COMMENT 'FIFA ranking at qualification.',
  is_host           BOOLEAN COMMENT 'TRUE if host nation.',
  has_history       BOOLEAN COMMENT 'TRUE if matched to dim_team_stats (has 1930+ history).',
  matches_played    BIGINT  COMMENT 'Historical match appearances.',
  win_pct           DOUBLE  COMMENT 'Historical win rate (0-1).',
  goals_for         BIGINT  COMMENT 'Historical goals scored.',
  goals_against     BIGINT  COMMENT 'Historical goals conceded.',
  goal_difference   BIGINT  COMMENT 'Historical goal difference.',
  avg_goals_for     DOUBLE  COMMENT 'Historical attack rate.',
  avg_goals_against DOUBLE  COMMENT 'Historical defense rate.',
  wc_appearances    BIGINT  COMMENT 'Distinct World Cup editions played.',
  wc_matches_played BIGINT  COMMENT 'World Cup matches played.',
  wc_wins           BIGINT  COMMENT 'World Cup wins.',
  wc_win_pct        DOUBLE  COMMENT 'World Cup win rate (0-1).'
)
USING DELTA
COMMENT 'WC2026 participants (48) joined to historical stats (Gold). MERGE on team.';

MERGE INTO workshop_team_a_cba.gold.fct_wc2026_participants AS tgt
USING (
  SELECT
    f.team, f.group_name, f.confederation, f.fifa_ranking, f.is_host,
    (s.team IS NOT NULL) AS has_history,
    s.matches_played, s.win_pct, s.goals_for, s.goals_against, s.goal_difference,
    s.avg_goals_for, s.avg_goals_against,
    s.wc_appearances, s.wc_matches_played, s.wc_wins, s.wc_win_pct
  FROM workshop_team_a_cba.silver.silver_wc2026_fixture f
  LEFT JOIN workshop_team_a_cba.gold.dim_team_stats s ON f.team = s.team
) AS src
ON tgt.team = src.team
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;
