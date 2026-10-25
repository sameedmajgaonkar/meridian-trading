-- Drops pipeline tables to allow a clean redeployment.
-- After running this file, run a normal pipeline update to rebuild.

USE CATALOG meridian_t02;

-- Gold metric view + dimensions + facts
DROP VIEW IF EXISTS gold.mv_trading;
DROP TABLE IF EXISTS gold.fct_order_lines;
DROP TABLE IF EXISTS gold.fct_orders;
DROP TABLE IF EXISTS gold.dim_customer_scd2;
DROP TABLE IF EXISTS gold.dim_supplier;
DROP TABLE IF EXISTS gold.dim_part;
DROP TABLE IF EXISTS gold.dim_nation;
DROP TABLE IF EXISTS gold.dim_region;

-- Ops monitoring views
DROP TABLE IF EXISTS ops.pending_order_lines;
DROP TABLE IF EXISTS ops.duplicate_dispositions;
DROP TABLE IF EXISTS ops.quarantine_invalid;

-- Silver tables
DROP TABLE IF EXISTS silver.orders;
DROP TABLE IF EXISTS silver.order_lines;
DROP TABLE IF EXISTS silver.customer_changes;
DROP TABLE IF EXISTS silver.customer_history;

-- Bronze streaming tables
DROP TABLE IF EXISTS bronze.supplier;
DROP TABLE IF EXISTS bronze.part;
DROP TABLE IF EXISTS bronze.region;
DROP TABLE IF EXISTS bronze.nation;
DROP TABLE IF EXISTS bronze.customer;
DROP TABLE IF EXISTS bronze.lineitem;
DROP TABLE IF EXISTS bronze.orders;

-- Verify
SHOW TABLES IN bronze;
SHOW TABLES IN silver;
SHOW TABLES IN gold;
SHOW TABLES IN ops;
