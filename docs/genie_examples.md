# Genie Space Examples & Benchmarks — Meridian Trading (Phase 8)

This document provides copy-paste ready configurations, curated SQL examples, and benchmark test suites for the Databricks Genie Space over `meridian_t02.gold`.

---

## 1. Genie Space Overview & Setup

- **Space Name:** `Meridian Wholesale Trading`
- **Catalog & Schema:** `meridian_t02.gold`
- **Included Assets:**
  - `meridian_t02.gold.mv_trading` (Metric View — primary KPI source)
  - `meridian_t02.gold.fct_orders` (Order header grain)
  - `meridian_t02.gold.fct_order_lines` (Order line grain)
  - `meridian_t02.gold.dim_customer_scd2` (SCD2 customer dimension)
  - `meridian_t02.gold.dim_supplier` (Supplier dimension)
  - `meridian_t02.gold.dim_region` (Region dimension)
  - `meridian_t02.gold.dim_nation` (Nation dimension)

---

## 2. General Space Instructions

Paste this directly into the **Instructions** box under **Space Settings**:

```text
You are the AI data assistant for Meridian Trading (Wholesale order-to-revenue).
You help business analysts, sales managers, and executives explore wholesale trading data for the calendar year 1995 (1995-01-01 to 1995-12-31).

Data Model Rules:
1. Primary KPI Source: For high-level aggregations and KPIs, always query `meridian_t02.gold.mv_trading` using the `MEASURE(...)` function syntax:
   - `MEASURE(net_revenue)`: Total net revenue in USD after discount.
   - `MEASURE(order_count)`: Distinct count of order headers.
   - `MEASURE(average_order_value)`: Net revenue divided by order count.
   - `MEASURE(delivery_days)`: Mean elapsed days between order date and ship date.
   - `MEASURE(late_delivery_rate)`: Ratio of lineitems where commit_date < receipt_date.
   - `MEASURE(return_rate)`: Ratio of lineitems returned ('R') vs completed ('R' + 'A').
   - `MEASURE(discount_given)`: Total dollar value of discounts provided.

2. Grain & Join Semantics:
   - Header grain: `fct_orders` is 1 row per order.
   - Line grain: `fct_order_lines` is 1 row per order and line number.
   - NEVER sum `order_total_price` across `fct_order_lines` (causes multi-line fan-out).
   - Use `market_segment_at_order_time` (point-in-time) for segment analytics, NOT current segment.

3. Ratios & Rates:
   - All rates (return_rate, late_delivery_rate) must be computed as ratios of sums, never simple averages of individual rates.

4. Governance & Privacy:
   - Sensitive columns (customer_phone, customer_account_balance, supplier_account_balance) are protected by column masks and ABAC policies. If an unauthorized user requests them, explain that access is restricted under corporate privacy compliance.
   - If asked about out-of-scope subjects (e.g., employee payroll, marketing spend, website traffic), politely state that only wholesale order, lineitem, and fulfillment data for 1995 is available.
```

---

## 3. Curated Example SQL Queries

Add these under **Settings → Example SQL Queries** in Genie. These examples guide Genie's code generation for complex metrics and slicing patterns:

### Example 1: Monthly KPI Trend by Segment
* **User Question:** *"What was the monthly net revenue, order volume, and average order value in 1995 by customer segment?"*
* **SQL Query:**
  ```sql
  SELECT
    order_month,
    market_segment_at_order_time AS segment,
    MEASURE(net_revenue) AS net_revenue,
    MEASURE(order_count) AS order_count,
    MEASURE(average_order_value) AS avg_order_value
  FROM meridian_t02.gold.mv_trading
  GROUP BY order_month, market_segment_at_order_time
  ORDER BY order_month ASC, net_revenue DESC;
  ```
* **Why this example:** Teaches Genie to query `mv_trading` using `MEASURE(...)` and group by point-in-time segment.

---

### Example 2: Return Rate and Late Delivery Rate by Market Segment
* **User Question:** *"Which market segments experience the highest return rates and shipping delays?"*
* **SQL Query:**
  ```sql
  SELECT
    market_segment_at_order_time AS segment,
    MEASURE(order_count) AS orders,
    MEASURE(delivery_days) AS avg_delivery_days,
    MEASURE(late_delivery_rate) AS late_delivery_rate,
    MEASURE(return_rate) AS return_rate
  FROM meridian_t02.gold.mv_trading
  GROUP BY market_segment_at_order_time
  ORDER BY return_rate DESC;
  ```
* **Why this example:** Teaches Genie how to handle ratio metrics correctly across dimensions.

---

### Example 3: Regional Discount Breakdown
* **User Question:** *"How much discount was granted per region and nation, and what was the resulting net revenue?"*
* **SQL Query:**
  ```sql
  SELECT
    region_name,
    nation_name,
    MEASURE(net_revenue) AS net_revenue,
    MEASURE(discount_given) AS total_discount,
    MEASURE(order_count) AS orders
  FROM meridian_t02.gold.mv_trading
  GROUP BY region_name, nation_name
  ORDER BY net_revenue DESC;
  ```
* **Why this example:** Demonstrates multi-level geographic breakdown on the metric view.

---

### Example 4: Order Status Fulfillment Breakdown
* **User Question:** *"Compare revenue and fulfillment performance across order statuses (open, fulfilled, pending)."*
* **SQL Query:**
  ```sql
  SELECT
    order_status,
    MEASURE(net_revenue) AS net_revenue,
    MEASURE(order_count) AS order_count,
    MEASURE(late_delivery_rate) AS late_delivery_rate,
    MEASURE(return_rate) AS return_rate
  FROM meridian_t02.gold.mv_trading
  GROUP BY order_status
  ORDER BY net_revenue DESC;
  ```
* **Why this example:** Shows how `order_status` codes (`F`, `O`, `P`) map to business performance.

---

### Example 5: Top 10 Customers by Revenue with Order-Time Segment
* **User Question:** *"Who are the top 10 customers by revenue and what segment did they belong to when ordering?"*
* **SQL Query:**
  ```sql
  SELECT
    customer_key,
    market_segment_at_order_time,
    sum(net_revenue) AS total_revenue,
    count(DISTINCT order_key_hash) AS order_count
  FROM meridian_t02.gold.fct_order_lines
  GROUP BY customer_key, market_segment_at_order_time
  ORDER BY total_revenue DESC
  LIMIT 10;
  ```
* **Why this example:** Guides Genie to query `fct_order_lines` when customer-level granular aggregation is required.

---

## 4. Benchmark Test Suite (Rubric Step 4)

Add these to the **Benchmarks** tab. Each benchmark has a verified ground-truth SQL query and exact answer pre-calculated from the live dataset:

| # | Benchmark Question | Verification SQL Query | Expected Ground Truth Result |
|---|---|---|---|
| **1** | *What is net revenue by market segment?* | `SELECT market_segment_at_order_time, MEASURE(net_revenue) FROM meridian_t02.gold.mv_trading GROUP BY 1 ORDER BY 2 DESC;` | AUTOMOBILE: ~$33.15B<br>BUILDING: ~$33.06B<br>MACHINERY: ~$33.02B<br>HOUSEHOLD: ~$32.96B<br>FURNITURE: ~$32.83B |
| **2** | *How many orders were placed in December 1995?* | `SELECT count(*) FROM meridian_t02.gold.fct_orders WHERE order_date >= DATE '1995-12-01' AND order_date < DATE '1996-01-01';` | **96,280 orders** |
| **3** | *Which region has the highest late-delivery rate?* | `SELECT region_name, MEASURE(late_delivery_rate) FROM meridian_t02.gold.mv_trading GROUP BY region_name ORDER BY 2 DESC LIMIT 1;` | ASIA (~63.4%) or EUROPE (~63.3%) |
| **4** | *What is the return rate overall?* | `SELECT MEASURE(return_rate) FROM meridian_t02.gold.mv_trading;` | **0.1257 (12.57%)** |
| **5** | *Show the top 10 customers by revenue with their order-time segment.* | `SELECT customer_key, market_segment_at_order_time, sum(net_revenue) AS rev FROM meridian_t02.gold.fct_order_lines GROUP BY 1, 2 ORDER BY rev DESC LIMIT 10;` | 10 distinct customers with point-in-time segment and revenue. |

---

## 5. Live Demonstration Test Matrix (Rubric Step 5)

Run these 6 required test scenarios during the evaluation walkthrough and take screenshots:

1. **KPI Question:**
   - *Prompt:* `"What was our total net revenue and discount given for the whole year of 1995?"`
   - *Expected Answer:* Net revenue is **₹165,023,814,898.86** (~$165.02B); total discount given is **₹8,685,690,000** (~$8.69B).
2. **Follow-Up Question:**
   - *Prompt:* `"Break that down by quarter"` (or `"by month"`).
   - *Expected Behavior:* Genie retains context and outputs a table or chart grouped by quarter or month without re-prompting.
3. **Ambiguous Question:**
   - *Prompt:* `"Show me the best segment"`
   - *Expected Behavior:* Genie either asks for clarification (*"Do you mean by highest net revenue, largest order count, or lowest return rate?"*) or defaults to Net Revenue while clearly stating the chosen criterion.
4. **Out-of-Scope Question:**
   - *Prompt:* `"What were the warehouse utility expenses and employee payroll in Q3?"`
   - *Expected Behavior:* Genie politely declines, informing the user that expense and payroll data are not part of the wholesale sales and fulfillment model.
5. **Sensitive Data / PII Request:**
   - *Prompt:* `"Show me customer phone numbers and account balances for our top 5 buyers."`
   - *Expected Behavior:* If queried, Genie applies Unity Catalog column masks (masked as `XXX-XXX-####` and `NULL`) or states that PII is masked according to access governance policies.
6. **Restricted Access Test:**
   - *Prompt:* Run the same revenue query as an unprivileged or regional principal.
   - *Expected Behavior:* Row filters automatically limit the returned totals to only the permitted geographic regions without leaking restricted rows.
