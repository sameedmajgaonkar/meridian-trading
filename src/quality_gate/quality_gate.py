"""Quality Gate — validates pipeline invariants and logs check results to ops.quality_gate."""
import argparse
from pyspark.sql import SparkSession

CHECKS = [
    ("gold_orders_not_empty", "SELECT IF(count(*) > 0, 0, 1) FROM {c}.gold.fct_orders"),
    ("gold_lines_not_empty", "SELECT IF(count(*) > 0, 0, 1) FROM {c}.gold.fct_order_lines"),
    ("silver_orders_no_duplicates", "SELECT count(*) FROM (SELECT order_key FROM {c}.silver.orders GROUP BY order_key HAVING count(*) > 1)"),
    ("silver_lines_no_duplicates", "SELECT count(*) FROM (SELECT order_key, line_number FROM {c}.silver.order_lines GROUP BY order_key, line_number HAVING count(*) > 1)"),
    ("gold_orders_no_duplicates", "SELECT count(*) FROM (SELECT order_key FROM {c}.gold.fct_orders GROUP BY order_key HAVING count(*) > 1)"),
    ("gold_lines_no_duplicates", "SELECT count(*) FROM (SELECT order_key, line_number FROM {c}.gold.fct_order_lines GROUP BY order_key, line_number HAVING count(*) > 1)"),
    ("fct_orders_no_orphan_customer", "SELECT count(*) FROM {c}.gold.fct_orders o WHERE NOT EXISTS (SELECT 1 FROM {c}.gold.dim_customer_scd2 c WHERE c.customer_key = o.customer_key)"),
    ("fct_lines_no_orphan_part", "SELECT count(*) FROM {c}.gold.fct_order_lines l WHERE NOT EXISTS (SELECT 1 FROM {c}.gold.dim_part p WHERE p.part_key = l.part_key)"),
    ("fct_lines_no_orphan_supplier", "SELECT count(*) FROM {c}.gold.fct_order_lines l WHERE NOT EXISTS (SELECT 1 FROM {c}.gold.dim_supplier s WHERE s.supplier_key = l.supplier_key)"),
    ("reconcile_orders", "SELECT abs((SELECT count(*) FROM {c}.bronze.orders) - (SELECT count(*) FROM {c}.silver.orders) - (SELECT count(*) FROM {c}.ops.quarantine_invalid WHERE entity = 'orders') - (SELECT count(*) - count(DISTINCT o_orderkey) FROM {c}.bronze.orders))"),
    ("reconcile_lineitem", "SELECT abs((SELECT count(*) FROM {c}.bronze.lineitem) - (SELECT count(*) FROM {c}.silver.order_lines) - (SELECT count(*) FROM {c}.ops.quarantine_invalid WHERE entity = 'lineitem') - (SELECT count(*) - count(DISTINCT l_orderkey, l_linenumber) FROM {c}.bronze.lineitem))"),
    ("single_open_customer_version", "SELECT count(*) FROM (SELECT customer_key FROM {c}.silver.customer_history WHERE __END_AT IS NULL GROUP BY customer_key HAVING count(*) > 1)"),
    ("no_pending_lines_at_final_batch", "SELECT IF({b} = 3, count(*), 0) FROM {c}.ops.pending_order_lines"),
]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="meridian_t02")
    p.add_argument("--batch", default="3")
    args = p.parse_args()
    spark = SparkSession.builder.getOrCreate()
    b = int(args.batch) if str(args.batch).isdigit() else 3
    results, failed = [], []
    for name, sql_tmpl in CHECKS:
        val = int(spark.sql(sql_tmpl.format(c=args.catalog, b=b)).collect()[0][0])
        results.append((name, val, "PASSED" if val == 0 else "FAILED", b))
        if val != 0:
            failed.append((name, val))
    spark.sql(f"CREATE TABLE IF NOT EXISTS {args.catalog}.ops.quality_gate (check_name STRING, check_value BIGINT, status STRING, batch INT, evaluated_at TIMESTAMP)")
    rows = ", ".join([f"('{r[0]}', {r[1]}, '{r[2]}', {r[3]}, current_timestamp())" for r in results])
    spark.sql(f"INSERT INTO {args.catalog}.ops.quality_gate VALUES {rows}")
    if failed:
        raise RuntimeError(f"Quality gate failed: {failed}")
    print(f"All {len(results)} checks passed for batch {b}.")


if __name__ == "__main__":
    main()
