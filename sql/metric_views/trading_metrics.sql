USE CATALOG IDENTIFIER(:catalog);

CREATE OR REPLACE VIEW gold.mv_trading WITH METRICS LANGUAGE YAML AS $$
version: 1.1
source: gold.fct_order_headers
comment: 'Wholesale KPIs for validated 1995 order headers and their valid lines.'
joins:
  - name: lines
    source: gold.fct_order_items
    on: source.order_key_hash = lines.order_key_hash
    cardinality: one_to_many
fields:
  - name: order_date
    expr: source.order_date
    comment: 'Order placement date; defines the reporting window.'
  - name: order_month
    expr: date_trunc('MONTH', source.order_date)
    comment: 'Calendar month of the order date.'
  - name: order_status
    expr: source.order_status
    comment: 'O=open; F=fulfilled; P=partially fulfilled.'
  - name: market_segment_at_order_time
    expr: source.market_segment_at_order_time
    comment: 'Customer segment valid on the order date.'
  - name: region_name
    expr: source.region_name
    comment: 'Customer region used for geographic reporting and entitlements.'
  - name: nation_name
    expr: source.nation_name
    comment: 'Customer nation within the region hierarchy.'
measures:
  - name: net_revenue
    expr: SUM(lines.net_revenue)
    comment: 'Extended price after discount, excluding tax.'
  - name: order_count
    expr: COUNT(source.order_key_hash)
    comment: 'Validated order headers, counted once regardless of line count.'
  - name: average_order_value
    expr: try_divide(MEASURE(net_revenue), MEASURE(order_count))
    comment: 'Net revenue divided by validated header count.'
  - name: delivery_days
    expr: try_divide(SUM(lines.transit_days), COUNT(lines.line_number))
    comment: 'Mean days from shipment to receipt across valid lines.'
  - name: late_delivery_rate
    expr: try_divide(SUM(lines.is_late), COUNT(lines.line_number))
    comment: 'Fraction of valid lines received after their commit date.'
  - name: return_rate
    expr: try_divide(SUM(lines.is_returned), COUNT(lines.line_number))
    comment: 'Fraction of all valid lines whose return flag is R.'
  - name: discount_given
    expr: SUM(lines.discount_amount)
    comment: 'Total line discount amount before tax.'
$$;
