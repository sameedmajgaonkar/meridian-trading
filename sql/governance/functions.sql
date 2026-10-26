USE CATALOG IDENTIFIER(:catalog);

-- Governance functions for row filtering and column masking.

CREATE TABLE IF NOT EXISTS gov.entitlements (
  principal STRING NOT NULL,
  region_key BIGINT,
  nation_key BIGINT
);

CREATE OR REPLACE FUNCTION gov.region_nation_filter(
  p_region_key BIGINT, p_nation_key BIGINT)
RETURNS BOOLEAN
COMMENT 'Region/nation entitlement row filter'
RETURN is_account_group_member('t02_admins')
    OR EXISTS (SELECT 1 FROM gov.entitlements e
               WHERE e.principal = current_user()
                 AND (e.region_key = p_region_key OR e.nation_key = p_nation_key));

CREATE OR REPLACE FUNCTION gov.mask_customer_phone(phone STRING)
RETURNS STRING
COMMENT 'Partial phone mask; unmasked for pii_readers only'
RETURN CASE WHEN is_account_group_member('t02_pii_readers') THEN phone
            ELSE concat('XXX-XXX-', right(phone, 4)) END;

CREATE OR REPLACE FUNCTION gov.mask_account_balance(amount DECIMAL(18, 2))
RETURNS DECIMAL(18, 2)
COMMENT 'NULL balance; unmasked for pii_readers only'
RETURN CASE WHEN is_account_group_member('t02_pii_readers') THEN amount
            ELSE CAST(NULL AS DECIMAL(18, 2)) END;
