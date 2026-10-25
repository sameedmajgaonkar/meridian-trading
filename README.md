# Meridian Trading — Project Meridian Package 02

> Governed Databricks Lakehouse for **Wholesale order-to-revenue** (`meridian_t02`).

This repository implements an end-to-end governed lakehouse on Databricks Free Edition using Lakeflow Pipelines, Unity Catalog governance (Governed Tags and ABAC policies), SCD Type 2 change data capture, a semantic metric view, and automated quality gates.

---

## 1. Quickstart & Execution

All CLI commands use your configured Databricks CLI profile (e.g. `--profile <profile>`).

1. **Bootstrap Unity Catalog Objects**:
   Run `sql/setup/create_project.sql` in the SQL Editor with `:catalog = 'meridian_t02'`. Creates catalog, schemas (`landing`, `bronze`, `silver`, `gold`, `gov`, `ops`), and volume `/Volumes/meridian_t02/landing/raw_files`.
2. **Deploy the Asset Bundle**:
   ```bash
   databricks bundle deploy -t dev
   ```
3. **Run Pipeline Progression**:
   Databricks Free Edition has **one serverless compute slot**. Ensure the SQL warehouse is stopped before triggering jobs:
   ```bash
   databricks api post /api/2.0/sql/warehouses/<warehouse-id>/stop --json '{}'
   ```
   Run the job (runs with `simulate_batch=next` by default, advancing one batch per run):
   ```bash
   databricks bundle run meridian_t02_job
   ```
   Execute 3 times to land and process Batches 1, 2, and 3.
4. **Governance Setup**:
   Governance SQL policies (`sql/governance/apply_policies.sql`, `sql/governance/functions.sql`) are re-applied after a full pipeline refresh.

---

## 2. Architecture & Data Flow

```
Raw Files (Parquet Batches 1, 2, 3 in UC Volume)
  │
  ▼ [Auto Loader Streaming Ingestion]
Bronze Layer (`meridian_t02.bronze.*`)
  ├── orders, lineitem, customer, part, supplier, nation, region
  │
  ▼ [Quality Rules, Quarantine Predicates, Deduplication]
Silver Layer (`meridian_t02.silver.*`)
  ├── orders (deduplicated by order_key; invalid rows dropped to ops)
  ├── order_lines (deduplicated by order_key, line_number)
  ├── customer_changes (streaming table of change records)
  └── Ops Quarantines (`ops.quarantine_invalid`, `ops.duplicate_dispositions`, `ops.pending_order_lines`)
  │
  ▼ [AUTO CDC INTO & SCD Type 2]
Silver Customer History (`meridian_t02.silver.customer_history`)
  └── Tracked on market_segment with valid_from (__START_AT) and valid_to (__END_AT)
  │
  ▼ [Point-in-Time Join: o_orderdate BETWEEN valid_from AND coalesce(valid_to, ...)]
Gold Star Schema (`meridian_t02.gold.*`)
  ├── dim_customer_scd2 (with row filter on customer geography)
  ├── dim_supplier, dim_part, dim_nation, dim_region
  ├── fct_orders (header grain: 1 row per order_key)
  └── fct_order_lines (line grain: 1 row per order_key + line_number)
  │
  ▼ [YAML 1.1 Specification, one_to_many joins]
Semantic Metric View (`meridian_t02.gold.mv_trading`)
  └── 7 Business Measures aggregating header and line grains independently
```

---

## 3. Data Profile & Ingestion Plan

- **Locked Business Window (ADR-001):** Calendar year 1995 (`1995-01-01` to `1996-01-01`), sampled with `o_orderkey % 500 = 0` (~700 orders, ~3,000 lines per batch).
- **Synthetic Flaw Injections:**
  - `orders`: Null customer keys and negative order prices.
  - `lineitem`: Non-positive quantities, discount > 1, and exact duplicates.
  - `delayed headers`: 5 orders from Batch 3 whose lineitems arrive early in Batch 2 (held in `ops.pending_order_lines` until headers arrive in Batch 3).
- **Manifest Baseline:** Each batch generates an immutable manifest under `_manifest/batch=N` with pre-computed valid counts and expected financial sums.

---

## 4. Silver Quality Contract & Quarantine

- **Deduplication:** Deterministic "newest file wins" rule (`row_number() OVER (PARTITION BY key ORDER BY _source_file DESC, _row_hash DESC)`). Discarded duplicates are logged in `ops.duplicate_dispositions`.
- **Validation:** Enforced via `EXPECT ... ON VIOLATION DROP ROW` in `src/pipeline/silver.sql`.
- **Quarantine:** All dropped invalid rows are captured in `ops.quarantine_invalid` using non-short-circuiting predicates (`if(NOT coalesce(<cond>, false), 'REASON', NULL)`).
- **Early Lineitems:** Lines arriving before order headers are captured in `ops.pending_order_lines` with disposition reasons (`NO_HEADER`, `NO_CUSTOMER_VERSION`).

---

## 5. Slowly Changing Dimensions (SCD Type 2)

- Customer changes stream through `silver.customer_changes` and are processed into `silver.customer_history` using Databricks Lakeflow `AUTO CDC INTO ... STORED AS SCD TYPE 2` sequenced by `effective_date`.
- `dim_customer_scd2` exposes `valid_from` (`__START_AT`), `valid_to` (`__END_AT`), and `is_current`.
- Point-in-time joins bind orders strictly to the customer segment active when the order was placed:
  ```sql
  o.order_date >= h.valid_from AND (h.valid_to IS NULL OR o.order_date < h.valid_to)
  ```

---

## 6. Business KPI Definitions (Metric View)

Defined in `sql/metric_views/trading_metrics.sql` using YAML 1.1 `one_to_many` fact join over `fct_orders` and `fct_order_lines`:

| Measure | Formula | Grain |
|---|---|---|
| `net_revenue` | `SUM(lines.net_revenue)` | Line |
| `order_count` | `COUNT(source.order_key_hash)` | Header |
| `average_order_value` | `try_divide(MEASURE(net_revenue), MEASURE(order_count))` | Ratio |
| `delivery_days` | `try_divide(SUM(lines.transit_days), COUNT(lines.line_number))` | Line |
| `late_delivery_rate` | `try_divide(SUM(lines.is_late), COUNT(lines.line_number))` | Line |
| `return_rate` | `try_divide(SUM(lines.is_returned), COUNT(lines.line_number))` | Line |
| `discount_given` | `SUM(lines.discount_amount)` | Line |

---

## 7. Security & Governance Model

- **Governed Tags:** `sensitivity_level` (public, internal, confidential, restricted), `pii_type` (contact, financial, government_id, none), `medallion_layer` (landing, bronze, silver, gold).
- **ABAC Column Masks:**
  - `mask_contact_pii`: Masks `customer_phone` to `XXX-XXX-####` for users not in `t02_pii_readers`.
  - `mask_financial_pii`: Masks `customer_account_balance` and `supplier_account_balance` to `NULL` for users not in `t02_pii_readers`.
- **Row Filters:**
  - `region_nation_filter`: Declared on Gold tables with `WITH ROW FILTER`. Users in `t02_admins` (verified via `is_account_group_member`) see all 5 regions; non-admin users only see regions and nations explicitly granted in `gov.entitlements`.

---

## 8. Architecture Decision Records (ADRs)

- **ADR-001 (Date Window):** Locked window `1995-01-01` to `1996-01-01` ensuring complete return and fulfillment status cycles.
- **ADR-002 (Deterministic Hash):** Natural order key hashed as `lower(sha2(cast(o_orderkey as string), 256))` for facts linkage.
- **ADR-003 (Unified Metric View):** All 7 KPIs exposed in one YAML 1.1 metric view using `one_to_many` join to avoid line fan-out double counting.
- **ADR-004 (Standard CDC):** SCD2 implemented with standard Lakeflow streaming `AUTO CDC INTO` sequenced by `effective_date`.
- **ADR-005 (Native SQL Governance):** Governed tags and catalog-scoped ABAC policies deployed via native SQL DDL.
- **ADR-006 (Bundle Scopes):** Declarative Automation Bundle owns only compute resources (1 pipeline + 1 job); data catalogs and volumes persist independently.

---

## 9. Deliverables & Acceptance Status

| Phase | Milestone | Status | Linked Evidence |
|---|---|---|---|
| **0** | Profile & Design | COMPLETE | `evidence/runs/` |
| **1** | Landing Simulator & Bronze | COMPLETE | `evidence/p1_catalog.png`, `evidence/p1_groups.png` |
| **2** | Silver, Quarantine & SCD2 | COMPLETE | Verified via gate & unit tests |
| **3** | Gold Star & Metric View | COMPLETE | `sql/metric_views/trading_metrics.sql` |
| **4** | Governance (Tags, Masks, Filters) | COMPLETE | `sql/governance/apply_policies.sql` |
| **5** | DAB Bundle & Quality Gate | COMPLETE | `resources/job.yml`, `resources/pipeline.yml` |
| **6** | Business KPI Dashboard | COMPLETE | `evidence/p6_dashboard.png` |
| **7** | Operations Dashboard | PENDING UI EVIDENCE | `sql/analysis/ops_widgets.sql` |
| **8** | Genie Agent Space | PENDING UI EVIDENCE | `docs/genie.md` |
| **9** | Power BI DirectQuery | PENDING UI EVIDENCE | `docs/power_bi.md` |
| **10** | Production Target Deployment | BUNDLE VALIDATED | `databricks.yml` |

---

## 10. Official Documentation References

- [Databricks Lakeflow Pipelines](https://docs.databricks.com/aws/en/delta-live-tables/)
- [Databricks Metric Views](https://docs.databricks.com/aws/en/uc-semantics/metric-views/)
- [Unity Catalog Governed Tags](https://docs.databricks.com/aws/en/admin/governed-tags/)
- [Row Filters and Column Masks](https://docs.databricks.com/aws/en/data-governance/unity-catalog/filters-and-masks/)
- [Databricks Asset Bundles (DABs)](https://docs.databricks.com/aws/en/dev-tools/bundles/)
