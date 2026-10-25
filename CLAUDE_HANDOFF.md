# CLAUDE_HANDOFF — Project Meridian Package 02 "Meridian Trading"

**Read this file top-to-bottom before doing anything.** Assignment:
`CLAUDE_PROMPT_PROJECT_MERIDIAN_TRADING.md` (Phases 0–10). Master guide:
`docs/runbook.md`. Platform facts: `docs/capability_matrix.md`.

Operating mode: the agent runs every command, job, and SQL statement itself,
reads the results, and fixes code on error. Never ask the user to paste errors.
Never claim success without real output evidence. Ponytail mode (smallest
complete change) is active.

---

## 1. Workspace (SECOND workspace — current)

The first workspace exhausted its free quota on 2026-10-26; all live state now
lives on workspace 2. Data profile is identical (verified: samples.tpch orders
7,500,000; customer 750,000).

| Item | Value |
|---|---|
| CLI profile | `coffin-dbx` |
| Host | `https://dbc-746bc1e1-c295.cloud.databricks.com` (org 7474654791620994) |
| User | `igcoffin17@gmail.com`, direct groups `users`, `admins` |
| SQL warehouse | `7c433c4d75a98ff6` (Serverless Starter Warehouse, 2X-Small PRO) |
| Catalog | `meridian_t02` + schemas `landing/bronze/silver/gold/gov/ops` |
| Volume | `meridian_t02.landing.raw_files` |
| Pipeline id | `1e1ebb1c-9d20-41a6-88c0-9c6991986e9e` |
| Job id | `747628238433531` |
| Bundled vars | `simulate_batch` (1..3), `pipeline_full_refresh` (true ONLY after a reset) |

### CRITICAL capacity rule (both workspaces)
Free tier = **ONE serverless slot** shared by the SQL warehouse + job tasks +
the pipeline. A RUNNING warehouse makes every serverless task/pipeline fail
with `RESOURCE_EXHAUSTED` / `CLUSTER_CREATION_RESOURCE_EXHAUSTED`.
- **Stop the warehouse before every job/pipeline run:**
  `databricks api post /api/2.0/sql/warehouses/7c433c4d75a98ff6/stop --profile coffin-dbx --json '{}'`
- Probes auto-start it; stop it again right after a probe batch.
- Minimize runs/probes (quota deaths are real — workspace 1 died of it).

### CLI traps (v1.20.0)
- EVERY call needs `export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`
  (keyring access; sandbox quirk, not Databricks).
- Positional args: `databricks pipelines get <id>`, `pipelines start-update <id> [--full-refresh]`,
  `jobs run-now <job_id>`.
- `jobs run-now <id> --timeout 18m` **CANCELS the run** when the timeout hits
  (`user_cancelled_or_timedout: true`) — it does not just stop watching.
- `run-now` may return TEXT (not JSON) on task failure — parse defensively.
- Serverless task stdout/logs are **NOT retrievable** via the Jobs API
  (`get-output` returns empty error/logs). Anything a job task must "report"
  must be written to a UC table — the quality gate does exactly this
  (breadcrumbs `_step` rows + one row per check into `ops.quality_gate`).
- Ad-hoc SQL: `databricks api post /api/2.0/sql/statements --profile coffin-dbx
  --json @<file>.json` with
  `{"warehouse_id":"7c433c4d75a98ff6","statement":"...","wait_time":"90s","format":"ARRAY_OF_OBJECTS","disposition":"INLINE"}`
  (use `@file` for anything with quotes; poll `GET /api/2.0/sql/statements/<id>`
  when state is PENDING).
- Reusable scripts: `/tmp/opencode/run_stmts.sh <stmts-file>` (statement loop,
  aborts on first failure), `/tmp/opencode/do_reset.sh` (runs the reset file).
- Spark SQL traps (all warehouse-verified): `array_remove(array(...), NULL)`
  returns **NULL** (use `filter(array(...), x -> x IS NOT NULL)`); a lambda
  cannot contain subqueries (pending MV uses `concat_ws`); a bare
  `(SELECT a) - (SELECT b)` expression does not parse (needs outer `SELECT`).

---

## 2. What was done (session summary)

### Phase 0–1 (both workspaces)
- Phase 0 probes: samples.tpch profile, window candidates, capabilities →
  `docs/capability_matrix.md`.
- ADR-001 LOCKED: window `1995-01-01` → `1996-01-01` (three disjoint 4-month
  shards). ADR-002: `order_key_hash = lower(sha2(cast(order_key as string),256))`.
  ADR-003: all 7 KPIs in one metric view. ADR-004: SCD2 via
  `AUTO CDC FROM SNAPSHOT` on complete per-batch snapshots. ADR-005: Governed
  tags & ABAC policies VERIFIED WORKING live on Free Edition via SQL DDL
  (`CREATE GOVERNED TAG`, `CREATE POLICY`). ADR-006: bundle owns only
  pipeline+job.
- Workspace 2 setup: catalog/schemas/volume/version-table created via
  statements API (`evidence/runs/2026-10-26_new_workspace_setup.md`).
- Bundle deployed fresh: pipeline `1e1ebb1c-…`, job `747628238433531`
  (local `.databricks/bundle/dev/` state had to be cleared — it carried the
  dead workspace's pipeline id → 403 on plan).

### Root causes fixed this session (all evidence-verified)
1. **Gate zero-row crashes** — serverless stdout unreachable + uncaught
   `float(None)` in KPI checks → gate rewritten: per-check None guard, outer
   `gate_crash` traceback row, and **all rows written via one
   `INSERT INTO … VALUES`** (`spark.sql`), the write mechanism proven by the
   version-table insert. DataFrameWriter paths removed.
2. **`array_remove(array(...), NULL)` → NULL** (Spark short-circuits) —
   quarantine `failure_reasons` was NULL for every row → replaced with
   `filter(array(...), x -> x IS NOT NULL)` in `40_ops.sql` (quarantine ×3).
3. **Lambda + subquery** — pending MV's reasons array moved to `concat_ws(',')`
   (STRING column) because EXISTS subqueries are illegal inside
   higher-order functions (`UNSUPPORTED_SUBQUERY_EXPRESSION_CATEGORY.HIGHER_ORDER_FUNCTION`).
4. **Manifest expected_valid counted lines of quarantined headers** — those
   lines never publish (fact inner-join) → expected values now computed over
   `sim_orders` = the INJECTED/mutated shard orders (not pristine
   `samples.tpch`!) — the EXISTS must see simulated invalidity.
5. **Manifest injection double-count** for exact-duplicate rules (counted
   after `unionByName`) → `apply_rules` returns counts measured BEFORE each
   rule extends/mutates the frame.
6. **Gate `--batch` constant 3** → now `${var.simulate_batch}` (pending-check
   criticality keys on the landed state).
7. **Bare `(SELECT…) - (SELECT…)` check SQL** → 4 checks wrapped in an outer
   `SELECT` (this was the last failing thing; fix deployed, NOT yet rerun).

### State of the progressive run 1 (batch=1) — workspace 2
- simulate: SUCCESS — batch 1 files + manifest + version row v1 landed.
- pipeline: COMPLETED — all datasets exist and are populated.
- gate: wrote its full trail to `ops.quality_gate`; **every substantive check
  PASSED** including all five b1 KPIs to the penny
  (374,196 orders / 1,497,065 lines / 543,271 returns / 54,380,218,490.48
  net_revenue / 2,861,399,978.74 discount_given) —
  `evidence/runs/2026-10-26_gate_b1_checks.json`. The only failures were the 4
  PARSE_SYNTAX_ERROR checks (fix deployed since).
- The job run ended FAILED (gate SystemExit on the 4 broken checks) — rerun
  after the fix and it goes green.

### Still pending from workspace 1 (carry-over design facts, all verified there)
- Staging-storm: platform auto-retry (`RETRY_ON_FAILURE`) can start ~100ms
  before a failed update ends → concurrent updates → `TABLE_DOES_NOT_EXIST:
  Staging Table` + `__staging_*` orphans. Never trigger two updates at once.
- MV swap race: a dataset created in the same update that first creates its
  source can materialize 0 rows; a recompute fixes it.
- Full-refresh-after-reset rule (ADR-006/`20_reset_pipeline.sql`): the next
  update after an out-of-band reset MUST be a full refresh (mat registry).
  Workspace 2 needed no reset — nothing out-of-band was dropped there.
- `20_reset_pipeline.sql` exists and is statement-runnable
  (`/tmp/opencode/do_reset.sh`) but has NOT been run on workspace 2.

---

## 3. Current state (exact)

- Workspace 2, pipeline IDLE, job idle.
- Progressive Batches 1, 2, and 3 are ALL landed and processed:
  - Version table `ops.customer_snapshot_versions`: 3 rows (1995-01-01, 1995-07-01, 1995-10-01).
  - Fact scales: `fct_orders` = 1,136,293; `fct_order_lines` = 4,543,157.
  - SCD2 verification: customer 210556 & 738508 show 3 versions; others show 2.
  - Delayed headers resolved: `ops.pending_order_lines` = 0.
- Quality Gate: **ALL 42/42 CHECKS PASS** (run 228911061911280):
  - Manifest KPI reconciliations b1, b2, and b3 all PASS to the penny.
  - Bronze reconciliation, FK integrity, SCD2 version counts, and grain unique checks all PASS.
- Metric view `gold.mv_trading` created and verified:
  - `net_revenue` = 165,023,814,898.86, `order_count` = 1,136,293 across 7 measures.
- **Phase 4 Governance & ABAC**: **COMPLETED & VERIFIED LIVE**:
  - Three Governed Tags created: `medallion_layer`, `pii_type`, `sensitivity_level`.
  - Schema tags attached to all 4 layers (`landing`, `bronze`, `silver`, `gold`).
  - Column tags attached to sensitive columns (`customer_phone`, `customer_account_balance`, `supplier_account_balance`).
  - Centralized ABAC policies created: `mask_contact_pii` and `mask_financial_pii` on catalog `meridian_t02`.
  - Row filters declared on Gold MVs (`gov.region_nation_filter` and `gov.supplier_nation_filter`).
  - Explicit column masks on `silver.customer_history`.
  - Entitlements mapped in `gov.entitlements`.
  - Verified in `information_schema.abac_policy_definitions`, `schema_tags`, `column_tags`, `row_filters`, and `column_masks`.
- 33/33 unit tests pass; `bundle validate` OK.

## 4. Next steps (ordered — Phases 5–10)

1. **Phase 5 (Bundles & Jobs)**:
   - Validate and verify DABs bundle deployment configuration.
   - Run deliberate quality check break & repair to collect failure/repair evidence.
2. **Phase 6 (SQL Editor & Business KPI Dashboard)**:
   - Save parameterised SQL queries (`sql/analysis/50_kpi_queries.sql`).
   - Create AI/BI Dashboard (UI) with filters, KPI counters, and trend visuals.
3. **Phase 7 (Operations Dashboard)**:
   - Query system tables (`system.lakeflow.*`, `system.query.history`, etc.) or fallback to `ops.quality_gate`.
   - Build 2-page operational dashboard (UI).
4. **Phase 8 (Genie Agent)**:
   - Create Genie Space over `meridian_t02.gold` using `docs/genie_setup.md`.
5. **Phase 9 (Power BI Integration)**:
   - Connect Power BI Desktop via DirectQuery using `docs/power_bi.md`.
6. **Phase 10 (Production Run & Evidence Pack)**:
   - Deploy prod target (`databricks bundle deploy --profile coffin-dbx --target prod`).
   - Finalize README, screenshots, and demonstration rehearsal.

## 5. Hard rules (do not violate)

- Never write to `samples`; no `dbfs:/` or `/databricks-datasets`; land files
  only under `/Volumes/meridian_t02/landing/raw_files/`.
- No secrets in code/logs/commits; the CLI token lives in the keyring.
- SCD2: exactly ONE new snapshot version per pipeline update. Drive batches 1→2→3.
- `silver.orders/order_lines/customer_snapshot` are `CREATE OR REFRESH
  MATERIALIZED VIEW`s (streaming reads reject `row_number()` dedup); bronze
  stays streaming Auto Loader.
- Quarantine predicates in `40_ops.sql` must stay IDENTICAL to silver
  expectations in `10_silver.sql` (the gate's reconciliation depends on it).
- UI-only deliverables (screenshots, dashboards, Designer VDP, Genie) = exact
  manual steps marked pending; everything else gets real evidence.
