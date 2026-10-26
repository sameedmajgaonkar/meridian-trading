-- Compare all seven metrics at month/region/historical-segment grain.
WITH m AS (
  SELECT order_month,region_name,market_segment_at_order_time,
    MEASURE(net_revenue) AS revenue,MEASURE(order_count) AS orders,
    MEASURE(average_order_value) AS aov,MEASURE(delivery_days) AS days,
    MEASURE(late_delivery_rate) AS late,MEASURE(return_rate) AS returns,
    MEASURE(discount_given) AS discount
  FROM IDENTIFIER(:catalog || '.gold.mv_trading')
  GROUP BY order_month,region_name,market_segment_at_order_time
), o AS (
  SELECT date_trunc('MONTH',order_date) AS order_month,region_name,market_segment_at_order_time,
    count(*) AS orders FROM IDENTIFIER(:catalog || '.gold.fct_order_headers')
  GROUP BY 1,2,3
), l AS (
  SELECT date_trunc('MONTH',order_date) AS order_month,region_name,market_segment_at_order_time,
    sum(net_revenue) AS revenue,count(*) AS lines,sum(transit_days) AS days,
    sum(is_late) AS late,sum(is_returned) AS returns,sum(discount_amount) AS discount
  FROM IDENTIFIER(:catalog || '.gold.fct_order_items') GROUP BY 1,2,3
)
SELECT m.order_month,m.region_name,m.market_segment_at_order_time,
  m.revenue AS metric_revenue,l.revenue AS fact_revenue,m.orders AS metric_orders,o.orders AS fact_orders
FROM m FULL OUTER JOIN o USING (order_month,region_name,market_segment_at_order_time)
LEFT JOIN l USING (order_month,region_name,market_segment_at_order_time)
WHERE m.orders IS NULL OR o.orders IS NULL OR m.orders<>o.orders
  OR NOT (coalesce(abs(m.revenue-l.revenue)<=0.01,false) OR (m.revenue IS NULL AND l.revenue IS NULL))
  OR NOT (coalesce(abs(m.aov-try_divide(l.revenue,o.orders))<0.000001,false)
    OR (m.aov IS NULL AND l.revenue IS NULL))
  OR NOT (coalesce(abs(m.days-try_divide(l.days,l.lines))<0.000001,false) OR (m.days IS NULL AND l.lines IS NULL))
  OR NOT (coalesce(abs(m.late-try_divide(l.late,l.lines))<0.000001,false) OR (m.late IS NULL AND l.lines IS NULL))
  OR NOT (coalesce(abs(m.returns-try_divide(l.returns,l.lines))<0.000001,false) OR (m.returns IS NULL AND l.lines IS NULL))
  OR NOT (coalesce(abs(m.discount-l.discount)<=0.01,false) OR (m.discount IS NULL AND l.discount IS NULL));
