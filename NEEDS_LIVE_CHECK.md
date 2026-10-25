# Items Needing Live Workspace Verification

The following items require live execution on the Databricks workspace compute:

- Dev bundle deploy and end-to-end `bundle run` with new task order and parameters.
- Landing simulation batches: verify small batches (~700 orders, ~3k lines), non-zero injection counts, `_SUCCESS` written to volume, and `--batch 1` rerun is a no-op.
- Single pipeline update processing all 3 batches at once vs 3 progressive updates yielding identical SCD2 history (2 customers with 3 versions).
- Governed row filter and mask enforcement on Gold tables: execute `sql/governance/restricted_probe.sql` as restricted principal, verifying AMERICA-only rows, masked phone (`XXX-XXX-####`), and `NULL` account balances.
