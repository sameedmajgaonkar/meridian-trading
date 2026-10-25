-- MUTATING alternative to 10_create_project.sql, only after a catalog-creation
-- denial is recorded. :workspace_catalog must be the actual inspected catalog.
-- Set :nn from databricks.yml. Never supply samples or system as the catalog.
-- Run statement by statement in a fresh SQL Editor session; no file uploads here.
DECLARE OR REPLACE VARIABLE trainee_number STRING DEFAULT :nn;
DECLARE OR REPLACE VARIABLE target_catalog STRING DEFAULT :workspace_catalog;
SELECT assert_true(trainee_number RLIKE '^[0-9]{2}$', 'nn must contain two digits');
SELECT assert_true(target_catalog RLIKE '^[a-zA-Z_][a-zA-Z0-9_]*$'
  AND lower(target_catalog) NOT IN ('samples', 'system'), 'Use the inspected workspace catalog');
DECLARE OR REPLACE VARIABLE target_prefix STRING DEFAULT concat(target_catalog, '.t', trainee_number, '_');

CREATE SCHEMA IF NOT EXISTS IDENTIFIER(target_prefix || 'landing');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER(target_prefix || 'bronze');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER(target_prefix || 'silver');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER(target_prefix || 'gold');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER(target_prefix || 'gov');
CREATE SCHEMA IF NOT EXISTS IDENTIFIER(target_prefix || 'ops');
CREATE VOLUME IF NOT EXISTS IDENTIFIER(target_prefix || 'landing.raw_files')
  COMMENT 'Landing zone for batch file drops';
-- Verify in Catalog Explorer (runbook 1.2 screenshot). USE CATALOG + plain
-- SHOW works; SHOW ... IN IDENTIFIER() is not a supported position.
USE CATALOG IDENTIFIER(target_catalog);
SHOW SCHEMAS;
-- Then override catalog and schema_prefix in databricks.yml; document the denial.
