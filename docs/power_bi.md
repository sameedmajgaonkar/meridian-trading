# Power BI Integration

Desktop app work (Windows) — marked **PENDING UI** until screenshots exist.

## Connect

1. Power BI Desktop -> Get Data -> **Azure Databricks**.
2. Connection: Server Hostname `<workspace-host>`, HTTP path of the SQL Warehouse `/sql/1.0/warehouses/<warehouse-id>`. Auth: Personal Access Token (PAT) or Databricks OAuth.
3. Mode: **DirectQuery** for `meridian_t02.gold.mv_trading` (and dims if needed).

## Build (minimum three visuals)

1. **Line chart**: X `order_month`, Y net revenue (`MEASURE(net_revenue)`).
2. **Bar chart**: X `market_segment_at_order_time`, Y average order value (`MEASURE(average_order_value)`).
3. **Card / KPI**: return rate (`MEASURE(return_rate)`) + late delivery rate (`MEASURE(late_delivery_rate)`).
4. Optional table: top customers by revenue.

## Verify

- Values match the dashboard/SQL numbers for the same filters (grain check: order count = headers, not lines).
- Refresh identity: publishing identity sees data via its own row-filter/mask entitlements.
- Masked columns: as a restricted publisher, phone shows the mask and balance is NULL.
- Screenshot: `evidence/p9_powerbi.png`.

## Notes

- The metric view exposes `MEASURE(...)` — in custom native queries Power BI must use the `MEASURE()` function syntax; report visuals over published measure names work directly.
- DirectQuery avoids local storage of governed data and enforces Unity Catalog governance on refresh.
