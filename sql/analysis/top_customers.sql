SELECT customer_key,market_segment_at_order_time,region_name,
  sum(net_revenue) AS net_revenue,count(DISTINCT order_key) AS order_count
FROM meridian_t02_prod.gold.fct_order_items
GROUP BY customer_key,market_segment_at_order_time,region_name
HAVING sum(net_revenue)>=:minimum_revenue
ORDER BY net_revenue DESC LIMIT 20;
