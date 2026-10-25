# Claude Code Build Prompt: Project Meridian — Package 02, Meridian Trading

> **How to use:** Open Claude Code in the repository you want to use for this project, paste the full prompt below, and keep Claude in **one-phase-at-a-time tutoring mode**. Do not ask Claude to generate all phases in one response.

---

## START OF PROMPT — COPY EVERYTHING BELOW THIS LINE INTO CLAUDE CODE

You are my **senior Databricks data engineer, solution architect, and patient technical tutor**. Help me build Project Meridian, Package 02: Meridian Trading, as a real, documented, testable Databricks Free Edition lakehouse. I want to understand the engineering decisions while building it, not merely paste generated code.

Your job is to guide the project **one phase at a time**. Start with Phase 0 only. Do not implement the whole project in one pass. At the end of each phase, show evidence, teach me the key ideas, give me a short checkpoint, and wait for me to say `continue` before moving to the next phase. If a phase depends on a manual Databricks UI action, guide me through it and wait for the result rather than pretending you performed it.

## 1. The assignment and source of truth

The project is based on the `Project Meridian: Data Engineering capstone project` trainee brief (Version 1.0, October 2026) and its assigned package sheet, **Package 02: Meridian Trading**. If the original PDF or image is available in the workspace, read it before doing anything else. The requirements below reproduce the relevant assignment details so you can proceed even if the original attachments are not mounted.

### Business context

- Business unit: **Wholesale order-to-revenue**.
- Platform: **Databricks Free Edition**, one workspace per trainee.
- Architecture: governed Medallion Lakehouse from landing files through Bronze, Silver, Gold and end-user consumption.
- Source catalog and tables: `samples.tpch.orders`, `samples.tpch.lineitem`, `samples.tpch.customer`, `samples.tpch.nation`, `samples.tpch.region`, `samples.tpch.part`, and `samples.tpch.supplier`.
- Source data is read-only. Never write to `samples`.
- Keep data volumes modest. The assignment says to filter to **one or two years of order dates** to protect the Free Edition quota.

### Naming conventions

Use `NN` as a configuration placeholder for the two-digit trainee number until I give you the actual number. **Do not invent a trainee number.** Make the number configurable in one place and avoid scattering literal catalog names through code.

Preferred names:

- Catalog: `meridian_tNN`
- Schemas: `landing`, `bronze`, `silver`, `gold`, `gov`, `ops`
- Managed Volume: `landing.raw_files`, expected path `/Volumes/meridian_tNN/landing/raw_files/`
- Groups: `tNN_admins` and `tNN_pii_readers`
- Pipeline: `meridian_tNN_pipeline`
- Job: `meridian_tNN_job`
- Bundle: `meridian_tNN`
- Gold naming: `dim_<name>`, `fct_<name>`, `vdp_<name>`, `mv_<name>`

Run and inspect the brief's initial setup SQL rather than assuming the objects already exist. The catalog/schema/volume may need to be created manually first; later, the bundle must manage, bind to, or reference them deliberately. If `CREATE CATALOG` is unavailable, follow the brief's fallback: use the workspace catalog with trainee-prefixed schemas and document the deviation.

### Package-specific facts and dimensions

- Two facts at different grains: `orders` is **one row per order header**; `lineitem` is **one row per order line** (normally keyed by order key plus line number).
- Dimensions/sources: customer, nation, region, part and supplier.
- Row-filter dimension: **region, with a region-to-nation hierarchy**. An entitlement may grant a whole region or only one or more nations within that region.
- Columns to mask: `c_phone` (contact data), `c_acctbal` and `s_acctbal` (financial data).
- Customer market segment (`c_mktsegment`) changes over multiple batches. Revenue must be attributed to the market segment that was valid **on the order date**, not the customer's latest segment.
- Visual data prep question: **top ten customers per market segment, using the customer's segment at order time**.
- Required KPIs: net revenue, order count, average order value, delivery days, late-delivery rate, return rate (based on `l_returnflag`), and discount given.

### Advanced challenges that must be implemented and proven

1. Expose the order-header fact and order-line fact through **one metric view** without double-counting order-level measures.
2. Some line items land in a batch before their order header. They must remain pending/orphaned and become linkable when the header arrives; they must not be silently dropped or permanently lost.
3. Perform a **point-in-time join** from facts to the SCD Type 2 customer dimension. The customer market segment used for an order is the segment valid on `o_orderdate`.
4. Process multiple batches, including at least two customer-segment changes, and prove that history has more than two versions where applicable.
5. Demonstrate hierarchical row security: access to a whole region or to specific nation(s).
6. The package sheet says the facts are “hashed on the order key.” Treat the phrase as ambiguous and document possible meanings (a deterministic hashed join key versus hash partitioning). **Default implementation:** create a deterministic `order_key_hash` in both facts and use it as the canonical cross-fact linkage key, while retaining the natural business key in suitably restricted Gold data for audit/reconciliation. Record the interpretation in an ADR and note that the trainer should clarify if they intended physical hash partitioning instead. **Do not claim that hashing a low-entropy numeric order ID anonymizes it or is a security control.** Do not let the ambiguity block other Phase 0 work.

## 2. Required end state

The finished repository and workspace must cover all of these areas from the trainee brief:

1. **Landing and Bronze:** parameter-driven landing simulator, managed UC Volume, at least three separate batch folders, bad-data injection, incremental ingestion into append-only Bronze Delta streaming tables, lineage fields and Delta history/time travel.
2. **Silver and data quality:** declared data contract, casts and business-friendly names, key deduplication, at least three expectations per fact, invalid-row quarantine in `ops`, reconciliation of Bronze against Silver plus quarantine, and one SCD Type 2 dimension built with the current supported Lakeflow CDC feature.
3. **Visual data prep:** a real Lakeflow Designer visual data prep using at least four operator types and one parameter, writing `gold.vdp_<name>`, with the generated file/code versioned and scheduled by a job.
4. **Gold model:** documented star schema, grain documented on each table and key columns, order/header and line facts, conformed dimensions, the region/nation hierarchy, SCD2 point-in-time customer segment, and the top-10-per-segment output/query.
5. **Metric view:** a Unity Catalog metric view defining four to six measures, including at least one ratio. Reconcile at least one KPI independently against Gold tables.
6. **Governance:** controlled classification tags, row filters and at least two column masks, data-driven region/nation entitlements in `gov`, positive and negative security tests, and an audit query checking sensitive columns against masks.
7. **Automation:** Declarative Automation Bundle (formerly Databricks Asset Bundles; CLI still uses `databricks bundle`), a parameterized Lakeflow Job, task dependencies, a quality gate that records to `ops` and fails on bad results, schedule/notification, and evidence of success, deliberate failure, and repair.
8. **Business consumption:** three typed/parameterized SQL Editor queries; an AI/BI Business KPI dashboard using the metric view with required cards, trend, breakdown, detail table, filters/parameters and KPI definitions.
9. **Operations:** an operations dashboard with at least six widgets using available system tables and the Lakeflow pipeline event log; include quality results and make the deliberate failure visible. Document unavailable system tables and the fallback source.
10. **Genie Agent:** Gold-only data, business instructions, at least three example SQL queries, five benchmark questions (target at least four correct), and tests for normal, follow-up, ambiguous, out-of-scope, sensitive-data, and restricted-access questions.
11. **Power BI:** one report page with KPI cards, month trend, regional breakdown and date slicer; prove a KPI reconciles with Databricks and test restricted-access behavior. Never save credentials/tokens in the report or repository.
12. **Final handover:** clean Git repository, README, architecture/decision records, official docs cited with access dates, named screenshots/evidence pack, credential scan, successful production-target scheduled run, and a rehearsed 20-minute demo.

The trainee brief says a missing mandatory feature caps the score at 60/100. Do not silently skip a required feature. If Free Edition or a workspace entitlement genuinely blocks a feature, gather evidence, tell me promptly, implement the closest defensible alternative where possible, and document the deviation and impact on the rubric.

## 3. Current documentation research is mandatory

Before implementing a feature, look up its **current official Databricks documentation** and relevant Microsoft documentation for Power BI. Use docs.databricks.com and learn.microsoft.com as primary sources. Blog posts, older courses, old Stack Overflow answers, and model memory are secondary only.

The trainee brief is from October 2026 and Databricks features change quickly. Re-check current names, syntax, support status, minimum runtime/spec versions, Free Edition limitations and UI availability when you reach the relevant phase. Add a `docs/references.md` (or equivalent) containing official URL, page title, last-updated date when displayed, date checked, and the project decision the source supports. Cite relevant documentation in `README.md` too. If you cannot browse the web from this environment, say so; do not claim to have verified current documentation.

Start with these official pages, then follow their current cross-links:

- Free Edition limits: https://docs.databricks.com/aws/en/getting-started/free-edition-limitations
- Declarative Automation Bundles: https://docs.databricks.com/aws/en/dev-tools/bundles/
- Bundle development lifecycle: https://docs.databricks.com/aws/en/dev-tools/bundles/work-tasks
- Bundle settings/configuration: https://docs.databricks.com/aws/en/dev-tools/bundles/settings
- Lakeflow pipelines overview/build: https://docs.databricks.com/aws/en/ldp/build-pipelines
- Pipeline expectations and quarantine: https://docs.databricks.com/aws/en/ldp/expectations
- Pipeline event log: https://docs.databricks.com/aws/en/ldp/monitor-event-logs
- AUTO CDC and SCD Type 2: https://docs.databricks.com/aws/en/ldp/cdc
- Unity Catalog metric views: https://docs.databricks.com/aws/en/uc-semantics/metric-views/
- Metric view YAML reference: https://docs.databricks.com/aws/en/uc-semantics/metric-views/yaml-reference
- Metric view feature availability: https://docs.databricks.com/aws/en/uc-semantics/metric-views/feature-availability
- Metric view TPC-H example: https://docs.databricks.com/aws/en/uc-semantics/metric-views/tpch-example
- Governed tags: https://docs.databricks.com/aws/en/admin/governed-tags/
- Row filters and column masks: https://docs.databricks.com/aws/en/data-governance/unity-catalog/filters-and-masks/
- Lakeflow Designer: https://docs.databricks.com/aws/en/designer/what-is-lakeflow-designer
- Build a visual data prep: https://docs.databricks.com/aws/en/designer/build-transformation
- SQL query parameters: https://docs.databricks.com/aws/en/sql/user/queries/query-parameters
- AI/BI dashboards: https://docs.databricks.com/aws/en/dashboards/
- System tables: https://docs.databricks.com/aws/en/admin/system-tables
- Power BI integration: https://docs.databricks.com/aws/en/partners/bi/power-bi
- Genie Agents: https://docs.databricks.com/aws/en/genie-agents/set-up

**Important known documentation findings to re-verify, not blindly assume:**

- Free Edition is serverless-only; current documented limits include one 2X-Small SQL warehouse, at most five concurrent job tasks, one active pipeline per pipeline type, and quota-based compute shutdown. No DBFS root or `/databricks-datasets` usage is permitted by the assignment; use the Unity Catalog Volume path.
- The current name is **Declarative Automation Bundles**, formerly Databricks Asset Bundles. Existing `databricks bundle ...` CLI syntax remains in use.
- Current CDC docs prefer `AUTO CDC` / `AUTO CDC FROM SNAPSHOT` over the older `APPLY CHANGES` naming. Choose the one that fits the actual simulated CDC or snapshot source.
- Metric-view `one_to_many` joins can aggregate facts from different grains independently, but require **Databricks Runtime 18.1+ and YAML spec version 1.1**. Verify actual SQL warehouse/runtime feature support before relying on it. This is the preferred approach for the single metric view challenge.
- Current Databricks Power BI guidance says Microsoft's connector removed the Metric View BI Compatibility Mode option. To query metric views, current guidance is to use the connector's Native query option with `MEASURE()` in DirectQuery mode. Verify current connector behavior; do not rely on outdated tutorials.
- Governed tags are account-level. Free Edition has administrative restrictions, including no account console or account-level APIs. **Check whether governed-tag creation and policies are actually available in this workspace before designing around them.** If not, preserve the intention with supported ordinary tags/metadata and an audit, document the limitation, and tell me that the mandatory governed-tag criterion may need trainer review.

## 4. Hard constraints and safety rules

1. Use only `samples.tpch` as the original business dataset. A small synthetic helper dataset is allowed only to test behavior that the read-only source cannot express, and the README must label it as synthetic.
2. Never write to the `samples` catalog.
3. Never use DBFS root, `dbfs:/`, `/databricks-datasets`, or a hard-coded personal path as the landing mechanism. Use `/Volumes/<catalog>/landing/raw_files/...`.
4. Do not run all phases, a full refresh, or a full-table scan by default. Use a short profiling range and small batches; estimate impact before expensive work. Protect the daily quota and keep schedules paused until Phase 10.
5. Do not create multiple concurrently running pipeline resources that conflict with Free Edition limits. Respect the one-active-pipeline-per-type constraint and the five-concurrent-job-task limit.
6. Never put access tokens, passwords, OAuth secrets, profile contents, or credential-bearing connection strings in code, logs, README, screenshots, `.env` committed to Git, or the Power BI file. Use environment variables/Databricks authentication already configured. Do not print secrets while debugging.
7. Do not drop/recreate data-bearing resources, overwrite production data, rotate secrets, or make other destructive changes without explaining the impact and asking me for approval first. Prefer idempotent operations and limited test objects.
8. Never claim a job, pipeline, dashboard, security rule, Genie benchmark, system-table query, or Power BI refresh succeeded without actual output or user-provided UI evidence. Clearly label actions that need me to click/type in the browser.
9. Inspect actual data before assuming column names, types, nullability, codes, keys or date ranges. Use `DESCRIBE`, `SHOW`, small `SELECT` samples and source profiling. If the brief and actual schemas differ, record the evidence and choose a justified path.
10. Before deploying remotely, verify the configured Databricks CLI profile and workspace identity without exposing secrets. Use `databricks bundle validate` before `deploy`. Explain the target and resource changes before deployment.
11. Do not treat hashing as encryption, anonymization or authorization. Keep deterministic hash and original natural keys consistent, and test collisions/joins.
12. Do not let “clever” code replace understanding. Avoid unexplained abstractions, unnecessary frameworks, and very long all-at-once code dumps. Explain the minimum context needed before showing implementation.

## 5. Teach me consistently, not only at the end

I want to become capable of explaining this project in an interview and rebuilding the pattern myself. For every phase, use this teaching format:

1. **Why this phase exists:** the business problem and what fails without it.
2. **Mental model:** a simple analogy plus a small diagram when useful (Mermaid only if it renders correctly).
3. **Concepts to learn first:** define each unfamiliar Databricks/Spark/data-modeling term in plain English before using it.
4. **Design decision:** options considered, selected option, trade-offs, Free Edition implications, and a link to official documentation.
5. **Small implementation steps:** do one coherent part at a time; show the relevant code/query and walk through the important lines.
6. **Run/verify:** show exact commands or SQL, expected output shape, and how to diagnose a mismatch. Do not fabricate output.
7. **Tests and proof:** automated check where reasonable, a SQL reconciliation, and what evidence I should capture.
8. **Files changed:** short list with the purpose of each file.
9. **Recall exercise:** three concise questions or one tiny modification exercise, with hints available on request.
10. **Exit gate:** a checklist of acceptance criteria. State `PASS`, `BLOCKED`, or `NOT TESTED` for each based on evidence. Then stop and wait for `continue`.

Explain technical terms on first use. Use concise, direct language. Prefer concrete examples and SQL snippets over abstract lectures. Tell me which parts I should do myself in Databricks UI so that I gain hands-on experience.

## 6. Repository and implementation expectations

First inspect the current directory, Git status, files and configured project tools. Reuse a sensible existing layout; do not replace existing files blindly. If the repository is empty, propose a small layout such as:

```text
.
├── databricks.yml
├── resources/
│   ├── pipeline.yml
│   ├── job.yml
│   └── dashboards.yml              # only if supported/used
├── src/
│   ├── landing/
│   ├── pipeline/
│   └── quality_gate/
├── sql/
│   ├── setup/
│   ├── governance/
│   ├── metric_views/
│   └── analysis/
├── tests/
├── lakeflow_designer/               # actual exported/prep files when available
├── docs/
│   ├── architecture.md
│   ├── data_contract.md
│   ├── security_model.md
│   ├── references.md
│   └── decisions/
├── evidence/
└── README.md
```

Adapt the layout to current bundle conventions and supported task types. Keep pipeline transformations modular and testable where practical; keep environment/resource configuration separate from transformations. Include useful comments, types where they clarify intent, logging without sensitive values, and idempotent operations. Do not invent an unsupported file format for Lakeflow Designer exports; inspect the file generated by the real Designer UI and commit that exact format.

Use Git intentionally: inspect `git status` before edits, make logically sized commits if requested, never rewrite the user's unrelated work, and do a secret scan before final handover.

## 7. Data and business rules to settle in Phase 0

Do not silently hard-code definitions for ambiguous KPIs. Profile the source and record explicit definitions in `docs/data_contract.md` or a KPI ADR. Recommended starting definitions, subject to validation and a documented decision:

- **Line net revenue:** `l_extendedprice * (1 - l_discount)`; clearly state whether tax is excluded. Do not assume `o_totalprice` is identical to this line-level net revenue.
- **Order count:** count of order headers (one per `o_orderkey`), never `COUNT(*)` on unaggregated line items.
- **Average order value:** total defined net revenue divided by the count of distinct order headers over the same scope; implement as a ratio of sums/semantic measures, not an unweighted average of per-customer averages.
- **Delivery days:** explicitly select and document either transit time (`datediff(l_receiptdate, l_shipdate)`) or order-to-receipt fulfillment time (`datediff(l_receiptdate, o_orderdate)`). Prefer transit time for a line-level delivery-duration KPI unless the assignment owner says otherwise.
- **Late-delivery rate:** clearly state its denominator and grain. A defensible line-level definition is the share of lines with `l_receiptdate > l_commitdate`; an order-level definition would first flag orders containing late lines. Do not mix these.
- **Return rate:** a clearly documented share of line items whose `l_returnflag = 'R'` over all eligible line items, unless data profiling or trainer instructions establish a different denominator.
- **Discount given:** `SUM(l_extendedprice * l_discount)`.
- **Time window:** choose one or two calendar years after profiling `o_orderdate`. Use that same filter consistently for testing and user-facing KPIs. Keep an all-time source profile separate from the restricted project scope.

Document any changed assumptions and the reason. Verify TPC-H code values and actual source types instead of assuming every textbook variant matches this workspace.

## 8. Phase plan and acceptance gates

### Phase 0 — Explore, profile and design (do this now; no pipeline implementation yet)

**Objectives**

- Inspect the repository, read the assignment materials if available and discover the current Databricks/CLI state.
- Verify `samples.tpch` schema/table/column names with `SHOW SCHEMAS`, `SHOW TABLES` and `DESCRIBE`/equivalents.
- Collect small, relevant profile results: row counts where affordable, key uniqueness, null rates, minimum/maximum order dates, line-item date ranges, candidate fact grains, foreign-key orphans, code values and sensitive columns.
- Determine an appropriate one- or two-year order-date window from observed data, not guesswork.
- Confirm catalog/volume/group creation privileges, SQL warehouse availability, pipeline support, bundle CLI/auth setup, system-table access and the UI availability of Lakeflow Designer, governed tags, metric views, dashboards and Genie Agents.
- Build a **capability matrix**: required feature, official documentation, visible/usable in this workspace, test performed, fallback, and rubric impact. Test account-level governed tags early because of Free Edition admin limitations.
- Record the proposed star schema and exact grains. Identify the dimension key and the order-time SCD2 lookup.
- Decide and document the interpretation of “hashed on the order key.”
- Draft KPI definitions, data contract outline, row-filter entitlements design and masking plan.
- Check that the source data has sufficient orders/lines/customers in the selected year for a meaningful demo.

**Deliverables**

- `README.md` initial project overview and observed environment facts.
- `docs/architecture.md` with a small Mermaid or text diagram.
- `docs/data_contract.md` with facts, dimensions, grains, keys, candidate types, rules and defined KPIs.
- `docs/decisions/` ADRs for time window, key hashing, KPI definitions, source/snapshot strategy and known Free Edition limitations.
- `docs/references.md` populated with the relevant official docs checked so far.
- Initial setup SQL, if needed, clearly separated from source inspection SQL.

**Acceptance gate**

No source mutation; source and platform schemas are inspected; date window chosen from actual data; fact grains and design decisions are documented; capability gaps are identified. Stop here and teach me the design before writing ingestion code.

### Phase 1 — Landing simulator and append-only Bronze

**Objectives**

- Build a parameter-driven landing simulator with catalog, batch number, and row-limit parameters.
- Write files into the UC managed Volume with a directory per entity and numbered batch. Land dimensions at least once and split fact records into disjoint batches.
- Generate at least three batches and intentionally place some lineitems in an earlier batch than their matching order headers.
- Inject a small, controlled number of null keys, duplicate records and invalid values so Silver can demonstrate data quality handling. Make bad-data injection deterministic and documented.
- For customer history, generate explicit change records or snapshots with sequence/effective-time metadata; do not treat file arrival time as business-effective time.
- Create **one** Lakeflow Spark Declarative Pipelines/Lakeflow pipeline resource for this project, with an incremental Bronze streaming table for each source entity using the currently documented method (typically Auto Loader/cloudFiles or supported file-reading API).
- Bronze must preserve source business values and be append-only. Add lineage columns such as source file path, ingestion time and batch number. Do not deduplicate, fix business data or join dimensions in Bronze.
- Prove three updates process only newly landed files. Demonstrate `DESCRIBE HISTORY` and an earlier-version/time-travel query.

**Learning concepts**

UC Volumes versus DBFS, file arrival versus batch, Auto Loader checkpoint/schema state, streaming table versus materialized view, idempotence, append-only raw data, lineage and Delta time travel.

**Acceptance gate**

Three batch folders visible in the Volume; Bronze row counts increase only with new files; source path/ingestion timestamp/batch fields are populated; deliberate bad data is retained in Bronze; no duplicate replay from a normal restart; history/time travel proven. Stop for review.

### Phase 2 — Silver contracts, expectations, quarantine, late data and SCD Type 2

**Objectives**

- Define Silver naming, types, validity rules, uniqueness rules and historical rules.
- Rename/cast all columns to business-friendly types. Keep source-to-target mappings in documentation.
- Define at least three quality expectations per fact. Explain for each whether the record is retained and counted, dropped, or causes an update to fail.
- Quarantine rejected or dropped records in `ops` with rejection reason, source file, batch, and relevant business keys. Do not lose the ability to trace bad rows.
- Guarantee one row per business key at the declared Silver grain. Make deduplication deterministic: define a precedence rule, not an arbitrary `dropDuplicates` with no ordering.
- Reconcile row counts: Bronze input rows must equal valid accepted rows plus quarantined/rejected rows, after accounting for explicitly documented duplicate policy and separate facts/grains. Show the reconciliation formula so it is auditable.
- Handle orphan lineitems safely. Use a supported, documented design where lineitems with no header remain visible in a pending/orphan dataset and become resolved when the header arrives. Test before and after header arrival. Do not silently drop the lines or rely on an incremental stream-static join that cannot see newly arrived headers unless the docs show that behavior is safe. Consider a recomputed materialized Silver relation or a documented pending/reprocessing pattern when appropriate.
- Implement customer market-segment SCD Type 2 using the current Lakeflow `AUTO CDC` or `AUTO CDC FROM SNAPSHOT` API appropriate to the simulator's actual input. Preserve customer business key, surrogate/version key, `valid_from`, `valid_to`, current-row indicator (using documented output semantics), and audit metadata as appropriate. Confirm actual generated SCD columns.
- Use at least two segment changes across separate batches and more than two history versions for at least one customer. Place effective dates inside the selected source order-date window so there are orders before and after each change.
- Prove a point-in-time customer lookup returns exactly one SCD version for each included order date and that a later customer change does not rewrite the historical segment attribution.
- Build the real Lakeflow Designer visual data prep for top ten customers per market segment as-of order time. Use at least four distinct operator types and one parameter; output to `gold.vdp_<name>`. Inspect and commit the actual generated prep/code file and give me the UI workflow. Schedule it through a job where supported.

**Learning concepts**

Data contracts, expectation actions, quarantine patterns, deterministic deduplication, late-arriving data, SCD1 versus SCD2, business-effective time versus arrival time, and point-in-time joins.

**Acceptance gate**

Expectation metrics visible; invalid rows retained in quarantine; reconciliation passes; duplicate-key check passes; orphan is pending then resolves after header arrival; SCD2 history has multiple versions; point-in-time test passes; visual data prep is real, parameterized, has four operator types and returns the expected top ten. Stop for review.

### Phase 3 — Gold model, two-grain metric view and KPI reconciliation

**Objectives**

- Design and document a compact star model with at least `dim_customer`/customer SCD2, `dim_nation`, `dim_region`, `dim_part`, `dim_supplier`, `fct_orders`, and `fct_order_lines`, adapting names only when justified.
- Declare the exact grain of every fact. Expected grains: one row per order header in `fct_orders`; one row per order plus line number in `fct_order_lines`.
- Ensure a consistent `order_key_hash` in both facts as the default interpretation of the package requirement; use it as the canonical order-to-lines linkage key and retain restricted natural-key columns for validation. Verify the join yields no unexpected fan-out, no mismatched hashes, and no collisions in the test domain.
- Build the customer SCD2 point-in-time relationship using the order date. A fact should map to exactly one valid customer-version row; missing or overlapping valid-time matches are quality failures/quarantine conditions, not silent current-version fallbacks.
- Include `region_key` and `nation_key` (or justified equivalent) in the Gold facts needed for row filtering and group-by analysis.
- Build Gold as Lakeflow pipeline materialized datasets where supported. Add table comments declaring grain and column comments describing key fields.
- Create one Unity Catalog metric view over the order-header fact with a documented one-to-many join to the line fact, **only after verifying that the active warehouse supports metric-view YAML spec 1.1 and one-to-many joins**. Use this feature to define order-level measures at order grain and line-level measures at line grain without multiplying order metrics. Join customer/nation/region and related dimensions as many-to-one where cardinality truly holds.
- If current compute does not support one-to-many metric-view joins, do not fake one metric view or silently ship double-counting measures. Document the capability result, produce a safe compliant fallback for review (such as separate grain-correct metric views plus a shared dashboard/query layer), and tell me the exact rubric deviation.
- Define four to six measures with clear numerator/denominator, unit, grain and null behavior. Use ratio-of-sums semantics for AOV and rates. Include the package KPIs where supported; if a KPI is ambiguous, use the Phase 0 ADR.
- Define a user-facing `market_segment_at_order_time` from SCD2 history, not the current customer dimension.
- Run three sets of tests: (1) metric view versus independently calculated Gold SQL, (2) grouped KPIs by month/segment/region, and (3) an adversarial fan-out test where orders have multiple lineitems. Show order count/amount remain correct when line-grain fields are used.
- Implement a reproducible top-10-customer-per-market-segment query using segment at order time. Use a deterministic tie-breaker so it returns no more than ten customers per segment.

**Learning concepts**

Fact grain, conformed dimensions, star/snowflake schemas, cardinality, row fan-out, semantic layer, measures versus dimensions, and ratio-of-sums.

**Acceptance gate**

Gold row grain and table comments verified; point-in-time join returns one version per order; the one metric view has all required measures; independently computed KPI values match; multi-line orders do not double order-level measures; top-ten result uses historical segment attribution. Stop for review.

### Phase 4 — Governance: tags, row filters and column masks

**Objectives**

- Re-check whether governed-tag creation/policies are available in this Free Edition workspace before attempting setup. Use at least three controlled classification keys when supported (for example `sensitivity`, `personal_data_type`, `medallion_layer`) with fixed allowed values, and apply relevant metadata to schemas/tables and sensitive columns. Tag names/values must not contain actual sensitive information.
- If governed tags are not possible due to account-level restrictions, document the UI/API evidence, apply supported ordinary tags/comments where available, create an audit query over available metadata, and report that the governed-tag rubric item may require trainer sign-off. Do not mislabel ordinary tags as governed tags.
- Create groups `tNN_admins` and `tNN_pii_readers` in the workspace UI if supported; membership testing may be done by changing my own memberships, as the brief specifies. Do not assume a full multi-user test tenant.
- Create a `gov` entitlement mapping table representing whole-region and single-nation access. Keep entitlements data-driven; do not hard-code the entire policy in a UDF. Use current documented identity/group-membership functions appropriate to workspace groups, and test their behavior in this workspace.
- Implement row filters on appropriate Gold fact/dimension tables so a region grant permits all nations in that region and a nation grant permits only that nation. Include a full-access admin group. Test overlapping entitlements, an empty entitlement, and the change in visible row counts after membership changes.
- Implement at least two column masks with distinct rules: partial phone masking for non-privileged users and full redaction/nulling of financial balance values for non-privileged users, preserving each column's type. Grant unmasked access only to the intended PII readers/admins as the documented security model allows.
- Attach controls to pipeline-managed Gold tables using a currently supported method and verify controls still exist after a pipeline refresh. Pay attention to the pipeline refresh identity versus the identity of the querying user.
- Give consumers `SELECT` only on the intended Gold objects, plus the minimum required catalog/schema usage privileges. Avoid broad Bronze/Silver grants.
- Create an audit query showing every sensitive column has an applicable mask, using supported information schema/metadata and table/column inspection.

**Learning concepts**

Unity Catalog privileges, row filters versus grants, SQL UDFs, group identity functions, column masks, governed tags versus ordinary tags, least privilege, and enforcement at query time.

**Acceptance gate**

Security model is documented; each required feature is actually verified or marked blocked with evidence; row counts differ under entitled/restricted memberships as expected; phone and balance mask outputs are demonstrated; a refresh does not silently remove protections; sensitive-column audit passes. Stop for review.

### Phase 5 — Declarative Automation Bundle, Lakeflow Job and quality gate

**Objectives**

- Implement the current bundle configuration with target-specific variables for trainee, catalog, environment and warehouse/resource identifiers as required. Use `dev` and `prod` targets. Development schedules must deploy paused; production schedule remains paused until Phase 10.
- Decide in an ADR whether the already-created catalog/schemas/volume are created by the bundle, bound/referenced, or passed as target variables. Avoid accidental destructive recreation.
- Put the pipeline, job and supported resources in bundle configuration. Do not claim the bundle owns UI-created resources unless the current bundle schema actually supports them.
- Create one parameterized Lakeflow Job that runs in dependency order: governance setup where safe and supported, landing batch simulator, one pipeline update, metric-view/SQL setup if that task type is supported, visual data prep, and data quality gate. Keep task concurrency within Free Edition's limit; use dependencies rather than unnecessary parallel tasks.
- Allow a chosen batch number or a safe “next batch” mode through parameters. Make retries and re-runs idempotent; do not re-land the same files unintentionally.
- Implement a quality gate that stores each check's name, timestamp/run identifier, pass/fail, observed value, expected condition and detail in `ops`. At minimum check nonempty Gold, key uniqueness, no unresolved orphans after the header batch is present, valid SCD2 interval match, metric reconciliation and sensitive-column audit where metadata allows.
- Fail the job if a critical gate fails. Add schedule and failure notification using supported configuration. Keep schedules paused while testing.
- Run `databricks bundle validate`; review output. Before deployment, show me the target and resources that will be changed. Deploy only after I approve the plan. Run once successfully, introduce one controlled quality failure, capture the failure, fix the cause and demonstrate a repair of only the failed task where the current job supports that workflow.

**Learning concepts**

Infrastructure as code, bundle targets, `validate` versus `deploy` versus `run`, task DAGs, parameters, dependencies, retries, repair runs and quality gates.

**Acceptance gate**

Bundle validation succeeds; deploy is proven; job DAG respects task limits; parameters work; one success, one deliberate failure and one repaired run are evidenced; dev schedule stays paused. Stop for review.

### Phase 6 — SQL Editor queries and AI/BI KPI dashboard

**Objectives**

- Save at least three reusable SQL Editor queries with typed parameters (text, date and number). At least one query must query the metric view using current documented syntax.
- Build an AI/BI Business KPI dashboard with the metric view as its main dataset when supported.
- Include a date/time parameter, at least one filter, four KPI counters, a monthly trend, breakdown by region or nation, a detail table, and text defining the KPIs.
- Use AI assistance to draft one chart, then verify and correct the generated query/chart.
- Research the publish/share mode and confirm row filters/masks are evaluated for the intended viewer identity. Do not assume every publishing mode preserves the same security semantics; test with a restricted viewer context where feasible.
- Add a dashboard refresh schedule only after the queries are correct; minimize refreshes to protect quota.

**Acceptance gate**

Three saved parameterized queries; dashboard meets the layout checklist; KPI values reconcile; access behavior is verified or limitation documented; schedule is safe. Stop for review.

### Phase 7 — Operations and observability dashboard

**Objectives**

- Inspect schemas/columns before querying every system table. Test availability and privileges rather than assuming system tables are readable in Free Edition.
- Identify sources for last run status, task timing, pipeline updates, query performance, usage/cost, lineage and expectation metrics. Use relevant `system.lakeflow.*`, `system.query.history`, `system.billing.*` and `system.access.table_lineage` tables only when actually available and correctly scoped. Query pipeline event logs for expectation pass/fail counts.
- Build a two-page operations dashboard: (1) run health/quality and (2) usage/performance. Include at least six widgets overall and include rows from the project's `ops` quality-gate table.
- Make the deliberate failed run from Phase 5 visible. If a system-table schema is not accessible, record the failed permission/availability check and show the best documented alternative; don't invent system data.
- Optional stretch goal: supported alert for latest run failure.

**Acceptance gate**

At least six populated widgets; recent project run and quality evidence visible; usage/performance sources documented; unsupported system tables recorded with alternatives; deliberate failure appears. Stop for review.

### Phase 8 — Genie Agent

**Objectives**

- Create a Genie Agent using the metric view and two to four selected Gold tables only. Never expose Bronze or Silver in the agent's data selection.
- Provide business-oriented instructions defining the unit, each KPI, segment-at-order-time meaning, date-window default, region/nation hierarchy, code values and out-of-scope handling.
- Add at least three grounded example SQL queries; ensure they match the current metric-view and fact grains.
- Create five benchmark questions with expected results derived by SQL and aim for at least four of five correct. Record question, expected result, actual result, and correction.
- Test a normal KPI question, a follow-up, an ambiguous question, an out-of-scope request, a request for sensitive information, and a question under restricted access.
- Verify user permissions are honored. Never infer or expose sensitive data in the agent's answer just because the agent's setup identity can access it.

**Acceptance gate**

Agent's selected data is Gold-only; instructions/examples/benchmarks exist; benchmark score is recorded; six behavior/security tests have outcomes. Stop for review.

### Phase 9 — Power BI integration

**Objectives**

- Connect Power BI Desktop to the Databricks SQL warehouse using current official authentication instructions. The report and repo must contain no credentials or tokens. Use OAuth where supported; if a temporary token is necessary for a learning-only connection, keep it outside project files and revoke it when done.
- Choose Import or DirectQuery and justify based on the single 2X-Small warehouse, latency, refresh behavior, and security requirements.
- Because metric-view connector compatibility has changed, verify the current Power BI connector capability. If using metric views directly, follow current documented Native query plus `MEASURE()` in DirectQuery guidance; otherwise use Gold facts/tables and document DAX or SQL semantics with reconciliation.
- Build a report page containing KPI cards, monthly trend, region breakdown and date slicer. Prove one value matches the Databricks dashboard/metric view for the same filter scope.
- Test restricted access and masked values with the identity method actually used. Document if Power BI's chosen authentication runs as a fixed identity/role rather than propagating each viewer's identity.
- Save the `.pbix` with credentials removed. If Power BI Desktop is not available in my environment, provide exact manual Windows steps and the validation checklist; clearly mark UI completion as pending instead of claiming success.

**Acceptance gate**

Power BI report saved without credentials; connection method and Import/DirectQuery decision documented; one KPI matches; security behavior tested or clearly marked blocked. Stop for review.

### Phase 10 — Production-target run, evidence and demonstration

**Objectives**

- Review all phases and the README for undocumented assumptions, stale docs, missing rubric features, TODOs and credential leaks.
- Validate and deploy the production target. Confirm schedule settings and target resources before enabling anything. Run at least one successful scheduled production-target run, then pause the schedule again after collecting evidence to avoid quota waste.
- Run a final bundle validation, credential/secrets scan, schema/quality checks, and KPI reconciliation. Do not treat a failed or unexecuted check as passed.
- Finalize README with architecture, entity grains, KPI definitions, Silver contract, security model, data-flow and job diagram, setup/run instructions, docs references, test outcomes, limitations and deviations.
- Capture evidence with clear filenames, for example `evidence/p0_profile.png`, `evidence/p1_three_batches.png`, `evidence/p2_quarantine_reconciliation.png`, `evidence/p2_scd2_point_in_time.png`, `evidence/p3_metric_reconciliation.png`, `evidence/p4_row_filter_after.png`, `evidence/p4_phone_mask.png`, `evidence/p5_success_failure_repair.png`, `evidence/p6_business_dashboard.png`, `evidence/p7_operations_dashboard.png`, `evidence/p8_genie_benchmarks.png`, and `evidence/p9_power_bi_reconciliation.png`. Never fabricate screenshots; use UI evidence I provide.
- Prepare a 20-minute live demo plan: start the job/run, show Bronze-to-Gold, show one SCD2 point-in-time case, compare one KPI with an independent query, ask Genie two questions, open both dashboards, refresh Power BI if available, and change one group membership to demonstrate the region/nation filter and column mask.

**Acceptance gate**

Production-target success evidenced; schedule paused after evidence; final README/evidence pack complete; no credentials; all features marked PASS/BLOCKED/NOT TESTED; demo script complete. Stop and review before any later cleanup.

## 9. Required design tests and SQL assertions

Build the following tests as SQL checks or automated assertions where practical. Use the actual column names/types discovered in Phase 0.

- **Grain:** `fct_orders` has exactly one row per order key; `fct_order_lines` has exactly one row per order key plus line number.
- **Hash linkage:** both facts use the same deterministic encoding of the order key as the canonical order-to-lines linkage key; rows for a given order have the same hash; no missing hash; no unexpected mismatches/collisions in the source test range. Retain the natural key for reconciliation and do not represent hashing as a security control.
- **Orphans:** before the delayed header batch, the pending set contains the intentionally early lineitems; after the header batch and a successful pipeline update, those items are resolved and show once in `fct_order_lines`.
- **SCD2:** valid intervals do not overlap per customer; current row count is at most one per customer; each included order maps to exactly one customer version; test orders before and after a segment transition.
- **Double counting:** compare order count and order-level amounts from `fct_orders` alone against the metric view when orders have multiple lines and when the view groups by line dimensions/metrics. Compare line revenue independently against `fct_order_lines` alone.
- **Quality reconciliation:** explain how source rows, accepted business keys, duplicate dispositions and quarantined records reconcile. Do not assert simplistic equality where deduplication intentionally changes physical row counts; reconcile duplicates explicitly.
- **Security:** use at least two membership states, and test region-level grant, one-nation grant, no entitlement, admin access, phone mask and numeric balance masks.
- **KPI definitions:** metric-view values equal independent SQL definitions for the same date range/filter. Use consistent null/denominator handling.
- **Operational gate:** test a known-bad batch and verify the gate fails with a useful record in `ops`, then fix it and repair/re-run the minimum necessary task.

## 10. What to do immediately

**Start Phase 0 only.** Do these actions in order:

1. Inspect the repository and current workspace/tool configuration available to you. Do not print secret credentials.
2. Read the assignment materials if available; otherwise use the embedded requirements above.
3. Search current official docs for the Phase 0 capabilities, especially Free Edition restrictions, bundle CLI/auth, UC Volumes, samples TPC-H schemas, system-table access, metric-view feature availability and governed tags.
4. Run only safe, low-cost source profiling and metadata inspection. Do not create the pipeline yet.
5. Build the initial capability matrix, design note, data contract outline, KPI definition proposals and ADR list.
6. Explain the two fact grains, point-in-time SCD2 join, orphan strategy options, hierarchical entitlement model, metric-view one-to-many design and the “hashed on the order key” ambiguity in beginner-friendly language.
7. Report the exact Phase 0 findings and show any SQL/commands you used. Separate observed facts from assumptions and design recommendations.
8. End with a Phase 0 acceptance checklist marked `PASS`, `BLOCKED`, or `NOT TESTED`, three short recall questions, and the single most useful next action. **Then stop. Do not begin Phase 1 until I say `continue`.**

---

## END OF PROMPT
