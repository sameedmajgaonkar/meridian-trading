# Genie setup (Phase 8)

Space over the governed Gold layer; benchmark with 5 questions whose answers
are verified first with the SQL below (numbers come from your actual run —
compute them with the "verify" queries, then compare Genie's answers).

## Space

1. **AI/BI Genie → New space**: title `Meridian Wholesale Revenue`,
   catalog/schema `meridian_t02.gold`; include `mv_trading`, `fct_orders`,
   `fct_order_lines`, `dim_customer_scd2`.
2. Instructions (paste):

```
This space answers wholesale order-to-revenue questions for the 1995 window
(orders 1995-01-01 to 1995-12-31). Grain rules:
- Header facts (fct_orders, mv_trading source) are one row per order.
- fct_order_lines is one row per order and line number.
- Never sum order_total_price across lines; revenue KPI is net_revenue
  (extended_price * (1 - discount_rate)) summed over lines.
- Use market_segment_at_order_time (point-in-time), never current segment.
- Rate KPIs are ratios of sums; a zero denominator means "no eligible data".
```

3. Example queries to attach (also in `sql/analysis/`):
   1. `SELECT order_month, MEASURE(net_revenue) FROM meridian_t02.gold.mv_trading GROUP BY order_month ORDER BY order_month;`
   2. `SELECT market_segment_at_order_time, MEASURE(return_rate) FROM meridian_t02.gold.mv_trading GROUP BY market_segment_at_order_time ORDER BY return_rate DESC;`
   3. `SELECT region_name, MEASURE(discount_given) FROM meridian_t02.gold.mv_trading GROUP BY region_name ORDER BY discount_given DESC;`

## Benchmark (run each; record Genie's answer vs verified query)

| # | Question | Verify with |
|---|---|---|
| 1 | What is net revenue by market segment? | 50_kpi_queries 6.1 grouped by segment |
| 2 | How many orders were placed in December 1995? | `SELECT count(*) FROM meridian_t02.gold.fct_orders WHERE order_date >= DATE '1995-12-01' AND order_date < DATE '1996-01-01'` |
| 3 | Which region has the highest late-delivery rate? | `SELECT region_name, MEASURE(late_delivery_rate) FROM meridian_t02.gold.mv_trading GROUP BY region_name ORDER BY 2 DESC` |
| 4 | What is the return rate overall? | `SELECT MEASURE(return_rate) FROM meridian_t02.gold.mv_trading` |
| 5 | Show the top 10 customers by revenue with their order-time segment | 53_vdp_equivalent |

Pass criteria: right grain (no line fan-out), point-in-time segment, correct
rate semantics. Screenshot: `evidence/p8_genie.png`.
