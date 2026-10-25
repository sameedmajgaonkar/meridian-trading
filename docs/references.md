# References — official documentation with access dates

Rule: primary sources are `docs.databricks.com` and `learn.microsoft.com`. Every
entry records the official URL, the page title, the "Last updated" date shown on
the page when visible, the date this project checked it, and the project
decision the source supports. Pages not fetched in a session stay in
[Pending verification](#pending-verification) until checked; never cite an
unchecked page as current.

## Verified this session (checked 2026-10-25)

| Official URL | Title | Page last updated | Supports |
|---|---|---|---|
| https://docs.databricks.com/aws/en/getting-started/free-edition-limitations | Databricks Free Edition limitations | Oct 18, 2026 | [ADR-005](decisions/adr-005-platform-limitations.md), [capability matrix](capability_matrix.md): one 2X-Small SQL warehouse, max 5 concurrent job tasks, one active pipeline per type, no account console / account-level APIs, serverless-only |
| https://docs.databricks.com/aws/en/dev-tools/bundles/ | What are Declarative Automation Bundles? | Sep 11, 2026 | Phase 5 bundle design: DAB (formerly Asset Bundles), CLI ≥ 0.218.0, `bundle init/validate/deploy`, OAuth U2M recommended |
| https://docs.databricks.com/aws/en/ldp/cdc | The AUTO CDC APIs: Simplify change data capture with pipelines | Oct 9, 2026 | [ADR-004](decisions/adr-004-source-and-history.md): `AUTO CDC FROM SNAPSHOT` with a version query / `next_snapshot_and_version` selector; SCD2 emits `__START_AT`/`__END_AT`; requires serverless, Pro, or Advanced pipelines |
| https://docs.databricks.com/aws/en/ldp/expectations/ | Manage data quality with pipeline expectations | Sep 11, 2026 | Quarantine design: `EXPECT` (warn) / `EXPECT ... ON VIOLATION DROP ROW` / `FAIL UPDATE`; **expectations are not supported with `AUTO CDC FROM SNAPSHOT`** — see [capability matrix](capability_matrix.md#quality-and-cdc) |
| https://docs.databricks.com/aws/en/data-governance/unity-catalog/filters-and-masks/ | Row filters and column masks | Oct 9, 2026 | [ADR-005](decisions/adr-005-platform-limitations.md), [security model](security_model.md): table-level `SET ROW FILTER` / `SET MASK` UDFs apply to **tables, not views**; masks must be type-preserving; time travel unsupported with table-level controls |
| https://docs.databricks.com/aws/en/admin/governed-tags/ | Governed tags | Oct 12, 2026 | [ADR-005](decisions/adr-005-platform-limitations.md): governed tags and their policies are **account-level**; Free Edition has no account console or account-level APIs, so creation is expected BLOCKED; fallback = ordinary tags + audit + documented deviation |
| https://docs.databricks.com/aws/en/uc-semantics/metric-views/feature-availability | Metric view feature availability | Oct 13, 2026 | [ADR-003](decisions/adr-003-kpis.md): `one_to_many` joins need YAML spec 1.1 and DBR ≥ 18.1; SQL warehouses auto-update, so the workspace DBSQL version drives support |
| https://docs.databricks.com/aws/en/uc-semantics/metric-views/yaml-reference | Metric views YAML reference | Oct 13, 2026 | Phase 3 metric view grammar: `source`, `joins` with `on:`/`cardinality:`, fields/measures; invoker-dependent expressions (`current_user()`, `is_member()`) are not allowed in definitions; RLS/masked sources block metric-view materialization |
| https://docs.databricks.com/aws/en/uc-semantics/metric-views/tpch-example | Metric view TPC-H example | Oct 2026 | Phase 3 `one_to_many` join example (`on: source.x = join.x`) mirrored in `sql/metric_views/20_mv_trading.sql` |
| https://docs.databricks.com/aws/en/sql/language-manual/functions/read_files | read_files table-valued function | Oct 2026 | Phase 1 Bronze: volume paths, `format =>`, `_metadata.file_path` lineage columns, `STREAM(read_files(...))` |
| https://docs.databricks.com/aws/en/ldp/developer/ldp-sql-ref-create-flow | CREATE FLOW (pipelines) | Oct 15, 2026 | Phase 2 SCD2: exact `AUTO CDC ... FROM SNAPSHOT (query) WITH VERSION (query) KEYS ... STORED AS SCD TYPE 2` syntax, `current_snapshot_version()`/`last_snapshot_version()`, `TRACK HISTORY ON`, error codes for the runbook |
| https://docs.databricks.com/aws/en/ldp/parameters | Use parameters with pipelines | Oct 12, 2026 | Phase 1–3: pipeline `configuration` parameters referenced as `${...}` in SQL sources — keeps `var.nn` the single source of truth |
| https://docs.databricks.com/aws/en/dev-tools/bundles/settings | Bundle configuration (settings) | Sep 11, 2026 | Phase 5 `databricks.yml`: variables, include, targets/deployment modes |
| https://docs.databricks.com/aws/en/dev-tools/bundles/resources | Bundle resource definitions | Oct 2026 | Phase 5 `resources/`: pipelines (`libraries`, `catalog`, `schema`, `serverless`, `configuration`) and jobs (`tasks`, `spark_python_task`, `pipeline_task`, `environments`, paused schedule) |
| https://docs.databricks.com/aws/en/ldp/build-pipelines | Build pipelines (overview index) | Oct 12, 2026 | Navigation page — detailed syntax verified via the CREATE FLOW / read_files / expectations pages above |

Workspace-observed runtime facts are recorded in the
[capability matrix](capability_matrix.md), not here.

## Pending verification

Verify before the phase that uses the page; move to the table above with the
access date. Access was blocked by DNS earlier on 2026-10-25 and restored later
the same day.

- https://docs.databricks.com/aws/en/ldp/monitor-event-logs — pipeline event log (Phase 2, 7)
- https://docs.databricks.com/aws/en/admin/system-tables — system tables (Phase 7; schemas + lakeflow/job tables confirmed visible by `SHOW` on 2026-10-25; SELECT rights still unverified)
- https://docs.databricks.com/aws/en/designer/what-is-lakeflow-designer — Lakeflow Designer (Phase 2 visual prep)
- https://docs.databricks.com/aws/en/designer/build-transformation — visual data prep build (Phase 2)
- https://docs.databricks.com/aws/en/sql/user/queries/query-parameters — SQL query parameters (Phase 6)
- https://docs.databricks.com/aws/en/dashboards/ — AI/BI dashboards (Phase 6–7)
- https://docs.databricks.com/aws/en/genie-agents/set-up — Genie Agents (Phase 8)
- https://docs.databricks.com/aws/en/partners/bi/power-bi — Power BI integration (Phase 9)
- https://docs.databricks.com/aws/en/dev-tools/bundles/work-tasks — bundle lifecycle (Phase 5)

## Platform and setup

See the verified Free Edition limitations row above. Local trainee brief:
`Project Meridian: Data Engineering capstone project` (Version 1.0, October
2026) and Package 02 sheet (`Project Meridian - Databricks Free Edition DE
Problem Statement.pdf`, `Package_02_trading.png` in the repository root).

## Modeling and history

See the verified AUTO CDC and metric-view availability rows above.
