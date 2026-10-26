USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA bronze;

-- Raw columns are retained; lineage is added without cleaning.
CREATE OR REFRESH STREAMING TABLE bronze.orders_raw
COMMENT 'Grain: one landed orders source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/orders/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE bronze.order_items_raw
COMMENT 'Grain: one landed lineitem source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/lineitem/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE bronze.customers_raw
COMMENT 'Grain: one landed customer source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/customer/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE bronze.nations_raw
COMMENT 'Grain: one landed nation source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/nation/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE bronze.regions_raw
COMMENT 'Grain: one landed region source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/region/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE bronze.parts_raw
COMMENT 'Grain: one landed part source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/part/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE bronze.suppliers_raw
COMMENT 'Grain: one landed supplier source record; append-only.'
AS SELECT *, _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('${meridian.landing_path}/supplier/', format => 'parquet'));
