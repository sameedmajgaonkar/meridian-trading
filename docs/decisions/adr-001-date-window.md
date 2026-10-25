# ADR-001: Choose the order-date window from observed data

Status: **LOCKED 2026-10-25** — one calendar year: inclusive `1995-01-01`,
exclusive `1996-01-01`, stored as `order_start_date` / `order_end_date` in
`databricks.yml`.

Choose one full calendar year inside observed `o_orderdate` coverage. Start with a year that provides roughly 50,000 or more orders (a project heuristic, not a source fact) and enough customers with orders across at least three months to demonstrate two segment transitions. Use two years only if the first choice lacks enough activity. Compare measured counts and quota implications before expanding.

Run metadata inspection first, then explicitly opt into the one-pass all-time order-date aggregation in `sql/setup/01_date_candidates.sql`. Choose an interior calendar year where possible; source minimum and maximum dates alone do not prove year completeness. Verify the chosen year with `02_profile_window.sql`, including segment coverage and candidate customer timelines.

Store the final inclusive start and exclusive end in `databricks.yml`. Apply the window to headers and bring along all their lines, regardless of shipment/receipt year. Land a complete snapshot of the **selected customer population**, not merely customers active in each later batch, so snapshot absence cannot create accidental deletions.

Trade-off: one year limits logical data volume; date predicates do not guarantee physical pruning of the samples storage. Avoid repeated all-time scans. Global row counts and null-date diagnostics must stay labeled separately from the selected project scope.

Evidence to record: source storage estimate, observed first/last dates per year, selected order/line/customer counts, segment codes, demo candidates, and rationale for one versus two years. All are currently NOT TESTED.

Sources: local package sheet (“one or two years”), [Free Edition limits](../references.md#platform-and-setup). Official-page access is unverified in this session.

---

## Observed evidence (2026-10-25, evidence under `evidence/runs/`)

### Per-year coverage (`01_date_candidates.sql`, run `20261025T152913Z_dates_85622edf`)

| Year | First order | Last order | Orders | Null dates |
|---|---|---|---|---|
| 1992 | 1992-01-01 | 1992-12-31 | 1,139,873 | 0 |
| 1993 | 1993-01-01 | 1993-12-31 | 1,138,893 | 0 |
| 1994 | 1994-01-01 | 1994-12-31 | 1,137,944 | 0 |
| 1995 | 1995-01-01 | 1995-12-31 | 1,136,308 | 0 |
| 1996 | 1996-01-01 | 1996-12-31 | 1,141,556 | 0 |
| 1997 | 1997-01-01 | 1997-12-31 | 1,137,325 | 0 |
| 1998 | 1998-01-01 | 1998-08-02 (partial) | 668,101 | 0 |

Every full year clears the ~50k heuristic by a wide margin, so activity alone
cannot pick the year.

### The deciding factor: code-diversity boundary (diagnostic run `20261025T153119Z_diag_codes`)

`samples.tpch` carries classic TPC-H generation semantics with a boundary at
**1995-06-16**:

- Lines shipping after 1995-06-16 are **all `N`** (`l_returnflag`); orders dated
  after it are **all `O`** (`o_orderstatus`).
- Only 1995 contains all three return flags (N 3,401,497 / A 570,544 /
  R 571,251 by ship year) *and* all three order statuses (O 707,328 /
  F 237,791 / P 191,189 by order date) inside one calendar year.
- A 1996–1998 window would make the return-rate KPI identically zero and lose
  order-status diversity; 1992–1994 lack `N`/`O` entirely.

### Selected-year profile (`02_profile_window.sql`, run `20261025T153202Z_profile_70cb9460`)

- Orders: 1,136,308 rows = 1,136,308 distinct `o_orderkey` = 1,136,308 distinct
  SHA-256 hashes (no collisions), 432,892 distinct customers, 0 null keys.
- Lines: 4,543,292 rows, all unique on `(l_orderkey, l_linenumber)`; receipts
  extend to 1996-05-30, so next-year shipments are deliberately included.
- 0 orphan lines (ship-window cohort), 0 orders without customer, 0 FK
  violations across part/supplier/nation/region.
- Market segments: 5 codes, 85,982–87,117 customers each.
- SCD2 demo candidates: 10 customers with 9–10 active months and 10–14 orders
  in 1995 (e.g. `210556`, `738508`, `373396`), enough for two segment changes
  plus a three-version history for one customer.
- Source storage: orders 188.5 MB / 3 files, lineitem 753.8 MB / 10 files
  (Delta) — a one-year slice stays modest for the Free Edition quota.

### Rationale summary

One year (1995) satisfies every requirement: the ≥50k heuristic, ≥3-month
customer activity for SCD2, and — unlike any other single year — non-degenerate
return and status codes. Two years would double ingest volume for no additional
capability, so the two-year fallback is not used.
