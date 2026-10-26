"""Evaluate invariants, persist diagnostics, then fail the task when necessary."""
import argparse
import re
from datetime import datetime, timezone

CHECKS = [
    # 1. Gold table non-emptiness
    ("orders_nonempty", "SELECT IF(count(*) > 0,0,1) FROM {c}.gold.fct_order_headers"),
    ("items_nonempty", "SELECT IF(count(*) > 0,0,1) FROM {c}.gold.fct_order_items"),

    # 2. Row reconciliation across Bronze, Silver, Quarantine, and Gold
    ("orders_accounted", "SELECT abs((SELECT count(*) FROM {c}.bronze.orders_raw) - (SELECT count(*) FROM {c}.silver.order_headers) - (SELECT count(*) FROM {c}.ops.quarantine_records WHERE entity='orders'))"),
    ("items_accounted", "SELECT abs((SELECT count(*) FROM {c}.bronze.order_items_raw) - (SELECT count(*) FROM {c}.silver.order_items) - (SELECT count(*) FROM {c}.ops.quarantine_records WHERE entity='lineitem' AND stage IN ('validation','duplicate')))"),
    ("gold_headers_complete", "SELECT abs((SELECT count(*) FROM {c}.silver.order_headers) - (SELECT count(*) FROM {c}.gold.fct_order_headers))"),
    ("gold_items_accounted", "SELECT abs((SELECT count(*) FROM {c}.silver.order_items) - (SELECT count(*) FROM {c}.gold.fct_order_items) - (SELECT count(*) FROM {c}.ops.pending_order_items) - (SELECT count(*) FROM {c}.ops.quarantine_records WHERE stage='parent'))"),

    # 3. Primary key uniqueness
    ("orders_unique", "SELECT count(*) FROM (SELECT order_key FROM {c}.gold.fct_order_headers GROUP BY order_key HAVING count(*)<>1)"),
    ("items_unique", "SELECT count(*) FROM (SELECT order_key,line_number FROM {c}.gold.fct_order_items GROUP BY order_key,line_number HAVING count(*)<>1)"),

    # 4. Customer SCD Type 2 validity, non-overlapping intervals, and history period coverage
    ("customer_versions_valid", "SELECT count(*) FROM {c}.gold.fct_order_headers o LEFT JOIN {c}.silver.customer_versions h ON o.customer_key=h.customer_key AND o.order_date>=h.__START_AT AND (h.__END_AT IS NULL OR o.order_date<h.__END_AT) WHERE h.customer_key IS NULL"),
    ("customer_intervals_disjoint", "SELECT count(*) FROM (SELECT customer_key,__START_AT,__END_AT,lead(__START_AT) OVER (PARTITION BY customer_key ORDER BY __START_AT) AS next_start FROM {c}.silver.customer_versions) WHERE next_start IS NOT NULL AND (__END_AT IS NULL OR __END_AT>next_start)"),
    ("one_open_customer_version", "SELECT count(*) FROM (SELECT customer_key,count_if(__END_AT IS NULL) AS open_versions FROM {c}.silver.customer_versions GROUP BY customer_key) WHERE open_versions<>1"),
    ("three_versions_demonstrated", "SELECT IF({b}=3,abs(count(*)-2),0) FROM (SELECT customer_key FROM {c}.silver.customer_versions GROUP BY customer_key HAVING count(*)=3 AND count(DISTINCT market_segment)=3)"),
    ("history_periods_used", "SELECT IF({b}=3,count(*),0) FROM (SELECT customer_key FROM {c}.gold.fct_order_headers WHERE customer_key IN (SELECT customer_key FROM {c}.silver.customer_versions GROUP BY customer_key HAVING count(*)=3) GROUP BY customer_key HAVING count(DISTINCT customer_version_key)<>3)"),

    # 5. Delayed headers: batch 2 pending lines, batch 3 resolution
    ("early_items_pending", "SELECT IF({b}=2 AND count(*)=0,1,0) FROM {c}.ops.pending_order_items"),
    ("pending_cleared", "SELECT IF({b}=3,count(*),0) FROM {c}.ops.pending_order_items"),

    # 6. Referential integrity to dimensions
    ("parts_present", "SELECT count(*) FROM {c}.gold.fct_order_items l LEFT ANTI JOIN {c}.gold.dim_parts p ON l.part_key=p.part_key"),
    ("suppliers_present", "SELECT count(*) FROM {c}.gold.fct_order_items l LEFT ANTI JOIN {c}.gold.dim_suppliers s ON l.supplier_key=s.supplier_key"),

    # 7. Lakeflow Designer / Top Customers ranking invariants
    ("top_customers_valid", "SELECT count(*) FROM (SELECT market_segment_at_order_time,count(*) n,count(DISTINCT customer_key) customers,max(rank_in_segment) rank FROM {c}.gold.vdp_top_customers GROUP BY market_segment_at_order_time) WHERE n>10 OR customers<>n OR rank<>n"),

    # 8. Metric View vs. fact table exact mathematical reconciliation
    ("all_metrics_reconcile", """WITH m AS (
      SELECT MEASURE(net_revenue) revenue,MEASURE(order_count) orders,MEASURE(average_order_value) aov,
        MEASURE(delivery_days) days,MEASURE(late_delivery_rate) late,MEASURE(return_rate) returns,
        MEASURE(discount_given) discount FROM {c}.gold.mv_trading
    ), l AS (SELECT sum(net_revenue) revenue,count(*) lines,sum(transit_days) days,
      sum(is_late) late,sum(is_returned) returns,sum(discount_amount) discount FROM {c}.gold.fct_order_items),
    o AS (SELECT count(*) orders FROM {c}.gold.fct_order_headers)
    SELECT IF(abs(m.revenue-l.revenue)<=0.01 AND m.orders=o.orders
      AND abs(m.aov-try_divide(l.revenue,o.orders))<0.000001
      AND abs(m.days-try_divide(l.days,l.lines))<0.000001
      AND abs(m.late-try_divide(l.late,l.lines))<0.000001
      AND abs(m.returns-try_divide(l.returns,l.lines))<0.000001
      AND abs(m.discount-l.discount)<=0.01,0,1) FROM m CROSS JOIN l CROSS JOIN o"""),
]


def evaluate_checks(spark, checks, catalog, batch):
    results = []
    for name, sql in checks:
        try:
            value = spark.sql(sql.format(c=catalog, b=batch)).first()[0]
            if value is None:
                raise ValueError("Check returned NULL")
            results.append((name, "PASSED" if value == 0 else "FAILED", str(value), ""))
        except Exception as error:
            results.append((name, "ERROR", None, str(error)[:1000]))
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--run-id", default="manual")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", args.catalog):
        parser.error("Invalid catalog identifier")
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.getOrCreate()
    catalog = args.catalog
    batch = spark.sql(f"SELECT max(_batch_id) FROM {catalog}.bronze.orders_raw").first()[0]
    if batch not in (1, 2, 3):
        raise RuntimeError("No successfully ingested batch")
    table = f"{catalog}.ops.quality_gate"
    schema = "checked_on TIMESTAMP,batch INT,check_name STRING,status STRING,value STRING,detail STRING,run_id STRING"
    spark.sql(f"CREATE TABLE IF NOT EXISTS {table} ({schema})")
    results = evaluate_checks(spark, CHECKS, catalog, batch)
    now = datetime.now(timezone.utc)
    rows = [(now, batch, name, status, value, detail, args.run_id) for name, status, value, detail in results]
    spark.createDataFrame(rows, schema).write.mode("append").saveAsTable(table)
    if any(status != "PASSED" for _, status, _, _ in results):
        raise RuntimeError(f"Quality gate failed; inspect {table} for run {args.run_id}")
    print(f"All {len(results)} checks passed for batch {batch}")


if __name__ == "__main__":
    main()
