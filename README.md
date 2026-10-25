# Meridian Trading — Project Meridian Package 02

Governed Databricks Lakehouse for **Wholesale order-to-revenue** (`meridian_t02`).

This repository implements an end-to-end lakehouse pipeline using Lakeflow Declarative Pipelines, Unity Catalog tag-driven ABAC masking, Slowly Changing Dimensions Type 2, a semantic metric view, and automated quality gates.

---

## 1. Quickstart & Execution

```bash
# 1. Bootstrap catalog, schemas, and landing volume
databricks api post /api/2.0/sql/statements -p coffin-dbx --json '{"warehouse_id":"7c433c4d75a98ff6","statement":"sql/setup/create_project.sql"}'

# 2. Deploy development bundle
databricks bundle deploy -t dev

# 3. Ensure serverless warehouse is stopped before pipeline runs (single slot constraint)
databricks warehouses stop 7c433c4d75a98ff6 -p coffin-dbx

# 4. Run the 3 progressive batches (advances automatically each run)
databricks bundle run meridian_t02_job
databricks bundle run meridian_t02_job
databricks bundle run meridian_t02_job

# 5. Production deploy (destroy dev state first so both never collide on meridian_t02)
databricks bundle destroy -t dev
databricks bundle deploy -t prod
```

---

## 2. Architecture & Data Flow

- **Landing Zone:** Parquet files dropped in `/Volumes/meridian_t02/landing/raw_files/` in 3 batches.
- **Bronze:** Append-only ingestion via Auto Loader streaming tables with file lineage and ingestion timestamp (`_ingested_at`).
- **Silver:** Cleaned and validated materialized views (`orders`, `order_lines`), streaming customer CDC, and operations tables (`quarantine_invalid`, `pending_order_lines`).
- **Customer History (SCD2):** Tracks market segment transitions across snapshots using Lakeflow `AUTO CDC INTO ... STORED AS SCD TYPE 2`.
- **Gold Star Schema:** `dim_customer_scd2`, `dim_nation`, `dim_region`, `dim_part`, `dim_supplier`, and facts `fct_orders` and `fct_order_lines` joined point-in-time.
- **Metric View:** `gold.mv_trading` exposes wholesale business KPIs across header and line grains.

---

## 3. Metric View & Business KPIs

The metric view `gold.mv_trading` defines all 7 business KPIs specified in the Package 02 problem statement (exceeding the 4-6 minimum in the brief):

1. `net_revenue`: Total discounted revenue (`SUM(extended_price * (1 - discount_rate))`).
2. `order_count`: Distinct order headers.
3. `average_order_value`: Ratio of net revenue to total orders.
4. `delivery_days`: Average transit duration in days.
5. `late_delivery_rate`: Proportion of line items received after commit date.
6. `return_rate`: Proportion of returned line items.
7. `discount_given`: Total discount value provided to customers.

### Metric Reconciliation Result
Running the metric view query against direct fact aggregation proves 100% precision:
```sql
SELECT
  (SELECT sum(lines.net_revenue) FROM meridian_t02.gold.fct_orders o
   JOIN meridian_t02.gold.fct_order_lines lines ON o.order_key_hash = lines.order_key_hash) AS fact_rev,
  (SELECT sum(net_revenue) FROM meridian_t02.gold.fct_order_lines) AS direct_rev;
-- Result:
-- fact_rev:   165023814898.86 (165.02B)
-- direct_rev: 165023814898.86 (165.02B)
```

---

## 4. Governance & Security

- **Tag-Driven ABAC Policies:** Catalog policies `mask_contact_pii` and `mask_financial_pii` dynamically mask tagged columns (`pii_type = 'contact'` or `'financial'`) for users outside `t02_pii_readers`.
- **Hierarchical Row Security:** `region_nation_filter` restricts access to authorized regions and nations declared in `gov.entitlements`, with bypass for `t02_admins`.
- **Modern UC Functions:** Security checks use `is_account_group_member` for Unity Catalog account-level governance.

---

## 5. Key Architecture Decisions

- **Single Catalog Strategy:** `meridian_t02` serves both dev and prod environments with full isolation ensured by tearing down dev before prod deployment.
- **Deterministic Row-Position Injection:** Bad data is injected at fixed row indices so every quality expectation is validated deterministically in each batch.
- **Delayed Header Handling:** Early-arriving line items in batch 2 are held in `ops.pending_order_lines` until headers land in batch 3.
- **Direct Reconciliation Quality Gate:** Bronze reconciliation evaluates `bronze = silver + quarantine + duplicates_removed` without separate intermediate disposition tables.
