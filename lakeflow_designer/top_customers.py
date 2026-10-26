# Databricks notebook source
# This executable counterpart supports the real Designer canvas documented in README.md.
import re

dbutils.widgets.text("catalog", "meridian_t02_dev")
dbutils.widgets.text("segment", "ALL")
catalog = dbutils.widgets.get("catalog")
segment = dbutils.widgets.get("segment")
if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", catalog):
    raise ValueError("Invalid catalog")
if segment not in ("ALL", "AUTOMOBILE", "BUILDING", "FURNITURE", "HOUSEHOLD", "MACHINERY"):
    raise ValueError("Invalid market segment")

# COMMAND ----------
# Join: line -> header -> customer version valid at order time.
orders = spark.sql(f"""
SELECT l.order_key, l.extended_price * (1 - l.discount_rate) AS net_revenue,
  o.customer_key, h.market_segment AS market_segment_at_order_time,
  h.customer_nation_key, n.n_regionkey AS customer_region_key
FROM {catalog}.silver.order_items l
JOIN {catalog}.silver.order_headers o ON l.order_key = o.order_key
JOIN {catalog}.silver.customer_versions h
  ON o.customer_key=h.customer_key AND o.order_date>=h.__START_AT
 AND (h.__END_AT IS NULL OR o.order_date<h.__END_AT)
JOIN {catalog}.bronze.nations_raw n ON h.customer_nation_key=n.n_nationkey
""")
if segment != "ALL":
    orders = orders.where(orders.market_segment_at_order_time == segment)
orders.createOrReplaceTempView("customer_orders")

# COMMAND ----------
# Aggregate and rank: customer revenue within the historical market segment.
result = spark.sql("""
WITH totals AS (
  SELECT customer_key,market_segment_at_order_time,customer_nation_key,customer_region_key,
    sum(net_revenue) AS net_revenue,count(DISTINCT order_key) AS order_count
  FROM customer_orders GROUP BY customer_key,market_segment_at_order_time,customer_nation_key,customer_region_key
), ranked AS (
  SELECT *,row_number() OVER (PARTITION BY market_segment_at_order_time
    ORDER BY net_revenue DESC,customer_key) AS rank_in_segment FROM totals
)
SELECT * FROM ranked WHERE rank_in_segment<=10 ORDER BY market_segment_at_order_time,rank_in_segment
""")
result.createOrReplaceTempView("top_customers")

# COMMAND ----------
# Replace the derived output while declaring its security in the same statement.
spark.sql(f"""
CREATE OR REPLACE TABLE {catalog}.gold.vdp_top_customers
USING DELTA
COMMENT 'Grain: top-ten customer and order-time segment, whole landed cohort; segment parameter applied before rank.'
WITH ROW FILTER {catalog}.gov.region_nation_filter ON (customer_region_key,customer_nation_key)
AS SELECT * FROM top_customers
""")
spark.sql(f"ALTER TABLE {catalog}.gold.vdp_top_customers SET TAGS ('medallion_layer'='gold')")

# COMMAND ----------
display(result)
