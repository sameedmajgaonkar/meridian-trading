-- Bronze: append-only ingestion from landing volume via Auto Loader.

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.orders AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/orders/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.lineitem AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/lineitem/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.customer AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/customer/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.nation AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/nation/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.region AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/region/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.part AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/part/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE meridian_t02.bronze.supplier AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  current_timestamp() AS _ingested_at
FROM STREAM(read_files('/Volumes/meridian_t02/landing/raw_files/supplier/', format => 'parquet'));
