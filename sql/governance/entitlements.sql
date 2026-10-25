-- Data-driven entitlements for row-level access control.
-- Region grant = all nations in region; nation grant = single nation; no row = no data.

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.gov.entitlements') (
  principal STRING NOT NULL,
  region_key BIGINT,
  nation_key BIGINT
);

INSERT INTO IDENTIFIER(:catalog || '.gov.entitlements')
SELECT current_user(), 1, NULL
WHERE NOT EXISTS (
  SELECT 1 FROM IDENTIFIER(:catalog || '.gov.entitlements')
  WHERE principal = current_user() AND region_key = 1 AND nation_key IS NULL
);

INSERT INTO IDENTIFIER(:catalog || '.gov.entitlements')
SELECT current_user(), NULL, 19
WHERE NOT EXISTS (
  SELECT 1 FROM IDENTIFIER(:catalog || '.gov.entitlements')
  WHERE principal = current_user() AND region_key IS NULL AND nation_key = 19
);
