"""Phase 1 landing simulator — turns the read-only samples.tpch source into
deterministic parquet batches in the governed landing volume.

One row = one physical source record. Batches are disjoint 4-month shards
covering the locked window exactly (ADR-001); each batch also re-lands the
FULL selected customer population (a complete snapshot) stamped with a
business-effective date (ADR-004), so AUTO CDC FROM SNAPSHOT can diff
snapshots into SCD2.

Deterministic: injections key on source values, so a rerun lands byte-identical
content. Idempotent: a batch directory that already has files is skipped, so
Auto Loader never sees rewritten files.

Run as a Databricks job spark_python_task (spark session is provided):
  simulate.py --catalog meridian_t02 --schema-prefix "" --batch 3
              --order-start 1995-01-01 --order-end 1996-01-01
"""

import argparse
import json

from pyspark.sql import SparkSession, functions as F

from injection import (
    BATCH_EFFECTIVE_DATES,
    CUSTOMER_RULES,
    EARLY_ORDER_LIMIT,
    EARLY_ORDER_PREDICATE,
    LINEITEM_RULES,
    ORDERS_RULES,
    SEGMENTS,
    changes_for_batch,
    shard_range,
)

STATIC_DIMS = ("nation", "region", "part", "supplier")


def apply_rules(spark, df, rules):
    """Apply injection rules; None action duplicates whole rows (extra copies).
    Returns (df, counts) with counts[name] = rows the rule injects, measured
    BEFORE the rule extends or mutates the frame — counting after a duplicate
    rule would double-count originals + copies."""
    counts = {}
    for name, pred, action in rules:
        counts[name] = df.filter(pred).count()
        if action is None:
            df = df.unionByName(df.filter(pred))
        else:
            col, repl = action
            df = df.withColumn(col, F.expr(f"CASE WHEN {pred} THEN {repl} ELSE {col} END"))
    return df, counts


def write_once(spark, path, df):
    """Write a batch once; skip if it already landed (idempotency guard)."""
    try:
        spark.read.parquet(path).limit(1).count()
        print(f"skip {path}: already landed")
        return False
    except Exception:
        df.write.mode("overwrite").parquet(path)
        print(f"landed {path}: {df.count()} rows")
        return True


def seg_next(expr):
    """SQL: cyclic successor of a segment expression over the 5 observed codes."""
    arr = "array(" + ", ".join(f"'{s}'" for s in SEGMENTS) + ")"
    return (f"element_at({arr}, CAST((array_position({arr}, {expr}) "
            f"% {len(SEGMENTS)}) + 1 AS INT))")


def cumulative_changes(batch):
    """(keys changed once, keys changed twice) up to and including this batch."""
    once, twice = [], []
    for b in range(2, batch + 1):
        for key, change_no in changes_for_batch(b):
            (twice if change_no == 2 else once).append(key)
    return once, twice


def customer_snapshot(spark, batch, eff, start_iso, end_iso):
    """Full selected customer population with segment changes applied."""
    once, twice = cumulative_changes(batch)
    in_list = lambda keys: ", ".join(map(str, keys)) or "-1"
    segment = "c_mktsegment"
    if once:
        segment = f"CASE WHEN c_custkey IN ({in_list(once)}) THEN {seg_next(segment)} ELSE {segment} END"
        if twice:
            segment = f"CASE WHEN c_custkey IN ({in_list(twice)}) THEN {seg_next(segment)} ELSE {segment} END"
    return spark.sql(f"""
        SELECT c.*, {segment} AS c_mktsegment_final,
               DATE '{eff}' AS snapshot_effective_date
        FROM samples.tpch.customer c
        WHERE EXISTS (
          SELECT 1 FROM samples.tpch.orders o
          WHERE o_orderdate >= DATE '{start_iso}' AND o_orderdate < DATE '{end_iso}'
            AND o.o_custkey = c.c_custkey
        )
    """).drop("c_mktsegment").withColumnRenamed("c_mktsegment_final", "c_mktsegment")


def valid_orders_expr():
    return ("o_custkey IS NOT NULL AND o_totalprice >= 0 "
            "AND o_orderstatus IN ('O', 'F', 'P')")


def valid_lines_expr():
    return ("l_orderkey IS NOT NULL AND l_quantity > 0 AND l_extendedprice >= 0 "
            "AND l_discount BETWEEN 0 AND 1 AND l_tax BETWEEN 0 AND 1 "
            "AND l_linestatus IN ('O', 'F') AND l_returnflag IN ('N', 'A', 'R') "
            "AND l_shipdate IS NOT NULL AND l_commitdate IS NOT NULL "
            "AND l_receiptdate IS NOT NULL AND l_receiptdate >= l_shipdate")


def early_keys(spark, start_iso):
    """Same five valid batch-3 orders chosen deterministically on every call."""
    s3s, s3e = shard_range(start_iso, 3)
    rows = spark.sql(f"""
        SELECT o_orderkey FROM samples.tpch.orders
        WHERE o_orderdate >= DATE '{s3s}' AND o_orderdate < DATE '{s3e}'
          AND {EARLY_ORDER_PREDICATE} AND {valid_orders_expr()}
        LIMIT {EARLY_ORDER_LIMIT}
    """).collect()
    return [r.o_orderkey for r in rows]


def land_batch(spark, vol, batch, start_iso, end_iso):
    """Land one batch and return its manifest (the raw-source baseline the
    quality gate reconciles Gold against)."""
    eff = BATCH_EFFECTIVE_DATES[batch]
    shard_start, shard_end = shard_range(start_iso, batch)
    bdir = lambda entity: f"{vol}/{entity}/batch={batch}"
    manifest = {"batch": batch, "shard_start": shard_start, "shard_end": shard_end,
                "snapshot_effective_date": eff, "rows": {}, "injections": {},
                "expected_valid": {}, "early_lines_order_keys": [],
                "segment_changes": []}

    if batch == 1:
        for entity in STATIC_DIMS:
            write_once(spark, bdir(entity), spark.table(f"samples.tpch.{entity}"))
            manifest["rows"][entity] = spark.table(f"samples.tpch.{entity}").count()

    # Orders: shard + injections.
    orders = spark.sql(f"""
        SELECT * FROM samples.tpch.orders
        WHERE o_orderdate >= DATE '{shard_start}' AND o_orderdate < DATE '{shard_end}'
    """)
    orders, counts = apply_rules(spark, orders, ORDERS_RULES)
    # The header-validity check in the lineitem expected-value computation must
    # see the INJECTED orders (mutated df), not the pristine source — the
    # quarantined headers exist only in the simulated data.
    orders.createOrReplaceTempView("sim_orders")
    write_once(spark, bdir("orders"), orders)
    manifest["rows"]["orders"] = orders.count()
    manifest["injections"].update(counts)
    manifest["expected_valid"]["orders"] = orders.filter(valid_orders_expr()).count()

    # Lines: this shard's own population first; expected values mirror
    # Silver's dedup + validity applied to the shard ONLY (early lines have
    # later order dates and reconcile under their own shard at batch 3).
    lineitem = spark.sql(f"""
        SELECT l.* FROM samples.tpch.lineitem l
        JOIN (SELECT o_orderkey FROM samples.tpch.orders
              WHERE o_orderdate >= DATE '{shard_start}' AND o_orderdate < DATE '{shard_end}') o
          ON l.l_orderkey = o.o_orderkey
    """)
    early = None
    written = lineitem
    if batch == 2:  # lines of five later orders arrive before their headers
        keys = early_keys(spark, start_iso)
        key_list = ", ".join(map(str, keys)) or "-1"
        early = spark.sql(f"""
            SELECT l.* FROM samples.tpch.lineitem l
            JOIN (SELECT o_orderkey FROM samples.tpch.orders
                  WHERE o_orderdate >= DATE '{shard_range(start_iso, 3)[0]}'
                    AND o_orderdate < DATE '{shard_range(start_iso, 3)[1]}') o
              ON l.l_orderkey = o.o_orderkey
            WHERE l.l_orderkey IN ({key_list})
        """)
        written = lineitem.unionByName(early)
        manifest["early_lines_order_keys"] = keys
    written, counts = apply_rules(spark, written, LINEITEM_RULES)
    shard_only, _ = apply_rules(spark, lineitem, LINEITEM_RULES)
    shard_only.createOrReplaceTempView("sim_lineitem")
    # Lines whose header fails order validity are dispositioned with the
    # header's quarantine entry and never publish, so the expected values
    # count only lines with a valid in-shard header.
    deduped = spark.sql(f"""
        SELECT count(*) AS lines,
               sum(CAST(l_extendedprice * (1 - l_discount) AS DECIMAL(18, 2))) AS net_revenue,
               sum(CAST(l_extendedprice * l_discount AS DECIMAL(18, 2))) AS discount_given,
               sum(if(l_returnflag = 'R', 1, 0)) AS returns
        FROM (SELECT *, row_number() OVER (PARTITION BY l_orderkey, l_linenumber
                                           ORDER BY sha2(to_json(struct(*)), 256) DESC) AS rn
              FROM sim_lineitem
              WHERE EXISTS (SELECT 1 FROM sim_orders o
                            WHERE o.o_orderkey = l_orderkey
                              AND o.o_orderdate >= DATE '{shard_start}'
                              AND o.o_orderdate < DATE '{shard_end}'
                              AND {valid_orders_expr()}))
        WHERE rn = 1 AND {valid_lines_expr()}
    """).collect()[0]
    manifest["expected_valid"] = {"orders": manifest["expected_valid"]["orders"],
                                  "lineitem": deduped.lines,
                                  "net_revenue": float(deduped.net_revenue),
                                  "discount_given": float(deduped.discount_given),
                                  "returns": int(deduped.returns)}
    if batch == 3:  # their headers land now; the held-back lines must resolve
        keys = early_keys(spark, start_iso)
        key_list = ", ".join(map(str, keys)) or "-1"
        written = written.filter(f"l_orderkey NOT IN ({key_list})")
    write_once(spark, bdir("lineitem"), written)
    manifest["rows"]["lineitem"] = written.count()
    manifest["injections"].update(counts)

    # Customer: complete snapshot per batch (ADR-004) + duplicate injection.
    snapshot = customer_snapshot(spark, batch, eff, start_iso, end_iso)
    snapshot, counts = apply_rules(spark, snapshot, CUSTOMER_RULES)
    write_once(spark, bdir("customer"), snapshot)
    manifest["rows"]["customer"] = snapshot.count()
    manifest["injections"].update(counts)
    # segment_changes audit trail: original source value + new value
    for b in range(2, batch + 1):
        for key, change_no in changes_for_batch(b):
            if b == batch:
                orig = spark.sql(
                    f"SELECT c_mktsegment FROM samples.tpch.customer WHERE c_custkey = {key}"
                ).collect()[0][0]
                new = orig
                for _ in range(change_no):
                    new = SEGMENTS[(SEGMENTS.index(new) + 1) % len(SEGMENTS)]
                manifest["segment_changes"].append(
                    {"customer_key": key, "change": change_no, "from": orig, "to": new})

    # Register the snapshot version for the AUTO CDC FROM SNAPSHOT flow.
    cat, prefix = args.catalog, args.schema_prefix
    spark.sql(f"""INSERT INTO {cat}.{prefix}ops.customer_snapshot_versions
                  SELECT DATE '{eff}', current_timestamp()
                  WHERE NOT EXISTS (
                    SELECT 1 FROM {cat}.{prefix}ops.customer_snapshot_versions
                    WHERE version = DATE '{eff}')""")

    (spark.createDataFrame([(json.dumps(manifest, sort_keys=True),)], "manifest STRING")
     .repartition(1).write.mode("overwrite").text(f"{vol}/_manifest/batch={batch}"))
    print(f"manifest batch={batch}: {json.dumps(manifest)[:300]}")
    return manifest


def main():
    global start_iso, args
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default="meridian_t02")
    ap.add_argument("--schema-prefix", default="")
    ap.add_argument("--batch", type=int, default=3)
    ap.add_argument("--order-start", default="1995-01-01")
    ap.add_argument("--order-end", default="1996-01-01")
    args = ap.parse_args()
    if not 1 <= args.batch <= 3:
        raise SystemExit("the demo plan ships exactly three batches (1..3)")
    start_iso, end_iso = args.order_start, args.order_end
    vol = f"/Volumes/{args.catalog}/{args.schema_prefix}landing/raw_files"
    spark = SparkSession.builder.getOrCreate()
    for b in range(1, args.batch + 1):
        land_batch(spark, vol, b, start_iso, end_iso)
    print("landing complete")


if __name__ == "__main__":
    main()
