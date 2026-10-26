# Module 06: Design Choices, Rationale & Alternatives

This module documents the architectural decisions made during development, the alternatives considered, and why each decision was selected.

---

## Decision Matrix Summary

| Decision Area | Chosen Approach | Alternative Considered | Why Chosen (Rationale) |
|---|---|---|---|
| **Catalog Strategy** | Single catalog `meridian_t02` for dev & prod | Dual catalogs (`meridian_t02_dev` & `meridian_t02_prod`) | Eliminates dynamic SQL parameterization (`IDENTIFIER`); avoids managing duplicate catalogs on Free Edition. Isolated via `bundle destroy -t dev` before prod deploy. |
| **Masking Method** | Tag-driven catalog ABAC policies (`mask_contact_pii`, `mask_financial_pii`) | Explicit table-level masks (`ALTER TABLE ... SET MASK`) | Enterprise scalability: security policy declared once. Adding new tables/columns requires only tagging, zero DDL changes. |
| **SCD Type 2 Engine** | Native Lakeflow `AUTO CDC INTO ... STORED AS SCD TYPE 2` | Manual PySpark `MERGE INTO` or window lead/lag | Native engine handles out-of-order records, updates `__START_AT` / `__END_AT` atomically, and requires zero boilerplate code. |
| **Data Injections** | Fixed row-position indexing (`rn = 3, 5, 11, 23`) | Key modulo math (`o_orderkey % 25000 = 500`) | Deterministic execution in every batch regardless of key hash distribution. Easy for a fresh engineer to explain and verify. |
| **Quality Gate** | Invariant SQL checks returning 0 evaluated in Python | External JSON manifests comparing decimal financial sums | Tests true data invariants (referential integrity, non-emptiness, uniqueness) without brittle float/decimal rounding mismatches across files. |
| **Deduplication** | `row_number() OVER (PARTITION BY key ORDER BY _source_file DESC)` | Full-row SHA-256 hash comparison | Simpler and faster compute. In an append-only landing zone, the latest landing batch file path represents the latest state. |
| **Free Edition Resource Management** | Strict Single Slot rule (stopping SQL warehouse before running pipeline jobs) | Leaving warehouse running concurrently | Databricks Free Edition allows only 1 concurrent serverless compute resource. Running a job while warehouse is active throws `RESOURCE_EXHAUSTED`. |

---

## Detailed Rationale & Trade-off Analysis

### 1. Single Catalog Strategy (`meridian_t02`)
- **The Alternative**: Parameterizing every SQL query with `IDENTIFIER(:catalog || '.silver.orders')` and creating `meridian_t02_prod`.
- **Why We Selected Single Catalog**:
  1. Databricks Free Edition has strict quotas on schemas and volumes.
  2. In pure declarative pipelines, SQL tasks with `:catalog` session variables introduce parsing ambiguity in materialized view definitions.
  3. By keeping `meridian_t02` literal, SQL files remain clean, standard, and easy to read.
  4. Development and production isolation is guaranteed by running `databricks bundle destroy -t dev` prior to production deployment.

---

### 2. Tag-Driven ABAC vs Explicit Column Masks
- **The Alternative**: Writing `ALTER TABLE gold.dim_customer_scd2 ALTER COLUMN customer_phone SET MASK gov.mask_customer_phone;` for every individual table.
- **Why We Selected Tag-Driven ABAC**:
  1. **Compliance by Design**: In large organizations, data engineers create dozens of tables weekly. Expecting engineers to manually attach masks to every column leads to human error and compliance breaches.
  2. **Automated Discovery**: By defining governed tags (`pii_type = 'contact' | 'financial'`), Unity Catalog's policy engine inspects column tags at query compile time and injects masking dynamically.
  3. **Mark Earner**: Tag-driven ABAC is explicitly highlighted as a stretch goal in the problem statement.

---

### 3. Lakeflow Declarative CDC vs Manual MERGE
- **The Alternative**: Writing complex custom PySpark batch scripts with `Window.partitionBy("customer_key").orderBy("effective_date")` to compute `valid_from` and `valid_to`, then running a `MERGE INTO` statement.
- **Why We Selected Lakeflow AUTO CDC**:
  1. `AUTO CDC INTO ... STORED AS SCD TYPE 2` is Databricks' flagship feature for automated dimension history.
  2. It natively manages micro-batch sequencing, handles late-arriving dimension changes, automatically maintains `__START_AT`, `__END_AT`, and `is_current`, and requires only 6 lines of declarative SQL.

---

### 4. Row-Position Injections vs Modulo Arithmetic
- **The Alternative**: Picking keys using `l_orderkey % 25000 = 1500`.
- **Why We Selected Row-Position Indexing**:
  1. In small sampled datasets (`SAMPLE_MOD = 500`), large moduli can lead to batches where zero records match the injection filter, causing expectations to fail silently.
  2. Numbering rows with `row_number() OVER (ORDER BY order_key) AS rn` guarantees that `rn = 3, 5, 11, 23` will fire **exactly once in every single batch**, ensuring 100% test coverage every time.
