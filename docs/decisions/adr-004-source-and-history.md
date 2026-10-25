# ADR-004: Complete effective-dated snapshots and recoverable late lines

Status: **DESIGN SELECTED; snapshot API syntax verified against docs (Oct 9, 2026); live CDC test pending in Phase 2**.

The source is static `samples.tpch`; historical customer changes and file disorder must therefore be explicitly labeled synthetic fixtures derived from selected source records. A deterministic manifest will define at least three batches, injected invalid/duplicate records, early lines, delayed headers, and two market-segment transitions for at least one customer.

Prefer AUTO CDC FROM SNAPSHOT because the simulator can provide a **complete snapshot of the same selected customer population** at each effective date. Baseline is effective at the selected window start; two later snapshots change a chosen customer at business dates inside that window. Unchanged customers remain in every snapshot. Do not feed a partial batch as a full snapshot: missing customers could be interpreted as deletes.

Use a supported versioned snapshot source that returns snapshots in increasing business-effective order. Confirm that CDC's generated interval sequence can represent these dates; otherwise map the monotonic snapshot version explicitly to effective dates before the point-in-time join. Never use file-arrival time as the business clock. CDC creates the interval ends. Source snapshots do not supply prebuilt `valid_to` rows as though they were already SCD2 output.

Alternative: explicit change events with AUTO CDC sequenced by effective date. Use this if the current snapshot API cannot express the required sequence deterministically, recording the reason. Either approach must prove three versions, no overlaps, one current version, and exactly one version per included order.

Represent open ends as NULL and join with `order_date >= valid_from AND (order_date < valid_to OR valid_to IS NULL)`. Facts carry the resulting customer version key. Before/at/after boundary examples must prove the half-open rule. Do not resolve errors by falling back to the current customer row.

For late headers, retain all valid deduplicated lines in Silver and recompute resolved and pending sets against current valid headers. A materialized view recalculates its result during updates, so previously unmatched rows can resolve. A stream-static join can leave them permanently unmatched. Save before/after pending keys and ensure each resolves exactly once. History errors and invalid keys have distinct dispositions from missing headers.

Trade-offs: some recomputation in exchange for simpler correctness at modest Free Edition volume; complete snapshots in exchange for clearer history semantics. Future scale may justify change events or a more complex streaming state design.

Sources: [AUTO CDC and pipelines](../references.md#modeling-and-history). Verified 2026-10-25 against the AUTO CDC page (Oct 9, 2026): `AUTO CDC FROM SNAPSHOT` accepts a `FROM SNAPSHOT (query) WITH VERSION (version query)` selector and `STORED AS SCD TYPE 2`, emitting `__START_AT`/`__END_AT`; unchanged keys stay active per snapshot. Two live constraints to design around: (1) the pipeline must be serverless, Pro, or Advanced — Free Edition is serverless-only, which qualifies; (2) **expectations are not supported with `AUTO CDC FROM SNAPSHOT`**, so the customer snapshot is validated (expectations + quarantine) in a preceding dataset and the SCD2 target is checked by post-flow SQL (version counts, overlap tests, exactly-one-version join).
