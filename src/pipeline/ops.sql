-- Ops: tracking for quarantined invalid rows, duplicate discards, and pending early lines.
-- Recomputed per update so invalid rows and discarded duplicates reconcile with Bronze.

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.ops.quarantine_invalid AS
WITH orders_eval AS (
  SELECT
    CAST(o_orderkey AS BIGINT) AS order_key,
    CAST(o_custkey AS BIGINT) AS customer_key,
    filter(array(
      if(NOT coalesce(o_orderkey IS NOT NULL, false), 'ORDER_KEY_REQUIRED', NULL),
      if(NOT coalesce(o_custkey IS NOT NULL, false), 'CUSTOMER_KEY_REQUIRED', NULL),
      if(NOT coalesce(o_orderdate >= DATE '${order_start_date}' AND o_orderdate < DATE '${order_end_date}', false),
         'ORDER_DATE_OUT_OF_WINDOW', NULL),
      if(NOT coalesce(o_totalprice >= 0, false), 'ORDER_TOTAL_PRICE_NEGATIVE', NULL),
      if(NOT coalesce(o_orderstatus IN ('O', 'F', 'P'), false), 'ORDER_STATUS_INVALID', NULL)
    ), x -> x IS NOT NULL) AS failure_reasons,
    row_number() OVER (PARTITION BY o_orderkey ORDER BY _source_file DESC, _row_hash DESC) AS rn,
    _source_file, _batch_id
  FROM ${catalog}.bronze.orders
),
lines_eval AS (
  SELECT
    CAST(l_orderkey AS BIGINT) AS order_key,
    CAST(l_linenumber AS INT) AS line_number,
    filter(array(
      if(NOT coalesce(l_orderkey IS NOT NULL, false), 'LINE_ORDER_KEY_REQUIRED', NULL),
      if(NOT coalesce(l_linenumber IS NOT NULL AND l_linenumber > 0, false), 'LINE_NUMBER_INVALID', NULL),
      if(NOT coalesce(l_quantity > 0, false), 'QUANTITY_NONPOSITIVE', NULL),
      if(NOT coalesce(l_extendedprice >= 0, false), 'EXTENDED_PRICE_NEGATIVE', NULL),
      if(NOT coalesce(l_discount BETWEEN 0 AND 1, false), 'DISCOUNT_OUT_OF_RANGE', NULL),
      if(NOT coalesce(l_tax BETWEEN 0 AND 1, false), 'TAX_OUT_OF_RANGE', NULL),
      if(NOT coalesce(l_linestatus IN ('O', 'F') AND l_returnflag IN ('N', 'A', 'R'), false), 'CODES_INVALID', NULL),
      if(NOT coalesce(l_shipdate IS NOT NULL AND l_commitdate IS NOT NULL AND l_receiptdate IS NOT NULL, false), 'DATES_REQUIRED', NULL),
      if(NOT coalesce(l_receiptdate >= l_shipdate, false), 'RECEIPT_BEFORE_SHIP', NULL)
    ), x -> x IS NOT NULL) AS failure_reasons,
    row_number() OVER (PARTITION BY l_orderkey, l_linenumber ORDER BY _source_file DESC, _row_hash DESC) AS rn,
    _source_file, _batch_id
  FROM ${catalog}.bronze.lineitem
),
customers_eval AS (
  SELECT
    CAST(c_custkey AS BIGINT) AS customer_key,
    filter(array(
      if(NOT coalesce(c_custkey IS NOT NULL, false), 'CUSTOMER_KEY_REQUIRED', NULL),
      if(NOT coalesce(c_mktsegment IN ('AUTOMOBILE', 'BUILDING', 'FURNITURE', 'HOUSEHOLD', 'MACHINERY'), false),
         'MARKET_SEGMENT_INVALID', NULL),
      if(NOT coalesce(effective_date IS NOT NULL, false), 'EFFECTIVE_DATE_REQUIRED', NULL)
    ), x -> x IS NOT NULL) AS failure_reasons,
    _source_file, _batch_id
  FROM ${catalog}.bronze.customer
)
SELECT 'orders' AS entity, order_key, CAST(NULL AS INT) AS line_number, customer_key, failure_reasons, _source_file, _batch_id
FROM orders_eval WHERE rn = 1 AND size(failure_reasons) > 0
UNION ALL
SELECT 'lineitem' AS entity, order_key, line_number, CAST(NULL AS BIGINT) AS customer_key, failure_reasons, _source_file, _batch_id
FROM lines_eval WHERE rn = 1 AND size(failure_reasons) > 0
UNION ALL
SELECT 'customer' AS entity, CAST(NULL AS BIGINT) AS order_key, CAST(NULL AS INT) AS line_number, customer_key, failure_reasons, _source_file, _batch_id
FROM customers_eval WHERE size(failure_reasons) > 0;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.ops.duplicate_dispositions AS
WITH orders_ranked AS (
  SELECT CAST(o_orderkey AS BIGINT) AS order_key,
         row_number() OVER (PARTITION BY o_orderkey ORDER BY _source_file DESC, _row_hash DESC) AS rn,
         max(_row_hash) OVER (PARTITION BY o_orderkey) <> min(_row_hash) OVER (PARTITION BY o_orderkey) AS is_conflict,
         _row_hash, _source_file, _batch_id
  FROM ${catalog}.bronze.orders
),
lines_ranked AS (
  SELECT CAST(l_orderkey AS BIGINT) AS order_key,
         CAST(l_linenumber AS INT) AS line_number,
         row_number() OVER (PARTITION BY l_orderkey, l_linenumber ORDER BY _source_file DESC, _row_hash DESC) AS rn,
         max(_row_hash) OVER (PARTITION BY l_orderkey, l_linenumber) <> min(_row_hash) OVER (PARTITION BY l_orderkey, l_linenumber) AS is_conflict,
         _row_hash, _source_file, _batch_id
  FROM ${catalog}.bronze.lineitem
)
SELECT 'orders' AS entity, order_key, CAST(NULL AS INT) AS line_number,
  _row_hash, is_conflict, _source_file, _batch_id
FROM orders_ranked WHERE rn > 1
UNION ALL
SELECT 'lineitem' AS entity, order_key, line_number,
  _row_hash, is_conflict, _source_file, _batch_id
FROM lines_ranked WHERE rn > 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.ops.pending_order_lines AS
SELECT
  l.order_key_hash,
  l.line_number,
  l.order_key,
  concat_ws(',',
    if(NOT EXISTS (SELECT 1 FROM ${catalog}.silver.orders h
                   WHERE h.order_key_hash = l.order_key_hash), 'NO_HEADER', NULL),
    if(EXISTS (SELECT 1 FROM ${catalog}.silver.orders h
               WHERE h.order_key_hash = l.order_key_hash)
       AND NOT EXISTS (SELECT 1 FROM ${catalog}.gold.fct_orders f
                       WHERE f.order_key_hash = l.order_key_hash), 'NO_CUSTOMER_VERSION', NULL)
  ) AS reasons,
  l._source_file,
  l._batch_id
FROM ${catalog}.silver.order_lines l
WHERE NOT EXISTS (
  SELECT 1 FROM ${catalog}.gold.fct_order_lines f
  WHERE f.order_key_hash = l.order_key_hash AND f.line_number = l.line_number)
  AND NOT EXISTS (
  SELECT 1 FROM ${catalog}.ops.quarantine_invalid q
  WHERE q.entity = 'orders' AND q.order_key = l.order_key);
