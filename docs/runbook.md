# Runbook — Project Meridian Execution Guide

Ordered build and verification guide for the Meridian Trading lakehouse (`meridian_t02`).
All CLI commands use your configured Databricks CLI profile (e.g. `--profile <profile>`).

## 1. Setup & Governance Pre-requisites

1. **Groups (UI)**: Settings -> Identity & Access -> Groups -> Create `t02_admins` and `t02_pii_readers`. Add your user to both.
   - Screenshot: `evidence/p1_groups.png`
2. **Catalog & Volume (SQL Editor)**: Execute `sql/setup/create_project.sql` with `:catalog = 'meridian_t02'`.
   - Creates catalog `meridian_t02`, schemas (`landing`, `bronze`, `silver`, `gold`, `gov`, `ops`), and volume `/Volumes/meridian_t02/landing/raw_files`.
   - Screenshot: `evidence/p1_catalog.png`

## 2. Deploy & Run Pipeline

1. **Deploy Development Bundle**:
   ```bash
   databricks bundle deploy -t dev
   ```
2. **Run Pipeline Progression (Batches 1 -> 2 -> 3)**:
   - Free Edition has one serverless compute slot. Ensure the SQL warehouse is stopped before running jobs:
     ```bash
     databricks api post /api/2.0/sql/warehouses/<warehouse-id>/stop --json '{}'
     ```
   - Trigger the job (`simulate_batch` defaults to `next`, advancing one batch per run):
     ```bash
     databricks bundle run meridian_t02_job
     ```
   - Run three times to land Batches 1, 2, and 3. The 6-task job runs: `gov_setup` & `simulate_batch` -> `pipeline_update` -> `gov_apply` & `metric_view` -> `quality_gate`.
   - Evidence: Verify `ops.quality_gate` has 42/42 checks PASS (`SELECT * FROM meridian_t02.ops.quality_gate ORDER BY checked_on DESC`).

## 3. Verify Star Schema, SCD2 & Metric View

1. **SCD2 Point-in-Time History**:
   ```sql
   SELECT customer_key, market_segment, valid_from, valid_to, is_current
   FROM meridian_t02.gold.dim_customer_scd2
   ORDER BY customer_key, valid_from;
   ```
2. **Metric View Aggregation (reconciled to the penny)**:
   ```sql
   SELECT order_status,
     MEASURE(net_revenue), MEASURE(order_count), MEASURE(average_order_value),
     MEASURE(delivery_days), MEASURE(late_delivery_rate),
     MEASURE(return_rate), MEASURE(discount_given)
   FROM meridian_t02.gold.mv_trading GROUP BY order_status;
   ```

## 4. Governance Verification

1. Run `sql/governance/audit.sql` to verify catalog tags, column tags, row filters, and ABAC column masks.
2. Run `sql/governance/restricted_probe.sql` as a non-admin / restricted identity:
   - Verifies row filter limits data strictly to entitled regions/nations.
   - Verifies phone is masked (`XXX-XXX-####`) and balance is `NULL`.
   - Screenshot: `evidence/p4_masks.png`

## 5. Dashboards & Genie

1. **Business KPI Dashboard**: Databricks -> Dashboards -> Open `Meridian Trading — Wholesale Executive KPIs`.
   - Screenshot: `evidence/p6_dashboard.png`
2. **Operations Telemetry Dashboard**: Open `Meridian Trading — Operations Telemetry` (run health & system cost telemetry).
   - Screenshot: `evidence/p7_ops_dashboard.png`
3. **Genie Agent Space**: AI/BI -> Genie -> Space `Meridian Wholesale Revenue`.
   - Ask benchmark questions from `docs/genie.md`.
   - Screenshot: `evidence/p8_genie.png`

## 6. Power BI DirectQuery Integration

1. Open Power BI Desktop on Windows.
2. Connect via **Azure Databricks** connector using DirectQuery on `meridian_t02.gold.mv_trading`.
3. Add 3 visuals per `docs/power_bi.md`: Monthly Revenue Trend, AOV by Segment, Return & Late Rate cards.
4. Screenshot: `evidence/p9_powerbi.png`

## 7. Production Deployment (Phase 10)

1. Validate and deploy production target:
   ```bash
   databricks bundle validate -t prod
   databricks bundle deploy -t prod
   ```
2. Keep schedule paused until demonstration.
