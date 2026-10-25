# Proposed security model

Design only. No grants, filters, masks, groups, or governed tags have been created or tested. Exact SQL/API syntax must be checked against current documentation and this workspace before Phase 4.

## Row entitlement model

`gov.entitlements(principal_type, principal_name, region_key, nation_key)` stores either a user identity or a supported group identity. A row with a region and NULL nation grants the whole region. A row with both region and nation grants that nation only, and the nation must belong to the declared region. Both geography keys NULL is invalid, not a wildcard. Several valid grants are combined with OR.

Authorization uses the customer's nation and parent region, including in both facts. Supplier geography is a separate dimension role. Persist the customer geography needed for policy evaluation on each exposed fact so a direct line-table query cannot bypass header protection. Protect customer/nation/region dimensions too; do not infer protection from fact-table joins.

| Identity state | Row visibility | Phone / balances |
|---|---|---|
| `tNN_admins` only | All rows | Still masked |
| `tNN_pii_readers` only, with one-nation entitlement | That nation | Unmasked |
| Region entitlement, no PII membership | All nations in granted region | Masked |
| One-nation entitlement, no PII membership | Granted nation only | Masked |
| No admin membership or entitlement | No business rows | No PII entitlement |

An admin row bypass and a PII mask bypass are independent conditions. Keep principal strings out of dynamic SQL. Select the identity function after inspecting group scope: account-group membership and workspace-local membership are not interchangeable. `current_user()` identifies the querying principal; it does not test group membership.

Workspace ownership/admin privileges can allow policy changes even when query results are filtered. Changing one's own group membership demonstrates query behavior, but does not establish separation from the workspace owner. Record this Free Edition limitation and use a restricted principal if the workspace supports one.

## Column protection and classification

| Source column / target | Classification proposal | Without PII-reader membership |
|---|---|---|
| `c_phone` / `customer_phone` | `contact` | Reveal last four characters only; short values fully masked; NULL remains NULL |
| `c_acctbal` / `customer_account_balance` | `financial` | Typed DECIMAL NULL |
| `s_acctbal` / `supplier_account_balance` | `financial` | Typed DECIMAL NULL |

Masks must preserve declared types. Redacting balances to zero would fabricate a meaningful amount. A public hash of an integer order ID is not a privacy measure. Expose natural keys only to the reconciliation role; table-level SELECT also exposes columns unless a supported column restriction or projection boundary is deliberately used.

Classify exposed names and any other sensitive attributes found in DESCRIBE. Start with a controlled vocabulary such as `public`, `internal`, `contact`, `financial`. Governed tags require a real policy/allowed-values test. Ordinary tags are a documented fallback with weaker enforcement, not evidence that the mandatory governed-tag feature was met.

## Enforcement and evidence plan

1. Inspect group scope and supported membership functions, create the two groups through the supported UI, and record results without credentials.
2. Test entitlements as region, single nation, multiple nations, none, and admin. Compare expected key sets, not just counts.
3. Test PII membership independently from row-admin membership, including typed NULL and short/NULL phone behavior.
4. Apply supported filters/masks to each pipeline-managed Gold object. Verify they survive a normal update, and audit all sensitive Gold columns for a mask.
5. Give consumers only required `USE CATALOG`, `USE SCHEMA`, and governed Gold access. Remove unintended broad grants and check the effective grants; access through an unfiltered alternate object defeats the policy.
6. Repeat through metric views, dashboard viewer identity, Genie, and Power BI restricted refresh. Publishing with embedded owner credentials or importing unmasked data has different security semantics and needs explicit evidence.

The pipeline's execution identity is not the dashboard viewer. Avoid private customer details in screenshots. Gold natural keys, metadata identity exports, and raw probe results are reviewable local evidence, not automatically public artifacts.
