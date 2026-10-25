-- Data-driven entitlements for row-level access control.
-- Region grant = all nations in region; nation grant = single nation; no row = no data.
-- Created by setup and populated by an admin.
CREATE TABLE IF NOT EXISTS meridian_t02.gov.entitlements (
  principal STRING NOT NULL,
  region_key BIGINT,
  nation_key BIGINT
);

-- Demo rows for the signed-in admin (function-level demos; the group bypass
-- already grants full rows). TPC-H region 1 = AMERICA, nation 19 = ROMANIA.
INSERT INTO meridian_t02.gov.entitlements
SELECT current_user(), 1, NULL;

INSERT INTO meridian_t02.gov.entitlements
SELECT current_user(), NULL, 19;

-- To exercise a real restricted principal, insert rows for a non-admin user
-- or service principal, e.g.:
-- INSERT INTO meridian_t02.gov.entitlements SELECT 'analyst@example.com', 1, NULL;

-- Inspection:
SELECT * FROM meridian_t02.gov.entitlements ORDER BY principal, region_key NULLS LAST;
