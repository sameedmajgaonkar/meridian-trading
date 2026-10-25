-- Phase 3 — the two-grain metric view (ADR-003: all seven package KPIs).
-- Source = header fact; the line fact joins one_to_many, so header measures
-- aggregate at header grain and line measures at line grain — no fan-out, no
-- SUM(DISTINCT). MEASURE() composes ratio KPIs from other measures;
-- try_divide keeps a zero denominator as NULL ("no eligible data"), never
-- infinity (data contract).
-- Run in the SQL editor after the first pipeline update (Phase 3), then
-- re-verify after Phase 4 attaches the row filters (runbook step 5.3).
-- shortcut: catalog is literal here (manual SQL-editor file); sed it if the
-- workspace-catalog fallback is ever activated.
CREATE OR REPLACE VIEW meridian_t02.gold.mv_trading WITH METRICS LANGUAGE YAML AS $$
version: 1.1
source: meridian_t02.gold.fct_orders
joins:
  - name: lines
    source: meridian_t02.gold.fct_order_lines
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
    expr: try_divide(SUM(lines.transit_days), SUM(lines.transit_eligible))
  - name: late_delivery_rate
    expr: try_divide(SUM(lines.is_late), SUM(lines.late_eligible))
  - name: return_rate
    expr: try_divide(SUM(lines.is_returned), SUM(lines.return_eligible))
  - name: discount_given
    expr: SUM(lines.discount_amount)
$$;

-- smoke check (run right after creating it):
-- SELECT order_month, MEASURE(net_revenue) FROM meridian_t02.gold.mv_trading
-- GROUP BY order_month ORDER BY order_month;
