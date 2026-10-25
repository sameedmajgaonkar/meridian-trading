"""Phase 5 quality gate — runs after every pipeline update.

Records every check in ops.quality_gate (evidence trail) and fails the job
task when a critical check fails, so no bad result reaches the dashboards.
`batch` tells the gate how many batches have landed; the pending-lines check
is only critical at the final batch (delayed headers are expected earlier).

Run as a Databricks job spark_python_task after the pipeline task:
  quality_gate.py --catalog meridian_t02 --schema-prefix "" --batch 3
"""

import argparse
import json

from pyspark.sql import SparkSession

KPI_TOLERANCE = 0.01


def read_manifests(spark, vol, batch):
    """Per-batch expected values written by the simulator (raw-source baseline)."""
    out = []
    for b in range(1, batch + 1):
        try:
            rows = spark.read.text(f"{vol}/_manifest/batch={b}").collect()
            out.append(json.loads("".join(r.value for r in rows)))
        except Exception:
            print(f"warning: manifest for batch {b} not found")
    return out


def build_checks(cat, prefix, batch, manifests):
    p = f"{cat}.{prefix}"
    checks = []

    def zero(name, sql, critical=True):
        checks.append({"name": name, "kind": "zero", "critical": critical, "sql": sql})

    # 1. Physical reconciliation: Bronze = invalid + duplicate-discarded + accepted.
    for entity, silver in (("orders", "silver.orders"),
                           ("lineitem", "silver.order_lines"),
                           ("customer", "silver.customer_snapshot")):
        zero(f"bronze_reconciliation_{entity}", f"""
            SELECT (SELECT count(*) FROM {p}bronze.{entity})
                 - ((SELECT count(*) FROM {p}ops.quarantine_invalid WHERE entity = '{entity}')
                  + (SELECT count(*) FROM {p}ops.duplicate_dispositions WHERE entity = '{entity}')
                  + (SELECT count(*) FROM {p}{silver}))""")

    # 2. Silver uniqueness and hash semantics (ADR-002).
    zero("silver_orders_unique", f"""
        SELECT count(*) - count(DISTINCT order_key_hash) FROM {p}silver.orders""")
    zero("silver_lines_unique", f"""
        SELECT count(*) - count(DISTINCT order_key_hash, line_number)
        FROM {p}silver.order_lines""")
    zero("order_hash_collision", f"""
        SELECT (SELECT count(DISTINCT order_key) FROM {p}silver.orders)
             - (SELECT count(DISTINCT order_key_hash) FROM {p}silver.orders)""")

    # 3. History shape: no duplicate versions, overlaps, open-version excess,
    #    or zero-length intervals.
    h = f"{p}silver.customer_history"
    zero("customer_history_duplicate_versions", f"""
        SELECT count(*) FROM (
          SELECT customer_key, __START_AT FROM {h}
          GROUP BY customer_key, __START_AT HAVING count(*) > 1)""")
    zero("customer_history_zero_length_intervals", f"""
        SELECT count(*) FROM {h} WHERE __END_AT IS NOT NULL AND __END_AT <= __START_AT""")
    zero("customer_history_overlapping_intervals", f"""
        SELECT count(*) FROM {h} h1 JOIN {h} h2 ON h1.customer_key = h2.customer_key
        WHERE h1.__START_AT < h2.__START_AT
          AND h2.__START_AT < coalesce(h1.__END_AT, DATE '9999-12-31')""")
    zero("customer_history_multiple_open_versions", f"""
        SELECT count(*) FROM (
          SELECT customer_key FROM {h} WHERE __END_AT IS NULL
          GROUP BY customer_key HAVING count(*) > 1)""")

    # 4. Exactly one customer version per published header (ADR-004 point-in-time).
    zero("orders_customer_version_unique", f"""
        SELECT count(*) FROM (
          SELECT o.order_key_hash FROM {p}silver.orders o
          LEFT JOIN {p}gold.dim_customer_scd2 h
            ON o.customer_key = h.customer_key
           AND o.order_date >= h.valid_from
           AND (h.valid_to IS NULL OR o.order_date < h.valid_to)
          GROUP BY o.order_key_hash HAVING count(h.customer_key) <> 1)""")

    # 5. Delayed headers: pending lines are normal mid-run, must resolve by the
    #    final batch (data contract: gate certifies final KPIs).
    zero("pending_order_lines", f"""
        SELECT count(*) FROM {p}ops.pending_order_lines""", critical=(batch >= 3))

    # 6. Gold grains and reference integrity.
    zero("gold_fct_orders_grain", f"""
        SELECT count(*) - count(DISTINCT order_key_hash) FROM {p}gold.fct_orders""")
    zero("gold_fct_order_lines_grain", f"""
        SELECT count(*) - count(DISTINCT order_key_hash, line_number)
        FROM {p}gold.fct_order_lines""")
    zero("lines_part_fk_valid", f"""
        SELECT count(*) FROM {p}gold.fct_order_lines l
        LEFT JOIN {p}gold.dim_part d ON l.part_key = d.part_key
        WHERE d.part_key IS NULL""")
    zero("lines_supplier_fk_valid", f"""
        SELECT count(*) FROM {p}gold.fct_order_lines l
        LEFT JOIN {p}gold.dim_supplier d ON l.supplier_key = d.supplier_key
        WHERE d.supplier_key IS NULL""")

    # 7. KPI reconciliation against the manifest (computed from the raw source
    #    at landing time, excluding injected rows) over each landed shard.
    for m in manifests:
        if "shard_start" not in m:
            continue
        shard = (f"order_date >= DATE '{m['shard_start']}' "
                 f"AND order_date < DATE '{m['shard_end']}'")
        e = m["expected_valid"]
        pairs = [
            ("orders", f"SELECT count(*) FROM {p}gold.fct_orders WHERE {shard}", e["orders"], 0),
            ("lines", f"SELECT count(*) FROM {p}gold.fct_order_lines WHERE {shard}", e["lineitem"], 0),
            ("returns", f"SELECT sum(is_returned) FROM {p}gold.fct_order_lines WHERE {shard}",
             e["returns"], 0),
            ("net_revenue", f"SELECT sum(net_revenue) FROM {p}gold.fct_order_lines WHERE {shard}",
             e["net_revenue"], KPI_TOLERANCE),
            ("discount_given",
             f"SELECT sum(discount_amount) FROM {p}gold.fct_order_lines WHERE {shard}",
             e["discount_given"], KPI_TOLERANCE),
        ]
        for metric, sql, expected, tol in pairs:
            checks.append({"name": f"kpi_reconciliation_b{m['batch']}_{metric}",
                           "kind": "kpi", "critical": True, "sql": sql,
                           "expected": expected, "tolerance": tol})

    # 8. SCD2 segment-change story (runbook 2.2): every injected segment
    #    change must show up as exactly one extra history version. Without
    #    this the runtime's one-version-per-update rule could be violated
    #    silently (history shape alone stays valid on a flat replay).
    cumulative = {}
    for m in manifests:
        for ch in m.get("segment_changes", []):
            key = str(ch["customer_key"])
            # Each manifest entry is exactly one new history version; the
            # "change" field is the occurrence number (1st/2nd), not a count.
            cumulative[key] = cumulative.get(key, 0) + 1
    for key, changes in sorted(cumulative.items()):
        checks.append({"name": f"scd2_segment_versions_c{key}",
                       "kind": "kpi", "critical": True,
                       "sql": f"SELECT count(DISTINCT __START_AT) FROM {p}silver.customer_history "
                              f"WHERE customer_key = {key}",
                       "expected": 1 + changes, "tolerance": 0})
    return checks


def _esc(v):
    # Spark SQL string literals treat backslash as an escape character.
    return str(v).replace("\\", "\\\\").replace("'", "''")


def _log(spark, cat, prefix, batch, rows):
    """Append rows to ops.quality_gate via one SQL INSERT. Serverless task
    stdout is not retrievable through the Jobs API, so the gate must be fully
    observable through this table; DataFrameWriter paths stay unused."""
    if not rows:
        return
    values = ", ".join(
        f"('{_esc(n)}', '{_esc(s)}', '{_esc(v)}', '{_esc(d)}')"
        for n, s, v, d in rows)
    spark.sql(f"""INSERT INTO {cat}.{prefix}ops.quality_gate
        SELECT current_timestamp(), {int(batch)}, t.check_name, t.status,
               t.value, t.detail
        FROM VALUES {values} AS t(check_name, status, value, detail)""")


def run(spark, cat, prefix, batch):
    vol = f"/Volumes/{cat}/{prefix}landing/raw_files"
    rows, failures = [], []
    try:
        spark.sql(f"""CREATE TABLE IF NOT EXISTS {cat}.{prefix}ops.quality_gate
                      (checked_on TIMESTAMP, batch INT, check_name STRING,
                       status STRING, value STRING, detail STRING)""")
        _log(spark, cat, prefix, batch,
             [("_step", "INFO", "session + gate table ready", "")])
    except Exception:
        import traceback
        print("gate table setup failed:\n" + traceback.format_exc())

    try:
        manifests = read_manifests(spark, vol, batch)
        _log(spark, cat, prefix, batch, [(
            "_step", "INFO",
            f"manifests loaded: {[m.get('batch') for m in manifests]}", "")])
        for chk in build_checks(cat, prefix, batch, manifests):
            try:
                result = spark.sql(chk["sql"]).collect()
                value = result[0][0] if result and result[0][0] is not None else None
                if chk["kind"] == "zero":
                    status = "PASS" if value == 0 else ("WARN" if not chk["critical"] else "FAIL")
                elif value is None:
                    status, value = "ERROR", "NULL result (no eligible data)"
                else:
                    delta = abs(float(value) - float(chk["expected"]))
                    status = "PASS" if delta <= chk["tolerance"] else "FAIL"
                    value = f"{value} (expected {chk['expected']}, tol {chk['tolerance']})"
                rows.append((chk["name"], status, str(value), ""))
                if status in ("FAIL", "ERROR"):
                    failures.append(chk["name"])
            except Exception as exc:  # a broken check must surface, not vanish
                rows.append((chk["name"], "ERROR", str(exc)[:400], ""))
                failures.append(chk["name"])
        _log(spark, cat, prefix, batch, [(
            "_step", "INFO", f"checks done: {len(rows)} rows, failures: {failures}", "")])
    except Exception:
        import traceback
        rows.append(("gate_crash", "ERROR", traceback.format_exc()[-800:], ""))
        failures.append("gate_crash")

    try:
        _log(spark, cat, prefix, batch, rows)
    except Exception:
        import traceback
        print("gate write failed:\n" + traceback.format_exc())

    print(json.dumps([{ "check": r[0], "status": r[1], "value": r[2]} for r in rows], indent=1))
    if failures:
        raise SystemExit(f"QUALITY GATE FAILED: {', '.join(failures)}")
    print("QUALITY GATE PASSED")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default="meridian_t02")
    ap.add_argument("--schema-prefix", default="")
    ap.add_argument("--batch", type=int, default=3)
    args = ap.parse_args()
    spark = SparkSession.builder.getOrCreate()
    run(spark, args.catalog, args.schema_prefix, args.batch)


if __name__ == "__main__":
    main()
