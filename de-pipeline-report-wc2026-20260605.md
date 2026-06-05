# Pipeline report — wc2026 — 2026-06-05

Built by `/de-pipeline` wizard (Existing raw-landing variant — Bronze pre-existing, started at Silver).
Workspace: `dbc-d67b23f8-4c4d.cloud.databricks.com`. Engineer: nino.di.giannantonio@qubika.com.
Catalog: `workshop_team_a_cba`. Warehouse: `Starter Warehouse` (serverless, `df980289c7dd0364`).

## Summary
- **Source**: 5 existing Bronze tables in `workshop_team_a_cba.bronze` (raw landing).
- **Layers**: Silver (3 tables + 2 helpers), Gold (4 tables + 1 DQ table).
- **Pipeline style**: idempotent — every load is `CREATE TABLE IF NOT EXISTS` + `MERGE` by PK with `WHEN NOT MATCHED BY SOURCE THEN DELETE`, so reruns converge to identical state.
- **Data quality**: 23 checks across both layers, **all passing, 0 failures**.

## Object tree

| FQN | Rows | Grain / notes |
|---|---|---|
| `silver._team_name_map` | 569 | raw_name → canonical_name (casing fix) |
| `silver.silver_match_results` | 47,865 | one row per match (1930+), PK `match_id` |
| `silver.silver_goalscorers` | 46,978 | one row per goal, PK `goal_id` |
| `silver.silver_wc2026_fixture` | 48 | qualified teams, PK `team` |
| `silver._dq_results` | 12 | DQ rule outcomes |
| `gold.fct_match_results` | 47,865 | clean match fact, PK `match_id` |
| `gold.fct_wc_only` | 868 | World Cup matches only |
| `gold.dim_team_stats` | 331 | one row per team, cumulative stats (played matches) |
| `gold.fct_wc2026_participants` | 48 | qualified teams ⟕ dim_team_stats |
| `gold._dq_results` | 11 | DQ rule outcomes |

All schemas, tables, and columns have UC `COMMENT`s.

## Data quality issues found & fixed in `bronze.results`

| # | Issue | Found | Resolution |
|---|---|---|---|
| 1 | Exact duplicate rows | 2,527 | `DISTINCT` dedupe |
| 2 | Mixed date formats (`dd/MM/yyyy` vs `yyyy-MM-dd`) | 974 (948 post-1930) | dual-format `try_to_date` COALESCE → 100% parse |
| 3 | Non-numeric `"NA"` scores | 72 | cast to NULL; rows kept (flagged by NULL scores) |
| 4 | `neutral` stored as `"TRUE"/"FALSE"` strings | all | cast to boolean |
| 5 | No `match_id` / all-string types | — | sha2 surrogate key + typed casts |
| 6 | **Team-name casing corruption** (`SPAIN` vs `Spain`) — fragmented team identities | 1,466 rows / 235 dup identities | `_team_name_map` canonicalization before former_names; collapsed 566→331 real teams |
| 7 | **60 unplayed future WC2026 fixtures** in results (the schedule, NULL scores) | 60 | kept in fact tables (flagged NULL); excluded from `dim_team_stats` (played-only) |

Issues 6 and 7 were **not** in the known-issues list — discovered during profiling (rubric "find data issues beyond the known ones").

Also applied: 1930+ filter; `former_names` date-bounded historical-name normalization; shootout enrichment (`had_shootout`, `shootout_winner`).

## Data quality results

**Silver (`silver._dq_results`)** — 12 rules, all pass. Key: row count reconciles to source (1930+ deduped); `match_id`/`goal_id` unique & non-null; `result` in {W,D,L}; result consistent with score (0 mismatches); no pre-1930 rows; fixture = 48.

**Gold (`gold._dq_results`)** — 11 rules, all pass. Key: `fct_match_results` count == Silver; `fct_wc_only` all World Cup & count == Silver WC; `dim_team_stats` team unique, W+D+L == matches_played, no negative goals, **goals reconcile cross-layer with Silver**; participants == 48, all matched to history.

## dim_team_stats design (the open-ended table)

One row per team over **played** matches (both home & away perspectives), built for a tournament simulator:
- **Strength**: `win_pct`, `avg_goals_for` (attack rate), `avg_goals_against` (defense rate)
- **Comparability**: `matches_played`, `goals_for/against`, `goal_difference`
- **World Cup pedigree** ("how far they got"): `wc_appearances` (distinct editions actually played), `wc_matches_played`, `wc_wins`, `wc_win_pct`, `wc_goals_for/against`

Validated against real history: Brazil 22 WC appearances, Argentina 18, Spain 16, Germany 20 — all correct.

## Local repo layout

```
temp/wc2026-pipeline/
├── sql/
│   ├── 00_silver_team_name_map.sql
│   ├── 01_silver_match_results.sql
│   ├── 02_silver_goalscorers.sql
│   ├── 03_silver_wc2026_fixture.sql
│   ├── 04_gold_fct_match_results.sql
│   ├── 05_gold_fct_wc_only.sql
│   ├── 06_gold_dim_team_stats.sql
│   └── 07_gold_fct_wc2026_participants.sql
└── notebooks/
    ├── silver_dq_checks.sql   (Databricks SQL notebook — upserts silver._dq_results)
    └── gold_dq_checks.sql     (Databricks SQL notebook — upserts gold._dq_results)
```

## Rerun order (idempotent)

```
sql/00 → 01 → 02 → 03            # silver
notebooks/silver_dq_checks.sql   # silver DQ
sql/04 → 05 → 06 → 07            # gold
notebooks/gold_dq_checks.sql     # gold DQ
```

## Next steps

- [ ] Import the two DQ notebooks into the workspace: `databricks workspace import ...`
- [ ] Spot-check `dim_team_stats` against an external source for one more team
- [ ] (Optional) Wrap the run order in a Databricks Job for scheduling
- [ ] Framework contribution: the `_team_name_map` casing-canonicalization pattern is broadly reusable — candidate for a kit skill (see Caveats)

## Caveats / things found mid-build

1. **MCP `databricks` points to the Avant workspace, not Qubika** — profiling had to go through the CLI SQL Statement Execution API against the Qubika `Starter Warehouse`. Worth flagging for the kit (MCP/profile mismatch is a silent footgun).
2. **Rubric catalog `workshop_team_a` is a placeholder** — real catalog is `workshop_team_a_cba`.
3. **Casing corruption was the highest-impact issue** and was *not* on the known list — it silently doubled the team dimension. A reusable "team/entity name canonicalization" skill would have saved several diagnosis rounds (good framework-contribution candidate).
