-- Phase 4 — runs AS the demo analyst service principal
-- (governance_probe_job, run_as = ${var.probe_principal}). Its only data
-- grant: one gov.entitlements row (region 1 = AMERICA); it is NOT a member of
-- t02_admins / t02_pii_readers, so row filters and masks apply in full.
-- Writes the restricted view into ops.restricted_probe; read the latest run_ts
-- as an admin. Expected (precomputed as admin): fct_orders_rows = 271568
-- (AMERICA 226165 ∪ ROMANIA 45403), regions AMERICA+EUROPE only, phones
-- XXX-XXX-*, balances NULL, supplier dim = nation-19 suppliers only.
INSERT INTO meridian_t02.ops.restricted_probe
SELECT 'current_user', current_user()
UNION ALL SELECT 'is_member_admins', CAST(is_member('t02_admins') AS STRING)
UNION ALL SELECT 'is_member_pii_readers', CAST(is_member('t02_pii_readers') AS STRING)
UNION ALL SELECT 'mask_phone_direct', meridian_t02.gov.mask_customer_phone('555-123-4567')
UNION ALL SELECT 'mask_balance_direct', COALESCE(CAST(meridian_t02.gov.mask_account_balance(CAST(100.00 AS DECIMAL(18, 2))) AS STRING), 'NULL_returned')
UNION ALL SELECT 'fct_orders_rows', (SELECT CAST(count(*) AS STRING) FROM meridian_t02.gold.fct_orders)
UNION ALL SELECT 'fct_regions_seen', (SELECT concat_ws(',', collect_list(region_name || '=' || n)) FROM (SELECT region_name, count(*) n FROM meridian_t02.gold.fct_orders GROUP BY region_name ORDER BY region_name))
UNION ALL SELECT 'dim_supplier_rows', (SELECT CAST(count(*) AS STRING) FROM meridian_t02.gold.dim_supplier)
UNION ALL SELECT 'customer_phone_sample', (SELECT concat_ws('|', collect_list(customer_phone)) FROM (SELECT customer_phone FROM meridian_t02.gold.dim_customer_scd2 LIMIT 3))
UNION ALL SELECT 'customer_balance_nonnull_of_100', (SELECT CAST(count(*) AS STRING) FROM (SELECT customer_account_balance FROM meridian_t02.gold.dim_customer_scd2 LIMIT 100) t WHERE customer_account_balance IS NOT NULL)
UNION ALL SELECT 'mv_net_revenue', (SELECT CAST(MEASURE(net_revenue) AS STRING) FROM meridian_t02.gold.mv_trading)
UNION ALL SELECT 'mv_order_count', (SELECT CAST(MEASURE(order_count) AS STRING) FROM meridian_t02.gold.mv_trading);
