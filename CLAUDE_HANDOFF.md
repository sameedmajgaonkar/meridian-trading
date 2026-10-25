# PROJECT MERIDIAN (PACKAGE 02) — COMPREHENSIVE CLAUDE HANDOFF & CONTEXT DOSSIER

> **Purpose:** Feed this entire document directly to Claude (or any AI assistant) to provide complete, uninterrupted context on the architecture, technical decisions, live workspace state, and exact progress across all 10 phases of **Project Meridian: Wholesale Order-to-Revenue Lakehouse (`meridian_t02`)**.

---

## 1. Executive Summary & Project Mandate

- **Project Name:** Meridian Trading (Package 02: Wholesale Order-to-Revenue).
- **Trainee / Namespace:** `NN=02`, Catalog: `meridian_t02`.
- **Platform:** Databricks Free Edition (`dbc-746bc1e1-c295.cloud.databricks.com`, org `7474654791620994`).
- **Core Assignment:** End-to-end governed lakehouse implementing:
  1. Multi-batch streaming ingestion with deterministic data-quality injection and quarantine handling.
  2. Point-in-time dimensional enrichment with Type 2 Slowly Changing Dimensions (`dim_customer_scd2`).
  3. Star-schema facts (`fct_orders`, `fct_order_lines`) linked by deterministic key hashing (`order_key_hash`).
  4. Unified semantic Metric View (`gold.mv_trading`) using YAML 1.1 syntax resolving two distinct fact grains without double-counting.
  5. Enterprise Unity Catalog governance: **Governed Tags**, **Centralized ABAC Policies**, declarative row filters, and column masks.
  6. Declarative Automation Bundles (DABs) orchestrating Lakeflow streaming pipelines and 42-rule automated quality gates.
  7. AI/BI Dashboards (Business KPIs & System Tables Operations Telemetry), Genie conversational data space, and Power BI DirectQuery integration.

---

## 2. Live Databricks Workspace & Infrastructure Context

| Resource | Identity / Value | Operational Status / Notes |
|---|---|---|
| **Host** | `https://dbc-746bc1e1-c295.cloud.databricks.com` | Org ID: `7474654791620994` |
| **CLI Profile** | `coffin-dbx` | Configured with Databricks CLI v1.20.0 |
| **Active User** | `igcoffin17@gmail.com` | User ID: `77130264245433` |
| **User Entitlements** | Member of `admins`, `users`, `t02_admins` | Intentionally removed from `t02_pii_readers` to verify active masking |
| **SQL Warehouse** | `7c433c4d75a98ff6` | "Serverless Starter Warehouse", 2X-Small PRO |
| **Dev Job ID** | `747628238433531` | `meridian_t02_job` (3 tasks: simulator → pipeline → quality gate) |
| **Dev Pipeline ID** | `1e1ebb1c-9d20-41a6-88c0-9c6991986e9e` | `meridian_t02_pipeline` (Continuous/Serverless Lakeflow Pipeline) |
| **Prod Job ID** | `118635285146392` | `meridian_t02_job` (Target `prod`, validated and deployed) |
| **Prod Pipeline ID** | `ed73a303-8088-40fb-928c-b4ae8935c2c2` | `meridian_t02_pipeline` (Target `prod`) |
| **Business Dashboard** | `01f1d0c30bc61590aad90b67ae5df1a5` | "Meridian Trading — Wholesale Executive KPIs (1995)" (Published) |
| **Operations Dashboard** | `01f1d0c3172f1f619a0fb3eb410c857e` | "Meridian Trading — Operations Telemetry" (2 Pages, Published) |
| **Genie Space** | Active in workspace | Gold schema semantic context + security rules configured |
| **Catalog** | `meridian_t02` | Schemas: `landing`, `bronze`, `silver`, `gold`, `gov`, `ops` |
| **Volume Path** | `/Volumes/meridian_t02/landing/raw_files/` | Batches `batch_1`, `batch_2`, `batch_3` landed |

---

## 3. Critical Free Edition Platform Rules & Environment Traps

1. **The Single Serverless Slot Rule:**
   - Databricks Free Edition provides **exactly ONE shared serverless compute slot** across the SQL Warehouse, Lakeflow Pipelines, and Serverless Job tasks.
   - If the SQL Warehouse is in state `RUNNING`, running a pipeline update or serverless job task will immediately fail with `RESOURCE_EXHAUSTED` or `CLUSTER_CREATION_RESOURCE_EXHAUSTED`.
   - **Remedy:** Always stop the warehouse before launching jobs or pipeline updates:
     ```bash
     export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
     databricks api post /api/2.0/sql/warehouses/7c433c4d75a98ff6/stop --profile coffin-dbx --json '{}'
     ```
2. **Local Keyring Requirement:**
   - In the local shell, Databricks CLI reads OAuth credentials through D-Bus. Every shell session requires:
     ```bash
     export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
     ```
3. **Serverless Task Logging in Unity Catalog:**
   - Serverless Python tasks on Databricks Free Edition do not return stdout/stderr via the `jobs get-output` API.
   - All quality gate outcomes, execution breadcrumbs, and error tracebacks are persisted into `meridian_t02.ops.quality_gate`.
4. **Governed Tags & ABAC Availability on Free Edition:**
   - Disproved the misconception that Free Edition lacks Governed Tags or ABAC.
   - `CREATE GOVERNED TAG ... VALUES (...)` and `CREATE POLICY ... ON CATALOG` are fully supported via SQL DDL on Databricks Serverless DBSQL / DBR 18.1+.

---

## 4. Architecture & Medallion Pipeline Design

```
Raw Files (Parquet Batches 1, 2, 3 in UC Volume)
  │
  ▼ [Streaming Auto Loader]
Bronze Layer (`meridian_t02.bronze.*`)
  ├── orders_raw, lineitem_raw, customer_snapshot_raw, etc.
  │
  ▼ [Quality Rules, Quarantine Predicates, Deduplication]
Silver Layer (`meridian_t02.silver.*`)
  ├── orders (deduplicated by order_key)
  ├── order_lines (validated line items)
  ├── customer_history (clean snapshot trail)
  └── [Ops Quarantines in `ops.*`: quarantined_orders, quarantined_lines, pending_order_lines]
  │
  ▼ [AUTO CDC FROM SNAPSHOT & SCD Type 2]
Gold Dimensions (`meridian_t02.gold.*`)
  ├── dim_customer_scd2 (with __START_AT, __END_AT, is_current)
  ├── dim_supplier, dim_part, dim_nation, dim_region, dim_date
  │
  ▼ [Point-in-Time Join: o_orderdate BETWEEN __START_AT AND coalesce(__END_AT, ...)]
Gold Facts (`meridian_t02.gold.*`)
  ├── fct_orders (grain: 1 row per order_key; 1,136,293 rows)
  └── fct_order_lines (grain: 1 row per order_key + line_number; 4,543,157 rows)
        Linked by: order_key_hash = lower(sha2(cast(order_key as string), 256))
  │
  ▼ [YAML 1.1 Specification, one_to_many joins]
Semantic Metric View (`meridian_t02.gold.mv_trading`)
  ├── Facts: fct_orders (primary) + fct_order_lines (one_to_many)
  └── 7 Business Measures (Net Revenue: $165.02B, Orders: 1.14M, AOV, Delivery Days, etc.)
```

### Locked Business Window & Reconciled Numbers (1995 Full Year)
- **Time Window:** Orders placed between `1995-01-01` and `1996-01-01` (ADR-001).
- **Total Valid Orders:** `1,136,293`
- **Total Valid Line Items:** `4,543,157`
- **Total Reconciled Net Revenue:** `$165,023,814,898.86`
- **Total Reconciled Discount Given:** `$8,685,385,024.16`
- **Pending Early Order Lines:** `0` (100% resolved after Batch 3 delayed header arrival).
- **SCD2 Customer Snapshots:** Customers `210556` and `738508` have 3 distinct historical versions; all other transitioned customers have 2.

---

## 5. Phase-by-Phase Implementation & Verification Record

### Phase 0: Discovery, Profiling & Architectural Decisions
- Source catalog: `samples.tpch` (read-only baseline).
- Architecture decision records committed:
  - `ADR-001`: 1995 calendar year lock (complete returns/status cycle).
  - `ADR-002`: SHA-256 deterministic natural key hashing.
  - `ADR-003`: Unified 7-measure metric view with independent grain aggregation.
  - `ADR-004`: `AUTO CDC FROM SNAPSHOT` on version-tagged customer snapshots.
  - `ADR-005`: Native SQL DDL for Governed Tags and Catalog ABAC Policies.
  - `ADR-006`: Bundle scopes limited to 2 resources (pipeline + job).

### Phase 1: Landing Simulator & Bronze Layer
- Script: `src/landing/simulate.py` with deterministic mutation engine `src/landing/injection.py`.
- Generates 3 disjoint 4-month batches into `/Volumes/meridian_t02/landing/raw_files/batch_N/`.
- Injected anomalies: negative prices, future dates, invalid status codes, orphan lines, duplicate records.
- Streaming ingestion via Databricks Auto Loader into `meridian_t02.bronze.*`.

### Phase 2: Silver Layer, SCD2 & Quarantine
- Materialized views in `src/pipeline/10_silver.sql` and `20_customer_scd2.sql`.
- Quarantines captured in `meridian_t02.ops`:
  - `quarantined_orders`, `quarantined_order_lines`, `quarantined_customer_snapshots`.
  - Intentionally early line items routed to `ops.pending_order_lines` with disposition tracking.
- `dim_customer_scd2` built via `AUTO CDC FROM SNAPSHOT` tracking changes in `market_segment`, `address`, and `account_balance`.

### Phase 3: Gold Star Schema & Semantic Metric View
- Star schema materialized views in `src/pipeline/30_gold.sql`:
  - `fct_orders`, `fct_order_lines`, `dim_customer_scd2`, `dim_supplier`, `dim_part`, `dim_nation`, `dim_region`, `dim_date`.
- Metric View created via SQL DDL in `sql/metric_views/20_mv_trading.sql`:
  - YAML 1.1 spec with `one_to_many` join between `fct_orders` and `fct_order_lines`.
  - 7 measures: `net_revenue`, `order_count`, `average_order_value`, `delivery_days`, `late_delivery_rate`, `return_rate`, `discount_given`.
  - Fully reconciled to the penny ($165,023,814,898.86).

### Phase 4: Governance, Governed Tags & ABAC
- **Governed Tags Created Live:**
  - `sensitivity_level`: `('public', 'internal', 'confidential', 'restricted')`
  - `pii_type`: `('contact', 'financial', 'government_id', 'none')`
  - `medallion_layer`: `('landing', 'bronze', 'silver', 'gold')`
- **Central ABAC Policies Active:**
  - `mask_contact_pii`: Column mask applied to any column tagged `pii_type = 'contact'`. Mask: `XXX-XXX-` + last 4 digits.
  - `mask_financial_pii`: Column mask applied to any column tagged `pii_type = 'financial'`. Mask: `NULL`.
- **Row Filters & Table Masks:**
  - Row filter UDF `meridian_t02.gov.region_nation_filter` restricts non-admin users to their authorized sales regions.
  - Table-level masks applied to underlying Delta materialization tables.
- **Entitlement Separation Verification:**
  - User `igcoffin17@gmail.com` in `t02_admins` sees all 5 regions.
  - User removed from `t02_pii_readers`: Top 5 buyer queries output masked phone numbers (`XXX-XXX-4043`) and `NULL` account balances.

### Phase 5: Declarative Automation Bundle & Quality Gate
- `databricks.yml` configured for `dev` and `prod`.
- Automated Python Quality Gate `src/quality_gate/quality_gate.py`:
  - Evaluates 42 reconciliation, schema, foreign-key, and SCD2 rules.
  - Writes audit trail to `ops.quality_gate`.
  - Latest Run Result: **42/42 checks PASS**.

### Phase 6: Parameterized SQL Queries & Business KPI Dashboard
- 3 Parameterized SQL Queries created via API:
  - Date Filter: `4a631ba7-0b98-4da9-b55e-e30b4ece41fa`
  - Text Filter: `a435cdf0-4740-4a50-b610-cbe9eb07b5ed`
  - Number Filter: `7497ba52-a317-4400-845e-07a09e6847cf`
- **Dashboard 1 ("Meridian Trading — Wholesale Executive KPIs (1995)")**:
  - Dashboard ID: `01f1d0c30bc61590aad90b67ae5df1a5`
  - Connected directly to `meridian_t02.gold.mv_trading`.
  - Widgets: Markdown KPI definitions, 4 Metric Counters (Net Revenue, Total Orders, AOV, Return Rate), Region dropdown filter, Monthly Net Revenue by Segment line chart, Revenue by Region bar chart, Total Discount Given bar chart, Top Customers by Segment table.
  - Evidence: `evidence/p6_dashboard.png`.

### Phase 7: Operations Telemetry Dashboard (`system.*` Tables)
- **Dashboard 2 ("Meridian Trading — Operations Telemetry")**:
  - Dashboard ID: `01f1d0c3172f1f619a0fb3eb410c857e`
  - Page 1: *Run Health & Quality* (`system.lakeflow.pipeline_update_timeline`, `system.lakeflow.job_run_timeline`, `meridian_t02.ops.quality_gate`).
  - Page 2: *Cost, Usage & Audit* (`system.billing.usage`, `system.access.audit`, `system.query.history`).
  - Published and operational in workspace.

### Phase 8: Genie Agent Space
- Configured over `meridian_t02.gold`.
- Trusted assets and curated domain examples added (`docs/genie_examples.md`).
- **Privacy Policy Verification:** When prompted for top buyer phone numbers and account balances, Genie politely rejected the request citing corporate privacy policies and offered non-sensitive aggregations instead.

---

## 6. What Remains to Reach 100% Capstone Completion

### Phase 9: Power BI Desktop DirectQuery Integration
- **Objective:** Connect external Power BI Desktop to Databricks SQL Warehouse.
- **Connection Parameters:**
  - **Connector:** Azure Databricks
  - **Server Hostname:** `dbc-746bc1e1-c295.cloud.databricks.com`
  - **HTTP Path:** `/sql/1.0/warehouses/7c433c4d75a98ff6`
  - **Catalog/Schema:** `meridian_t02.gold`
  - **Data Connectivity Mode:** `DirectQuery`
  - **Target Table:** `meridian_t02.gold.mv_trading` (or Gold fact tables)
- **Required Visuals:**
  1. Monthly Net Revenue Line Chart (`order_month` vs `MEASURE(net_revenue)`).
  2. Average Order Value by Segment Bar Chart (`market_segment_at_order_time` vs `MEASURE(average_order_value)`).
  3. Executive Risk Card: Return Rate (`MEASURE(return_rate)`) & Late Delivery Rate (`MEASURE(late_delivery_rate)`).
- **Environment Note:** If working on Linux without Power BI Desktop, documentation in `docs/power_bi.md` serves as the verified specification.

### Phase 10: Production Job Run & Final 20-Minute Demo
1. **Trigger Production Job:**
   - Prod Job ID: `118635285146392`.
   - Ensure SQL Warehouse `7c433c4d75a98ff6` is in state `STOPPED`.
   - Run: `databricks jobs run-now 118635285146392 --profile coffin-dbx`.
2. **Collect Run Evidence:** Record run ID, status, and task timing in `evidence/runs/`.
3. **Rehearse 20-Minute Live Demonstration:**
   - Step 1: Show DAB bundle and Job DAG in Databricks UI.
   - Step 2: Show Bronze Auto Loader → Silver SCD2 → Gold Star Schema.
   - Step 3: Demonstrate SCD2 point-in-time accuracy for customer `210556`.
   - Step 4: Open Business KPI Dashboard and cross-filter by Region/Segment.
   - Step 5: Open Operations Telemetry Dashboard and inspect `ops.quality_gate` & `system.billing.usage`.
   - Step 6: Query Genie with natural language business questions.
   - Step 7: Demonstrate ABAC masking by querying `dim_customer_scd2` as non-PII reader vs PII reader.

---

## 7. Key Files & Repository Map

```
/home/sameed/meridian-trading/
├── databricks.yml                      # Declarative bundle config (dev & prod targets)
├── resources/
│   ├── pipeline.yml                    # Serverless Lakeflow pipeline resource
│   └── job.yml                         # 3-task serverless orchestration job
├── src/
│   ├── landing/simulate.py             # Multi-batch simulator with manifest writer
│   ├── landing/injection.py            # Deterministic data-quality flaw injection
│   ├── pipeline/00_bronze.sql          # Auto Loader streaming ingestion
│   ├── pipeline/10_silver.sql          # Clean Silver tables + quarantine routing
│   ├── pipeline/20_customer_scd2.sql   # AUTO CDC FROM SNAPSHOT SCD2 model
│   ├── pipeline/30_gold.sql            # Star schema facts & dimensions
│   ├── pipeline/40_ops.sql             # Quarantines & pending lines tracking
│   └── quality_gate/quality_gate.py    # Automated 42-rule verification engine
├── sql/
│   ├── governance/30_tags.sql          # Governed tag definitions & attachments
│   ├── governance/31_udfs.sql          # Masking and row filter UDFs
│   ├── governance/32_apply.sql         # Table masks, row filters & ABAC policies
│   ├── metric_views/20_mv_trading.sql  # YAML 1.1 single-metric-view specification
│   └── analysis/50_kpi_queries.sql     # Parameterized business queries
├── docs/
│   ├── architecture.md                 # Medallion design and data contract
│   ├── capability_matrix.md            # Live platform feature support matrix
│   ├── genie_examples.md               # Genie agent domain benchmarks & test cases
│   └── runbook.md                      # Complete end-to-end operational checklist
├── evidence/
│   ├── p6_dashboard.png                # Screenshot of published Business KPI Dashboard
│   └── runs/                           # Automated run logs and audit markdown files
└── CLAUDE_HANDOFF.md                   # THIS FILE (Comprehensive context document)
```
