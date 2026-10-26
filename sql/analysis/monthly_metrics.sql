SELECT order_month,market_segment_at_order_time,
  MEASURE(net_revenue) AS net_revenue,MEASURE(order_count) AS order_count,
  MEASURE(average_order_value) AS average_order_value
FROM meridian_t02_prod.gold.mv_trading
WHERE order_date>=:start_date AND order_date<:end_date
GROUP BY order_month,market_segment_at_order_time ORDER BY order_month,market_segment_at_order_time;
