USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA bronze;

-- Shared checked views make Silver and quarantine use identical rules.
CREATE TEMPORARY VIEW orders_checked AS
WITH typed AS (
  SELECT try_cast(o_orderkey AS BIGINT) AS order_key,
    sha2(CAST(o_orderkey AS STRING), 256) AS order_key_hash,
    try_cast(o_custkey AS BIGINT) AS customer_key,
    try_cast(o_orderdate AS DATE) AS order_date,
    try_cast(o_totalprice AS DECIMAL(18,2)) AS order_total_price,
    CAST(o_orderstatus AS STRING) AS order_status,
    to_json(struct(b.*)) AS raw_record, _source_file, _batch_id, _ingested_at
  FROM bronze.orders_raw b
)
SELECT *, order_key IS NOT NULL AND customer_key IS NOT NULL AS keys_valid,
  coalesce(order_date >= DATE '1995-01-01' AND order_date < DATE '1996-01-01', false) AS date_valid,
  coalesce(order_total_price >= 0 AND order_status IN ('O','F','P'), false) AS values_valid,
  CASE WHEN order_key IS NULL THEN 1 ELSE row_number() OVER (
    PARTITION BY order_key ORDER BY _batch_id DESC, _source_file DESC, _ingested_at DESC, raw_record DESC
  ) END AS candidate_rank
FROM typed;

CREATE OR REFRESH MATERIALIZED VIEW silver.order_headers (
  CONSTRAINT keys_valid EXPECT (keys_valid) ON VIOLATION DROP ROW,
  CONSTRAINT date_valid EXPECT (date_valid) ON VIOLATION DROP ROW,
  CONSTRAINT values_valid EXPECT (values_valid) ON VIOLATION DROP ROW
)
COMMENT 'Grain: one valid order header; highest landed batch wins.'
AS SELECT * EXCEPT (raw_record, _ingested_at, candidate_rank)
FROM orders_checked WHERE candidate_rank = 1;

CREATE TEMPORARY VIEW lines_checked AS
WITH typed AS (
  SELECT try_cast(l_orderkey AS BIGINT) AS order_key,
    sha2(CAST(l_orderkey AS STRING), 256) AS order_key_hash,
    try_cast(l_linenumber AS INT) AS line_number,
    try_cast(l_partkey AS BIGINT) AS part_key, try_cast(l_suppkey AS BIGINT) AS supplier_key,
    try_cast(l_quantity AS DECIMAL(18,2)) AS quantity,
    try_cast(l_extendedprice AS DECIMAL(18,2)) AS extended_price,
    try_cast(l_discount AS DECIMAL(9,6)) AS discount_rate,
    try_cast(l_tax AS DECIMAL(9,6)) AS tax_rate,
    try_cast(l_shipdate AS DATE) AS ship_date, try_cast(l_commitdate AS DATE) AS commit_date,
    try_cast(l_receiptdate AS DATE) AS receipt_date,
    CAST(l_linestatus AS STRING) AS line_status, CAST(l_returnflag AS STRING) AS return_flag,
    to_json(struct(b.*)) AS raw_record, _source_file, _batch_id, _ingested_at
  FROM bronze.order_items_raw b
)
SELECT *, order_key IS NOT NULL AND part_key IS NOT NULL AND supplier_key IS NOT NULL
    AND coalesce(line_number > 0, false) AS keys_valid,
  coalesce(quantity > 0 AND extended_price >= 0, false) AS amounts_valid,
  coalesce(discount_rate BETWEEN 0 AND 1 AND tax_rate BETWEEN 0 AND 1, false) AS rates_valid,
  coalesce(line_status IN ('O','F') AND return_flag IN ('N','A','R'), false) AS codes_valid,
  ship_date IS NOT NULL AND commit_date IS NOT NULL AND receipt_date IS NOT NULL
    AND coalesce(receipt_date >= ship_date, false) AS dates_valid,
  CASE WHEN order_key IS NULL OR line_number IS NULL THEN 1 ELSE row_number() OVER (
    PARTITION BY order_key, line_number
    ORDER BY _batch_id DESC, _source_file DESC, _ingested_at DESC, raw_record DESC
  ) END AS candidate_rank
FROM typed;

CREATE OR REFRESH MATERIALIZED VIEW silver.order_items (
  CONSTRAINT keys_valid EXPECT (keys_valid) ON VIOLATION DROP ROW,
  CONSTRAINT amounts_valid EXPECT (amounts_valid) ON VIOLATION DROP ROW,
  CONSTRAINT rates_valid EXPECT (rates_valid) ON VIOLATION DROP ROW,
  CONSTRAINT codes_valid EXPECT (codes_valid) ON VIOLATION DROP ROW,
  CONSTRAINT dates_valid EXPECT (dates_valid) ON VIOLATION DROP ROW
)
COMMENT 'Grain: one intrinsically valid order_key and line_number, including pending headers.'
AS SELECT * EXCEPT (raw_record, _ingested_at, candidate_rank)
FROM lines_checked WHERE candidate_rank = 1;

CREATE OR REFRESH STREAMING TABLE silver.customer_events (
  CONSTRAINT customer_key_required EXPECT (customer_key IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT segment_valid EXPECT (market_segment IN ('AUTOMOBILE','BUILDING','FURNITURE','HOUSEHOLD','MACHINERY'))
    ON VIOLATION FAIL UPDATE,
  CONSTRAINT effective_date_required EXPECT (effective_date IS NOT NULL AND customer_nation_key IS NOT NULL)
    ON VIOLATION FAIL UPDATE
)
COMMENT 'Grain: one customer change at an effective date; invalid CDC fails the update.'
AS SELECT CAST(c_custkey AS BIGINT) AS customer_key, CAST(c_name AS STRING) AS customer_name,
  CAST(c_mktsegment AS STRING) AS market_segment, CAST(c_phone AS STRING) AS customer_phone,
  CAST(c_acctbal AS DECIMAL(18,2)) AS customer_account_balance,
  CAST(c_nationkey AS BIGINT) AS customer_nation_key, CAST(effective_date AS DATE) AS effective_date,
  _source_file, _batch_id
FROM STREAM(bronze.customers_raw);
