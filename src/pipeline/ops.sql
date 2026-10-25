-- Phase 2 — dispositions and quarantines. Materialized views recomputed on
-- every refresh from Bronze, so invalid rows and discarded duplicates are
-- never lost and the quality gate's reconciliation always closes:
--   Bronze rows = invalid (quarantine) + duplicate-discarded + accepted.
-- Disposition precedence: a duplicate occurrence is dispositioned as a
-- duplicate even if its content is also invalid; validity is judged for
-- deduplicated winners only. A pending line moves out of ops.pending_order_lines
-- automatically once its header resolves (recompute-per-refresh) — its before/
-- after evidence is the batch-2 vs batch-3 pipeline snapshots (runbook).
-- Lines of quarantined headers never publish; they are dispositioned with the
-- header's quarantine entry and excluded from pending.

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.ops.quarantine_invalid AS
WITH orders_typed AS (
  SELECT
    CAST(o_orderkey AS BIGINT) AS order_key,
    CAST(o_custkey AS BIGINT) AS customer_key,
    CAST(o_orderdate AS DATE) AS order_date,
    CAST(o_totalprice AS DECIMAL(18, 2)) AS order_total_price,
    CAST(o_orderstatus AS STRING) AS order_status,
    row_number() OVER (PARTITION BY o_orderkey
                       ORDER BY _source_file DESC, _row_hash DESC) AS rn,
    _source_file, _batch_id
  FROM ${catalog}.bronze.orders
),
lines_typed AS (
  SELECT
    CAST(l_orderkey AS BIGINT) AS order_key,
    CAST(l_linenumber AS INT) AS line_number,
    CAST(l_quantity AS DECIMAL(18, 2)) AS quantity,
    CAST(l_extendedprice AS DECIMAL(18, 2)) AS extended_price,
    CAST(l_discount AS DECIMAL(9, 6)) AS discount_rate,
    CAST(l_tax AS DECIMAL(9, 6)) AS tax_rate,
    CAST(l_linestatus AS STRING) AS line_status,
    CAST(l_returnflag AS STRING) AS return_flag,
    CAST(l_shipdate AS DATE) AS ship_date,
    CAST(l_commitdate AS DATE) AS commit_date,
    CAST(l_receiptdate AS DATE) AS receipt_date,
    row_number() OVER (PARTITION BY l_orderkey, l_linenumber
                       ORDER BY _source_file DESC, _row_hash DESC) AS rn,
    _source_file, _batch_id
  FROM ${catalog}.bronze.lineitem
),
customers_typed AS (
  SELECT
    CAST(c_custkey AS BIGINT) AS customer_key,
    CAST(c_mktsegment AS STRING) AS market_segment,
    row_number() OVER (PARTITION BY c_custkey, snapshot_effective_date
                       ORDER BY _source_file DESC, _row_hash DESC) AS rn,
    _source_file, _batch_id
  FROM ${catalog}.bronze.customer
)
SELECT 'orders' AS entity, order_key, CAST(NULL AS INT) AS line_number, customer_key,
  filter(array(
    if(order_key IS NULL, 'ORDER_KEY_REQUIRED', NULL),
    if(customer_key IS NULL, 'CUSTOMER_KEY_REQUIRED', NULL),
    if(NOT (order_date >= DATE '${order_start_date}' AND order_date < DATE '${order_end_date}'),
       'ORDER_DATE_OUT_OF_WINDOW', NULL),
    if(NOT (order_total_price >= 0), 'ORDER_TOTAL_PRICE_NEGATIVE', NULL),
    if(NOT (order_status IN ('O', 'F', 'P')), 'ORDER_STATUS_INVALID', NULL)
  ), x -> x IS NOT NULL) AS failure_reasons,
  _source_file, _batch_id
FROM orders_typed
WHERE rn = 1 AND (
       order_key IS NULL OR customer_key IS NULL
    OR NOT (order_date >= DATE '${order_start_date}' AND order_date < DATE '${order_end_date}')
    OR NOT (order_total_price >= 0) OR NOT (order_status IN ('O', 'F', 'P')))
UNION ALL
SELECT 'lineitem', order_key, line_number, CAST(NULL AS BIGINT),
  filter(array(
    if(order_key IS NULL, 'LINE_KEY_REQUIRED', NULL),
    if(NOT (line_number > 0), 'LINE_NUMBER_NONPOSITIVE', NULL),
    if(NOT (quantity > 0), 'QUANTITY_NONPOSITIVE', NULL),
    if(NOT (extended_price >= 0), 'EXTENDED_PRICE_NEGATIVE', NULL),
    if(NOT (discount_rate BETWEEN 0 AND 1), 'DISCOUNT_OUT_OF_RANGE', NULL),
    if(NOT (tax_rate BETWEEN 0 AND 1), 'TAX_OUT_OF_RANGE', NULL),
    if(NOT (line_status IN ('O', 'F') AND return_flag IN ('N', 'A', 'R')), 'CODE_INVALID', NULL),
    if(ship_date IS NULL OR commit_date IS NULL OR receipt_date IS NULL, 'DATES_REQUIRED', NULL),
    if(NOT (receipt_date >= ship_date), 'RECEIPT_BEFORE_SHIP', NULL)
  ), x -> x IS NOT NULL) AS failure_reasons,
  _source_file, _batch_id
FROM lines_typed
WHERE rn = 1 AND (
       order_key IS NULL OR NOT (line_number > 0) OR NOT (quantity > 0)
    OR NOT (extended_price >= 0) OR NOT (discount_rate BETWEEN 0 AND 1)
    OR NOT (tax_rate BETWEEN 0 AND 1)
    OR NOT (line_status IN ('O', 'F') AND return_flag IN ('N', 'A', 'R'))
    OR ship_date IS NULL OR commit_date IS NULL OR receipt_date IS NULL
    OR NOT (receipt_date >= ship_date))
UNION ALL
SELECT 'customer', CAST(NULL AS BIGINT), CAST(NULL AS INT), customer_key,
  filter(array(
    if(customer_key IS NULL, 'CUSTOMER_KEY_REQUIRED', NULL),
    if(NOT (market_segment IN ('AUTOMOBILE', 'BUILDING', 'FURNITURE', 'HOUSEHOLD', 'MACHINERY')),
       'MARKET_SEGMENT_INVALID', NULL)
  ), x -> x IS NOT NULL) AS failure_reasons,
  _source_file, _batch_id
FROM customers_typed
WHERE rn = 1 AND (customer_key IS NULL
    OR NOT (market_segment IN ('AUTOMOBILE', 'BUILDING', 'FURNITURE', 'HOUSEHOLD', 'MACHINERY')));

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.ops.duplicate_dispositions AS
WITH orders_ranked AS (
  SELECT CAST(o_orderkey AS BIGINT) AS order_key,
         row_number() OVER (PARTITION BY o_orderkey
                            ORDER BY _source_file DESC, _row_hash DESC) AS rn,
         max(_row_hash) OVER (PARTITION BY o_orderkey)
           <> min(_row_hash) OVER (PARTITION BY o_orderkey) AS is_conflict,
         _row_hash, _source_file, _batch_id
  FROM ${catalog}.bronze.orders
),
lines_ranked AS (
  SELECT CAST(l_orderkey AS BIGINT) AS order_key,
         CAST(l_linenumber AS INT) AS line_number,
         row_number() OVER (PARTITION BY l_orderkey, l_linenumber
                            ORDER BY _source_file DESC, _row_hash DESC) AS rn,
         max(_row_hash) OVER (PARTITION BY l_orderkey, l_linenumber)
           <> min(_row_hash) OVER (PARTITION BY l_orderkey, l_linenumber) AS is_conflict,
         _row_hash, _source_file, _batch_id
  FROM ${catalog}.bronze.lineitem
),
customers_ranked AS (
  SELECT CAST(c_custkey AS BIGINT) AS customer_key,
         row_number() OVER (PARTITION BY c_custkey, snapshot_effective_date
                            ORDER BY _source_file DESC, _row_hash DESC) AS rn,
         max(_row_hash) OVER (PARTITION BY c_custkey, snapshot_effective_date)
           <> min(_row_hash) OVER (PARTITION BY c_custkey, snapshot_effective_date) AS is_conflict,
         _row_hash, _source_file, _batch_id
  FROM ${catalog}.bronze.customer
)
SELECT 'orders' AS entity, order_key, CAST(NULL AS INT) AS line_number,
  _row_hash, is_conflict, _source_file, _batch_id
FROM orders_ranked WHERE rn > 1
UNION ALL
SELECT 'lineitem', order_key, line_number,
  _row_hash, is_conflict, _source_file, _batch_id
FROM lines_ranked WHERE rn > 1
UNION ALL
SELECT 'customer', CAST(NULL AS BIGINT), CAST(NULL AS INT),
  _row_hash, is_conflict, _source_file, _batch_id
FROM customers_ranked WHERE rn > 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.ops.pending_order_lines AS
SELECT
  l.order_key_hash,
  l.line_number,
  l.order_key,
  -- Reasons as a semicolon string: concat_ws skips NULLs, and neither
  -- array_remove(arr, NULL) (returns NULL) nor a lambda over an array that
  -- contains EXISTS subqueries (UNSUPPORTED_SUBQUERY in higher-order
  -- functions) is usable here.
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
  -- A line whose header is quarantined never publishes; it is dispositioned
  -- with the header's quarantine entry, not by pending.
  AND NOT EXISTS (
  SELECT 1 FROM ${catalog}.ops.quarantine_invalid q
  WHERE q.entity = 'orders' AND q.order_key = l.order_key);
