# Runbook — build, run, and evidence the whole project

Every step is one action + one line of why. Steps marked **UI** are done in the
browser; everything else is CLI or SQL editor. Checkboxes are the evidence
checklist — save every artifact into `evidence/` (it is git-ignored, which is
expected; the docs cite the paths).

Auth note for local shells: the CLI needs
`export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` before any
`databricks` command (sandbox keyring quirk — see `docs/capability_matrix.md`).

## Step 0 — prerequisites (done in Phase 0)

- [x] Phase 0 probes run, evidence saved (`evidence/runs/20261025T*`)
- [ ] `evidence/p0_profile.png` — **UI**: Data → samples → run a profile query → screenshot (pending)
- [ ] `evidence/p0_capability_matrix.png` — **UI**: Catalog Explorer showing `samples.tpch` tables (pending)
- [ ] Git initialized (`git init`, `.gitignore` already exists) — ADR-005 records the gap

## Step 1 — Phase 1: governance objects, landing, Bronze

1.1 **UI — create the two groups** (workspace admin):
Workspace admin → **Settings → Identity & access → Groups → Add group**:
`t02_admins` and `t02_pii_readers`; add `sameed1718@gmail.com` to both.
*Why: the row-filter and mask UDFs branch on these two names; membership is
also what we probe for `is_member()` vs `is_account_group_member()`.*
- [ ] screenshot `evidence/p1_groups.png`

1.2 **SQL editor — create the UC objects**: run `sql/setup/create_project.sql`
statement by statement. Expected: `SHOW SCHEMAS` lists landing/bronze/silver/
gold/gov/ops + `customer_snapshot_versions` table + `landing.raw_files` volume.
If `CREATE CATALOG` is denied: record the denial message and set `catalog` in `databricks.yml`.
- [ ] screenshot `evidence/p1_catalog.png` (Catalog Explorer showing the 6 schemas + volume)

1.3 **CLI — deploy the bundle** (creates the pipeline + job only):

```
databricks bundle deploy --profile coffin-dbx --target dev
```
- [ ] CLI output saved to `evidence/runs/<ts>_deploy.txt`

1.4 **UI or CLI — run the job once**:

```
databricks jobs run-now --job-id <id from bundle deploy output> --profile coffin-dbx
```
(or Workflows → meridian_t02_job → Run). **First run from a clean state:
deploy with `--var simulate_batch=1` and run the job**:

```
databricks bundle deploy --profile coffin-dbx --target dev --var simulate_batch=1
databricks jobs run-now --job-id <id from the deploy output> --profile coffin-dbx
```

**Stop the SQL warehouse first** (`POST /api/2.0/sql/warehouses/<id>/stop`) —
free-tier serverless capacity is a single slot shared by the warehouse, job
tasks, and the pipeline; a RUNNING warehouse makes every job task fail with
`CLUSTER_CREATION_RESOURCE_EXHAUSTED` / `RESOURCE_EXHAUSTED` (observed
2026-10-26). Probes auto-start it; stop it again after probing.

`quality_gate` runs with the same `simulate_batch` var — it reconciles whatever
batches have landed, warns on missing manifests, and keys the pending-lines
criticality on the landed state (delayed headers are expected before the final
batch). The SCD2 flow must see exactly ONE new snapshot
version per update (warning in `src/pipeline/20_customer_scd2.sql`) — run
batches strictly in order (1, then 2, then 3). Note: serverless pipelines
auto-retry a FAILED update (`RETRY_ON_FAILURE` in
`system.lakeflow.pipeline_update_timeline`); a retry can race the failed
update's staging cleanup — if you ever see
`TABLE_DOES_NOT_EXIST: Staging Table ...`, let all updates settle to IDLE,
clean orphans (see `sql/setup/reset_pipeline.sql`), and rerun.
- [ ] job run URL captured
- [ ] **UI** screenshot `evidence/p1_bronze_tables.png` (Catalog Explorer → bronze schema)

1.5 Verify Bronze lineage + Auto Loader incremental behavior:

```sql
SELECT _batch_id, _source_file, count(*) FROM meridian_t02.bronze.orders
GROUP BY _batch_id, _source_file ORDER BY _batch_id;
```
*Why: proves only newly landed files were processed per update.*

## Step 2 — Phase 2: silver, quarantine, SCD2, delayed headers

2.1 Deploy and run twice more, once with `--var simulate_batch=2`, then with
`--var simulate_batch=3` (one deploy per run; the first run in 1.4 used `1`).
The batch-2 run lands the five early lines whose headers arrive only in
batch 3; the batch-3 run resolves them. Each run: land → pipeline update →
quality gate.
- [ ] three run URLs captured

2.2 Prove SCD2 history (segment changes at 1995-07-01 / 1995-10-01):

```sql
SELECT customer_key, market_segment, valid_from, valid_to, is_current
FROM meridian_t02.gold.dim_customer_scd2
WHERE customer_key IN (210556, 738508, 254500, 299800)
ORDER BY customer_key, valid_from;
```
Expected: 210556 and 738508 show three versions; the other two show two.
- [ ] screenshot `evidence/p2_scd2_history.png`

2.3 Prove Delta history + time travel on a pipeline-managed table:

```sql
DESCRIBE HISTORY meridian_t02.bronze.orders;
SELECT count(*) FROM meridian_t02.bronze.orders VERSION AS OF 1;
```
- [ ] screenshot `evidence/p2_time_travel.png`

2.4 Dispositions: invalid rows kept with reasons, duplicates dispositioned,
early lines pending then resolved:

```sql
SELECT entity, failure_reasons, count(*) FROM meridian_t02.ops.quarantine_invalid
GROUP BY entity, failure_reasons ORDER BY entity;
SELECT entity, is_conflict, count(*) FROM meridian_t02.ops.duplicate_dispositions
GROUP BY entity, is_conflict;
SELECT * FROM meridian_t02.ops.pending_order_lines;
```
- [ ] after the batch-2 run: screenshot `evidence/p2_pending_before.png` (5 NO_HEADER lines)
- [ ] after the batch-3 run: screenshot `evidence/p2_pending_after.png` (0 rows)
- [ ] `evidence/runs/<ts>_quality_gate_*.txt` — gate log per run

## Step 3 — Phase 3: metric view + reconciliation

3.1 **SQL editor**: run `sql/metric_views/trading_metrics.sql` (creates
`gold.mv_trading` as YAML 1.1 metric view with the one_to_many join).

3.2 Reconcile the seven KPIs against independent source SQL:

```sql
SELECT order_status,
  MEASURE(net_revenue), MEASURE(order_count), MEASURE(average_order_value),
  MEASURE(delivery_days), MEASURE(late_delivery_rate),
  MEASURE(return_rate), MEASURE(discount_given)
FROM meridian_t02.gold.mv_trading GROUP BY order_status;
```
The quality gate already reconciled per-shard revenue/counts against the
simulator manifests (raw-source baseline); show `ops.quality_gate` PASS rows.
- [ ] screenshot `evidence/p3_metric_view.png`

## Step 4 — Phase 4: governance

4.1 Run `sql/governance/entitlements.sql` → `functions.sql` → `apply_policies.sql`
→ `grants.sql` in that order (apply_policies needs Gold tables to exist).
4.2 Run `sql/governance/audit.sql` as admin; save outputs.
4.3 **Probe `is_account_group_member`**: if the first function statement errors on
`is_account_group_member`, swap to `is_member`.
4.4 **Probe governed tags** once: Catalog Explorer → any Gold table → Tags →
try Add tag.
4.5 Restricted-principal checks (audit file, last 2 queries): log in as a
non-admin test user with an entitlements row (see entitlements.sql) — or, if only
one identity exists, run the queries and record that the check is covered by
the direct function tests instead.
- [ ] `evidence/runs/<ts>_governance_audit.txt`
- [ ] screenshot `evidence/p4_row_filter.png` (per-region counts)
- [ ] screenshot `evidence/p4_masks.png` (masked vs unmasked phone/balance)
- [ ] metric view still queries (run 3.2 again)

## Step 5 — Phase 5: bundle, job, quality gate (mostly done by deploy)

5.1 Show the deploy plan before any change: `databricks bundle deploy --profile coffin-dbx --dry-run > evidence/runs/<ts>_deploy_plan.txt`
5.2 `ops.quality_gate` evidence: `SELECT * FROM meridian_t02.ops.quality_gate ORDER BY checked_on DESC LIMIT 40;`
- [ ] screenshot `evidence/p5_quality_gate.png`

## Step 6 — Phase 6: SQL queries + AI/BI dashboard

6.1 Open each query in `sql/analysis/kpi_queries.sql` in the SQL editor,
create the typed parameter widgets by dragging the `:param` markers, save
all three.
6.2 **UI — create the dashboard**: Databricks → Dashboards → Create; add 4
widgets: (a) monthly KPI trend (6.1 by month), (b) region revenue mix (6.2),
(c) order-status split (6.3), (d) top-10 customers per segment from
`sql/analysis/top_customers.sql`. Publish to the workspace.
- [x] screenshot `evidence/p6_dashboard.png` (Meridian Trading — Wholesale Executive KPIs)

## Step 7 — Phase 7: operations dashboard

7.1 Create a second dashboard from `sql/analysis/ops_widgets.sql` widgets:
pipeline health, job runs, quality gate, quarantine pressure, spend, audit.
- [x] Operations dashboard created and published (Meridian Trading — Operations Telemetry)
- [ ] screenshot `evidence/p7_ops_dashboard.png` (pending upload)

## Step 8 — Phase 8: Genie

8.1 **UI**: Databricks → Genie → New space over `meridian_t02.gold`; paste the
instructions + examples from `docs/genie.md`; run the benchmark questions.
- [x] Genie Space created and benchmarks evaluated (`docs/genie.md`)
- [ ] screenshot `evidence/p8_genie.png`

## Step 9 — Phase 9: Power BI

9.1 Follow `docs/power_bi.md` (Desktop on Windows; Direct Query to the
warehouse; three visuals; refresh-identity check).
- [ ] screenshot `evidence/p9_powerbi.png`

## Step 10 — Phase 10: production run

10.1 Deploy the prod target: `databricks bundle deploy --profile coffin-dbx --target prod`
(the pipeline switches to production mode; the schedule stays PAUSED until
demonstrated).
10.2 **UI**: show the prod job, demonstrate it, then flip the schedule to
paused=ON afterwards if you prefer it off in steady state.
10.3 Re-run the full evidence checklist above and update README's phase table.
- [ ] `evidence/runs/<ts>_prod_deploy.txt`
- [ ] README statuses updated

## Troubleshooting (what each failure means)

| Symptom | Meaning | Fix |
|---|---|---|
| CLI: `OS keyring unreachable` | sandbox dbus issue, not Databricks | export DBUS_SESSION_BUS_ADDRESS |
| `CREATE CATALOG` denied | privilege missing on Free Edition | record denial → fallback SQL 11 → set `catalog`/`schema_prefix` vars |
| Pipeline error mentioning `${catalog}` unresolved | pipeline parameter substitution not applied | set the literal catalog in `src/pipeline/*.sql` and redeploy (recorded fallback) |
| `AUTO_CDC_FROM_SNAPSHOT_NON_EMPTY_TARGET_WITHOUT_VERSION` | WITH VERSION missing | should not happen — customer_history.sql includes it |
| `Function last_snapshot_version() can only be used in the WITH VERSION clause` | it resolved, but outside WITH VERSION (e.g. in the snapshot query) | keep it ONLY in the WITH VERSION selector; the snapshot query uses `max(version)` + the one-version-per-update rule |
| Gold MV built with 0 rows while sources have data | the MV was refreshed during the update that first CREATED its source — pipeline MV creation swaps `__staging_*` tables in, and a dependency can refresh against the not-yet-swapped (empty) source | rerun the pipeline update once tables exist (no swaps → clean recompute); verified 2026-10-25: `fct_orders` was 0 after the first creation update, the same PIT join returned 1,136,293 rows via warehouse SQL, and a recompute filled it |
| `RESOURCE_DOES_NOT_EXIST: __materialization_mat_...` | out-of-band DROP of a pipeline dataset left the pipeline's mat registry stale — a NORMAL update replays the stale reference | the next update after `reset_pipeline.sql` must be a FULL REFRESH (`databricks pipelines start-update <id> --full-refresh`); safe when the version table holds ≤1 pending version |
| `TABLE_DOES_NOT_EXIST: Staging Table '<uuid>'` | a pipeline update's staging swap-table vanished mid-run — a concurrent update raced it (observed: platform auto-retry `RETRY_ON_FAILURE` overlapping the failed update) | wait for pipeline IDLE, drop `__staging_%` orphans (reset file has the query), rerun; never trigger two updates at once |
| SCD2 history has fewer versions than expected (shape checks pass) | a pipeline update processed ≥2 pending versions (multi-version replay) | run `sql/setup/reset_pipeline.sql` (empties the version table), then rerun batches strictly 1 → 2 → 3; the gate's `scd2_segment_versions_*` checks now fail loudly on this |
| `CANNOT_CHANGE_DATASET_TYPE` (STREAMING_TABLE ↔ MATERIALIZED_VIEW) | a dataset's type changed in pipeline SQL but the old object still exists | run `sql/setup/reset_pipeline.sql` (drops pipeline datasets; keeps volume, manifests), redeploy, rerun |
| `APPLY_CHANGES_FROM_SNAPSHOT_ERROR.OUT_OF_ORDER_SNAPSHOT_VERSION` | version table got a smaller/equal date | insert only strictly increasing effective dates |
| `INVALID_AUTO_CDC_FROM_SNAPSHOT_VERSION_QUERY` | version query returned >1 row or NULL | keep the `LIMIT 1` selector as shipped |
| `RESOURCE_EXHAUSTED` / `CLUSTER_CREATION_RESOURCE_EXHAUSTED` on any serverless task or pipeline | free tier has ONE serverless slot shared by the SQL warehouse + job tasks + the pipeline; something else is holding it (usually the starter warehouse RUNNING) | stop the warehouse (`POST /api/2.0/sql/warehouses/<id>/stop`), wait for state STOPPED, rerun; keep probes short and stop the warehouse after each probe batch. Both workspaces showed this on 2026-10-26 |
| quality gate FAIL `bronze_reconciliation_*` | quarantine predicates drifted from silver expectations | keep silver.sql and ops.sql predicates identical |
| metric view errors after Phase 4 | metric view over row-filtered source unsupported in materialization mode | see capability_matrix fallback |
| `spark_python_task` rejected | serverless environment spec drifted | keep `environment_key: default` from job.yml |
| Gate task fails with 0 rows in `ops.quality_gate` and serverless logs are empty | serverless task stdout/logs are NOT retrievable via the Jobs API (`get-output` returns empty error/logs fields) — a silent exception is invisible; the original DataFrameWriter write path failed without a trace | gate now writes breadcrumbs + every check row via a single `INSERT INTO … VALUES` (the mechanism proven by the version-table insert); diagnose by reading `ops.quality_gate`, not task logs |
| Quarantine rows exist but `failure_reasons` is NULL for all of them | Spark's `array_remove(array(...), NULL)` returns **NULL** when the element argument is NULL (short-circuits the whole function; warehouse-verified 2026-10-25) | use `filter(array(...), x -> x IS NOT NULL)` — fixed in `ops.sql` (quarantine ×3 + pending reasons) |
| Gate KPI `lines/returns/net_revenue` FAIL by a small delta while `orders` reconciles exactly | the manifest's `expected_valid` counted lines of quarantined headers — those lines never publish (the fact's inner join drops them) and sit as permanent `NO_HEADER` pending rows | fixed in `simulate.py`: expected values count only lines with a valid in-shard header; `pending_order_lines` excludes header-quarantined orphans (dispositioned with the header's quarantine entry). Re-running simulate rewrites landed manifests (entity dirs skip idempotently; manifests rewrite unconditionally) |
| Manifest injection counts are 2× for exact-duplicate rules | the manifest counted matching rows AFTER `unionByName` added the copies (originals + copies) | fixed in `simulate.py`: `apply_rules` counts injections before each rule extends/mutates the frame |
