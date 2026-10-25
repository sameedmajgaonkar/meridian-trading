-- Data-driven entitlements for row-level access control.

CREATE TABLE IF NOT EXISTS meridian_t02.gov.entitlements (
  principal STRING NOT NULL,
  region_key BIGINT,
  nation_key BIGINT
);

INSERT INTO meridian_t02.gov.entitlements
SELECT current_user(), 1, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM meridian_t02.gov.entitlements
  WHERE principal = current_user() AND region_key = 1 AND nation_key IS NULL
);

INSERT INTO meridian_t02.gov.entitlements
SELECT current_user(), NULL, 19
WHERE NOT EXISTS (
  SELECT 1 FROM meridian_t02.gov.entitlements
  WHERE principal = current_user() AND region_key IS NULL AND nation_key = 19
);
