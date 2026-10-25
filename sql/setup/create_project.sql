-- Project Meridian setup: catalog, schemas, volume.
-- Run in SQL Editor. Takes :catalog parameter (default 'meridian_t02').
DECLARE OR REPLACE VARIABLE project_catalog STRING DEFAULT :catalog;

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

SHOW SCHEMAS;
SHOW VOLUMES IN landing;
