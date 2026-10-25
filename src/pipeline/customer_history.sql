-- Phase 2 — customer SCD Type 2 with the current supported CDC feature
-- (AUTO CDC FROM SNAPSHOT — ADR-004: complete per-batch snapshots).
-- The version is the snapshot's business-effective DATE, so __START_AT /
-- __END_AT are directly usable for point-in-time joins. The version table
-- ops.customer_snapshot_versions is appended by the landing simulator; the
-- WITH VERSION selector picks versions strictly newer than the last
-- committed one and returns no row when nothing new arrived (documented
-- pattern from the CREATE FLOW reference).
-- LIVE-VERIFIED RUNTIME CONSTRAINTS (2026-10-25): current_snapshot_version()
-- is not resolvable at all, and last_snapshot_version() resolves ONLY inside
-- the WITH VERSION clause. The snapshot query therefore cannot know which
-- version the engine selected — it must simply return the newest landed
-- snapshot (max(version)). That is CORRECT only while at most ONE new
-- version exists per pipeline update (each job run adds exactly one batch:
-- run --batch 1, then 2, then 3; the reset file empties the version table).
-- INVIOLABLE OPERATING RULE: never run a pipeline update that would process
-- two or more pending versions (e.g. the default --batch 3 on a fresh
-- target, or a full refresh with history) — every intermediate version
-- would diff against the newest snapshot and the SCD2 history would be
-- silently wrong except for shape. The quality gate pins the segment-change
-- version counts (scd2_segment_versions_*) and fails the job loudly if this
-- rule is ever violated. (Upgrade: revisit when current_snapshot_version()
-- resolves on this runtime.)
-- Expectations are NOT supported with AUTO CDC FROM SNAPSHOT (docs,
-- verified 2026-10-25): validation happens in silver.customer_snapshot
-- above; history shape is re-checked afterwards by the quality gate.

CREATE OR REFRESH STREAMING TABLE ${catalog}.silver.customer_history;

CREATE FLOW customer_snapshot_flow AS
AUTO CDC INTO ${catalog}.silver.customer_history
FROM SNAPSHOT (
  SELECT customer_key, customer_name, market_segment, customer_phone,
         customer_account_balance, customer_nation_key
  FROM ${catalog}.silver.customer_snapshot
  WHERE snapshot_effective_date =
        (SELECT max(version) FROM ${catalog}.ops.customer_snapshot_versions)
)
WITH VERSION (
  SELECT version
  FROM ${catalog}.ops.customer_snapshot_versions
  WHERE NOT EXISTS (SELECT 1 FROM last_snapshot_version())
     OR version > (SELECT version FROM last_snapshot_version())
  ORDER BY version
  LIMIT 1
)
KEYS (customer_key)
STORED AS SCD TYPE 2
TRACK HISTORY ON market_segment;
