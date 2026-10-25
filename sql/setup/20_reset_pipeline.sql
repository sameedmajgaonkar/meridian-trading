-- RESET: drop every dataset the pipeline owns so it can be redeployed and
-- rebuilt from scratch (used after changing a dataset's type in pipeline SQL —
-- e.g. STREAMING_TABLE -> MATERIALIZED_VIEW — which the runtime rejects on
-- existing datasets, and after code changes that need a clean first update).
--
-- AFTER RUNNING THIS FILE, the next pipeline update MUST be a FULL REFRESH:
-- out-of-band drops leave the pipeline's internal materialization registry
-- stale (observed 2026-10-25: the SCD2 flow still referenced the dropped
-- `__materialization_mat_<pipeline_id>_<dataset>_1` backing table and failed
-- with RESOURCE_DOES_NOT_EXIST). A full refresh rebuilds every dataset with
-- fresh mat/staging state. Full refresh is SAFE with respect to the SCD2
-- one-version rule only when ops.customer_snapshot_versions holds at most the
-- one pending version — this file empties it, and the simulator re-registers
-- exactly one version per progressive job run (--batch 1, then 2, then 3).
-- Manual file: run statement by statement in the SQL editor.
-- shortcut: catalog is literal (manual SQL-editor file); sed it if the
-- workspace-catalog fallback is ever activated.
--
-- What is deliberately KEPT:
--   * /Volumes/meridian_t02/landing/raw_files/** — landed batch files and
--     _manifest/*.json stay; the landing simulator is idempotent (a batch
--     directory that already has files is skipped) and the quality gate
--     reconciles against the manifests.
--   * gov.* (entitlements, row filters, UDFs) and the schemas/volume
--     themselves — created by sql/setup/10_create_project.sql, not the bundle.
--
-- What is EMPTIED on purpose:
--   * ops.customer_snapshot_versions — the runtime resolves
--     last_snapshot_version() ONLY inside WITH VERSION and
--     current_snapshot_version() not at all, so the SCD2 snapshot query
--     cannot replay multiple pending versions in one update (it selects
--     max(version)). Emptying the table guarantees each job run
--     (--batch 1, then 2, then 3) re-registers exactly one new version.
--     The simulator re-inserts rows idempotently (WHERE NOT EXISTS).
--   * gov.* (entitlements, row filters, UDFs) and the schemas/volume
--     themselves — created by sql/setup/10_create_project.sql, not the bundle.
--
-- Syntax per LIVE VERIFICATION (2026-10-25, this runtime): pipeline-managed
-- materialized views register as tables and reject DROP MATERIALIZED_VIEW
-- with DROP_COMMAND_TYPE_MISMATCH — DROP TABLE works for both pipeline MVs
-- and streaming tables. DROP VIEW is only for the metric view (a plain view).

USE CATALOG meridian_t02;

-- Gold metric view + dimensions + facts (recreated by pipeline/Phase 3 SQL)
DROP VIEW IF EXISTS gold.mv_trading;
DROP TABLE IF EXISTS gold.fct_order_lines;
DROP TABLE IF EXISTS gold.fct_orders;
DROP TABLE IF EXISTS gold.dim_customer_scd2;
DROP TABLE IF EXISTS gold.dim_supplier;
DROP TABLE IF EXISTS gold.dim_part;
DROP TABLE IF EXISTS gold.dim_nation;
DROP TABLE IF EXISTS gold.dim_region;

-- Ops monitoring views (recreated by the pipeline)
DROP TABLE IF EXISTS ops.pending_order_lines;
DROP TABLE IF EXISTS ops.duplicate_dispositions;
DROP TABLE IF EXISTS ops.quarantine_invalid;

-- Silver: the three typed datasets (now MATERIALIZED VIEWs — dropping these
-- is REQUIRED when they previously existed as STREAMING TABLEs) + the SCD2
-- target, so the AUTO CDC FROM SNAPSHOT flow replays all versions cleanly.
DROP TABLE IF EXISTS silver.orders;
DROP TABLE IF EXISTS silver.order_lines;
DROP TABLE IF EXISTS silver.customer_snapshot;
DROP TABLE IF EXISTS silver.customer_history;

-- Bronze: dropping the streaming tables resets Auto Loader state, so the
-- recreated tables re-ingest every landed file in one clean pass (and
-- DESCRIBE HISTORY / VERSION AS OF in runbook step 2.3 start from version 1).
DROP TABLE IF EXISTS bronze.supplier;
DROP TABLE IF EXISTS bronze.part;
DROP TABLE IF EXISTS bronze.region;
DROP TABLE IF EXISTS bronze.nation;
DROP TABLE IF EXISTS bronze.customer;
DROP TABLE IF EXISTS bronze.lineitem;
DROP TABLE IF EXISTS bronze.orders;

-- Empty the SCD2 version bookkeeping so the replayed story starts clean
-- (the simulator re-registers one version per job run, in order).
DELETE FROM ops.customer_snapshot_versions;

-- A FAILED pipeline update can leave orphaned staging swap-tables behind
-- (observed 2026-10-25: __staging_<update_id>_<dataset> typed
-- MATERIALIZED_VIEW in silver/gold/ops when a retry raced the update's
-- cleanup). Find and drop them:
SELECT table_schema, table_name FROM meridian_t02.information_schema.tables
WHERE table_name LIKE '__staging_%';
-- then for each row, e.g.:
-- DROP TABLE IF EXISTS gold.__staging_<update_id>_<dataset>;

-- Verify: nothing left but the kept artifacts.
SHOW TABLES IN bronze;
SHOW TABLES IN silver;
SHOW TABLES IN gold;
SHOW TABLES IN ops;
SELECT * FROM ops.customer_snapshot_versions ORDER BY version;
