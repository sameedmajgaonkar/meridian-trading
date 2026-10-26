# Module 07: Trainer Demo & Interview Defense Guide

This module provides a **minute-by-minute evaluation walkthrough script** and comprehensive answers to technical questions the trainer may ask during your evaluation.

---

## 1. 15-Minute Evaluation Walkthrough Script

### Minute 0 to 2: The Elevator Pitch
> *"Good morning. Today I am presenting **Project Meridian (Package 02: Wholesale Order-to-Revenue)**. Our goal was to build a production-grade, governed lakehouse on Databricks Free Edition. The core business scenario processes wholesale orders and fulfillment line items for calendar year 1995 across 5 global market segments. The solution is fully declarative, automated via Databricks Asset Bundles (DABs), secured via Unity Catalog tag-driven ABAC masking and hierarchical row security, and verified with automated quality gates."*

---

### Minute 2 to 5: Pipeline & Medallion Architecture
- **Action**: Open the Databricks Lakeflow Pipeline UI (`meridian_t02_pipeline`).
- **Explanation**:
  - Show the DAG: Landing $\to$ Bronze $\to$ Silver $\to$ Gold.
  - Explain Auto Loader: *"Bronze ingests raw Parquet drops incrementally from our landing volume using `STREAM(read_files(...))`. We attach metadata lineage columns including `_source_file`, `_batch_id`, and `_ingested_at`."*
  - Explain Silver Data Quality: *"In Silver, we use declarative expectations with `EXPECT ... ON VIOLATION DROP ROW`. Dropped invalid rows are quarantined into `ops.quarantine_invalid` with clear failure reasons, and clean rows are deduplicated with `row_number() OVER (PARTITION BY key ORDER BY _source_file DESC)`."*

---

### Minute 5 to 8: The Three Advanced Challenges
- **Action**: Open `sql/metric_views/trading_metrics.sql` and the pipeline graph showing `customer_history` and `pending_order_lines`.
- **Explanation**:
  1. **Advanced Challenge 1 (Metric View Grain)**:
     - *"Notice how `fct_orders` (header grain) and `fct_order_lines` (line grain) are joined inside our YAML 1.1 metric view with `cardinality: one_to_many`. This allows `order_count` to aggregate headers and `net_revenue` to aggregate lines without multi-line fan-out double-counting. We verified this with a direct SQL reconciliation where both equal exactly **$165.02B**."*
  2. **Advanced Challenge 2 (Delayed Headers)**:
     - *"In distributed commerce, fulfillment lines often arrive before ERP headers. In Batch 2, 5 lines landed without headers. Our pipeline held them safely in `ops.pending_order_lines`. When Batch 3 landed, the headers arrived, and Lakeflow automatically linked the lines into `gold.fct_order_lines`, bringing pending lines to 0."*
  3. **Advanced Challenge 3 (Customer SCD Type 2)**:
     - *"Customer market segments change over time. Using Lakeflow `AUTO CDC INTO ... STORED AS SCD TYPE 2`, we track segment transitions. Two customers reached 3 versions across our 3 batches. In `gold.fct_orders`, we perform a point-in-time join `o.order_date >= valid_from AND (valid_to IS NULL OR o.order_date < valid_to)` so orders are attributed to the segment at order placement time."*

---

### Minute 8 to 11: Unity Catalog Governance & Live ABAC Demo
- **Action**: Open SQL Editor. Run `sql/governance/audit.sql`.
- **Explanation**:
  - *"We implemented tag-driven Attribute-Based Access Control (ABAC), which is enterprise best practice. Instead of table-by-table masking, we define policies `mask_contact_pii` and `mask_financial_pii` on the catalog matching tags `pii_type = 'contact'` and `'financial'`."*
  - *"For row security, we implemented `region_nation_filter` using modern `is_account_group_member`. An admin in `t02_admins` sees all 5 global regions. A user with an America region grant in `gov.entitlements` sees all American nations. A user with no entitlement sees zero rows."*
  - Show the 3 queries in `sql/governance/audit.sql`: column tags, active ABAC policies, and sensitive column coverage.

---

### Minute 11 to 13: Quality Gate & Job Runs
- **Action**: Open the Databricks Workflows / Jobs UI (`meridian_t02_job`).
- **Explanation**:
  - Show the 6-task workflow: `gov_setup` $\to$ `simulate_batch` $\to$ `pipeline_update` $\to$ `gov_apply` $\to$ `metric_view` $\to$ `quality_gate`.
  - *"Our quality gate evaluates 13 deterministic SQL invariant checks that must return 0: non-empty Gold, uniqueness in Silver/Gold, zero orphan fact rows, single open customer version, 0 pending lines at final batch, and Bronze reconciliation: $\text{Bronze} = \text{Silver} + \text{Quarantine} + \text{Duplicates}$."*
  - Show the deliberate failure and repair in job run history.
  - Show `sql/analysis/failed_run_alert.sql` querying `system.lakeflow.job_run_timeline`.

---

### Minute 13 to 15: AI/BI Dashboards & Q&A
- **Action**: Open the Lakeview Dashboard (`Meridian Trading — Wholesale Executive KPIs (1995)`).
- **Explanation**:
  - Show the 7 KPIs matching the metric view.
  - Show the monthly net revenue by market segment trend chart.
  - Show the regional discount breakdown and customer rankings.

---

## 2. Tough Questions & Winning Answers

### Q1: *"Why did you declare `WITH ROW FILTER` inside the `CREATE MATERIALIZED VIEW` statement instead of using `ALTER TABLE ... SET ROW FILTER`?"*
**Winning Answer**:
> *"On Databricks Unity Catalog, Materialized Views and Streaming Tables created via Lakeflow/DLT do not support late-binding `ALTER TABLE SET ROW FILTER` or `SET MASK`. The engine compiles view definitions statically at pipeline creation time. Therefore, row filters must be declared inline via `CREATE OR REFRESH MATERIALIZED VIEW ... WITH ROW FILTER ... ON (...)`. For column masking, we avoided table alterations entirely by deploying centralized catalog-level ABAC policies that match column tags dynamically."*

---

### Q2: *"How does your metric view prevent order header double-counting when joining to line items?"*
**Winning Answer**:
> *"In Databricks Metric Views (YAML 1.1), the `joins` block declares explicit `cardinality: one_to_many` between the root source `gold.fct_orders` and the joined table `gold.fct_order_lines`. When a query requests `order_count`, the query engine aggregates `COUNT(source.order_key_hash)` over `fct_orders` before applying the join, completely eliminating fan-out multiplication. When requesting `net_revenue`, it aggregates `SUM(lines.net_revenue)` over `fct_order_lines`. We verified this mathematically: metric view revenue matches direct line revenue to the exact cent ($165,023,814,898.86)."*

---

### Q3: *"Why did you use `is_account_group_member` instead of `is_member` in your governance functions?"*
**Winning Answer**:
> *"Databricks recommends `is_account_group_member` for all modern Unity Catalog governance. `is_account_group_member` verifies membership against account-level groups defined in the Databricks Account Console and synced from enterprise identity providers like Azure AD/Okta. `is_member` is a legacy function primarily intended for workspace-local groups. Account-level checks ensure our governance policies remain portable across dev, test, and prod workspaces."*

---

### Q4: *"How does your pipeline handle delayed headers if a shipment arrives before the order header?"*
**Winning Answer**:
> *"In our landing simulator, 5 order lines arrive in Batch 2 while their order headers arrive in Batch 3. In Silver, the lines are validated and stored in `silver.order_lines`. However, because `gold.fct_order_lines` joins directly to `gold.fct_orders`, those lines are not prematurely published to Gold. Instead, they are captured in `ops.pending_order_lines`. When Batch 3 runs and the headers land in Gold, the materialized view automatically promotes the pending lines into `gold.fct_order_lines`, and `ops.pending_order_lines` drops to 0. Our quality gate asserts `no_pending_lines_at_final_batch = 0`."*

---

### Q5: *"How did you manage the compute constraints of Databricks Free Edition?"*
**Winning Answer**:
> *"Databricks Free Edition allows only one active Serverless compute resource at a time. If an analyst leaves a Serverless Starter Warehouse running while a Serverless Lakeflow pipeline or Python task executes, Databricks terminates the job with `RESOURCE_EXHAUSTED`. We automated strict lifecycle management: our run instructions and bundle tasks ensure the warehouse is stopped prior to triggering bundle runs, and each pipeline run completes within 2 minutes."*

---

### Q6: *"Why did you use a single catalog `meridian_t02` for both dev and prod instead of separate catalogs?"*
**Winning Answer**:
> *"Using a single catalog keeps our SQL files completely standard, literal, and clean without messy `IDENTIFIER(:catalog || ...)` parameter interpolation. Environment isolation is guaranteed via Databricks Asset Bundles: development workloads run in dev mode, and before deploying to production, we execute `databricks bundle destroy -t dev` to clean up development compute state before deploying the production target."*
