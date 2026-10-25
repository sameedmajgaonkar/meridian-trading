# ADR-006 — Bundle owns pipeline and job; setup SQL owns UC data objects

Date: 2026-10-25 · Status: accepted

## Context

The bundle needs the catalog/schemas/volume to exist, and the brief requires
one pipeline resource + one job. Everything could be declared as bundle
resources (DAB supports schemas/volumes), but `bundle destroy` then becomes a
data-destruction command, and full pipeline refreshes already have the power
to recreate managed tables (losing attached row filters/masks).

## Decision

- The bundle manages exactly two resources: `meridian_t02_pipeline` and
  `meridian_t02_job` (plus their source files).
- `meridian_t02` catalog, the six schemas, `landing.raw_files`, and
  `ops.customer_snapshot_versions` are created ONCE by
  `sql/setup/10_create_project.sql` (fallback 11) and referenced, never
  managed, by the bundle.
- Governance SQL (30–34) attaches policies; it is re-applied manually after a
  pipeline FULL REFRESH (a refresh can drop/recreate pipeline-managed tables
  and lose attached policies).

## Consequences

- `bundle destroy` removes only the pipeline and job definitions; data
  survives. Deletion of data is an explicit SQL decision, not a deploy flag.
- First deploy requires the setup SQL to have run (job tasks reference
  catalog/schemas/volume).
- The workspace-catalog fallback needs `catalog` + `schema_prefix` variable
  changes; the pipeline picks them up via its configuration parameters.
