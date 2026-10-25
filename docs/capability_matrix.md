# Capability matrix — live evidence for Free Edition dependencies

`NOT TESTED` = no evidence yet. `PASS` = observed success (evidence path cited).
`BLOCKED` = attempted and denied with the actual failure recorded.
`PENDING` = expected to work from verified docs, live probe still required.

All live probes ran **2026-10-25** from `scripts/phase0.py` against profile
`sameed-dbx` (read-only SQL only; DDL is deliberately forbidden in Phase 0).
From **2026-10-26** the workspace switched to profile `coffin-dbx`
(`dbc-746bc1e1-c295.cloud.databricks.com`, user `igcoffin17@gmail.com`) after the
first workspace exhausted its free quota; connection facts live in
`CLAUDE_HANDOFF.md`.
Raw outputs are Git-ignored under `evidence/runs/<stamp>_<stage>_<id>/`.

## Identity, CLI, and compute

| Dependency | Probe | Observed 2026-10-25 | Result | Impact / fallback |
|---|---|---|---|---|
| CLI auth (OS keyring) | `databricks current-user me --profile <profile>` | Without a session bus the CLI fails: `error getting token: cache: OS keyring unreachable: dial unix /run/user/1000/bus: connect: operation not permitted`. With `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` exported → verified on BOTH workspaces used (2026-10-25: `sameed1718@gmail.com`, 2026-10-26: `igcoffin17@gmail.com`); direct groups `users`, `admins` | PASS (with workaround) | Export `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` in every sandbox shell / CI step; alternative: `DATABRICKS_AUTH_STORAGE=plaintext`. This is a local sandbox quirk, **not** a Databricks denial. NOTE: the first workspace exhausted its free quota mid-project (2026-10-26); all live state now lives on the second workspace (profile `coffin-dbx`) |
| CLI version | `databricks --version` | v1.20.0 | PASS | `databricks.yml` requires `>= 1.20.0` |
| SQL warehouse | `warehouses list` | `Serverless Starter Warehouse`, id `7c433c4d75a98ff6`, 2X-Small, PRO type, serverless enabled, state STOPPED (second workspace; the first workspace's `a20a2b2aaf17c10f` was identical but is now dead) | PASS | Matches the Free Edition limit of one 2X-Small warehouse; probes pass `--warehouse` explicitly |
| DBSQL version | `SELECT current_version()` | `dbsql_version` 2026.39 (`u_build` a8c836b2…, `r_build` 7eecc1dc…, `dbr_version` null — serverless) | PASS | Recorded for feature-support decisions (metric views); auto-updated channels mean no pinned DBR |
| Workspace identity functions | pending | — | NOT TESTED | `is_member()` vs `current_user()` availability checked in Phase 4 before writing the row-filter UDF |

## Source (read-only `samples.tpch`)

| Dependency | Probe | Observed 2026-10-25 | Result | Impact |
|---|---|---|---|---|
| Source schemas | `SHOW SCHEMAS IN samples` | accuweather, bakehouse, clickbench, information_schema, nyctaxi, tpch | PASS | Source present; nothing written to it |
| Source tables | `SHOW TABLES IN samples.tpch` | 8 tables: customer, lineitem, nation, orders, part, partsupp, region, supplier | PASS | `partsupp` exists but is unused by the contract (7 assigned tables only) |
| Source column types | `DESCRIBE TABLE` ×7 | keys BIGINT/INT, names/flags STRING, dates DATE, money + discount/tax DECIMAL(18,2) | PASS | Confirms candidate types in [data_contract](data_contract.md); contract casts discount/tax down to DECIMAL(9,6) explicitly |
| Source storage | `DESCRIBE DETAIL` orders / lineitem | Delta; orders 188,534,438 B / 3 files; lineitem 753,837,113 B / 10 files | PASS | Aggregates on 2X-Small are practical; date predicates give logical scope, not physical pruning |
| Date coverage (opt-in scan) | `01_date_candidates.sql` | Years 1992–1998; ~1.14 M orders per full year; 1998 partial (to Aug 2); 0 null order dates | PASS | Feeds [ADR-001](decisions/adr-001-date-window.md) |

## Selected window profile (1995)

| Dependency | Probe | Observed 2026-10-25 | Result | Impact |
|---|---|---|---|---|
| Window grain | `02_profile_window.sql` @ 1995-01-01→1996-01-01 | 1,136,308 orders = 1,136,308 distinct keys = 1,136,308 distinct SHA-256 hashes; 4,543,292 lines all unique on (order_key, line_number); 432,892 customers | PASS | [ADR-002](decisions/adr-002-order-key-hash.md) collision check passed; grains hold |
| Source orphan/FK integrity | orphan + FK probes | 0 orphan lines (ship-window cohort), 0 orders without customer, 0 missing part/supplier/nation/region parents | PASS | Synthetic orphans must be injected by our simulator, not the source |
| Code values | `code_values` probe | market segments: AUTOMOBILE/BUILDING/FURNITURE/HOUSEHOLD/MACHINERY (~86k each); return flags N 3,401,497 / A 570,544 / R 571,251; line_status F 1,334,234 / O 3,209,058; order_status O 707,328 / F 237,791 / P 191,189 | PASS | All approved code sets non-degenerate inside 1995 — the deciding evidence for [ADR-001](decisions/adr-001-date-window.md) |
| Source code-generation boundary | full-time diagnostic (diag_codes run) | Lines shipping after 1995-06-16 are all `N`; orders after 1995-06-16 are all `O` (F/P before) | PASS (diagnostic) | A 1996+ window would yield a zero return rate and no order-status diversity; 1992–1994 lack `N`/`O`. Documented in ADR-001 |
| SCD2 demo candidates | `scd_demo_candidates` @ 1995 | 10 customers with 9–10 active months and 10–14 orders (e.g. 210556, 738508, 373396) | PASS | Simulator seed keys come from this list, per [data_contract](data_contract.md#synthetic-fixture-contract-later-phases) |

## Platform capabilities

| Dependency | Probe | Observed 2026-10-25 | Result | Impact |
|---|---|---|---|---|
| Catalog creation | not attempted in Phase 0 (probe guard forbids DDL) | `SHOW CATALOGS` shows only samples, system, workspace — `meridian_t02` absent | NOT TESTED | Run `CREATE CATALOG` in Phase 1 setup; on denial use the workspace-catalog fallback per [ADR-005](decisions/adr-005-platform-limitations.md) |
| System schemas (visibility) | `SHOW SCHEMAS IN system` + `SHOW TABLES` ×4 | All visible: lakeflow (pipelines, pipeline_update_timeline, jobs, job_run_timeline, job_task_run_timeline, job_tasks…), query (history), billing (usage, list_prices, account_prices, attributed_usage), access (audit, column_lineage, table_lineage, workspaces_latest…) | PASS (SHOW) | [ADR-005](decisions/adr-005-platform-limitations.md) ops-dashboard telemetry likely available; SELECT rights verified in Phase 7 |
| Metric view `one_to_many` | verified docs (Oct 13, 2026): YAML reference + TPC-H example | LIVE (2026-10-26, workspace 2): created via statements API; grammar on this runtime requires `WITH METRICS LANGUAGE YAML AS $$...$$` (both `WITH METRICS` and `LANGUAGE YAML` clauses mandatory); all 7 measures by month OK; total `MEASURE(net_revenue)` = fact SUM to the penny → zero fan-out | PASS (live) | `evidence/runs/2026-10-26_phase3_metric_view.md`; ADR-003 verified live |
| Metric view over a row-filtered source | YAML reference: RLS/masked sources block metric-view **materialization**; query-time filtering expected to apply | LIVE (2026-10-26): `mv_trading` queried after `WITH ROW FILTER` attached to source `fct_orders` — no materialization block, admin totals unchanged (165,023,814,898.86 / 1,136,293) | PASS (live, admin bypass) | Restricted-principal totals = manual step (runbook 4.6); `evidence/runs/2026-10-26_phase4_governance.md` |
| Pipeline parameters `${...}` in SQL sources | verified docs (Oct 12, 2026): pipeline `configuration` → `${key}` substitution | — | PENDING | Used by all 5 pipeline files to keep `var.nn` as the single source of truth; failure fallback = literal catalog in pipeline SQL (runbook) |
| Serverless job `spark_python_task` | verified docs (Oct 2026): tasks need `environment_key` on serverless | LIVE: tasks run (simulate/quality_gate, 60–120s each); task stdout/logs are NOT retrievable via the Jobs API (`get-output` returns empty `error`/`logs`) | PARTIAL (live) | Jobs work; observability must come from UC tables — the quality gate writes breadcrumbs + check rows to `ops.quality_gate` via SQL INSERT |
| SQL: `array_remove(array(...), NULL)` | removing NULL elements from an array literal | returns **NULL** whenever the element argument is NULL (Spark short-circuits; verified via warehouse 2026-10-25) | BLOCKED (function misuse) | Use `filter(array(...), x -> x IS NOT NULL)` instead — the reason-list idiom in `40_ops.sql` |
| `AUTO CDC FROM SNAPSHOT` version selector | verified docs (Oct 15, 2026): `WITH VERSION` + `last_snapshot_version()` + `current_snapshot_version()`; 0-or-1-row rule | LIVE: `current_snapshot_version()` not resolvable at all; `last_snapshot_version()` resolves ONLY inside `WITH VERSION`; snapshot query therefore selects `max(version)` — correct only with exactly one new version per update (progressive batches; reset file empties the version table) | PARTIAL | Exact pattern + operating rule in `src/pipeline/20_customer_scd2.sql`; gate pins the segment-story version counts; runbook troubleshooting |
| Window dedup on streaming reads | `row_number() OVER (...)` on a streaming source | `NON_TIME_WINDOW_NOT_SUPPORTED_IN_STREAMING` on this runtime | BLOCKED | Silver = materialized views with the same dedup/expectations (architecture note); Bronze stays streaming |
| Pipeline update concurrency | serverless pipelines auto-retry a FAILED update (`RETRY_ON_FAILURE` trigger in `system.lakeflow.pipeline_update_timeline`); no retry knob in the pipeline spec | a retry can start while the failed update is still finishing → its staging-swap cleanup kills in-flight MV writes (`TABLE_DOES_NOT_EXIST: Staging Table '<uuid>'` storm) and leaves `__staging_<update_id>_<dataset>` orphans | PARTIAL (workaround) | Never trigger two updates at once; after a failure let the pipeline settle to IDLE, drop `__staging_%` orphans, rerun — `evidence/runs/2026-10-25_staging_table_diagnosis.md` |
| Governed tags | verified docs (2026) & tested live: `CREATE GOVERNED TAG` creates account-level tags with strict allowed values | LIVE (2026-10-26, workspace 2): `CREATE GOVERNED TAG` executed via DBSQL successfully created `medallion_layer`, `pii_type`, and `sensitivity_level` with fixed values lists. Applied to schemas via `ALTER SCHEMA ... SET TAGS` and columns via `ALTER TABLE ... ALTER COLUMN ... SET TAGS` | PASS (live) | Full rubric compliance achieved natively in SQL without needing Account Console UI. Recorded in `sql/governance/32_apply.sql` and `evidence/runs/2026-10-26_phase4_governance.md` |
| Row filters / column masks | verified docs (Oct 9, 2026): table-level `ALTER TABLE` UDFs; **not supported on views**; ABAC policies are the recommended alternative | LIVE (2026-10-26): `ALTER ... SET ROW FILTER/SET MASK` on MVs REJECTED (`EXPECT_TABLE_NOT_VIEW`); `CREATE MATERIALIZED VIEW ... WITH ROW FILTER f ON (cols)` ACCEPTED (declaration-time, ON = column names only — expressions like `CAST(NULL)` rejected); `SET TAGS` on MV columns ACCEPTED; masks therefore: real UC masks on `silver.customer_history` + centralized ABAC policies + mask UDFs called inline in the Gold MV definitions | PASS (live) | `evidence/runs/2026-10-26_phase4_governance.md`; `32_apply.sql` documents the pattern |
| ABAC policies (`CREATE POLICY`, tag-matched) | web+docs (2026): GA — row-filter/mask policies, tag-based governance scoped `ON CATALOG` / `ON SCHEMA` | LIVE (2026-10-26, workspace 2): `CREATE OR REPLACE POLICY mask_contact_pii` and `mask_financial_pii` created `ON CATALOG meridian_t02` using `COLUMN MASK` targeting `MATCH COLUMNS has_tag_value('pii_type', ...)`. Verified in `information_schema.abac_policy_definitions` | PASS (live) | Stretch goal 10 achieved! Tag-driven centralized masking enforced across all tables in catalog. |
| Expectations with `AUTO CDC FROM SNAPSHOT` | verified docs (Sep 11, 2026): "Expectations are not supported with AUTO CDC FROM SNAPSHOT" | — | PASS (doc) — design impact | [ADR-004](decisions/adr-004-source-and-history.md): customer SCD2 flow cannot carry expectations; validate the customer snapshot in a preceding quarantined dataset before the snapshot flow |
| Lakeflow Designer / Genie / AI/BI dashboards / Power BI | UI probes | — | NOT TESTED | Probes scheduled in Phases 2, 6, 8, 9 |

## Quality and CDC

Expectations support warn/drop/fail actions and metrics in the pipeline event
log, but **not** on `AUTO CDC FROM SNAPSHOT` flows. Consequence for this
project: the customer snapshot source is validated (expectations + quarantine)
before the snapshot flow, and the SCD2 target itself is checked by
post-flow SQL (version counts, overlap tests, exactly-one-version join) rather
than by flow expectations.

Sources: [references.md](references.md#verified-this-session-checked-2026-10-25).
