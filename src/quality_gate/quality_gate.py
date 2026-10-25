"""Quality gate — verifies lakehouse integrity, reconciles KPIs, and stores results."""

import argparse
import json
from decimal import Decimal

FINAL_BATCH = 3
KPI_TOLERANCE = Decimal("0.01")
REQUIRED_KEYS = ("shard_start", "shard_end", "expected_valid", "segment_changes")
REQUIRED_KPIS = ("orders", "lineitem", "returns", "net_revenue", "discount_given")


def read_manifests(spark, vol: str, batch: int) -> list[dict]:
    """Read manifests for batches 1..batch. Raises if missing or invalid."""
    manifests = []
    for b in range(1, batch + 1):
        path = f"{vol}/_manifest/batch={b}"
        rows = spark.read.text(path).collect()
        data = json.loads("".join(r.value for r in rows))
        for key in REQUIRED_KEYS:
            if key not in data:
                raise ValueError(f"Manifest batch {b} missing required key: {key}")
        for kpi in REQUIRED_KPIS:
            if kpi not in data["expected_valid"]:
                raise ValueError(f"Manifest batch {b} expected_valid missing: {kpi}")
        manifests.append(data)
    return manifests


def build_checks(catalog: str, batch: int, manifests: list[dict]) -> list[tuple]:
    """Build verification checks as (name, sql, expected, tolerance, critical)."""
    p = f"{catalog}."
    h = f"{p}silver.customer_history"
    checks = [
        # Gold population check
        ("gold_orders_not_empty", f"SELECT if(count(*) > 0, 0, 1) FROM {p}gold.fct_orders", 0, 0, True),
        ("gold_lines_not_empty", f"SELECT if(count(*) > 0, 0, 1) FROM {p}gold.fct_order_lines", 0, 0, True),

        # 1. Bronze physical reconciliation: Bronze = invalid + duplicates + silver
        ("bronze_reconciliation_orders", f"""
            SELECT (SELECT count(*) FROM {p}bronze.orders)
                 - ((SELECT count(*) FROM {p}ops.quarantine_invalid WHERE entity = 'orders')
                  + (SELECT count(*) FROM {p}ops.duplicate_dispositions WHERE entity = 'orders')
                  + (SELECT count(*) FROM {p}silver.orders))""", 0, 0, True),
        ("bronze_reconciliation_lineitem", f"""
            SELECT (SELECT count(*) FROM {p}bronze.lineitem)
                 - ((SELECT count(*) FROM {p}ops.quarantine_invalid WHERE entity = 'lineitem')
                  + (SELECT count(*) FROM {p}ops.duplicate_dispositions WHERE entity = 'lineitem')
                  + (SELECT count(*) FROM {p}silver.order_lines))""", 0, 0, True),
        ("bronze_reconciliation_customer", f"""
            SELECT (SELECT count(*) FROM {p}bronze.customer)
                 - ((SELECT count(*) FROM {p}ops.quarantine_invalid WHERE entity = 'customer')
                  + (SELECT count(*) FROM {p}silver.customer_changes))""", 0, 0, True),

        # 2. Silver uniqueness and hashing
        ("silver_orders_unique", f"SELECT count(*) - count(DISTINCT order_key_hash) FROM {p}silver.orders", 0, 0, True),
        ("silver_lines_unique", f"SELECT count(*) - count(DISTINCT order_key_hash, line_number) FROM {p}silver.order_lines", 0, 0, True),
        ("order_hash_collision", f"""
            SELECT (SELECT count(DISTINCT order_key) FROM {p}silver.orders)
                 - (SELECT count(DISTINCT order_key_hash) FROM {p}silver.orders)""", 0, 0, True),

        # 3. Customer history shape (SCD2)
        ("customer_history_duplicate_versions", f"""
            SELECT count(*) FROM (
              SELECT customer_key, __START_AT FROM {h}
              GROUP BY customer_key, __START_AT HAVING count(*) > 1)""", 0, 0, True),
        ("customer_history_zero_length_intervals", f"SELECT count(*) FROM {h} WHERE __END_AT IS NOT NULL AND __END_AT <= __START_AT", 0, 0, True),
        ("customer_history_overlapping_intervals", f"""
            SELECT count(*) FROM {h} h1 JOIN {h} h2 ON h1.customer_key = h2.customer_key
            WHERE h1.__START_AT < h2.__START_AT
              AND h2.__START_AT < coalesce(h1.__END_AT, DATE '9999-12-31')""", 0, 0, True),
        ("customer_history_multiple_open_versions", f"""
            SELECT count(*) FROM (
              SELECT customer_key FROM {h} WHERE __END_AT IS NULL
              GROUP BY customer_key HAVING count(*) > 1)""", 0, 0, True),

        # 4. Point-in-time join resolution
        ("orders_customer_version_unique", f"""
            SELECT count(*) FROM (
              SELECT o.order_key_hash FROM {p}silver.orders o
              LEFT JOIN {p}gold.dim_customer_scd2 h
                ON o.customer_key = h.customer_key
               AND o.order_date >= h.valid_from
               AND (h.valid_to IS NULL OR o.order_date < h.valid_to)
              GROUP BY o.order_key_hash HAVING count(h.customer_key) <> 1)""", 0, 0, True),

        # 5. Pending delayed lines: non-critical before final batch
        ("pending_order_lines", f"SELECT count(*) FROM {p}ops.pending_order_lines", 0, 0, batch >= FINAL_BATCH),

        # 6. Gold star schema integrity
        ("gold_fct_orders_grain", f"SELECT count(*) - count(DISTINCT order_key_hash) FROM {p}gold.fct_orders", 0, 0, True),
        ("gold_fct_order_lines_grain", f"SELECT count(*) - count(DISTINCT order_key_hash, line_number) FROM {p}gold.fct_order_lines", 0, 0, True),
        ("lines_part_fk_valid", f"""
            SELECT count(*) FROM {p}gold.fct_order_lines l
            LEFT JOIN {p}gold.dim_part d ON l.part_key = d.part_key
            WHERE d.part_key IS NULL""", 0, 0, True),
        ("lines_supplier_fk_valid", f"""
            SELECT count(*) FROM {p}gold.fct_order_lines l
            LEFT JOIN {p}gold.dim_supplier d ON l.supplier_key = d.supplier_key
            WHERE d.supplier_key IS NULL""", 0, 0, True),
    ]

    # 7. KPI reconciliation against manifests
    for m in manifests:
        shard = f"order_date >= DATE '{m['shard_start']}' AND order_date < DATE '{m['shard_end']}'"
        ev = m["expected_valid"]
        b_num = m["batch"]
        checks.extend([
            (f"kpi_reconciliation_b{b_num}_orders", f"SELECT count(*) FROM {p}gold.fct_orders WHERE {shard}", ev["orders"], 0, True),
            (f"kpi_reconciliation_b{b_num}_lines", f"SELECT count(*) FROM {p}gold.fct_order_lines WHERE {shard}", ev["lineitem"], 0, True),
            (f"kpi_reconciliation_b{b_num}_returns", f"SELECT coalesce(sum(is_returned), 0) FROM {p}gold.fct_order_lines WHERE {shard}", ev["returns"], 0, True),
            (f"kpi_reconciliation_b{b_num}_net_revenue", f"SELECT coalesce(sum(net_revenue), 0) FROM {p}gold.fct_order_lines WHERE {shard}", Decimal(str(ev["net_revenue"])), KPI_TOLERANCE, True),
            (f"kpi_reconciliation_b{b_num}_discount_given", f"SELECT coalesce(sum(discount_amount), 0) FROM {p}gold.fct_order_lines WHERE {shard}", Decimal(str(ev["discount_given"])), KPI_TOLERANCE, True),
        ])

    # 8. SCD2 segment versions proof
    cum_changes = {}
    for m in manifests:
        for ch in m.get("segment_changes", []):
            k = str(ch["customer_key"])
            cum_changes[k] = cum_changes.get(k, 0) + 1
    for k, cnt in sorted(cum_changes.items()):
        checks.append((
            f"scd2_segment_versions_c{k}",
            f"SELECT count(DISTINCT __START_AT) FROM {p}silver.customer_history WHERE customer_key = {k}",
            1 + cnt, 0, True
        ))

    return checks


def evaluate_check(name: str, sql: str, expected, tolerance, critical: bool, spark) -> tuple[str, str, str]:
    """Execute a single check and return (name, status, value_str)."""
    try:
        rows = spark.sql(sql).collect()
        raw_val = rows[0][0] if rows and rows[0][0] is not None else 0
        if isinstance(expected, Decimal):
            actual_dec = Decimal(str(raw_val))
            passed = abs(actual_dec - expected) <= tolerance
            val_str = f"{raw_val} (expected {expected}, tol {tolerance})"
        else:
            actual_num = float(raw_val)
            passed = abs(actual_num - float(expected)) <= float(tolerance)
            val_str = str(raw_val) if tolerance == 0 else f"{raw_val} (expected {expected})"

        if passed:
            status = "PASS"
        else:
            status = "WARN" if not critical else "FAIL"
        return name, status, val_str
    except Exception as exc:
        return name, "ERROR", str(exc)[:300]


def log_results(spark, catalog: str, batch: int, results: list[tuple[str, str, str]]):
    """Persist check results into ops.quality_gate. Fails if write fails."""
    spark.sql(f"""CREATE TABLE IF NOT EXISTS {catalog}.ops.quality_gate
                  (checked_on TIMESTAMP, batch INT, check_name STRING,
                   status STRING, value STRING, detail STRING)""")
    values = ", ".join(
        f"('{n.replace(\"'\", \"''\")}', '{s}', '{v.replace(\"'\", \"''\")}', '')"
        for n, s, v in results
    )
    spark.sql(f"""INSERT INTO {catalog}.ops.quality_gate
                  SELECT current_timestamp(), {int(batch)}, t.check_name, t.status, t.value, t.detail
                  FROM VALUES {values} AS t(check_name, status, value, detail)""")


def run(spark, catalog: str, batch: int):
    """Execute quality gate suite and report failures."""
    vol = f"/Volumes/{catalog}/landing/raw_files"
    manifests = read_manifests(spark, vol, batch)
    checks = build_checks(catalog, batch, manifests)

    results = []
    failures = []
    for name, sql, expected, tol, critical in checks:
        chk_name, status, val_str = evaluate_check(name, sql, expected, tol, critical, spark)
        results.append((chk_name, status, val_str))
        if status in ("FAIL", "ERROR"):
            failures.append(chk_name)

    log_results(spark, catalog, batch, results)
    print(json.dumps([{"check": r[0], "status": r[1], "value": r[2]} for r in results], indent=1))

    if failures:
        raise SystemExit(f"QUALITY GATE FAILED: {', '.join(failures)}")
    print("QUALITY GATE PASSED")


def main():
    parser = argparse.ArgumentParser(description="Lakehouse quality gate")
    parser.add_argument("--catalog", default="meridian_t02")
    parser.add_argument("--batch", type=int, default=3)
    args = parser.parse_args()

    from pyspark.sql import SparkSession
    spark = SparkSession.builder.getOrCreate()
    run(spark, args.catalog, args.batch)


if __name__ == "__main__":
    main()
