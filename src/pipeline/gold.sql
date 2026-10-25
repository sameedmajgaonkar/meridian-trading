-- Gold: star schema facts and dimensions with point-in-time SCD2 customer history.
-- Row filters enforce geographic entitlements declared via WITH ROW FILTER (see sql/governance/).

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.dim_region AS
SELECT CAST(r_regionkey AS BIGINT) AS region_key,
       CAST(r_name AS STRING) AS region_name
FROM ${catalog}.bronze.region
QUALIFY row_number() OVER (PARTITION BY r_regionkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.dim_nation AS
SELECT CAST(n_nationkey AS BIGINT) AS nation_key,
       CAST(n_name AS STRING) AS nation_name,
       CAST(n_regionkey AS BIGINT) AS region_key
FROM ${catalog}.bronze.nation
QUALIFY row_number() OVER (PARTITION BY n_nationkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.dim_part AS
SELECT CAST(p_partkey AS BIGINT) AS part_key,
       CAST(p_name AS STRING) AS part_name,
       CAST(p_type AS STRING) AS part_type
FROM ${catalog}.bronze.part
QUALIFY row_number() OVER (PARTITION BY p_partkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.dim_supplier
WITH ROW FILTER ${catalog}.gov.supplier_nation_filter ON (supplier_nation_key)
AS
SELECT CAST(s_suppkey AS BIGINT) AS supplier_key,
       CAST(s_name AS STRING) AS supplier_name,
       CAST(s_nationkey AS BIGINT) AS supplier_nation_key,
       CAST(s_acctbal AS DECIMAL(18, 2)) AS supplier_account_balance
FROM ${catalog}.bronze.supplier
QUALIFY row_number() OVER (PARTITION BY s_suppkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.dim_customer_scd2
WITH ROW FILTER ${catalog}.gov.region_nation_filter ON (customer_region_key, customer_nation_key)
AS
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
FROM ${catalog}.silver.customer_history h
LEFT JOIN ${catalog}.gold.dim_nation n
  ON h.customer_nation_key = n.nation_key;

-- Header grain: one row per order, joined point-in-time to customer history.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.fct_orders
WITH ROW FILTER ${catalog}.gov.region_nation_filter ON (customer_region_key, customer_nation_key)
AS
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
FROM ${catalog}.silver.orders o
JOIN ${catalog}.gold.dim_customer_scd2 h
  ON o.customer_key = h.customer_key
 AND o.order_date >= h.valid_from
 AND (h.valid_to IS NULL OR o.order_date < h.valid_to)
JOIN ${catalog}.gold.dim_nation n ON h.customer_nation_key = n.nation_key
JOIN ${catalog}.gold.dim_region r ON n.region_key = r.region_key;

-- Line grain: one row per order and line number.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.gold.fct_order_lines
WITH ROW FILTER ${catalog}.gov.region_nation_filter ON (customer_region_key, customer_nation_key)
AS
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
  (l.extended_price * (1 - l.discount_rate)) AS net_revenue,
  (l.extended_price * l.discount_rate) AS discount_amount,
  datediff(l.receipt_date, l.ship_date) AS transit_days,
  CASE WHEN l.receipt_date > l.commit_date THEN 1 ELSE 0 END AS is_late,
  IF(l.return_flag = 'R', 1, 0) AS is_returned
FROM ${catalog}.silver.order_lines l
JOIN ${catalog}.gold.fct_orders o ON l.order_key_hash = o.order_key_hash;
