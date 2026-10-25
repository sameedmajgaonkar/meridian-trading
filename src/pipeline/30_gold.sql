-- Phase 3 — Gold star schema: conformed dimensions plus two fact grains.
-- dim_customer_scd2 normalizes the AUTO CDC columns to the contract names and
-- resolves the customer's region so every governed table carries the same
-- (region, nation) pair for the row filter.
-- The point-in-time join selects exactly one history version per order by the
-- order's business date: joining is_current instead would rewrite historic
-- revenue into today's segment.

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.dim_region AS
SELECT CAST(r_regionkey AS BIGINT) AS region_key,
       CAST(r_name AS STRING) AS region_name
FROM ${catalog}.${schema_prefix}bronze.region
QUALIFY row_number() OVER (PARTITION BY r_regionkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.dim_nation AS
SELECT CAST(n_nationkey AS BIGINT) AS nation_key,
       CAST(n_name AS STRING) AS nation_name,
       CAST(n_regionkey AS BIGINT) AS region_key
FROM ${catalog}.${schema_prefix}bronze.nation
QUALIFY row_number() OVER (PARTITION BY n_nationkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.dim_part AS
SELECT CAST(p_partkey AS BIGINT) AS part_key,
       CAST(p_name AS STRING) AS part_name,
       CAST(p_type AS STRING) AS part_type
FROM ${catalog}.${schema_prefix}bronze.part
QUALIFY row_number() OVER (PARTITION BY p_partkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.dim_supplier AS
SELECT CAST(s_suppkey AS BIGINT) AS supplier_key,
       CAST(s_name AS STRING) AS supplier_name,
       CAST(s_nationkey AS BIGINT) AS supplier_nation_key,
       CAST(s_acctbal AS DECIMAL(18, 2)) AS supplier_account_balance
FROM ${catalog}.${schema_prefix}bronze.supplier
QUALIFY row_number() OVER (PARTITION BY s_suppkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

-- Runtime-verified 2026-10-26: WITH ROW FILTER declared on a pipeline MV
-- registers in information_schema but does NOT enforce on the read path (the
-- read scans the materialization computed under the pipeline owner), and
-- inline mask-UDF calls bake the owner's unmasked values into the
-- materialization. Enforcement therefore lives on the pipeline's
-- __materialization_* base tables — see sql/governance/32_apply.sql.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.dim_customer_scd2 AS
SELECT
  h.customer_key,
  h.customer_name,
  h.market_segment,
  h.customer_phone,
  h.customer_account_balance,
  h.customer_nation_key,
  n.region_key AS customer_region_key,
  h.__START_AT AS valid_from,
  h.__END_AT AS valid_to,
  h.__END_AT IS NULL AS is_current,
  concat(CAST(h.customer_key AS STRING), ':', CAST(h.__START_AT AS STRING)) AS customer_version_key
FROM ${catalog}.${schema_prefix}silver.customer_history h
LEFT JOIN ${catalog}.${schema_prefix}gold.dim_nation n
  ON h.customer_nation_key = n.nation_key;

-- Header grain: one row per order. Inner join drops headers without a valid
-- customer version; the quality gate counts any such header.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.fct_orders AS
SELECT
  o.order_key_hash,
  o.order_key,
  o.customer_key,
  o.order_date,
  o.order_total_price,
  o.order_status,
  h.customer_version_key,
  h.market_segment AS market_segment_at_order_time,
  h.customer_nation_key,
  h.customer_region_key,
  n.nation_name,
  r.region_name
FROM ${catalog}.${schema_prefix}silver.orders o
JOIN ${catalog}.${schema_prefix}gold.dim_customer_scd2 h
  ON o.customer_key = h.customer_key
 AND o.order_date >= h.valid_from
 AND (h.valid_to IS NULL OR o.order_date < h.valid_to)
JOIN ${catalog}.${schema_prefix}gold.dim_nation n ON h.customer_nation_key = n.nation_key
JOIN ${catalog}.${schema_prefix}gold.dim_region r ON n.region_key = r.region_key;

-- Line grain: one row per order and line number. Inherits the header's
-- customer version and geography so entitlement and point-in-time semantics
-- match the header fact exactly. KPI helper columns are computed here once.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}gold.fct_order_lines AS
SELECT
  l.order_key_hash,
  l.line_number,
  l.order_key,
  l.part_key,
  l.supplier_key,
  l.quantity,
  l.extended_price,
  l.discount_rate,
  l.tax_rate,
  l.ship_date,
  l.commit_date,
  l.receipt_date,
  l.line_status,
  l.return_flag,
  o.order_date,
  o.customer_key,
  o.customer_version_key,
  o.market_segment_at_order_time,
  o.customer_nation_key,
  o.customer_region_key,
  o.nation_name,
  o.region_name,
  CAST(l.extended_price * (1 - l.discount_rate) AS DECIMAL(18, 2)) AS net_revenue,
  CAST(l.extended_price * l.discount_rate AS DECIMAL(18, 2)) AS discount_amount,
  datediff(l.receipt_date, l.ship_date) AS transit_days,
  CASE WHEN l.receipt_date > l.commit_date THEN 1 ELSE 0 END AS is_late,
  IF(l.ship_date IS NOT NULL AND l.receipt_date IS NOT NULL, 1, 0) AS transit_eligible,
  IF(l.commit_date IS NOT NULL AND l.receipt_date IS NOT NULL, 1, 0) AS late_eligible,
  IF(l.return_flag IN ('N', 'A', 'R'), 1, 0) AS return_eligible,
  IF(l.return_flag = 'R', 1, 0) AS is_returned
FROM ${catalog}.${schema_prefix}silver.order_lines l
JOIN ${catalog}.${schema_prefix}gold.fct_orders o ON l.order_key_hash = o.order_key_hash;
