# Items Needing Live Workspace Verification

The following items require live execution on Databricks workspace compute:

- Verify the full flow across all 3 batches after code simplification.
- Demonstrate deliberate gate failure (e.g. inject an unhandled invalid row) and successful repair.
- Verify that row filters and column masks restrict data visibility correctly based on group membership (`t02_admins` and `t02_pii_readers`).
