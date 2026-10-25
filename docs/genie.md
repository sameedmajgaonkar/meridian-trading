# Genie Space — Meridian Trading

This document provides setup instructions, curated SQL examples, and benchmark test suites for the Databricks Genie Space over `meridian_t02.gold`.

---

## 1. Space Setup
- **Title:** `Meridian Wholesale Revenue`
- **Catalog & Schema:** `meridian_t02.gold`
- **Included Tables:**
  - `meridian_t02.gold.mv_trading` (Metric View — primary KPI source)
  - `meridian_t02.gold.fct_orders` (Order header grain)
  - `meridian_t02.gold.fct_order_lines` (Order line grain)
  - `meridian_t02.gold.dim_customer_scd2` (SCD2 customer dimension)
  - `meridian_t02.gold.dim_supplier`
  - `meridian_t02.gold.dim_region`
  - `meridian_t02.gold.dim_nation`

---

## 2. Space Instructions

Paste into **Space Settings -> Instructions**:

```text
You are the AI data assistant for Meridian Trading (Wholesale order-to-revenue).
You help business analysts explore wholesale trading data for the calendar year 1995 (1995-01-01 to 1995-12-31).

Data Model Rules:
1. Primary KPI Source: For high-level aggregations and KPIs, always query meridian_t02.gold.mv_trading using the MEASURE(...) function syntax:
   - MEASURE(net_revenue): Total net revenue in USD after discount.
   - MEASURE(order_count): Distinct count of order headers.
   - MEASURE(average_order_value): Net revenue divided by order count.
   - MEASURE(delivery_days): Mean elapsed days between order date and ship date.
   - MEASURE(late_delivery_rate): Ratio of lineitems where commit_date < receipt_date.
   - MEASURE(return_rate): Ratio of lineitems returned ('R') vs completed ('R' + 'A').
   - MEASURE(discount_given): Total dollar value of discounts provided.

2. Grain & Join Semantics:
   - Header grain: fct_orders is 1 row per order.
   - Line grain: fct_order_lines is 1 row per order and line number.
   - NEVER sum order_total_price across fct_order_lines (causes multi-line fan-out).
   - Use market_segment_at_order_time (point-in-time) for segment analytics, NOT current segment.

3. Ratios & Rates:
   - All rates (return_rate, late_delivery_rate) must be computed as ratios of sums, never simple averages of individual rates.

4. Governance & Privacy:
   - Sensitive columns (customer_phone, customer_account_balance, supplier_account_balance) are protected by column masks and ABAC policies. If an unauthorized user requests them, explain that access is restricted under corporate privacy compliance.
   - If asked about out-of-scope subjects (e.g. employee payroll, marketing spend), politely state that only wholesale order, lineitem, and fulfillment data for 1995 is available.
```

---

## 3. Example Queries

Add these under **Settings -> Example SQL Queries**:

1. **Monthly KPI Trend by Segment:**
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

2. **Return Rate and Late Delivery Rate by Market Segment:**
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

3. **Regional Discount Breakdown:**
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

4. **Order Status Fulfillment Breakdown:**
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

5. **Top 10 Customers by Revenue with Order-Time Segment:**
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

---

## 4. Benchmark Suite

| # | Question | Verification SQL Query |
|---|---|---|
| 1 | What is net revenue by market segment? | `SELECT market_segment_at_order_time, MEASURE(net_revenue) FROM meridian_t02.gold.mv_trading GROUP BY 1 ORDER BY 2 DESC;` |
| 2 | How many orders were placed in December 1995? | `SELECT count(*) FROM meridian_t02.gold.fct_orders WHERE order_date >= DATE '1995-12-01' AND order_date < DATE '1996-01-01';` |
| 3 | Which region has the highest late-delivery rate? | `SELECT region_name, MEASURE(late_delivery_rate) FROM meridian_t02.gold.mv_trading GROUP BY region_name ORDER BY 2 DESC LIMIT 1;` |
| 4 | What is the return rate overall? | `SELECT MEASURE(return_rate) FROM meridian_t02.gold.mv_trading;` |
| 5 | Show the top 10 customers by revenue with their order-time segment | `SELECT customer_key, market_segment_at_order_time, sum(net_revenue) AS total_revenue FROM meridian_t02.gold.fct_order_lines GROUP BY 1, 2 ORDER BY total_revenue DESC LIMIT 10;` |
