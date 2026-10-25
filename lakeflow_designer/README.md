# Lakeflow Designer — gold.vdp_top_customers (Phase 2/6 UI exercise)

The brief requires one Designer-built visual data product. The equivalent SQL
is in `sql/analysis/top_customers.sql`; build it in the Designer UI with
these operators, then commit the actual export (do not fabricate one).

## Steps

1. Databricks → **Lakeflow** (Designer) → New pipeline → name
   `meridian_t02_vdp_top_customers`; catalog `meridian_t02`, schema `gold`.
2. Add a **Source** node: `meridian_t02.gold.fct_order_lines`.
3. Add an **Aggregate** node: group by
   `market_segment_at_order_time, customer_key`; measures
   `SUM(net_revenue) AS net_revenue`,
   `COUNT(DISTINCT order_key_hash) AS order_count`.
4. Add a **Custom/window** operator:
   `row_number() OVER (PARTITION BY market_segment_at_order_time ORDER BY net_revenue DESC) AS rank_in_segment`.
5. Add a **Filter** node: `rank_in_segment <= 10`.
6. Add a **Sort** operator: `market_segment_at_order_time ASC, rank_in_segment ASC`.
7. Output target: `meridian_t02.gold.vdp_top_customers`.
8. Parameter: create a `segment` pipeline parameter and add the filter
   `market_segment_at_order_time = :segment` before ranking when demonstrating
   the single-segment view.
9. Run, verify 10 rows per segment (×5 segments), then **export/download the
   pipeline definition** and save as `evidence/p2_designer_export.json`
   (or as documented by the UI version at run time).

Screenshot after step 9: `evidence/p2_designer_pipeline.png`.

*Why these operators: source (ingest), aggregate (business question), window
rank (top-N per group), filter (N), sort (presentation). This is the smallest
operator set that shows the VDP pattern without duplicating the metric view.*
