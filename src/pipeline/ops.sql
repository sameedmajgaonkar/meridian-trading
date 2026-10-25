-- Ops: quarantine for invalid orders/lines and pending early lines.

CREATE OR REFRESH MATERIALIZED VIEW meridian_t02.ops.quarantine_invalid AS
SELECT 'orders' AS entity,
  CAST(o_orderkey AS BIGINT) AS order_key,
  CAST(NULL AS INT) AS line_number,
  CASE
    WHEN o_custkey IS NULL THEN 'CUSTOMER_KEY_REQUIRED'
    WHEN o_orderdate < DATE '1995-01-01' OR o_orderdate >= DATE '1996-01-01' THEN 'ORDER_DATE_OUT_OF_WINDOW'
    WHEN o_totalprice < 0 THEN 'ORDER_TOTAL_PRICE_NEGATIVE'
    WHEN o_orderstatus NOT IN ('O', 'F', 'P') THEN 'ORDER_STATUS_INVALID'
    ELSE 'UNKNOWN'
  END AS failure_reason,
  _source_file, _batch_id
FROM meridian_t02.bronze.orders
WHERE o_custkey IS NULL
   OR o_orderdate < DATE '1995-01-01' OR o_orderdate >= DATE '1996-01-01'
   OR o_totalprice < 0
   OR o_orderstatus NOT IN ('O', 'F', 'P')
QUALIFY row_number() OVER (PARTITION BY o_orderkey ORDER BY _source_file DESC) = 1

UNION ALL

SELECT 'lineitem' AS entity,
  CAST(l_orderkey AS BIGINT) AS order_key,
  CAST(l_linenumber AS INT) AS line_number,
  CASE
    WHEN l_quantity <= 0 THEN 'QUANTITY_NONPOSITIVE'
    WHEN l_discount < 0 OR l_discount > 1 THEN 'DISCOUNT_OUT_OF_RANGE'
    WHEN l_extendedprice < 0 THEN 'EXTENDED_PRICE_NEGATIVE'
    WHEN l_tax < 0 OR l_tax > 1 THEN 'TAX_OUT_OF_RANGE'
    WHEN l_receiptdate < l_shipdate THEN 'RECEIPT_BEFORE_SHIP'
    ELSE 'UNKNOWN'
  END AS failure_reason,
  _source_file, _batch_id
FROM meridian_t02.bronze.lineitem
WHERE l_quantity <= 0
   OR l_discount < 0 OR l_discount > 1
   OR l_extendedprice < 0
   OR l_tax < 0 OR l_tax > 1
   OR l_receiptdate < l_shipdate
QUALIFY row_number() OVER (PARTITION BY l_orderkey, l_linenumber ORDER BY _source_file DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW meridian_t02.ops.pending_order_lines AS
SELECT l.order_key_hash, l.line_number, l.order_key, l._source_file, l._batch_id
FROM meridian_t02.silver.order_lines l
WHERE NOT EXISTS (SELECT 1 FROM meridian_t02.gold.fct_orders o WHERE o.order_key_hash = l.order_key_hash)
  AND NOT EXISTS (SELECT 1 FROM meridian_t02.ops.quarantine_invalid q WHERE q.entity = 'orders' AND q.order_key = l.order_key);
