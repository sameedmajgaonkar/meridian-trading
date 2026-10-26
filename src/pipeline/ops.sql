USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA bronze;

CREATE OR REFRESH MATERIALIZED VIEW ops.quarantine_records
COMMENT 'Grain: one rejected source record, including duplicates and invalid-parent items.'
AS
SELECT 'orders' AS entity,
  CASE WHEN candidate_rank > 1 THEN 'duplicate' ELSE 'validation' END AS stage,
  order_key, CAST(NULL AS INT) AS line_number,
  CASE WHEN candidate_rank > 1 THEN 'DUPLICATE_KEY'
    WHEN NOT keys_valid THEN 'ORDER_KEYS_INVALID'
    WHEN NOT date_valid THEN 'ORDER_DATE_INVALID' ELSE 'ORDER_VALUES_INVALID' END AS failure_reason,
  raw_record, _source_file, _batch_id
FROM orders_checked
WHERE candidate_rank > 1 OR NOT (keys_valid AND date_valid AND values_valid)
UNION ALL
SELECT 'lineitem', CASE WHEN candidate_rank > 1 THEN 'duplicate' ELSE 'validation' END,
  order_key, line_number,
  CASE WHEN candidate_rank > 1 THEN 'DUPLICATE_KEY'
    WHEN NOT keys_valid THEN 'LINE_KEYS_INVALID'
    WHEN NOT amounts_valid THEN 'LINE_AMOUNTS_INVALID'
    WHEN NOT rates_valid THEN 'LINE_RATES_INVALID'
    WHEN NOT codes_valid THEN 'LINE_CODES_INVALID' ELSE 'LINE_DATES_INVALID' END,
  raw_record, _source_file, _batch_id
FROM lines_checked
WHERE candidate_rank > 1 OR NOT (keys_valid AND amounts_valid AND rates_valid AND codes_valid AND dates_valid)
UNION ALL
SELECT 'lineitem', 'parent', l.order_key, l.line_number, 'INVALID_ORDER_HEADER',
  to_json(struct(l.*)), l._source_file, l._batch_id
FROM silver.order_items l
WHERE NOT EXISTS (SELECT 1 FROM silver.order_headers o WHERE o.order_key = l.order_key)
  AND EXISTS (SELECT 1 FROM orders_checked o WHERE o.order_key = l.order_key AND o.candidate_rank = 1);

CREATE OR REFRESH MATERIALIZED VIEW ops.pending_order_items
COMMENT 'Grain: one valid line whose order header has not arrived; recomputed each update.'
AS SELECT l.* FROM silver.order_items l
WHERE NOT EXISTS (SELECT 1 FROM orders_checked o WHERE o.order_key = l.order_key);
