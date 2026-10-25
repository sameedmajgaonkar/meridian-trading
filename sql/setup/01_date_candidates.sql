-- EXPLICIT OPT-IN: reads the order-date column over the whole orders source.
-- First inspect orders_storage (sizeInBytes, numFiles) and warehouse quota.
-- One aggregation gives observed bounds, candidate years, and null-date count.
-- Counts are evidence, not a promise that a calendar year is complete.

-- probe: order_date_candidates
SELECT
  year(o_orderdate) AS order_year,
  min(o_orderdate) AS first_order_date,
  max(o_orderdate) AS last_order_date,
  count(*) AS order_rows,
  count_if(o_orderdate IS NULL) AS null_order_dates
FROM samples.tpch.orders
GROUP BY year(o_orderdate)
ORDER BY order_year;
