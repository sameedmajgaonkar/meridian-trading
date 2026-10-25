-- Parameterized analysis queries over the metric view.
-- dev catalog

-- 6.1 Monthly KPI trend by order-time market segment. :order_month_start DATE
SELECT order_month, market_segment_at_order_time,
  MEASURE(net_revenue) AS net_revenue,
  MEASURE(order_count) AS order_count,
  MEASURE(average_order_value) AS average_order_value,
  MEASURE(delivery_days) AS delivery_days,
  MEASURE(late_delivery_rate) AS late_delivery_rate,
  MEASURE(return_rate) AS return_rate,
  MEASURE(discount_given) AS discount_given
FROM meridian_t02.gold.mv_trading
WHERE order_month >= :order_month_start
GROUP BY order_month, market_segment_at_order_time
ORDER BY order_month, net_revenue DESC;

-- 6.2 Region revenue mix for one month. :as_of_month DATE
SELECT region_name, nation_name,
  MEASURE(net_revenue) AS net_revenue,
  MEASURE(order_count) AS order_count,
  MEASURE(average_order_value) AS average_order_value
FROM meridian_t02.gold.mv_trading
WHERE order_month = :as_of_month
GROUP BY region_name, nation_name
ORDER BY net_revenue DESC;

-- 6.3 Late-delivery and return exposure of in-flight vs finished orders
-- with a numeric threshold. :min_revenue NUMBER
SELECT order_status,
  MEASURE(net_revenue) AS net_revenue,
  MEASURE(order_count) AS order_count,
  MEASURE(late_delivery_rate) AS late_delivery_rate,
  MEASURE(return_rate) AS return_rate
FROM meridian_t02.gold.mv_trading
GROUP BY order_status
HAVING MEASURE(net_revenue) >= :min_revenue
ORDER BY net_revenue DESC;
