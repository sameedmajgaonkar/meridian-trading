-- Read-only probes. Run separately: a denied schema is evidence for that schema,
-- not evidence that all system tables or all platform features are unavailable.

-- probe: visible_catalogs
SHOW CATALOGS;

-- probe: system_schemas
SHOW SCHEMAS IN system;

-- probe: system_lakeflow_tables
SHOW TABLES IN system.lakeflow;

-- probe: system_query_tables
SHOW TABLES IN system.query;

-- probe: system_billing_tables
SHOW TABLES IN system.billing;

-- probe: system_access_tables
SHOW TABLES IN system.access;
