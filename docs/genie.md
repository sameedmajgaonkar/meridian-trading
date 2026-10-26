# Genie: configure, ask, review and evaluate

The existing **Meridian Wholesale Analyst** answers business questions from governed Gold data. **Genie Code** is the engineering assistant inside SQL/notebooks/Designer; use it to build or review SQL and canvas operators. The business agent does not directly assemble a Windows Power BI report or click Designer nodes.

## Actual configuration and source contract

| Setting | Current value |
|---|---|
| Existing agent/space | `01f1d0bfe1a414f08f3e9d5651d82266` |
| Warehouse | `7c433c4d75a98ff6` |
| Current source catalog | `meridian_t02_dev` |
| Versioned configuration | [meridian.genie.json](../src/genie/meridian.genie.json) |
| Recorded evaluation | `01f1d0de9a73145e8770f95a096e88f6`: DONE, 5/5 correct, zero needing review |

Fresh inspection confirmed the existing Genie still uses development sources. The final dashboards and Power BI SQL use production. Keep the evaluated development context for the recorded demo; a production Genie cutover requires every attachment, example and benchmark SQL to change together and a new evaluation. Do not label the development 5/5 result as production accuracy.

| Attach | Purpose | Grain/relationship |
|---|---|---|
| `gold.mv_trading` | Authoritative seven KPIs | Header/item measures aggregate at their own grains |
| `gold.fct_order_headers` | Order detail and historical attribution | One order |
| `gold.dim_customer_history` | Customer changes and sensitive profile questions | One customer validity interval |
| `gold.vdp_top_customers` | Assigned ranked customer product | Customer and historical segment in global top ten |

Four sources keep context focused. The metric view supplies item KPIs without adding every physical table. A header joins history through `customer_version_key`, not natural customer key alone. Technical columns can be excluded from conversational context; exclusion does not enforce security.

```mermaid
flowchart LR
  Q[Question with scope] --> C[Curated metadata and examples]
  C --> S[Generated SQL]
  S --> U[Unity Catalog permissions, row filters and ABAC]
  U --> R[Permitted results]
  R --> A[Answer, chart, table and inspectable SQL]
```

## Step 1: open and inspect the existing agent

1. In the workspace sidebar choose **Genie** and open **Meridian Wholesale Analyst**. The UI may call it a space or agent; match the ID above.
2. Choose **Configure/Edit**. In General select the project warehouse and keep the title/description focused on the landed 1995 cohort.
3. In **Data**, confirm the four fully qualified development sources above. Remove obsolete legacy table names only when they are actually attached.
4. Expand region, nation and segment columns. Enable entity matching/format assistance selectively where offered. Add useful business synonyms; avoid technical hash/path/batch clutter.
5. Open **Catalog → meridian_t02_dev → gold → mv_trading** in another tab. Inspect field and measure descriptions. Fix shared metric metadata at the source so dashboards and Genie keep one definition.
6. Keep the history version key available for examples and correct joins. A current profile uses `is_current=true`; historical revenue uses `market_segment_at_order_time`.

Capture the source list and metadata fields, including catalog names. Sharing the agent later does not grant underlying warehouse or Gold permissions.

## Step 2: add short global instructions

Under **Instructions → Text/General instructions**, paste:

```text
PURPOSE
Answer wholesale revenue and fulfillment questions for the landed 1995 cohort.
Use mv_trading for the seven KPIs. Monetary amounts are sample units, excluding tax.

TIME AND AMBIGUITY
Default order dates are 1995-01-01 through 1995-12-31.
When best/performance/success omits a KPI, ask the user to choose net revenue,
average order value or fulfillment. Do not run SQL until they answer.
Distinguish current customer segment from segment at order time.

SCOPE AND PRESENTATION
Explain missing data and permission errors. Respect the caller's access.
State dates and filters; display rates as percentages and NULL as unavailable.
Use a useful chart with a compact table and inspectable SQL.
```

Historical defaults avoid empty current-year answers. Explicit ambiguity handling prevents an arbitrary revenue interpretation of “best.” The first recorded ambiguity attempt chose revenue; the corrected instruction's retest asked for a KPI. Security comes from Unity Catalog, not the prompt.

## Step 3: add three reusable SQL examples

Open **SQL queries/examples**. Enter each natural-language question and SQL separately. Run SQL in the project warehouse before saving it. The examples below match the current development agent.

**Question: Show monthly revenue and order value by historical segment.**

```sql
SELECT order_month, market_segment_at_order_time,
  MEASURE(net_revenue) AS net_revenue,
  MEASURE(order_count) AS order_count,
  MEASURE(average_order_value) AS average_order_value
FROM meridian_t02_dev.gold.mv_trading
WHERE order_date >= DATE '1995-01-01' AND order_date < DATE '1996-01-01'
GROUP BY order_month, market_segment_at_order_time
ORDER BY order_month, market_segment_at_order_time;
```

**Question: Compare regional fulfillment.**

```sql
SELECT region_name, MEASURE(delivery_days) AS delivery_days,
  MEASURE(late_delivery_rate) AS late_delivery_rate,
  MEASURE(return_rate) AS return_rate
FROM meridian_t02_dev.gold.mv_trading
GROUP BY region_name
ORDER BY late_delivery_rate DESC, region_name;
```

**Question: Show the customer version used by each order.**

```sql
SELECT o.order_key, o.order_date, o.customer_key,
  h.market_segment, h.valid_from, h.valid_to
FROM meridian_t02_dev.gold.fct_order_headers o
JOIN meridian_t02_dev.gold.dim_customer_history h
  ON o.customer_version_key = h.customer_version_key
ORDER BY o.customer_key, o.order_date LIMIT 30;
```

Add these three questions under **Sample questions** as useful entry points. Keep formulas in the metric source; examples teach query structure and correct history joins.

## Step 4: evaluate five independent benchmarks

Open **Benchmarks**. Enter each question and its expected SQL from [the versioned configuration](../src/genie/meridian.genie.json), using SQL-answer mode where offered. Expected SQL calculates facts independently rather than copying old totals or simply repeating the metric definition.

| Benchmark | Expected calculation |
|---|---|
| Full 1995 net revenue | Sum item net revenue |
| December orders | Count headers in `[1995-12-01,1996-01-01)` |
| Regions ranked by late rate | Sum late flags / item count; region-name tie order |
| Full 1995 return rate | Sum R flags / all valid items |
| Top ten in each historical segment | Customer item sums and per-segment rank; customer-key ties |

1. Execute the expected SQL under the intended identity and scope.
2. Click **Run benchmarks/evaluation**.
3. Inspect every result and generated SQL, then the summary.
4. Capture actual score and any corrections. The recorded development score is 5/5; the assignment requires at least 4/5.
5. Rerun the affected benchmark after a metadata/example correction, and rerun the set after a material source/catalog change.

Benchmark correctness is evidence for those five questions, not a guarantee for arbitrary questions. Preserve the score with its source catalog and configuration.

## Step 5: run all six interaction tests

| Interaction | Copyable question | What to check |
|---|---|---|
| KPI | “Show monthly net revenue by historical segment for 1995.” | Metric source; month sort; historical segment |
| Follow-up | “Limit that to HOUSEHOLD and include order count.” | Same conversation retains date scope |
| Ambiguous | “Which region is best?” | Clarifying KPI question before SQL |
| Out of scope | “What are payroll, advertising costs and next-year forecast?” | Explains missing data; no invented result |
| Sensitive baseline | “Show current customer phones and balances.” | Actual query identity and expected baseline values |
| Restricted | “Show revenue by region and current customer contact details.” | Only entitled geography and permitted sensitive values |

Expand generated SQL for every test. The recorded restricted conversation under nation-0 access returned AFRICA only, 79 headers and 13,409,878.73 sample units; independent SQL also counted 79 headers. The authorized sensitive baseline is not masking proof.

For restricted testing follow [the governance save/restrict/restore sequence](governance.md). Accept results only after fresh SQL reports both project memberships FALSE. Start a new conversation to force fresh queries. Restore original entitlements and both refresh memberships, and wait for TRUE/TRUE before running any pipeline.

## Choose the answer visual

| Question | Visual | Reason |
|---|---|---|
| Monthly revenue | Line + compact table | Chronological movement |
| Region late/return rates | Horizontal percent bars + table | Clear category comparison |
| AOV / order count | Counter or table | One selected KPI/scope |
| Customer versions | Interval table | Exact dates and boundaries |
| Top ten in one segment | Horizontal bars | Readable ranked labels |
| All segment ranks | Table | A customer can appear in several historical segments |

State sample monetary units, selected dates and filters. Do not infer a business cause from a chart alone; decompose revenue into orders/value and state what the source cannot explain.

## Copyable Genie Code build prompt

Paste this into **Genie Code** where the existing agent's configuration/data can be inspected:

```text
Help me configure the existing Meridian Wholesale Analyst, ID
01f1d0bfe1a414f08f3e9d5651d82266, using its current meridian_t02_dev sources.
Use gold.mv_trading for the seven KPIs and attach only fct_order_headers,
dim_customer_history and vdp_top_customers as support.
Inspect actual measure metadata, header/item grains and history version keys.
Tell me which UI field receives each source, short instruction, sample question,
SQL example and benchmark. Draft three examples and five independent SQL expected
answers; execute expected SQL before saving when your tools permit it.
Use a 1995 default scope and ask for a KPI when “best” is ambiguous.
Choose monthly lines, region bars and exact history tables. Show generated SQL.
Report tool/UI limitations honestly. Preserve the existing agent and evaluated
catalog; a production migration needs all identifiers updated and re-evaluation.
```

Review prompt:

```text
Review this answer's SQL using the same identity and filters. Does order_count
count headers once, including headers without retained items? Does return_rate
use all valid items? Is customer segment historical? Compare with independent
Gold SQL and report differences, then make the smallest shared-context correction.
```

The assistant may explain steps when its available tools cannot edit a configuration. Inspect the actual saved fields; a prompt alone does not establish a built agent.

## Evidence and finishing

Capture sources, short instructions, three examples, actual benchmark results, and all six interactions. Save exact SQL/results and observation scope in [live evidence](../evidence/live/README.md). Share with intended consumers only after underlying permissions are ready. The source/configuration and UI evidence are separate deliverables.

See [dashboards](dashboards.md), [Designer](visual_data_prep.md), [Power BI](powerbi.md), [presentation](presentation.md), and [the live ledger](../NEEDS_LIVE_CHECK.md).

Official references: [Genie overview](https://docs.databricks.com/aws/en/genie/), [conversation API](https://docs.databricks.com/aws/en/genie/conversation-api).
