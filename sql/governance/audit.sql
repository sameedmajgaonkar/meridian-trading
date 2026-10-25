-- Audit listing and self-tests for Unity Catalog governance.
-- dev catalog

-- What is actually attached?
SELECT table_name, filter_name FROM system.information_schema.row_filters
WHERE table_catalog = 'meridian_t02';

SELECT table_name, column_name, mask_name FROM system.information_schema.column_masks
WHERE table_catalog = 'meridian_t02';

-- Governed Schema Tags:
SELECT schema_name, tag_name, tag_value
FROM meridian_t02.information_schema.schema_tags;

-- Governed Column Tags:
SELECT schema_name, table_name, column_name, tag_name, tag_value
FROM meridian_t02.information_schema.column_tags
ORDER BY schema_name, table_name, column_name;

-- Centralized Tag-Driven ABAC Policies:
SELECT policy_name, policy_type, on_securable_type, to_principals, match_columns, governed_tags
FROM meridian_t02.information_schema.abac_policy_definitions;

-- Direct function checks:
SELECT meridian_t02.gov.region_nation_filter(1, 1) AS region_grant_holds,
       meridian_t02.gov.region_nation_filter(4, CAST(NULL AS BIGINT)) AS no_grant,
       meridian_t02.gov.mask_account_balance(CAST(100.00 AS DECIMAL(18, 2))) AS masked_balance_as_admin;

-- Full-access check as admin (expected: all window rows):
SELECT count(*) AS fct_orders_all FROM meridian_t02.gold.fct_orders;

-- Per-region row distribution as admin:
SELECT region_name, count(*) AS rows FROM meridian_t02.gold.fct_orders
GROUP BY region_name ORDER BY region_name;

-- Restricted-principal check:
-- An identity without admin bypass (even if in pii_readers) sees ONLY its entitled rows.
SELECT region_name, count(*) AS rows FROM meridian_t02.gold.fct_orders
GROUP BY region_name ORDER BY region_name;

-- Mask visibility:
-- Without pii_readers: phone like XXX-XXX-XXXX, balance NULL
-- With pii_readers: unmasked phone and balance, restricted to entitled geography
SELECT customer_key, customer_phone, customer_account_balance
FROM meridian_t02.gold.dim_customer_scd2 LIMIT 5;
