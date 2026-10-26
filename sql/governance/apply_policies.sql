USE CATALOG IDENTIFIER(:catalog);

COMMENT ON COLUMN gold.fct_order_items.order_key IS 'Natural order header reference.';
COMMENT ON COLUMN gold.fct_order_items.order_key_hash IS 'SHA-256 join key shared with headers.';
COMMENT ON COLUMN gold.fct_order_items.line_number IS 'Item position within an order; key with order_key.';
COMMENT ON COLUMN gold.fct_order_items.part_key IS 'Natural key of the referenced part.';
COMMENT ON COLUMN gold.fct_order_items.supplier_key IS 'Natural key of the supplying organization.';
COMMENT ON COLUMN gold.fct_order_items.customer_version_key IS 'Customer history version valid at order_date.';
COMMENT ON COLUMN gold.dim_regions.region_key IS 'Natural TPCH region key.';
COMMENT ON COLUMN gold.dim_nations.nation_key IS 'Natural TPCH nation key.';
COMMENT ON COLUMN gold.dim_nations.region_key IS 'Parent region in the entitlement hierarchy.';
COMMENT ON COLUMN gold.dim_parts.part_key IS 'Natural TPCH part key.';
COMMENT ON COLUMN gold.dim_suppliers.supplier_nation_key IS 'Supplier nation; drives supplier row access.';
COMMENT ON COLUMN gold.fct_order_headers.customer_version_key IS 'Customer history version valid at order_date.';


ALTER SCHEMA landing SET TAGS ('medallion_layer' = 'landing');

ALTER SCHEMA bronze SET TAGS ('medallion_layer' = 'bronze');

ALTER SCHEMA silver SET TAGS ('medallion_layer' = 'silver');

ALTER SCHEMA gold SET TAGS ('medallion_layer' = 'gold');

ALTER TABLE gold.dim_customer_history ALTER COLUMN customer_phone SET TAGS ('pii_type'='contact','sensitivity_level'='confidential');

ALTER TABLE gold.dim_customer_history ALTER COLUMN customer_account_balance SET TAGS ('pii_type'='financial','sensitivity_level'='restricted');

ALTER TABLE gold.dim_suppliers ALTER COLUMN supplier_account_balance SET TAGS ('pii_type'='financial','sensitivity_level'='restricted');

ALTER TABLE silver.customer_versions ALTER COLUMN customer_phone SET TAGS ('pii_type'='contact','sensitivity_level'='confidential');

ALTER TABLE silver.customer_versions ALTER COLUMN customer_account_balance SET TAGS ('pii_type'='financial','sensitivity_level'='restricted');

ALTER TABLE silver.customer_events ALTER COLUMN customer_phone SET TAGS ('pii_type'='contact','sensitivity_level'='confidential');

ALTER TABLE silver.customer_events ALTER COLUMN customer_account_balance SET TAGS ('pii_type'='financial','sensitivity_level'='restricted');

ALTER TABLE bronze.customers_raw ALTER COLUMN c_phone SET TAGS ('pii_type'='contact','sensitivity_level'='confidential');

ALTER TABLE bronze.customers_raw ALTER COLUMN c_acctbal SET TAGS ('pii_type'='financial','sensitivity_level'='restricted');

ALTER TABLE bronze.suppliers_raw ALTER COLUMN s_acctbal SET TAGS ('pii_type'='financial','sensitivity_level'='restricted');

EXECUTE IMMEDIATE 'CREATE OR REPLACE POLICY mask_contact_pii ON CATALOG ' || :catalog || ' COLUMN MASK ' || :catalog || '.gov.mask_customer_phone TO `account users` FOR TABLES MATCH COLUMNS has_tag_value(\'pii_type\', \'contact\') AS pii_col ON COLUMN pii_col';

EXECUTE IMMEDIATE 'CREATE OR REPLACE POLICY mask_financial_pii ON CATALOG ' || :catalog || ' COLUMN MASK ' || :catalog || '.gov.mask_account_balance TO `account users` FOR TABLES MATCH COLUMNS has_tag_value(\'pii_type\', \'financial\') AS pii_col ON COLUMN pii_col';

-- Refresh preserves old masks; remove them only after ABAC is active.
ALTER MATERIALIZED VIEW gold.dim_customer_history ALTER COLUMN customer_phone DROP MASK;
ALTER MATERIALIZED VIEW gold.dim_customer_history ALTER COLUMN customer_account_balance DROP MASK;
ALTER MATERIALIZED VIEW gold.dim_suppliers ALTER COLUMN supplier_account_balance DROP MASK;

GRANT USE CATALOG ON CATALOG IDENTIFIER(:catalog) TO `account users`;

GRANT USE SCHEMA ON SCHEMA gold TO `account users`;

GRANT SELECT ON SCHEMA gold TO `account users`;
