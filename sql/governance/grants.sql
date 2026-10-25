-- Phase 4 — minimal consumer grants (run as admin). Admins keep owner rights;
-- pii_readers get unmasked PII via group membership in the mask/filter UDFs
-- but only SELECT on governed Gold (plus the quarantines for audit context).
-- shortcut: catalog is literal here (manual SQL-editor file).

GRANT USE CATALOG ON CATALOG meridian_t02 TO `t02_pii_readers`;
GRANT USE SCHEMA ON SCHEMA meridian_t02.gold TO `t02_pii_readers`;
GRANT SELECT ON SCHEMA meridian_t02.gold TO `t02_pii_readers`;
GRANT USE SCHEMA ON SCHEMA meridian_t02.ops TO `t02_pii_readers`;
GRANT SELECT ON TABLE meridian_t02.ops.quarantine_invalid TO `t02_pii_readers`;
