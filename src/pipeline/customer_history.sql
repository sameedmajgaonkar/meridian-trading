-- Customer history tracked as Slowly Changing Dimension Type 2.
-- Streams customer changes sequenced by effective_date into silver.customer_history.

CREATE OR REFRESH STREAMING TABLE ${catalog}.silver.customer_history;

CREATE FLOW customer_cdc AS AUTO CDC INTO ${catalog}.silver.customer_history
FROM STREAM(${catalog}.silver.customer_changes)
KEYS (customer_key)
SEQUENCE BY effective_date
COLUMNS * EXCEPT (effective_date, _source_file, _batch_id)
STORED AS SCD TYPE 2
TRACK HISTORY ON market_segment;
