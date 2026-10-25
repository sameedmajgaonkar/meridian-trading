-- Bind start_date and end_date as DATE parameters: [start, end).
-- Scope lines by their ORDER DATE through the header; retain next-year shipments.
-- These are logical scope limits, not a guarantee of physical file pruning.
-- Candidate source names must first be confirmed with 00_inspect_samples.sql.

-- probe: order_grain
SELECT
  count(*) AS order_rows,
  count(DISTINCT o_orderkey) AS distinct_order_keys,
  count_if(o_orderkey IS NULL) AS null_order_keys,
  count_if(o_custkey IS NULL) AS null_customer_keys,
  count_if(o_totalprice IS NULL OR o_totalprice < 0) AS invalid_order_prices,
  count(DISTINCT o_custkey) AS distinct_customers,
  min(o_orderdate) AS first_order_date,
  max(o_orderdate) AS last_order_date,
  count(DISTINCT sha2(cast(o_orderkey AS STRING), 256)) AS distinct_order_hashes
FROM samples.tpch.orders
WHERE o_orderdate >= :start_date AND o_orderdate < :end_date;

-- probe: line_grain_and_kpis
WITH order_keys AS (
  SELECT DISTINCT o_orderkey FROM samples.tpch.orders
  WHERE o_orderdate >= :start_date AND o_orderdate < :end_date
), scoped_lines AS (
  SELECT l.* FROM samples.tpch.lineitem l
  LEFT SEMI JOIN order_keys o ON l.l_orderkey = o.o_orderkey
)
SELECT
  count(*) AS line_rows,
  count(DISTINCT l_orderkey, l_linenumber) AS distinct_line_keys,
  count_if(l_linenumber IS NULL OR l_linenumber <= 0) AS invalid_line_numbers,
  count_if(l_partkey IS NULL) AS null_part_keys,
  count_if(l_suppkey IS NULL) AS null_supplier_keys,
  count_if(l_quantity IS NULL OR l_quantity <= 0) AS invalid_quantities,
  count_if(l_extendedprice IS NULL OR l_extendedprice < 0) AS invalid_prices,
  count_if(l_discount IS NULL OR l_discount < 0 OR l_discount > 1) AS invalid_discounts,
  count_if(l_tax IS NULL OR l_tax < 0 OR l_tax > 1) AS invalid_taxes,
  count_if(l_shipdate IS NULL OR l_commitdate IS NULL OR l_receiptdate IS NULL) AS missing_dates,
  count_if(l_receiptdate < l_shipdate) AS negative_transit_days,
  min(l_shipdate) AS first_ship_date,
  max(l_receiptdate) AS last_receipt_date,
  sum(l_extendedprice * (1 - l_discount)) AS net_revenue_ex_tax,
  sum(l_extendedprice * l_discount) AS discount_given,
  sum(datediff(l_receiptdate, l_shipdate)) AS transit_days_sum,
  count_if(l_receiptdate IS NOT NULL AND l_shipdate IS NOT NULL) AS transit_eligible_lines,
  count_if(l_receiptdate > l_commitdate) AS late_lines,
  count_if(l_receiptdate IS NOT NULL AND l_commitdate IS NOT NULL) AS late_eligible_lines,
  count_if(l_returnflag = 'R') AS returned_lines,
  count_if(l_returnflag IN ('R', 'A', 'N')) AS return_eligible_lines
FROM scoped_lines;

-- probe: source_orphans_by_ship_date
-- A separate diagnostic cohort: orphan lines cannot be selected by header date.
-- This tests ONLY lines shipped inside the chosen window. Null ship dates and
-- other years remain untested; do not claim a global zero-orphan result.
SELECT count(*) AS orphan_lines_in_ship_window,
       count_if(l.l_orderkey IS NULL) AS null_order_keys_in_ship_window
FROM samples.tpch.lineitem l
LEFT ANTI JOIN samples.tpch.orders o ON l.l_orderkey = o.o_orderkey
WHERE l.l_shipdate >= :start_date AND l.l_shipdate < :end_date;

-- probe: order_customer_orphans
SELECT count(*) AS orders_without_customer
FROM samples.tpch.orders o
LEFT ANTI JOIN samples.tpch.customer c ON o.o_custkey = c.c_custkey
WHERE o.o_orderdate >= :start_date AND o.o_orderdate < :end_date;

-- probe: dimension_keys
-- Modest dimension aggregates; no customer/supplier contact values are returned.
SELECT 'customer' AS entity, count(*) AS rows, count(DISTINCT c_custkey) AS distinct_keys,
       count_if(c_custkey IS NULL) AS null_keys FROM samples.tpch.customer
UNION ALL
SELECT 'nation', count(*), count(DISTINCT n_nationkey), count_if(n_nationkey IS NULL) FROM samples.tpch.nation
UNION ALL
SELECT 'region', count(*), count(DISTINCT r_regionkey), count_if(r_regionkey IS NULL) FROM samples.tpch.region
UNION ALL
SELECT 'part', count(*), count(DISTINCT p_partkey), count_if(p_partkey IS NULL) FROM samples.tpch.part
UNION ALL
SELECT 'supplier', count(*), count(DISTINCT s_suppkey), count_if(s_suppkey IS NULL) FROM samples.tpch.supplier;

-- probe: dimension_foreign_keys
WITH order_keys AS (
  SELECT DISTINCT o_orderkey FROM samples.tpch.orders
  WHERE o_orderdate >= :start_date AND o_orderdate < :end_date
), scoped_lines AS (
  SELECT l.* FROM samples.tpch.lineitem l
  LEFT SEMI JOIN order_keys o ON l.l_orderkey = o.o_orderkey
)
SELECT 'line_part' AS relationship, count(*) AS missing_parents
FROM scoped_lines l LEFT ANTI JOIN samples.tpch.part p ON l.l_partkey = p.p_partkey
UNION ALL
SELECT 'line_supplier', count(*) FROM scoped_lines l
LEFT ANTI JOIN samples.tpch.supplier s ON l.l_suppkey = s.s_suppkey
UNION ALL
SELECT 'customer_nation', count(*) FROM samples.tpch.customer c
LEFT ANTI JOIN samples.tpch.nation n ON c.c_nationkey = n.n_nationkey
UNION ALL
SELECT 'supplier_nation', count(*) FROM samples.tpch.supplier s
LEFT ANTI JOIN samples.tpch.nation n ON s.s_nationkey = n.n_nationkey
UNION ALL
SELECT 'nation_region', count(*) FROM samples.tpch.nation n
LEFT ANTI JOIN samples.tpch.region r ON n.n_regionkey = r.r_regionkey;

-- probe: code_values
WITH scoped_orders AS (
  SELECT o_orderkey, o_custkey, o_orderstatus FROM samples.tpch.orders
  WHERE o_orderdate >= :start_date AND o_orderdate < :end_date
), scoped_lines AS (
  SELECT l.* FROM samples.tpch.lineitem l
  LEFT SEMI JOIN scoped_orders o ON l.l_orderkey = o.o_orderkey
), scoped_customers AS (
  SELECT c.* FROM samples.tpch.customer c
  LEFT SEMI JOIN scoped_orders o ON c.c_custkey = o.o_custkey
)
SELECT 'market_segment' AS field, c_mktsegment AS code, count(*) AS rows
FROM scoped_customers GROUP BY c_mktsegment
UNION ALL
SELECT 'return_flag', l_returnflag, count(*) FROM scoped_lines GROUP BY l_returnflag
UNION ALL
SELECT 'line_status', l_linestatus, count(*) FROM scoped_lines GROUP BY l_linestatus
UNION ALL
SELECT 'order_status', o_orderstatus, count(*) FROM scoped_orders GROUP BY o_orderstatus;

-- probe: scd_demo_candidates
-- Candidate business keys only; these are not evidence of existing SCD history.
SELECT o_custkey AS customer_key, count(*) AS orders,
       count(DISTINCT month(o_orderdate)) AS active_months,
       min(o_orderdate) AS first_order, max(o_orderdate) AS last_order
FROM samples.tpch.orders
WHERE o_orderdate >= :start_date AND o_orderdate < :end_date
GROUP BY o_custkey
HAVING count(DISTINCT month(o_orderdate)) >= 3
ORDER BY active_months DESC, orders DESC, customer_key
LIMIT 10;
