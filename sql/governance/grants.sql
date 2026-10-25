-- Consumer grants for reader roles.

GRANT USE CATALOG ON CATALOG meridian_t02 TO `t02_pii_readers`;
GRANT USE SCHEMA ON SCHEMA meridian_t02.gold TO `t02_pii_readers`;
GRANT SELECT ON SCHEMA meridian_t02.gold TO `t02_pii_readers`;
