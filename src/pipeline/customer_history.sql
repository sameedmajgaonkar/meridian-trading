-- Customer history tracked as Slowly Changing Dimension Type 2.

CREATE OR REFRESH STREAMING TABLE meridian_t02.silver.customer_history;

CREATE FLOW customer_cdc AS AUTO CDC INTO meridian_t02.silver.customer_history
FROM STREAM(meridian_t02.silver.customer_changes)
KEYS (customer_key)
SEQUENCE BY effective_date
COLUMNS * EXCEPT (effective_date, _source_file, _batch_id)
STORED AS SCD TYPE 2
TRACK HISTORY ON market_segment;
