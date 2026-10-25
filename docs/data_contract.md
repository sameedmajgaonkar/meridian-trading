# Draft data contract

Status: **observed against the live source 2026-10-25** (inspect + 1995-window profile runs; evidence under `evidence/runs/`). Column names and types below are confirmed by `DESCRIBE TABLE` ×7; code sets are confirmed by the window profile. No writes were made to the source.

## Scope and types

Choose one or two full calendar years by `o_orderdate`, with an inclusive start and exclusive end. **Locked 2026-10-25 per [ADR-001](decisions/adr-001-date-window.md): `1995-01-01` inclusive → `1996-01-01` exclusive** (set in `databricks.yml` as `order_start_date` / `order_end_date`). Include **all** lines belonging to selected orders, even when shipment or receipt falls outside the order year (observed: receipts of 1995 orders extend to 1996-05-30). Do not filter fact lines independently by shipment date. A separate orphan diagnostic uses a clearly labeled shipment-date cohort.

Bronze retains source business values and arrival lineage. Silver casts using explicit, checked conversions; a failed cast is invalid data, not a default zero. Target monetary types below are candidates: observed source precision may require adjustment. Keep financial calculations in fixed-point decimals and round at presentation only.

| Source field(s) | Business field(s) | Candidate Silver/Gold type | Meaning / rule |
|---|---|---|---|
| `orders.o_orderkey`, `lineitem.l_orderkey` | `order_key` | BIGINT | Required; integral key encoded identically in both facts |
| derived from `order_key` | `order_key_hash` | STRING | SHA-256 lowercase hex, 64 characters; audit key retained |
| `l_linenumber` | `line_number` | INT | Required, > 0; unique with order hash |
| `o_custkey`, `c_custkey` | `customer_key` | BIGINT | Required order-to-customer FK |
| `o_orderdate` | `order_date` | DATE | Required; governs project window and historical attribution |
| `o_totalprice` | `order_total_price` | DECIMAL(18,2) | Required, >= 0; header amount, not defined net revenue |
| `o_orderstatus`, `l_linestatus`, `l_returnflag` | `order_status`, `line_status`, `return_flag` | STRING | Preserve source codes; **observed 2026-10-25 inside 1995**: `o_orderstatus` ∈ {O, F, P}, `l_linestatus` ∈ {O, F}, `l_returnflag` ∈ {N, A, R} — see note below |
| `l_partkey`, `p_partkey` | `part_key` | BIGINT | Line FK to part |
| `l_suppkey`, `s_suppkey` | `supplier_key` | BIGINT | Line FK to supplier |
| `l_quantity` | `quantity` | DECIMAL(18,2) | Required, > 0; do not assume integral quantities |
| `l_extendedprice` | `extended_price` | DECIMAL(18,2) | Required, >= 0 |
| `l_discount`, `l_tax` | `discount_rate`, `tax_rate` | DECIMAL(9,6) | Required, between 0 and 1 inclusive |
| `l_shipdate`, `l_commitdate`, `l_receiptdate` | `ship_date`, `commit_date`, `receipt_date` | DATE | Required for this demo's eligible line set; receipt >= ship |
| `c_mktsegment` | `market_segment` | STRING | Required tracked attribute; **observed 2026-10-25**: exactly 5 codes (AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, MACHINERY) |
| `c_nationkey`, `s_nationkey`, `n_nationkey` | role-specific nation keys | BIGINT | Customer and supplier geography stay distinguishable |
| `n_regionkey`, `r_regionkey` | `region_key` | BIGINT | Nation-to-region FK |
| `c_phone` | `customer_phone` | STRING | Contact data; partial mask |
| `c_acctbal`, `s_acctbal` | `customer_account_balance`, `supplier_account_balance` | DECIMAL(18,2) | Financial data; negative balance is allowed; mask to typed NULL |
| `c_name`, `p_name`, `s_name`, `n_name`, `r_name` | descriptive names | STRING | Classify names as well; avoid exposing unneeded contact fields |
| simulator metadata | `snapshot_effective_date` | DATE | Business-effective sequence; not ingestion time |
| CDC interval bounds | `valid_from`, `valid_to` | DATE (normalized) | Inclusive start, exclusive nullable end |
| derived from history | `customer_version_key`, `is_current` | STRING, BOOLEAN | Deterministic customer + effective-start key; current iff end is NULL |

Additional TPC-H attributes remain available in Bronze and are mapped when needed; this is the minimum proposed contract, not an assertion about every source column. Do not promote unused addresses/comments to Gold by default.

## Keys and checks

| Dataset | Grain / key | Required checks |
|---|---|---|
| Orders | `order_key_hash` | Required natural key, unique hash, required valid order date, nonnegative price, valid customer FK, exactly one customer version |
| Lines | `(order_key_hash, line_number)` | Required keys, positive quantity, nonnegative price, discount/tax within range, valid dates/codes, valid part/supplier FKs |
| Customer history | `(customer_key, valid_from)` | Unique version key, non-overlapping intervals, positive interval length, at most one open version, no uncovered included order |
| Nation | `nation_key` | Required/unique; valid `region_key` |
| Region / part / supplier | corresponding natural key | Required/unique; supplier nation FK |

Late delivery (`receipt_date > commit_date`) and returns are valid business events, not data-quality errors. Do not assert receipt must precede commitment. The global null-order-date count belongs in the separate all-time date profile; a window filter cannot detect those excluded NULL dates.

Hash proof compares distinct non-null natural keys with distinct hashes and checks nulls independently. Duplicate natural keys are deduplication problems, not hash collisions. Group by the hash and count distinct natural keys to diagnose any suspected collision.

## Physical-row reconciliation

For each completed input batch, apply validation before deduplication, and deduplicate valid keys using a documented deterministic ordering. Track exact duplicate occurrences separately; conflicting records with the same key must be flagged, not silently chosen by arrival order.

`Bronze physical rows = invalid physical rows + duplicate-discarded physical rows + accepted unique records`.

For valid, deduplicated lines:

`accepted unique lines = resolved lines + pending-header lines + other blocked-reference lines`.

Each record belongs to one disposition; multiple failure reasons are an array on that disposition, not additional copies. Invalid keys are invalid, not pending. Gold also requires a unique customer-history match; a header with invalid history does not make a publishable line. Record transitions so a formerly pending line can be demonstrated before and after resolution. Never equate physical Bronze count with Gold count after deduplication.

## KPI definitions

All measures use the same order-date scope, entitlement scope, and accepted Gold records. Fact amounts are not rounded per line. A zero denominator returns NULL, displayed as “no eligible data,” rather than zero or infinity. After the last batch, the quality gate requires intended pending lines to have resolved before certifying final KPIs; intermediate outputs must expose pending counts.

| KPI | Definition | Grain / denominator |
|---|---|---|
| Net revenue | `SUM(extended_price * (1 - discount_rate))` | Accepted lines, tax excluded; includes returned lines, with no invented refund subtraction |
| Order count | Count of eligible header keys once | Headers; never physical joined rows |
| Average order value | Net revenue / order count | Ratio of aggregate measures over the same scope |
| Delivery days | `SUM(datediff(receipt_date, ship_date)) / eligible_line_count` | Mean line transit days; both dates present and valid |
| Late-delivery rate | Lines with receipt > commit / eligible line count | Line grain; both dates present and valid |
| Return rate | Lines with return flag `R` / lines with an approved return code | Line count, not quantity or order count; **codes R/A/N observed 2026-10-25** (N 3,401,497 / A 570,544 / R 571,251 in 1995 — return rate ≈ 12.6%) |
| Discount given | `SUM(extended_price * discount_rate)` | Accepted lines; currency amount |

These are seven distinct business KPIs. [ADR-003](decisions/adr-003-kpis.md) records the conflict with the generic four-to-six-measure target and proposes preserving all seven package requirements in the metric view.

For line-attribute filters, order count means the count of distinct headers with at least one qualifying line, and AOV uses revenue from those qualifying lines. Such order counts are **not additive** across products or suppliers: an order may appear in several groups. Verify actual metric-view semantics against independent SQL before exposing those breakdowns. Do not fix fan-out with `SUM(DISTINCT order_total_price)`: two real orders may have the same amount.

## Synthetic fixture contract (later phases)

The original data stays read-only. The simulator may create explicitly labeled variants of selected TPC-H records to exercise otherwise unavailable behavior. Keep a manifest of selected keys, batch assignment, injected errors, early lines, delayed headers, and two effective segment changes. At least one customer has a baseline and two changes (three versions), with actual selected orders on the relevant sides of the change boundaries. Pick those keys and dates from `scd_demo_candidates`, not from a guessed source calendar.

### Concrete batch plan (generated 2026-10-25, implemented in `src/landing/`)

| Batch | Order-date shard (end exclusive) | Snapshot effective date | Customer snapshot | Extra content |
|---|---|---|---|---|
| 1 | 1995-01-01 → 1995-05-01 | 1995-01-01 | full selected population | nation/region/part/supplier land once |
| 2 | 1995-05-01 → 1995-09-01 | 1995-07-01 | full, first five seed segments changed | lines of 5 valid batch-3 orders (delayed headers) |
| 3 | 1995-09-01 → 1996-01-01 | 1995-10-01 | full, remaining five changed once + first two again | those 5 headers land; held-back lines resolve |

Deterministic injections (keyed on source values, in `src/landing/injection.py`):
orders `o_orderkey % 150001 = 3` → NULL customer key, `% 200003 = 11` → negative
total price; lineitem `% 175001 = 7` → non-positive quantity, `% 225007 = 9` →
discount > 1, `% 275017 = 13` → exact duplicate row; customer `% 400009 = 17` →
duplicate row. Disposition precedence: a duplicate occurrence counts as a
duplicate even if its content is also invalid; validity is judged for
deduplicated winners only.

Each batch writes `_manifest/batch=N.json` to the volume: shard dates,
effective date, row counts, per-rule injected counts, `expected_valid`
(order count, line count, returns, net revenue, discount given — computed from
the raw source excluding invalid rows) and the segment-change audit trail.
The quality gate reconciles Gold per shard against these manifest numbers.

## Evidence needed to finalize this contract

Save DESCRIBE outputs for all seven sources, observed candidate years, selected-window key/null/FK/code profiles, and candidate customer coverage. Resolve any type/code differences here before Phase 1. Current status: **NOT TESTED remotely**, blocked by the session's Databricks keyring access.

---

## Observed evidence (2026-10-25)

The keyring blocker was a local sandbox issue, not a Databricks denial: with
`DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` exported, the CLI
authenticates (see [capability matrix](capability_matrix.md#identity-cli-and-compute)).
Evidence runs:

| Contract point | Evidence | Result |
|---|---|---|
| Source types ×7 | `20261025T152741Z_inspect_29fe2318` | Keys BIGINT/INT, dates DATE, money DECIMAL(18,2), codes STRING — matches the candidate types above |
| Candidate years | `20261025T152913Z_dates_85622edf` | 1992–1998, ~1.14 M orders/full year, 0 null dates |
| Selected window 1995 | `20261025T153202Z_profile_70cb9460` | 1,136,308 orders = distinct keys = distinct SHA-256 hashes; 4,543,292 unique lines; 0 orphans; 0 FK violations; 0 nulls in scoped keys |
| Code sets | same run + `20261025T153119Z_diag_codes` | Segments ×5; return flags N/A/R; order status O/F/P; line status O/F — with the 1995-06-16 generation boundary documented |
| SCD2 fixture seeds | same profile run | 10 customers with 9–10 active months, 10–14 orders (210556, 738508, 373396, …) |

Type/code differences between the contract and the source: none. The only
cast the contract adds on top of the source is discount/tax
DECIMAL(18,2) → DECIMAL(9,6) (safe narrowing: observed domain is 0–1) and the
derived `order_key_hash` STRING. The contract is final for Phase 1.
