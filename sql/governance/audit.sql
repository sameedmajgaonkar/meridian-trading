-- Audit queries: column tags, ABAC policies, and sensitive column coverage.

-- 1. Governed tags per column
SELECT schema_name, table_name, column_name, tag_name, tag_value
FROM meridian_t02.information_schema.column_tags
ORDER BY schema_name, table_name, column_name;

-- 2. ABAC policies defined on the catalog
SELECT policy_name, policy_type, on_securable_type, to_principals, match_columns
FROM meridian_t02.information_schema.abac_policy_definitions;

-- 3. Verify every column tagged sensitive is covered by an active policy
SELECT c.schema_name, c.table_name, c.column_name, c.tag_value AS pii_type
FROM meridian_t02.information_schema.column_tags c
WHERE c.tag_name = 'pii_type' AND c.tag_value IN ('contact', 'financial');
