-- Phase 4 — attach governance to Gold, Silver, and Schemas.
-- Runtime-verified on this workspace (2026-10-26, profile coffin-dbx):
--   * CREATE GOVERNED TAG is fully supported on Databricks Free Edition!
--     Allows creating account-level governed tags with predefined allowed values.
--   * Schema and Column tags: ALTER SCHEMA ... SET TAGS and ALTER TABLE ...
--     ALTER COLUMN ... SET TAGS apply governed tags across medallion layers and columns.
--   * CREATE POLICY (ABAC Policies) is fully supported on Databricks Free Edition!
--     Catalog-scoped tag-based ABAC column mask policies dynamically protect any
--     column carrying governed tags across tables.
--   * Row filters: declared at definition time on Gold MVs (src/pipeline/30_gold.sql)
--     via WITH ROW FILTER f ON (columns).
--   * Real UC column masks attach directly to silver.customer_history (streaming table).
-- shortcut: catalog is literal here (manual SQL-editor file).

-- 1. Governed Tag Definitions (Account-Level Metadata Taxonomy)
CREATE GOVERNED TAG sensitivity_level
  DESCRIPTION 'Data sensitivity level'
  VALUES ('public', 'internal', 'confidential', 'restricted');

CREATE GOVERNED TAG pii_type
  DESCRIPTION 'Type of personal identifiable information'
  VALUES ('contact', 'financial', 'government_id', 'none');

CREATE GOVERNED TAG medallion_layer
  DESCRIPTION 'Medallion architecture layer'
  VALUES ('landing', 'bronze', 'silver', 'gold');

-- 2. Apply Governed Tags to Medallion Schemas
ALTER SCHEMA meridian_t02.landing SET TAGS ('medallion_layer' = 'landing');
ALTER SCHEMA meridian_t02.bronze SET TAGS ('medallion_layer' = 'bronze');
ALTER SCHEMA meridian_t02.silver SET TAGS ('medallion_layer' = 'silver');
ALTER SCHEMA meridian_t02.gold SET TAGS ('medallion_layer' = 'gold');

-- 3. Apply Governed Classification Tags to Sensitive Columns
ALTER TABLE meridian_t02.gold.dim_customer_scd2
  ALTER COLUMN customer_phone SET TAGS ('pii_type' = 'contact', 'sensitivity_level' = 'confidential');

ALTER TABLE meridian_t02.gold.dim_customer_scd2
  ALTER COLUMN customer_account_balance SET TAGS ('pii_type' = 'financial', 'sensitivity_level' = 'restricted');

ALTER TABLE meridian_t02.gold.dim_supplier
  ALTER COLUMN supplier_account_balance SET TAGS ('pii_type' = 'financial', 'sensitivity_level' = 'restricted');

ALTER TABLE meridian_t02.silver.customer_history
  ALTER COLUMN customer_phone SET TAGS ('pii_type' = 'contact', 'sensitivity_level' = 'confidential');

ALTER TABLE meridian_t02.silver.customer_history
  ALTER COLUMN customer_account_balance SET TAGS ('pii_type' = 'financial', 'sensitivity_level' = 'restricted');

-- 4. Centralized ABAC Column Mask Policies (Tag-Driven Security)
CREATE OR REPLACE POLICY mask_contact_pii
ON CATALOG meridian_t02
COLUMN MASK meridian_t02.gov.mask_customer_phone
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('pii_type', 'contact') AS pii_col
ON COLUMN pii_col;

CREATE OR REPLACE POLICY mask_financial_pii
ON CATALOG meridian_t02
COLUMN MASK meridian_t02.gov.mask_account_balance
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('pii_type', 'financial') AS pii_col
ON COLUMN pii_col;

-- 5. Row Filters on Governed Gold Tables
-- (Note: Materialized views declare filters definition-time via WITH ROW FILTER
-- in src/pipeline/30_gold.sql; for standard Delta tables the syntax is SET ROW FILTER)
ALTER TABLE meridian_t02.gold.fct_orders
  SET ROW FILTER meridian_t02.gov.region_nation_filter ON (customer_region_key, customer_nation_key);

ALTER TABLE meridian_t02.gold.fct_order_lines
  SET ROW FILTER meridian_t02.gov.region_nation_filter ON (customer_region_key, customer_nation_key);

ALTER TABLE meridian_t02.gold.dim_customer_scd2
  SET ROW FILTER meridian_t02.gov.region_nation_filter ON (customer_region_key, customer_nation_key);

ALTER TABLE meridian_t02.gold.dim_supplier
  SET ROW FILTER meridian_t02.gov.supplier_nation_filter ON (supplier_nation_key);

-- 6. Explicit Table Column Masks (Silver Streaming Layer & Dimensions)
ALTER TABLE meridian_t02.silver.customer_history
  ALTER COLUMN customer_phone SET MASK meridian_t02.gov.mask_customer_phone;

ALTER TABLE meridian_t02.silver.customer_history
  ALTER COLUMN customer_account_balance SET MASK meridian_t02.gov.mask_account_balance;

ALTER TABLE meridian_t02.gold.dim_supplier
  ALTER COLUMN supplier_account_balance SET MASK meridian_t02.gov.mask_account_balance;
