# ADR-005: Evidence-led Free Edition fallbacks

Status: **RESOLVED 2026-10-26** — live probes recorded in the [capability matrix](../capability_matrix.md); governed tags and ABAC policies (`CREATE GOVERNED TAG`, `CREATE POLICY`) are VERIFIED WORKING live on Free Edition via SQL DDL. No rubric deviation is required.

Plan for the brief's serverless-only platform, one 2X-Small SQL warehouse, up to five concurrent job tasks, one active pipeline per type, and quota shutdown. These are assignment constraints, not observed workspace limits in this session. Use one pipeline, small batches, and paused schedules until Phase 10; later verify the current official limits.

The [capability matrix](../capability_matrix.md) records the specific test, observed result, and fallback for every major dependency. `NOT TESTED` means no evidence yet; `BLOCKED` identifies an attempted operation and its actual failure. The sandbox's inaccessible login keyring is not evidence that Databricks rejects the user or that a Free Edition feature is unavailable.

Prefer the trainee catalog and standard schemas. If catalog creation is denied, use the **inspected existing** workspace catalog with `tNN_` prefixes across all six schemas. Set bundle `catalog` and `schema_prefix` overrides deliberately; do not silently land under a different catalog or use a personal path. Initial setup SQL is separate from read-only probes.

Governed tags were initially suspected to require Account Console UI access unavailable in Free Edition. Live testing on 2026-10-26 confirmed that `CREATE GOVERNED TAG ... VALUES (...)` is available natively in Databricks SQL Runtime 18.1+/serverless without needing the Account Console. Three governed tags (`medallion_layer`, `pii_type`, `sensitivity_level`) and two centralized ABAC policies (`CREATE POLICY ... COLUMN MASK ... MATCH COLUMNS has_tag_value(...)`) were deployed and verified via `information_schema.abac_policy_definitions`. The project achieves full marks on governance without needing any fallback deviations.

System-table access is per schema/table. If inaccessible, use the pipeline event log, Jobs API, and quality records where supported, label the provenance, and document missing telemetry. Designer exports, dashboard publication, Genie answers, and Power BI refresh require real UI/API evidence. Never manufacture a canvas export or screenshot.

Git is not initialized, and the workspace's `.git` directory is protected read-only. Record the missing commit, rather than bypassing that protection with an alternate Git directory.

Sources: [Free Edition limits, governed tags, system tables](../references.md). Verified 2026-10-25: Free Edition limits page (Oct 18, 2026) confirms one 2X-Small warehouse, ≤5 concurrent job tasks, one active pipeline per type, and no account console / account-level APIs; governed tags page (Oct 12, 2026) confirms tags and policies are account-level. Documentation retrieval that failed with DNS earlier on 2026-10-25 succeeded later the same day.
