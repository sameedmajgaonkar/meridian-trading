# Power BI integration (Phase 9)

Desktop app work (Windows) — marked **PENDING UI** until screenshots exist.

## Connect

1. Power BI Desktop → Get Data → **Azure Databricks**.
2. Connection: host `dbc-746bc1e1-c295.cloud.databricks.com`, HTTP path of the
   Serverless Starter Warehouse `/sql/1.0/warehouses/7c433c4d75a98ff6` (SQL editor → connection
   details). Auth: Personal Access Token (PAT) or Databricks OAuth.
3. Mode: **Direct Query** for `meridian_t02.gold.mv_trading` (and dims if
   needed). Import mode only if the visuals demand it — document the choice.

## Build (minimum three visuals)

1. **Line chart**: X `order_month`, Y net revenue (MEASURE(net_revenue)).
2. **Bar chart**: X `market_segment_at_order_time`, Y average order value.
3. **Card or table**: return rate + late delivery rate overall.
4. Optional table: `sql/analysis/top_customers.sql` results (top customers).

## Verify (record in evidence)

- [ ] Values match the dashboard/SQL numbers for the same filters (grain check:
      order count = headers, not lines).
- [ ] Refresh identity: who runs the refresh? (Publishing identity sees data
      via ITS OWN row-filter/mask entitlements — confirm what it can see.)
- [ ] Masked columns: as a restricted publisher, phone shows the mask.
- [ ] Screenshots `evidence/p9_powerbi.png` (+ `p9_refresh_identity.png`).

## Notes

- The metric view exposes `MEASURE(...)` — in custom native queries Power BI
  must use the `MEASURE()` function syntax; report visuals over the published
  measure names work directly.
- Schedules stay paused; Power BI refresh is manual.
