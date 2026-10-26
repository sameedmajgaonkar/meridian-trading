-- Zero rows means every sensitive column has an explicit mask or the matching ABAC policy.
-- Run with --param catalog=meridian_t02_dev; information_schema is filtered by your privileges.
WITH expected(schema_name,table_name,column_name,tag_value) AS (
  VALUES ('gold','dim_customer_history','customer_phone','contact'),
    ('gold','dim_customer_history','customer_account_balance','financial'),
    ('gold','dim_suppliers','supplier_account_balance','financial')
),
-- Tagged sensitive columns
sensitive AS (
  SELECT catalog_name,schema_name,table_name,column_name,tag_value
  FROM IDENTIFIER(:catalog || '.information_schema.column_tags')
  WHERE tag_name='pii_type' AND tag_value IN ('contact','financial')
),
-- Columns with a mask
masks AS (
  SELECT * FROM IDENTIFIER(:catalog || '.information_schema.column_masks')
),
-- Columns with a policy
policies AS (
  SELECT * FROM IDENTIFIER(:catalog || '.information_schema.abac_policy_definitions')
  WHERE policy_type='COLUMN_MASK' AND when_condition IS NULL
    AND array_contains(to_principals,'account users') AND coalesce(size(except_principals),0)=0
)
SELECT s.schema_name,s.table_name,s.column_name,s.tag_value AS pii_type
FROM sensitive s LEFT ANTI JOIN masks m
  ON m.table_catalog=s.catalog_name AND m.table_schema=s.schema_name
 AND m.table_name=s.table_name AND m.column_name=s.column_name
WHERE NOT EXISTS (
  SELECT 1 FROM policies p WHERE p.catalog_name=s.catalog_name
    AND (p.on_securable_type='CATALOG'
      OR (p.schema_name=s.schema_name AND p.on_securable_type='SCHEMA')
      OR (p.schema_name=s.schema_name AND p.securable_name=s.table_name AND p.on_securable_type='TABLE'))
    AND exists(p.governed_tags,t -> t.tag_key='pii_type' AND t.tag_value=s.tag_value)
    AND p.policy_name=IF(s.tag_value='contact','mask_contact_pii','mask_financial_pii')
)
UNION ALL
SELECT e.schema_name,e.table_name,e.column_name,'MISSING_PII_TAG' AS pii_type
FROM expected e LEFT ANTI JOIN sensitive s
  ON s.schema_name=e.schema_name AND s.table_name=e.table_name
 AND s.column_name=e.column_name AND s.tag_value=e.tag_value;
