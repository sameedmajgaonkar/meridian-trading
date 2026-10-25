-- Project Meridian setup: catalog, schemas, volume.

CREATE CATALOG IF NOT EXISTS meridian_t02
  COMMENT 'Project Meridian wholesale order-to-revenue';
USE CATALOG meridian_t02;
CREATE SCHEMA IF NOT EXISTS landing COMMENT 'Raw file drops';
CREATE SCHEMA IF NOT EXISTS bronze COMMENT 'Append-only raw tables';
CREATE SCHEMA IF NOT EXISTS silver COMMENT 'Validated, conformed tables';
CREATE SCHEMA IF NOT EXISTS gold COMMENT 'Business-ready models and metric views';
CREATE SCHEMA IF NOT EXISTS gov COMMENT 'Security functions and entitlements';
CREATE SCHEMA IF NOT EXISTS ops COMMENT 'Quality results and monitoring';
CREATE VOLUME IF NOT EXISTS landing.raw_files COMMENT 'Landing zone for batch file drops';

SHOW SCHEMAS;
SHOW VOLUMES IN landing;
