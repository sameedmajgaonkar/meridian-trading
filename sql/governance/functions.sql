-- Governance functions for row filtering and column masking.
-- Defines access logic used by row filters and centralized ABAC policies.
CREATE OR REPLACE FUNCTION meridian_t02.gov.region_nation_filter(
  region_key BIGINT, nation_key BIGINT)
RETURNS BOOLEAN
COMMENT 'Region/nation entitlement row filter (customer geography)'
RETURN is_member('t02_admins')
    OR is_member('t02_pii_readers')
    OR EXISTS (SELECT 1 FROM meridian_t02.gov.entitlements e
               WHERE e.principal = current_user()
                 AND (e.region_key = region_key OR e.nation_key = nation_key));

CREATE OR REPLACE FUNCTION meridian_t02.gov.mask_customer_phone(phone STRING)
RETURNS STRING
COMMENT 'Partial phone mask; unmasked for pii_readers only'
RETURN CASE WHEN is_member('t02_pii_readers') THEN phone
            ELSE concat('XXX-XXX-', right(phone, 4)) END;

CREATE OR REPLACE FUNCTION meridian_t02.gov.mask_account_balance(amount DECIMAL(18, 2))
RETURNS DECIMAL(18, 2)
COMMENT 'Typed NULL for balances; unmasked for pii_readers only'
RETURN CASE WHEN is_member('t02_pii_readers') THEN amount
            ELSE CAST(NULL AS DECIMAL(18, 2)) END;

-- Dedicated supplier filter: the CREATE MATERIALIZED VIEW ... WITH ROW FILTER
-- ON clause accepts only column names (runtime-verified), so the shared
-- region/nation function cannot receive a NULL region for supplier rows.
CREATE OR REPLACE FUNCTION meridian_t02.gov.supplier_nation_filter(nation_key BIGINT)
RETURNS BOOLEAN
COMMENT 'Nation entitlement row filter for supplier geography'
RETURN is_member('t02_admins')
    OR is_member('t02_pii_readers')
    OR EXISTS (SELECT 1 FROM meridian_t02.gov.entitlements e
               WHERE e.nation_key = nation_key);
