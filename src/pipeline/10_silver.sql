-- Phase 2 — Silver: typed, deduplicated, validated.
-- These are MATERIALIZED VIEWS (recomputed on every pipeline update), not
-- streaming tables: Structured Streaming does not allow non-time-window
-- functions (the row_number dedup) on a streaming read, and the contract's
-- dedup rule is "newest file wins" — a window, not first-seen streaming
-- dedup. Bronze remains append-only streaming (Auto Loader ingests only
-- newly landed files per update); Silver and Gold recompute from Bronze,
-- which is exactly the reconciliation model the quality gate enforces.
-- Invalid rows are dropped here (EXPECT ... ON VIOLATION DROP ROW) and are
-- preserved in ops.quarantine_invalid, which recomputes the same predicates
-- from Bronze. Duplicates never enter Silver: the dedup order is documented
-- and deterministic (latest source file, then row content hash), and every
-- discarded duplicate occurrence is dispositioned in ops.duplicate_dispositions.

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}silver.orders (
  CONSTRAINT orders_key_required EXPECT (order_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT orders_customer_key_required EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT orders_date_in_window
    EXPECT (order_date >= DATE '${order_start_date}' AND order_date < DATE '${order_end_date}')
    ON VIOLATION DROP ROW,
  CONSTRAINT orders_total_price_nonnegative EXPECT (order_total_price >= 0) ON VIOLATION DROP ROW,
  CONSTRAINT orders_status_valid EXPECT (order_status IN ('O', 'F', 'P')) ON VIOLATION DROP ROW
) AS
SELECT
  CAST(o_orderkey AS BIGINT) AS order_key,
  lower(sha2(CAST(o_orderkey AS STRING), 256)) AS order_key_hash,
  CAST(o_custkey AS BIGINT) AS customer_key,
  CAST(o_orderdate AS DATE) AS order_date,
  CAST(o_totalprice AS DECIMAL(18, 2)) AS order_total_price,
  CAST(o_orderstatus AS STRING) AS order_status,
  _source_file,
  _batch_id
FROM ${catalog}.${schema_prefix}bronze.orders
QUALIFY row_number() OVER (PARTITION BY o_orderkey ORDER BY _source_file DESC, _row_hash DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}silver.order_lines (
  CONSTRAINT lines_key_required EXPECT (order_key IS NOT NULL AND line_number IS NOT NULL)
    ON VIOLATION DROP ROW,
  CONSTRAINT lines_number_positive EXPECT (line_number > 0) ON VIOLATION DROP ROW,
  CONSTRAINT lines_quantity_positive EXPECT (quantity > 0) ON VIOLATION DROP ROW,
  CONSTRAINT lines_extended_price_nonnegative EXPECT (extended_price >= 0) ON VIOLATION DROP ROW,
  CONSTRAINT lines_discount_in_range EXPECT (discount_rate >= 0 AND discount_rate <= 1) ON VIOLATION DROP ROW,
  CONSTRAINT lines_tax_in_range EXPECT (tax_rate >= 0 AND tax_rate <= 1) ON VIOLATION DROP ROW,
  CONSTRAINT lines_codes_valid
    EXPECT (line_status IN ('O', 'F') AND return_flag IN ('N', 'A', 'R')) ON VIOLATION DROP ROW,
  CONSTRAINT lines_dates_required
    EXPECT (ship_date IS NOT NULL AND commit_date IS NOT NULL AND receipt_date IS NOT NULL)
    ON VIOLATION DROP ROW,
  CONSTRAINT lines_receipt_not_before_ship EXPECT (receipt_date >= ship_date) ON VIOLATION DROP ROW
) AS
SELECT
  CAST(l_orderkey AS BIGINT) AS order_key,
  lower(sha2(CAST(l_orderkey AS STRING), 256)) AS order_key_hash,
  CAST(l_linenumber AS INT) AS line_number,
  CAST(l_partkey AS BIGINT) AS part_key,
  CAST(l_suppkey AS BIGINT) AS supplier_key,
  CAST(l_quantity AS DECIMAL(18, 2)) AS quantity,
  CAST(l_extendedprice AS DECIMAL(18, 2)) AS extended_price,
  CAST(l_discount AS DECIMAL(9, 6)) AS discount_rate,
  CAST(l_tax AS DECIMAL(9, 6)) AS tax_rate,
  CAST(l_shipdate AS DATE) AS ship_date,
  CAST(l_commitdate AS DATE) AS commit_date,
  CAST(l_receiptdate AS DATE) AS receipt_date,
  CAST(l_linestatus AS STRING) AS line_status,
  CAST(l_returnflag AS STRING) AS return_flag,
  _source_file,
  _batch_id
FROM ${catalog}.${schema_prefix}bronze.lineitem
QUALIFY row_number() OVER (PARTITION BY l_orderkey, l_linenumber
                           ORDER BY _source_file DESC, _row_hash DESC) = 1;

-- Complete per-batch customer snapshots, validated and deduplicated here —
-- expectations are NOT supported with AUTO CDC FROM SNAPSHOT (docs, verified
-- 2026-10-25), so the CDC flow reads this already-clean dataset.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${schema_prefix}silver.customer_snapshot (
  CONSTRAINT customer_key_required EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT customer_segment_valid
    EXPECT (market_segment IN ('AUTOMOBILE', 'BUILDING', 'FURNITURE', 'HOUSEHOLD', 'MACHINERY'))
    ON VIOLATION DROP ROW,
  CONSTRAINT customer_snapshot_date_required EXPECT (snapshot_effective_date IS NOT NULL)
    ON VIOLATION DROP ROW
) AS
SELECT
  CAST(c_custkey AS BIGINT) AS customer_key,
  CAST(c_name AS STRING) AS customer_name,
  CAST(c_mktsegment AS STRING) AS market_segment,
  CAST(c_phone AS STRING) AS customer_phone,
  CAST(c_acctbal AS DECIMAL(18, 2)) AS customer_account_balance,
  CAST(c_nationkey AS BIGINT) AS customer_nation_key,
  CAST(snapshot_effective_date AS DATE) AS snapshot_effective_date,
  _source_file,
  _batch_id
FROM ${catalog}.${schema_prefix}bronze.customer
QUALIFY row_number() OVER (PARTITION BY c_custkey, snapshot_effective_date
                           ORDER BY _source_file DESC, _row_hash DESC) = 1;
