USE CATALOG IDENTIFIER(:catalog);

-- Data-driven entitlements for row-level access control.
-- Run after the first job run; the table is created by functions.sql.

INSERT INTO gov.entitlements
SELECT current_user(), 1, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM gov.entitlements
  WHERE principal = current_user() AND region_key = 1 AND nation_key IS NULL
);

INSERT INTO gov.entitlements
SELECT current_user(), NULL, 19
WHERE NOT EXISTS (
  SELECT 1 FROM gov.entitlements
  WHERE principal = current_user() AND region_key IS NULL AND nation_key = 19
);
