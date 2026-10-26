USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA bronze;

-- Policy lookup needs an explicit catalog; pipeline analysis ignores USE for UDF lookup.
-- Consumer tables are governed; refreshes use private/Silver inputs.
CREATE TEMPORARY VIEW nations_base AS
SELECT CAST(n_nationkey AS BIGINT) AS nation_key, CAST(n_name AS STRING) AS nation_name,
  CAST(n_regionkey AS BIGINT) AS region_key
FROM bronze.nations_raw
QUALIFY row_number() OVER (PARTITION BY n_nationkey ORDER BY _batch_id DESC, _source_file DESC) = 1;

CREATE TEMPORARY VIEW regions_base AS
SELECT CAST(r_regionkey AS BIGINT) AS region_key, CAST(r_name AS STRING) AS region_name
FROM bronze.regions_raw
QUALIFY row_number() OVER (PARTITION BY r_regionkey ORDER BY _batch_id DESC, _source_file DESC) = 1;

CREATE TEMPORARY VIEW parts_base AS
SELECT CAST(p_partkey AS BIGINT) AS part_key, CAST(p_name AS STRING) AS part_name,
  CAST(p_type AS STRING) AS part_type FROM bronze.parts_raw
QUALIFY row_number() OVER (PARTITION BY p_partkey ORDER BY _batch_id DESC, _source_file DESC) = 1;

CREATE TEMPORARY VIEW suppliers_base AS
SELECT CAST(s_suppkey AS BIGINT) AS supplier_key, CAST(s_name AS STRING) AS supplier_name,
  CAST(s_nationkey AS BIGINT) AS supplier_nation_key, n.region_key AS supplier_region_key,
  CAST(s_acctbal AS DECIMAL(18,2)) AS supplier_account_balance
FROM bronze.suppliers_raw s JOIN nations_base n ON s.s_nationkey = n.nation_key
QUALIFY row_number() OVER (PARTITION BY s_suppkey ORDER BY _batch_id DESC, _source_file DESC) = 1;

CREATE TEMPORARY VIEW customer_versions AS
SELECT h.customer_key, h.customer_name, h.market_segment, h.customer_phone,
  h.customer_account_balance, h.customer_nation_key, n.region_key AS customer_region_key,
  n.nation_name, r.region_name, h.__START_AT AS valid_from, h.__END_AT AS valid_to,
  h.__END_AT IS NULL AS is_current,
  concat(CAST(h.customer_key AS STRING), ':', CAST(h.__START_AT AS STRING)) AS customer_version_key
FROM silver.customer_versions h
LEFT JOIN nations_base n ON h.customer_nation_key = n.nation_key
LEFT JOIN regions_base r ON n.region_key = r.region_key;

CREATE TEMPORARY VIEW orders_enriched AS
SELECT o.*, c.customer_version_key, c.market_segment AS market_segment_at_order_time,
  c.customer_nation_key, c.customer_region_key, c.nation_name, c.region_name
FROM silver.order_headers o LEFT JOIN customer_versions c
  ON o.customer_key = c.customer_key AND o.order_date >= c.valid_from
 AND (c.valid_to IS NULL OR o.order_date < c.valid_to);

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_regions
COMMENT 'Grain: one region_key; global non-sensitive geography vocabulary.'
AS SELECT * FROM regions_base;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_nations
COMMENT 'Grain: one nation_key, conformed to customer and supplier geography.'
WITH ROW FILTER ${meridian.catalog}.gov.region_nation_filter ON (region_key, nation_key)
AS SELECT * FROM nations_base;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_parts
COMMENT 'Grain: one part_key; referenced product vocabulary.'
AS SELECT * FROM parts_base;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_suppliers (
  supplier_key BIGINT COMMENT 'Natural supplier key referenced by order items.',
  supplier_name STRING, supplier_nation_key BIGINT, supplier_region_key BIGINT,
  supplier_account_balance DECIMAL(18,2)
)
COMMENT 'Grain: one supplier_key; supplier geography drives its entitlements.'
WITH ROW FILTER ${meridian.catalog}.gov.region_nation_filter ON (supplier_region_key, supplier_nation_key)
AS SELECT * FROM suppliers_base;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_customer_history (
  customer_key BIGINT COMMENT 'Natural customer key; repeats across historical versions.',
  customer_name STRING, market_segment STRING,
  customer_phone STRING,
  customer_account_balance DECIMAL(18,2),
  customer_nation_key BIGINT, customer_region_key BIGINT, nation_name STRING, region_name STRING,
  valid_from DATE, valid_to DATE, is_current BOOLEAN,
  customer_version_key STRING COMMENT 'Customer key and valid_from; one history version.',
  CONSTRAINT geography_required EXPECT (customer_region_key IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Grain: one customer version; valid_from inclusive and valid_to exclusive.'
WITH ROW FILTER ${meridian.catalog}.gov.region_nation_filter ON (customer_region_key, customer_nation_key)
AS SELECT * FROM customer_versions;

CREATE OR REFRESH MATERIALIZED VIEW gold.fct_order_headers (
  order_key BIGINT COMMENT 'Natural order identifier; one row per header.',
  order_key_hash STRING COMMENT 'SHA-256 shared header/item join key, not access control.',
  customer_key BIGINT, order_date DATE, order_total_price DECIMAL(18,2), order_status STRING,
  _source_file STRING, _batch_id INT, customer_version_key STRING,
  market_segment_at_order_time STRING, customer_nation_key BIGINT, customer_region_key BIGINT,
  nation_name STRING, region_name STRING,
  CONSTRAINT customer_version_required EXPECT (customer_version_key IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT geography_required EXPECT (customer_region_key IS NOT NULL AND customer_nation_key IS NOT NULL)
    ON VIOLATION FAIL UPDATE
)
COMMENT 'Grain: one validated order header, attributed to the customer version at order_date.'
WITH ROW FILTER ${meridian.catalog}.gov.region_nation_filter ON (customer_region_key, customer_nation_key)
AS SELECT * EXCEPT (keys_valid, date_valid, values_valid) FROM orders_enriched;

CREATE OR REFRESH MATERIALIZED VIEW gold.fct_order_items (
  CONSTRAINT part_required EXPECT (part_exists) ON VIOLATION FAIL UPDATE,
  CONSTRAINT supplier_required EXPECT (supplier_exists) ON VIOLATION FAIL UPDATE,
  CONSTRAINT customer_required EXPECT (customer_version_key IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Grain: one order_key and line_number linked to a valid received header.'
WITH ROW FILTER ${meridian.catalog}.gov.region_nation_filter ON (customer_region_key, customer_nation_key)
AS SELECT l.order_key, l.order_key_hash, l.line_number, l.part_key, l.supplier_key,
  l.quantity, l.extended_price, l.discount_rate, l.tax_rate, l.ship_date, l.commit_date, l.receipt_date,
  l.line_status, l.return_flag, l._source_file, l._batch_id,
  o.order_date, o.customer_key, o.customer_version_key, o.market_segment_at_order_time,
  o.customer_nation_key, o.customer_region_key, o.nation_name, o.region_name,
  l.extended_price * (1 - l.discount_rate) AS net_revenue,
  l.extended_price * l.discount_rate AS discount_amount,
  datediff(l.receipt_date, l.ship_date) AS transit_days,
  IF(l.receipt_date > l.commit_date, 1, 0) AS is_late, IF(l.return_flag = 'R', 1, 0) AS is_returned,
  p.part_key IS NOT NULL AS part_exists, s.supplier_key IS NOT NULL AS supplier_exists
FROM silver.order_items l JOIN orders_enriched o ON l.order_key = o.order_key
LEFT JOIN parts_base p ON l.part_key = p.part_key
LEFT JOIN suppliers_base s ON l.supplier_key = s.supplier_key;
