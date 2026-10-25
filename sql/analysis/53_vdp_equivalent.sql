-- Phase 6 — SQL equivalent of gold.vdp_top_customers (the Lakeflow Designer
-- exercise, see lakeflow_designer/README.md): top 10 customers per order-time
-- market segment by net revenue. Line grain aggregated per (segment, customer),
-- then ranked per segment. Order counts are per-customer here and are NOT
-- additive across segments (data contract).
-- shortcut: catalog is literal here (manual SQL-editor file).
WITH line_revenue AS (
  SELECT customer_key, market_segment_at_order_time,
         sum(net_revenue) AS net_revenue,
         count(DISTINCT order_key_hash) AS order_count
  FROM meridian_t02.gold.fct_order_lines
  GROUP BY customer_key, market_segment_at_order_time
)
SELECT market_segment_at_order_time, customer_key, net_revenue, order_count,
  row_number() OVER (PARTITION BY market_segment_at_order_time
                     ORDER BY net_revenue DESC) AS rank_in_segment
FROM line_revenue
QUALIFY rank_in_segment <= 10
ORDER BY market_segment_at_order_time, rank_in_segment;
