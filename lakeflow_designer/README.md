# Lakeflow Designer: Visual Data Prep

Builds top ten customers per market segment using historical segment at order time.

- **Operators**: Source, Join, SQL, Filter, Aggregate, Sort, Output (7 operator types, exceeds 4+ requirement).
- **Parameters**: `catalog` (target catalog) and `segment` (market segment filter, default `ALL`).
- **Counterpart Python file**: [top_customers.py](top_customers.py) is the active production task in `resources/job.yml`. It performs the point-in-time customer history join, calculates net revenue, computes `DENSE_RANK() OVER (PARTITION BY c_mktsegment ORDER BY net_revenue DESC)`, and writes to `gold.vdp_top_customers` with region row filter attached.
- **Canvas Draft**: [top_customers.draft.designer.ipynb](top_customers.draft.designer.ipynb) contains the visual pipeline draft exported from the workspace.

To validate in UI: open the draft in Databricks Lakeflow Designer, bind parameters `:catalog` and `:segment`, preview output, and export as validated `.designer.ipynb`.
