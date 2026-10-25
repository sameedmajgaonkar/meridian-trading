-- Bronze: append-only ingestion from the landing volume via Auto Loader.
-- Preserves raw rows as received, adding file lineage and row content hashes.

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.orders AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/orders/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.lineitem AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/lineitem/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.customer AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/customer/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.nation AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/nation/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.region AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/region/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.part AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/part/', format => 'parquet'));

CREATE OR REFRESH STREAMING TABLE ${catalog}.bronze.supplier AS
SELECT *,
  _metadata.file_path AS _source_file,
  CAST(regexp_extract(_metadata.file_path, 'batch=([0-9]+)', 1) AS INT) AS _batch_id,
  sha2(to_json(struct(*)), 256) AS _row_hash
FROM STREAM(read_files('/Volumes/${catalog}/landing/raw_files/supplier/', format => 'parquet'));
