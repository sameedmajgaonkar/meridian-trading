-- Applies governed tags, schema tags, column tags, and ABAC masking policies.

USE CATALOG meridian_t02;

-- 1. Governed Tag Definitions
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
ALTER SCHEMA landing SET TAGS ('medallion_layer' = 'landing');
ALTER SCHEMA bronze SET TAGS ('medallion_layer' = 'bronze');
ALTER SCHEMA silver SET TAGS ('medallion_layer' = 'silver');
ALTER SCHEMA gold SET TAGS ('medallion_layer' = 'gold');

-- 3. Apply Governed Classification Tags to Sensitive Columns
ALTER TABLE gold.dim_customer_scd2
  ALTER COLUMN customer_phone SET TAGS ('pii_type' = 'contact', 'sensitivity_level' = 'confidential');

ALTER TABLE gold.dim_customer_scd2
  ALTER COLUMN customer_account_balance SET TAGS ('pii_type' = 'financial', 'sensitivity_level' = 'restricted');

ALTER TABLE gold.dim_supplier
  ALTER COLUMN supplier_account_balance SET TAGS ('pii_type' = 'financial', 'sensitivity_level' = 'restricted');

ALTER TABLE silver.customer_history
  ALTER COLUMN customer_phone SET TAGS ('pii_type' = 'contact', 'sensitivity_level' = 'confidential');

ALTER TABLE silver.customer_history
  ALTER COLUMN customer_account_balance SET TAGS ('pii_type' = 'financial', 'sensitivity_level' = 'restricted');

-- 4. Centralized ABAC Column Mask Policies
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
