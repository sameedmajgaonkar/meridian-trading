# Meridian Trading — Project Meridian Package 02

> Databricks Free Edition lakehouse for **Wholesale order-to-revenue** (trainee **NN=02**).
> All phases generated (Phases 0–10 artifacts in repo). **Run + evidence the
> steps in [docs/runbook.md](docs/runbook.md)** — it is the ordered build and
> the learn-afterwards guide.

## Variables (single source of truth)

| Variable | Value |
|---|---|
| Trainee number `NN` | `02` |
| Catalog | `meridian_t02` |
| Volume | `/Volumes/meridian_t02/landing/raw_files/` |
| Groups | `t02_admins`, `t02_pii_readers` |
| Workspace | `sameed-dbx` (`dbc-7b9af537-03b9.cloud.databricks.com` o=7474657326378857) |
| Source (read-only) | `samples.tpch` (orders, lineitem, customer, nation, region, part, supplier) |

All references to catalog / volume / groups use `var.nn` in `databricks.yml` — no scattered literals.

## Branching strategy

Git is not yet initialized (pending Bash availability). When initialized: `main` is protected; work on feature branches `phase-0`, `phase-1`, etc., PR → `main`.

## Phase 0 — what it is

- **Why:** settle date window, grain, hash meaning, KPI definitions, and capability gaps on observed data before writing any pipeline.
- **Mental model:** Bronze = loading dock (nothing thrown away), Silver = warehouse (typed + quarantined + SCD2), Gold = showroom (star + metric view), governance = badge reader.
- **Key docs:** `docs/superpowers/specs/2026-10-25-meridian-trading-phase0-design.md` (spec), `docs/architecture.md`, `docs/data_contract.md`, `docs/capability_matrix.md`, `docs/references.md`, `docs/decisions/`.
- **Locked window:** orders `1995-01-01` → `1996-01-01` (ADR-001) — the only full year with all return flags A/R/N and statuses F/P/O.

## Repo layout

```
.
├── databricks.yml            bundle: 2 resources only (ADR-006)
├── resources/                pipeline.yml (1 pipeline), job.yml (3 tasks, paused schedule)
├── src/landing/              simulate.py (parquet batches into the volume) + injection.py (deterministic plan)
├── src/pipeline/             00_bronze → 10_silver → 20_customer_scd2 → 30_gold → 40_ops (SQL, ${param} config)
├── src/quality_gate/         quality_gate.py (reconciliation + fail-on-bad)
├── sql/setup|governance|metric_views|analysis/   manual SQL (setup 10/11, gov 30–34, mv 20, analysis 50/53/54)
├── lakeflow_designer/        VDP exercise recipe (UI)
├── docs/superpowers/specs/   phase-0 design spec
├── docs/decisions/           ADR-001 … ADR-006
├── docs/runbook.md           THE ordered build + evidence checklist
└── evidence/                 git-ignored proof artifacts
```

## How to run Phase 0 probes

**Auth note (sandbox/CI shells):** the CLI reads tokens from the OS keyring.
If it fails with `OS keyring unreachable: dial unix /run/user/1000/bus`,
export `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` first
(alternative: `DATABRICKS_AUTH_STORAGE=plaintext`). This is a local environment
quirk, not a Databricks denial.

In the `sameed-dbx` SQL warehouse (or via `databricks experimental aitools tools query --profile sameed-dbx`):

```sql
-- see sql/explore/inspect_samples.sql and sql/explore/profile_window.sql
SHOW SCHEMAS IN samples;
DESCRIBE TABLE samples.tpch.orders;
SELECT min(o_orderdate), max(o_orderdate), count(*) FROM samples.tpch.orders;
```

Capture screenshots to `evidence/p0_*.png`.

## Observed environment facts

Verified live on 2026-10-25 (see `docs/capability_matrix.md` and `evidence/runs/`):

| Fact | Value | How verified |
|---|---|---|
| CLI version | v1.20.0 | `databricks --version` |
| CLI auth | works **only with** `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` exported | `current-user me` (sandbox keyring quirk; not a Databricks denial) |
| Warehouse | `Serverless Starter Warehouse`, 2X-Small PRO, id `a20a2b2aaf17c10f` | `warehouses list` |
| DBSQL version | 2026.39 (serverless) | `SELECT current_version()` |
| Catalog `meridian_t02` | not yet created | `SHOW CATALOGS` → only samples/system/workspace |
| Volume `landing.raw_files` | not yet created | pending Phase 1 probe |
| Date window | **LOCKED: 1995-01-01 → 1996-01-01** (ADR-001) | profile run on 1,136,308 orders |
| Source integrity | 0 orphans, 0 FK violations, hash collision check passed | 1995 profile run |
| Governed tags & ABAC | VERIFIED LIVE via SQL DDL (`CREATE GOVERNED TAG`, `CREATE POLICY`) on Free Edition | Tested live 2026-10-26 (`coffin-dbx`); 3 tags created & applied, 2 ABAC policies active |
| Metric view YAML 1.1 / one_to_many | requires DBR ≥ 18.1; SQL warehouses auto-update (2026.39) | Tested live 2026-10-26 (`gold.mv_trading` reconciled to the penny) |
| System tables | `system.lakeflow/query/billing/access` all visible via SHOW | `SHOW SCHEMAS IN system` + `SHOW TABLES` ×4; SELECT rights pending Phase 7 |
| Lakeflow Designer / Genie | pending UI probe | manual check |

## Quickstart

1. Create the two groups + run `sql/setup/create_project.sql` (runbook 1.1–1.2)
2. `databricks bundle deploy --profile coffin-dbx --target dev`
3. Run `meridian_t02_job` (lands 3 batches → pipeline update → quality gate)
4. Run `sql/metric_views/trading_metrics.sql`, then governance SQL files
5. Build the two dashboards, Genie space, Power BI (runbook 6–9)

## Phases

| # | Title | Status |
|---|---|---|
| 0 | Explore, Profile & Design | DONE (probes + evidence; 2 UI screenshots pending) |
| 1 | Landing simulator & Bronze | DONE (Batches 1-3 landed, streaming ingestion proven) |
| 2 | Silver, quarantine, SCD2, Designer prep | DONE (SCD2 3-version history verified, 0 pending lines) |
| 3 | Gold model, two-grain metric view | DONE (Star schema MVs + `mv_trading` reconciled live) |
| 4 | Governance (tags, row filters, masks) | DONE (Governed tags, ABAC policies, row filters, masks active) |
| 5 | Bundle, Job, quality gate | DONE (Job 747628238433531 green; 42/42 gate checks PASS) |
| 6 | SQL queries & AI/BI dashboard | DONE (Published dashboard on metric view with typed parameters; evidence saved) |
| 7 | Operations dashboard | DONE (2-page Operations Telemetry dashboard published on system tables) |
| 8 | Genie Agent | DONE (Space created, instructions & benchmarks configured) |
| 9 | Power BI | CONNECTION READY (DirectQuery string updated for workspace 2) |
| 10 | Production run & evidence | BUNDLE VALIDATED (dev & prod targets OK; ready for prod run) |

Statuses mean: GENERATED = code/config/SQL exist in repo, tests pass, needs a
real run; PENDING = requires interactive UI the agent cannot click.

## Security notes

- Never write to `samples`. Never use `dbfs:/` or hard-coded personal paths.
- Never commit tokens / secrets / `.env`. Bundle auth via env vars.
- Schedules stay paused until Phase 10.

## References

See `docs/references.md` for official Databricks + Microsoft docs with checked dates.

## License

Internal training project — not for distribution.
