-- Governed tags: a controlled vocabulary. Each tag only accepts the values listed here.
-- Run once, by hand. Tags are account-level, not per catalog.
CREATE GOVERNED TAG sensitivity_level
  DESCRIPTION 'How sensitive the data is'
  VALUES ('public', 'internal', 'confidential', 'restricted');

CREATE GOVERNED TAG pii_type
  DESCRIPTION 'Kind of personal or financial data in a column'
  VALUES ('contact', 'financial', 'government_id', 'none');

CREATE GOVERNED TAG medallion_layer
  DESCRIPTION 'Which medallion layer a schema belongs to'
  VALUES ('landing', 'bronze', 'silver', 'gold');
