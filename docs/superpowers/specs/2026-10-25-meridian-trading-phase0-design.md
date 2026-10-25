# Phase 0 — Explore, Profile & Design — Meridian Trading (NN=02)

> Status: **draft for review** — Phase 0 only. No pipeline / job code yet.
> Variables: `NN=02`, catalog `meridian_t02`, volume `/Volumes/meridian_t02/landing/raw_files/`, groups `t02_admins` / `t02_pii_readers`.

## 1. Why Phase 0 exists

Business problem: wholesale order-to-revenue needs trustworthy KPIs (revenue, AOV, delivery, returns) from two facts at different grains without double-counting, with historical segment attribution and row-level entitlements. Without Phase 0 we would guess the date window, grain, hash meaning, and security model — then rebuild everything when the warehouse or Free Edition proves us wrong. Phase 0 settles those decisions on observed data and documents the fallbacks.

## 2. Mental model (analogy + diagram)

**Analogy:** Bronze is the loading dock (boxes arrive unsorted, nothing thrown away). Silver is the warehouse (boxes opened, bad items quarantined, customer address history filed by valid dates). Gold is the showroom (clean star schema + metric view as the price list that doesn't double-count when you unfold a multi-line order). Governance is the badge reader (region vs nation badge, phone/balance masked).

```mermaid
flowchart LR
  S[samples.tpch\nread-only] --> LS[landing simulator\n/Volumes/meridian_t02/landing/raw_files/{entity}/batch=N]
  LS --> B[Bronze\nappend-only streaming tables\n_source_file,_ingest_ts,_batch_id]
  B --> SV[Silver\ntyped + deduped + quarantine in ops\ncustomer SCD2 via AUTO CDC FROM SNAPSHOT]
  SV --> G[Gold star\nfct_orders 1 row/order\nfct_order_lines 1 row/order+line\norder_key_hash in both]
  G --> MV[Metric View\none view, one_to_many line join\nratio-of-sums measures]
  G --> GOV[gov.entitlements + row filters + column masks]
  MV --> DASH[Dashboards / Genie / Power BI]
```

## 3. Concepts to learn first

- **Medallion (Bronze/Silver/Gold):** progressive refinement. Bronze preserves raw arrival, Silver enforces contract, Gold is business-ready.
- **Streaming table vs materialized view (Lakeflow):** streaming = incremental append via Auto Loader checkpoints; materialized = recomputed on refresh (needed for late-arriving header resolution).
- **Grain:** what one row means. `fct_orders` = one order header; `fct_order_lines` = one order line. Grain drives every COUNT and join.
- **SCD Type 2 + point-in-time join:** customer keeps history rows with `[valid_from, valid_to)` and `is_current`. An order joins to the *one* version where `o_orderdate` falls in that interval.
- **Metric View one_to_many:** lets one view expose order-level and line-level measures without fan-out multiplying order amounts. Requires Runtime 18.1+ / YAML 1.1.
- **Row filter / column mask / governed tag:** filter = predicate on read (region/nation), mask = rewrite of column value (phone/balance), governed tag = account-level classification policy (likely blocked on Free Edition).

## 4. Design decisions

### 4.1 "Hashed on the order key" — ADR-002

Options: (1) deterministic hash as canonical FK, (2) physical hash partitioning, (3) anonymization. **Selected:** (1) `order_key_hash = lower(sha2(cast(o_orderkey as string),256))` stored in both facts and used as the join key. Natural `o_orderkey` retained in restricted Gold columns for audit. Trade-off: extra column + hash collision test needed (practically zero for SHA-256 on ~1.5M keys). Document option 2 as "ask trainer" and explicitly reject 3 (hashing a low-entropy int is not a security control).

### 4.2 Date window — ADR-001

Profile `min/max(o_orderdate)` then choose **one calendar year** inside the observed range (fallback to two years if one year has < ~50k orders or insufficient segment activity). Keeps Free Edition quota safe while leaving enough orders before/after SCD2 changes. A separate all-time profile is kept for reference.

### 4.3 Orphan lineitems (lines before header)

**Selected:** Silver `fct_order_lines` as a **recomputed materialized view** that left-joins line to header on `order_key_hash`. Lines without a header stay in `ops.quarantine_orphans` and become resolved on the next refresh when the header batch lands. Rejected: streaming stream-static join that cannot see future headers (silent drop) and an always-streaming pending table (checkpoint complexity on Free Edition).

### 4.4 SCD2 customer segment

Simulator produces **snapshots with `valid_from` / `valid_to`** plus at least two `c_mktsegment` changes across batches and >2 versions for at least one customer. Silver uses `AUTO CDC FROM SNAPSHOT` (current Lakeflow CDC naming; re-check docs at implementation). Point-in-time predicate is `o_orderdate >= valid_from AND o_orderdate < valid_to` with exactly-one-match check; zero or >1 matches are quarantine/fail, not silent fallback to current.

### 4.5 Grain & hash linkage

Declared grains above; hash column is part of PK. Verification: `count(*) vs count(distinct order_key_hash)` on orders, `group by order_key_hash, line_number` uniqueness on lines, join fan-out test on multi-line orders.

### 4.6 Metric view

Only after verifying warehouse supports YAML 1.1 + `one_to_many`. One view over `fct_orders` with `one_to_many` to `fct_order_lines`, `many_to_one` to dims. Measures 4–6, ratio-of-sums for AOV/rates. Fallback if unsupported: two grain-correct views + dashboard note + documented rubric deviation (do not fake one view or ship double-counting).

### 4.7 Governance

`gov.entitlements(principal, region_key, nation_key)` data-driven. Row filter UDF uses `is_member('t02_admins')` / `is_member('t02_pii_readers')` where the workspace's identity function is available (re-check: `current_user()` vs `is_member`). Region grant = all nations in region; nation grant = single nation; empty = no rows; admin = full. Masks: `c_phone` partial (`***-***-1234` style, type-preserving), `c_acctbal/s_acctbal` full redaction. Attach via supported method to pipeline-managed Gold tables and re-verify after refresh. `SELECT` only on Gold.

### 4.8 Free Edition implications

- Serverless-only, one 2X-Small warehouse, 5 concurrent job tasks, 1 active pipeline per type → one pipeline resource, DAG respects concurrency.
- Governed tags: expect **BLOCKED** (account-level API); fallback = ordinary tags + audit query + deviation note.
- Schedules paused until Phase 10; batch sizes small; no full scans by default.

## 5. Small implementation steps (Phase 0 only)

1. Inspect workspace: `auth profiles`, `current-user me --profile sameed-dbx`, `warehouses list`.
2. Inspect source: `SHOW SCHEMAS IN samples`, `SHOW TABLES IN samples.tpch`, `DESCRIBE` each table.
3. Profile: row counts (cheap), `min/max(o_orderdate)`, `count(distinct o_orderkey)`, line-item date vs order date, key uniqueness, FK orphans, `distinct c_mktsegment / l_returnflag / l_linestatus`, sensitive columns.
4. Decide date window from profile; write ADRs.
5. Build capability matrix (table below) with live probes.
6. Draft `data_contract.md`, `architecture.md`, `references.md`.

## 6. Run / verify (exact probes to run in SQL warehouse)

All with `--profile sameed-dbx` via `databricks experimental aitools tools query` or SQL Editor:

```sql
-- 1. Catalog / schemas
SHOW SCHEMAS IN samples;
SHOW TABLES IN samples.tpch;

-- 2. Describe (repeat per table)
DESCRIBE TABLE samples.tpch.orders;
DESCRIBE TABLE samples.tpch.lineitem;

-- 3. Date window
SELECT min(o_orderdate), max(o_orderdate), count(*) FROM samples.tpch.orders;
SELECT min(l_shipdate), max(l_receiptdate) FROM samples.tpch.lineitem;

-- 4. Grain & volume
SELECT count(*) AS orders, count(DISTINCT o_orderkey) AS distinct_keys FROM samples.tpch.orders;
SELECT count(*) AS lines FROM samples.tpch.lineitem;

-- 5. Orphan check
SELECT count(*) FROM samples.tpch.lineitem l LEFT ANTI JOIN samples.tpch.orders o ON l.l_orderkey = o.o_orderkey;

-- 6. Codes & SCD2 probe
SELECT c_mktsegment, count(*) FROM samples.tpch.customer GROUP BY 1;
SELECT l_returnflag, count(*) FROM samples.tpch.lineitem GROUP BY 1;
```

Expected: no orphans in source (synthetic orphans come from our landing simulator), 5 segments, return flags `R/A/N`.
Diagnose: if counts look off vs TPC-H scale factor, note SF in data contract and keep window small.

## 7. Tests and proof (Phase 0 exit evidence)

- Screenshots/exports: `SHOW` results, profile SELECT outputs, warehouse version, pipeline/Designer/Genie/tag UI availability.
- SQL reconciliations: grain counts as above.
- File evidence: `evidence/p0_profile.png` (profile query), `evidence/p0_capability_matrix.png` (UI checks).

## 8. Files changed (Phase 0)

- `docs/superpowers/specs/2026-10-25-meridian-trading-phase0-design.md` — this spec
- `README.md` — project overview + env facts
- `docs/architecture.md` — diagram + component table
- `docs/data_contract.md` — grains, keys, types, rules, KPIs
- `docs/references.md` — official doc cites with checked dates
- `docs/decisions/adr-00N-*.md` — five ADRs
- `sql/setup/00_inspect_samples.sql` + `sql/setup/01_profile.sql` — inspect/profile SQL
- `databricks.yml` — placeholder bundle with `nn=02` variable

## 9. Recall exercise (hints on request)

1. Why must `fct_order_lines` be a materialized (recomputed) dataset rather than a pure streaming append if we want orphans to resolve?
2. Write the point-in-time join predicate for `fct_orders → dim_customer_scd2` and explain what happens when it returns 0 or 2 rows.
3. An order has 4 lines and `o_totalprice=1000`. Why does `COUNT(*)` on the joined view give 4, and what should `order_count` return?

## 10. Exit gate — Phase 0

| Criterion | Status |
|---|---|
| Source not mutated (samples read-only) | PASS — probes were SHOW/DESCRIBE/SELECT only; live evidence 2026-10-25 |
| Schemas/tables/columns inspected (SHOW/DESCRIBE) | PASS — 6 schemas, 8 tpch tables, DESCRIBE ×7 + DETAIL ×2 (`evidence/runs/20261025T152741Z_inspect_29fe2318`) |
| Date window chosen from observed data | PASS — **LOCKED: 1995-01-01 → 1996-01-01** ([ADR-001](../decisions/adr-001-date-window.md), code-diversity boundary rationale; stored in `databricks.yml`) |
| Fact grains & keys documented | PASS (drafted) + verified on source (1,136,308 = distinct keys = distinct hashes; 4,543,292 unique line keys) |
| Hash interpretation ADR filed | PASS (drafted) + collision check passed on live source |
| KPI definitions ADR filed | PASS (drafted); return-rate codes R/A/N now observed, non-degenerate in 1995 |
| Capability matrix built with live checks | PARTIAL PASS — SQL probes live (`docs/capability_matrix.md`); governed-tag/Designer/Genie UI probes pending |
| No pipeline/job created yet | PASS |
| Screenshots in `evidence/p0_*.png` | NOT TESTED — manual UI captures pending |

> Next action: capture the pending UI screenshots (`p0_profile.png`,
> `p0_capability_matrix.png`, governed-tag UI check), then start Phase 1 —
> `CREATE CATALOG meridian_t02` probe (catalog list shows only
> samples/system/workspace), volume, and the landing simulator design.

