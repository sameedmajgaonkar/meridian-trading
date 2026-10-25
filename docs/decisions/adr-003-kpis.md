# ADR-003: Grain-correct KPI definitions and seven package measures

Status: **DESIGN SELECTED; docs verified 2026-10-25; live one_to_many probe still required in Phase 3**.

Use the definitions and denominator rules in [data_contract.md](../data_contract.md#kpi-definitions). Net revenue excludes tax, includes returned lines without assuming a refund, and does not substitute `o_totalprice`. Delivery days means line transit time from shipment to receipt. Late rate and return rate use line counts. AOV and rates are ratios of aggregate measures, not averages of averages. Empty denominators return NULL.

The package image explicitly lists **seven KPIs** for the metric view. The generic brief/prompt asks for four to six measures. Proposed resolution: expose all seven package KPIs in one view and record the measure-count exception for trainer review; silently dropping discount given would lose a package requirement. This is a proposed rubric deviation, not evidence of trainer acceptance.

Preferred design: header source with a supported `one_to_many` line join, independent aggregation at each fact grain, and many-to-one dimension joins. The prompt claims YAML 1.1 and Runtime 18.1+; current docs and a tiny live view must verify this. A warehouse version string alone does not prove a join feature works.

Verification fixture: two orders, each with header total 100, with two and three lines respectively. Expected order count is 2 and summed header amount is 200, not 5 or 500. `SUM(DISTINCT amount)` would incorrectly return 100. Verify revenue against lines alone and test line-attribute grouping/filtering. Under a line filter, count distinct headers having qualifying lines; counts can overlap across groups.

Fallback if multi-grain metric-view support is absent: two grain-correct views and clearly labeled consumption queries while recording the single-view requirement as unmet. Do not present this fallback as full completion. A flattened header/line join is not acceptable without proven grain-preserving semantics.

Sources: local assignment image, [metric views / feature availability / YAML / TPC-H example](../references.md#modeling-and-history). Verified 2026-10-25: one-to-many joins require YAML spec 1.1 and DBR ≥ 18.1 (metric-view feature availability, Oct 13, 2026); the workspace SQL warehouse is auto-updated (dbsql 2026.39), so a tiny live view probe remains the gate before building the real view.
