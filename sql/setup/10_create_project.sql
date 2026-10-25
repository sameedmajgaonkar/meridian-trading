-- MUTATING setup: run manually, statement by statement, in SQL Editor only after
-- verifying identity. This file is NEVER included in the read-only probe runner.
-- Set :nn from databricks.yml variables.nn.default (currently 02).
-- Run in a fresh SQL session. Requires SQL session variables and IDENTIFIER.
DECLARE OR REPLACE VARIABLE trainee_number STRING DEFAULT :nn;
DECLARE OR REPLACE VARIABLE project_catalog STRING DEFAULT concat('meridian_t', trainee_number);
SELECT assert_true(trainee_number RLIKE '^[0-9]{2}$', 'nn must contain two digits');

CREATE CATALOG IF NOT EXISTS IDENTIFIER(project_catalog)
  COMMENT 'Project Meridian wholesale order-to-revenue';
USE CATALOG IDENTIFIER(project_catalog);
CREATE SCHEMA IF NOT EXISTS landing COMMENT 'Raw file drops';
CREATE SCHEMA IF NOT EXISTS bronze COMMENT 'Append-only raw tables';
CREATE SCHEMA IF NOT EXISTS silver COMMENT 'Validated, conformed tables';
CREATE SCHEMA IF NOT EXISTS gold COMMENT 'Business-ready models and metric views';
CREATE SCHEMA IF NOT EXISTS gov COMMENT 'Security functions and entitlements';
CREATE SCHEMA IF NOT EXISTS ops COMMENT 'Quality results and monitoring';
CREATE VOLUME IF NOT EXISTS landing.raw_files COMMENT 'Landing zone for batch file drops';

-- Phase 2: snapshot version bookkeeping for the customer SCD2 flow.
-- The landing simulator appends one row per batch; the pipeline's
-- WITH VERSION query reads it (see src/pipeline/20_customer_scd2.sql).
CREATE TABLE IF NOT EXISTS ops.customer_snapshot_versions
  (version DATE, landed_on TIMESTAMP);
-- IDENTIFIER() is not supported in SHOW positions — the USE CATALOG above
-- makes plain SHOW SCHEMAS list this catalog's schemas.
SHOW SCHEMAS;
SHOW VOLUMES IN landing;
