-- Two-grain metric view for wholesale order-to-revenue KPIs.

USE CATALOG meridian_t02;

CREATE OR REPLACE VIEW gold.mv_trading WITH METRICS LANGUAGE YAML AS $$
version: 1.1
source: gold.fct_orders
joins:
  - name: lines
    source: gold.fct_order_lines
    on: source.order_key_hash = lines.order_key_hash
    cardinality: one_to_many
dimensions:
  - name: order_date
    expr: source.order_date
  - name: order_month
    expr: date_trunc('MONTH', source.order_date)
  - name: order_status
    expr: source.order_status
  - name: market_segment_at_order_time
    expr: source.market_segment_at_order_time
  - name: region_name
    expr: source.region_name
  - name: nation_name
    expr: source.nation_name
measures:
  - name: net_revenue
    expr: SUM(lines.net_revenue)
  - name: order_count
    expr: COUNT(source.order_key_hash)
  - name: average_order_value
    expr: try_divide(MEASURE(net_revenue), MEASURE(order_count))
  - name: delivery_days
    expr: try_divide(SUM(lines.transit_days), COUNT(lines.line_number))
  - name: late_delivery_rate
    expr: try_divide(SUM(lines.is_late), COUNT(lines.line_number))
  - name: return_rate
    expr: try_divide(SUM(lines.is_returned), COUNT(lines.line_number))
  - name: discount_given
    expr: SUM(lines.discount_amount)
$$;
