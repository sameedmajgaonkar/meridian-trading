-- Silver: cleaned, typed, and validated datasets for orders, line items, and customers.

CREATE OR REFRESH MATERIALIZED VIEW meridian_t02.silver.orders (
  CONSTRAINT orders_key_required EXPECT (order_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT orders_customer_key_required EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT orders_date_in_window
    EXPECT (order_date >= DATE '1995-01-01' AND order_date < DATE '1996-01-01')
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
FROM meridian_t02.bronze.orders
QUALIFY row_number() OVER (PARTITION BY o_orderkey ORDER BY _source_file DESC) = 1;

CREATE OR REFRESH MATERIALIZED VIEW meridian_t02.silver.order_lines (
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
FROM meridian_t02.bronze.lineitem
QUALIFY row_number() OVER (PARTITION BY l_orderkey, l_linenumber ORDER BY _source_file DESC) = 1;

-- Customer changes: recording expectations only (no DROP ROW).
CREATE OR REFRESH STREAMING TABLE meridian_t02.silver.customer_changes (
  CONSTRAINT customer_key_required EXPECT (customer_key IS NOT NULL),
  CONSTRAINT customer_segment_valid
    EXPECT (market_segment IN ('AUTOMOBILE', 'BUILDING', 'FURNITURE', 'HOUSEHOLD', 'MACHINERY')),
  CONSTRAINT customer_effective_date_required EXPECT (effective_date IS NOT NULL)
) AS
SELECT
  CAST(c_custkey AS BIGINT) AS customer_key,
  CAST(c_name AS STRING) AS customer_name,
  CAST(c_mktsegment AS STRING) AS market_segment,
  CAST(c_phone AS STRING) AS customer_phone,
  CAST(c_acctbal AS DECIMAL(18, 2)) AS customer_account_balance,
  CAST(c_nationkey AS BIGINT) AS customer_nation_key,
  CAST(effective_date AS DATE) AS effective_date,
  _source_file,
  _batch_id
FROM STREAM(meridian_t02.bronze.customer);
