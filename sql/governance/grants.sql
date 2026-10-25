-- Consumer grants for reader roles.
-- dev catalog

GRANT USE CATALOG ON CATALOG meridian_t02 TO `t02_pii_readers`;
GRANT USE SCHEMA ON SCHEMA meridian_t02.gold TO `t02_pii_readers`;
GRANT SELECT ON SCHEMA meridian_t02.gold TO `t02_pii_readers`;
GRANT USE SCHEMA ON SCHEMA meridian_t02.ops TO `t02_pii_readers`;
GRANT SELECT ON TABLE meridian_t02.ops.quarantine_invalid TO `t02_pii_readers`;
