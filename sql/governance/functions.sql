-- Governance functions for row filtering and column masking.
-- Defines access logic used by row filters and centralized ABAC policies.

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.gov.entitlements') (
  principal STRING NOT NULL,
  region_key BIGINT,
  nation_key BIGINT
);

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.gov.region_nation_filter')(
  p_region_key BIGINT, p_nation_key BIGINT)
RETURNS BOOLEAN
COMMENT 'Region/nation entitlement row filter (customer geography)'
RETURN is_account_group_member('t02_admins')
    OR EXISTS (SELECT 1 FROM IDENTIFIER(:catalog || '.gov.entitlements') e
               WHERE e.principal = current_user()
                 AND (e.region_key = p_region_key OR e.nation_key = p_nation_key));

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.gov.mask_customer_phone')(phone STRING)
RETURNS STRING
COMMENT 'Partial phone mask; unmasked for pii_readers only'
RETURN CASE WHEN is_account_group_member('t02_pii_readers') THEN phone
            ELSE concat('XXX-XXX-', right(phone, 4)) END;

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.gov.mask_account_balance')(amount DECIMAL(18, 2))
RETURNS DECIMAL(18, 2)
COMMENT 'Typed NULL for balances; unmasked for pii_readers only'
RETURN CASE WHEN is_account_group_member('t02_pii_readers') THEN amount
            ELSE CAST(NULL AS DECIMAL(18, 2)) END;

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalog || '.gov.supplier_nation_filter')(p_nation_key BIGINT)
RETURNS BOOLEAN
COMMENT 'Nation entitlement row filter for supplier geography'
RETURN is_account_group_member('t02_admins')
    OR EXISTS (SELECT 1 FROM IDENTIFIER(:catalog || '.gov.entitlements') e
               WHERE e.principal = current_user()
                 AND e.nation_key = p_nation_key);
