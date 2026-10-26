WITH trading AS (
  SELECT order_date, region_name, market_segment_at_order_time,
    MEASURE(net_revenue) AS net_revenue,
    MEASURE(order_count) AS order_count,
    MEASURE(discount_given) AS discount_given
  FROM meridian_t02_prod.gold.mv_trading
  GROUP BY order_date, region_name, market_segment_at_order_time
), fulfillment AS (
  SELECT order_date, region_name, market_segment_at_order_time,
    count(*) AS line_count,
    sum(is_returned) AS returned_lines,
    sum(is_late) AS late_lines,
    sum(transit_days) AS transit_days_sum
  FROM meridian_t02_prod.gold.fct_order_items
  GROUP BY order_date, region_name, market_segment_at_order_time
)
SELECT t.*, date_trunc('MONTH', t.order_date) AS order_month,
  coalesce(f.line_count, 0) AS line_count,
  coalesce(f.returned_lines, 0) AS returned_lines,
  coalesce(f.late_lines, 0) AS late_lines,
  coalesce(f.transit_days_sum, 0) AS transit_days_sum
FROM trading t
LEFT JOIN fulfillment f
  ON t.order_date = f.order_date
 AND t.region_name = f.region_name
 AND t.market_segment_at_order_time = f.market_segment_at_order_time;
