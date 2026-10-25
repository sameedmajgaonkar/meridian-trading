-- Select each statement separately in SQL Editor, or use scripts/phase0.py inspect.
-- Metadata only: no source business rows or customer contact values are exported.

-- probe: identity
SELECT current_user() AS querying_user, current_version() AS sql_version;

-- probe: source_schemas
SHOW SCHEMAS IN samples;

-- probe: source_tables
SHOW TABLES IN samples.tpch;

-- probe: orders_columns
DESCRIBE TABLE samples.tpch.orders;

-- probe: lineitem_columns
DESCRIBE TABLE samples.tpch.lineitem;

-- probe: customer_columns
DESCRIBE TABLE samples.tpch.customer;

-- probe: nation_columns
DESCRIBE TABLE samples.tpch.nation;

-- probe: region_columns
DESCRIBE TABLE samples.tpch.region;

-- probe: part_columns
DESCRIBE TABLE samples.tpch.part;

-- probe: supplier_columns
DESCRIBE TABLE samples.tpch.supplier;

-- probe: orders_storage
DESCRIBE DETAIL samples.tpch.orders;

-- probe: lineitem_storage
DESCRIBE DETAIL samples.tpch.lineitem;
