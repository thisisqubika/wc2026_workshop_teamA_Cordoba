# wc2026_workshop_teamA_Cordoba

WC2026 Analytics Platform — **Team A** (Silver + Gold layers).

Builds clean, analytical tables from raw, dirty Bronze data (International Football
Results 1872–2026). Catalog: `workshop_team_a_cba` · Warehouse: Starter Warehouse
(serverless) · Pattern: idempotent `CREATE IF NOT EXISTS` + `MERGE` by PK with
delete-on-source-miss (reruns converge to identical state).

## Repo layout

```
sql/
  00_silver_team_name_map.sql        # helper: casing canonicalization map
  01_silver_match_results.sql        # silver
  02_silver_goalscorers.sql
  03_silver_wc2026_fixture.sql
  04_gold_fct_match_results.sql      # gold
  05_gold_fct_wc_only.sql
  06_gold_dim_team_stats.sql
  07_gold_fct_wc2026_participants.sql
notebooks/
  silver_dq_checks.sql               # upserts silver._dq_results
  gold_dq_checks.sql                 # upserts gold._dq_results
de-pipeline-report-wc2026-20260605.md
```

## Rerun order (idempotent)

```
sql/00 → 01 → 02 → 03            # silver
notebooks/silver_dq_checks.sql   # silver DQ
sql/04 → 05 → 06 → 07            # gold
notebooks/gold_dq_checks.sql     # gold DQ
```

---

## 🥉 Bronze (pre-existing — input only)

5 raw tables in `workshop_team_a_cba.bronze`. Only `results` is dirty.

| Table | Rows | Schema (key cols) | Status |
|---|---|---|---|
| `results` | 49,287 | all **STRING**: date, home_team, away_team, home_score, away_score, tournament, city, country, neutral | 🔴 dirty |
| `goalscorers` | ~48k | date, home_team, away_team, team, scorer, minute, own_goal, penalty | ✅ clean |
| `shootouts` | 675 | date, home_team, away_team, winner, first_shooter | ✅ clean |
| `former_names` | 36 | current, former, start_date, end_date | ✅ clean |
| `wc2026_fixture` | 48 | team, group, confederation, fifa_ranking, is_host | ✅ clean |

---

## 🥈 Silver — `workshop_team_a_cba.silver`

Cleaned, typed, deduped, team-name-normalized (1930+).

| Table | Rows | PK | Notes |
|---|---|---|---|
| `_team_name_map` | 569 | `raw_name` | helper: raw → canonical (casing fix) |
| `silver_match_results` | 47,865 | `match_id` | one row/match; 17 cols |
| `silver_goalscorers` | 46,978 | `goal_id` | one row/goal |
| `silver_wc2026_fixture` | 48 | `team` | typed fixture |
| `_dq_results` | 12 rules | `(table_name, rule)` | DQ outcomes |

**`silver_match_results` schema:** `match_id`, `date`, `home_team`, `away_team`,
`home_score`, `away_score`, `tournament_clean`, `city`, `country`, `neutral`,
`result_home`, `result_away`, `is_world_cup`, `had_shootout`, `shootout_winner`,
`year`, `decade`

**Transformations (in order):**
1. Casing canonicalization via `_team_name_map` (`SPAIN`→`Spain`)
2. Dedupe (exact + casing duplicates)
3. Date parse — dual format `COALESCE(yyyy-MM-dd, dd/MM/yyyy)` → 100%
4. `1930+` filter
5. Score cast (`"NA"`→NULL), `neutral` string→boolean
6. `former_names` date-bounded normalization (`Dahomey`→`Benin`)
7. Shootout enrichment (`had_shootout`, `shootout_winner`)
8. Derive `result_home/away` (W/D/L), `is_world_cup`, `year`, `decade`, `match_id` (sha2)

---

## 🥇 Gold — `workshop_team_a_cba.gold`

Analytical tables for Teams B/C.

| Table | Rows | PK | Purpose |
|---|---|---|---|
| `fct_match_results` | 47,865 | `match_id` | clean match fact (Silver promoted) |
| `fct_wc_only` | 868 | `match_id` | World Cup matches only |
| `dim_team_stats` | 331 | `team` | per-team cumulative stats (played matches) |
| `fct_wc2026_participants` | 48 | `team` | qualified teams ⟕ historical stats |
| `_dq_results` | 11 rules | `(table_name, rule)` | DQ outcomes |

**`dim_team_stats`** (built for a tournament simulator): `matches_played`,
`wins/draws/losses`, `win_pct`, `goals_for/against`, `goal_difference`,
`avg_goals_for/against`, `first/last_match`, `wc_appearances`, `wc_matches_played`,
`wc_wins`, `wc_win_pct`, `wc_goals_for/against`.

---

## ✅ Data Quality — 23 checks, all passing

**7 issues fixed in `bronze.results`:**

| # | Issue | Count | Fix |
|---|---|---|---|
| 1 | Exact duplicate rows | 2,527 | dedupe |
| 2 | Mixed date formats | 974 | dual-format parse |
| 3 | `"NA"` scores | 72 | →NULL, rows kept |
| 4 | `neutral` as strings | all | →boolean |
| 5 | No PK / all strings | — | sha2 key + casts |
| 6 | **Casing corruption** ⚠️ *(not on known list)* | 1,466 | `_team_name_map` → 566→331 teams |
| 7 | **60 unplayed WC2026 fixtures** ⚠️ *(not on known list)* | 60 | kept in facts, excluded from stats |

**Silver DQ (12):** row-count reconciliation, `match_id`/`goal_id` unique & non-null,
`result` ∈ {W,D,L}, result-vs-score consistency, no pre-1930, fixture=48.

**Gold DQ (11):** `fct` counts == Silver, `fct_wc_only` all-WC, `dim_team_stats`
team-unique + W+D+L==matches_played + no negative goals + **cross-layer goals
reconciliation**, participants==48 all matched.

**Validation against reality:** Brazil 22 WC appearances, Argentina 18, Spain 16,
Germany 20 — all correct. ✓

All schemas, tables, and columns carry Unity Catalog `COMMENT`s.
