"""Landing simulator — generates deterministic parquet batches in the landing volume.

Samples source orders (mod 500) and line items, applies flaw injections,
lands dimensional tables, and writes a reconciliation manifest per batch.
"""

import argparse
import json
from decimal import Decimal
from pathlib import Path

from bad_data import (
    BATCHES,
    EARLY_ORDER_LIMIT,
    EARLY_ORDER_PREDICATE,
    FINAL_BATCH,
    LINEITEM_RULES,
    ORDERS_RULES,
    SAMPLE_MOD,
    segment_after,
    segment_changes,
)


def apply_rules(df, rules, F):
    """Apply injection rules; None action duplicates rows. Returns (df, counts)."""
    counts = {}
    for name, pred, action in rules:
        matched = df.filter(pred)
        counts[name] = matched.count()
        if action is None:
            df = df.unionByName(matched)
        else:
            col, repl = action
            df = df.withColumn(col, F.expr(f"CASE WHEN {pred} THEN {repl} ELSE {col} END"))
    return df, counts


def write_once(path_str: str, df) -> bool:
    """Write DataFrame once. Skip if _SUCCESS or parquet files exist; fail if partial."""
    p = Path(path_str)
    if p.exists():
        if (p / "_SUCCESS").exists() or list(p.glob("*.parquet")):
            print(f"skip {path_str}: already landed")
            return False
        raise RuntimeError(f"Directory {path_str} exists without _SUCCESS or parquet files")
    df.write.parquet(path_str)
    print(f"landed {path_str}")
    return True


def land_dimensions(spark, vol: str, batch: int, all_cust_keys: list[int]):
    """Land static dimensions once in batch 1, and referenced parts/suppliers."""
    if batch != 1:
        return
    for entity in ("nation", "region"):
        write_once(f"{vol}/{entity}/batch=1", spark.table(f"samples.tpch.{entity}"))

    # Part and supplier referenced by the sampled lines across the window
    spark.sql(f"""
        SELECT * FROM samples.tpch.part
        WHERE p_partkey IN (
            SELECT DISTINCT l_partkey FROM samples.tpch.lineitem
            JOIN samples.tpch.orders ON l_orderkey = o_orderkey
            WHERE o_orderdate >= '1995-01-01' AND o_orderdate < '1996-01-01'
              AND o_orderkey % {SAMPLE_MOD} = 0
        )
    """).write.mode("ignore").parquet(f"{vol}/part/batch=1")

    spark.sql(f"""
        SELECT * FROM samples.tpch.supplier
        WHERE s_suppkey IN (
            SELECT DISTINCT l_suppkey FROM samples.tpch.lineitem
            JOIN samples.tpch.orders ON l_orderkey = o_orderkey
            WHERE o_orderdate >= '1995-01-01' AND o_orderdate < '1996-01-01'
              AND o_orderkey % {SAMPLE_MOD} = 0
        )
    """).write.mode("ignore").parquet(f"{vol}/supplier/batch=1")


def land_customers(spark, vol: str, batch: int, all_cust_keys: list[int]):
    """Batch 1 lands all customers with baseline effective date; 2 & 3 land only changes."""
    snap_date = BATCHES[batch]["snapshot_date"]
    cust_path = f"{vol}/customer/batch={batch}"

    if batch == 1:
        keys_str = ", ".join(map(str, all_cust_keys)) or "-1"
        df = spark.sql(f"""
            SELECT c.*, DATE '{snap_date}' AS effective_date
            FROM samples.tpch.customer c
            WHERE c.c_custkey IN ({keys_str})
        """)
        write_once(cust_path, df)
        return []

    # CDC feed: only changed customers
    changes = segment_changes(batch, all_cust_keys)
    if not changes:
        return []

    change_records = []
    for cust_key, change_count in changes:
        row = spark.sql(f"SELECT * FROM samples.tpch.customer WHERE c_custkey = {cust_key}").collect()[0]
        row_dict = row.asDict()
        orig_segment = row_dict["c_mktsegment"]
        new_segment = orig_segment
        for _ in range(change_count):
            new_segment = segment_after(new_segment)
        row_dict["c_mktsegment"] = new_segment
        row_dict["effective_date"] = snap_date
        change_records.append((row_dict, orig_segment, new_segment, change_count))

    df_changes = spark.createDataFrame([r[0] for r in change_records])
    write_once(cust_path, df_changes)
    return [{"customer_key": k, "change": cnt, "from": o, "to": n}
            for _, o, n, cnt in change_records]


def land_orders_and_lines(spark, vol: str, batch: int, F):
    """Land sampled order shard + lines, with flaw injections and delayed header story."""
    start = BATCHES[batch]["start"]
    end = BATCHES[batch]["end"]

    # Source window has no natural invalid rows (verified in Phase 0 profiling)
    raw_orders = spark.sql(f"""
        SELECT * FROM samples.tpch.orders
        WHERE o_orderdate >= DATE '{start}' AND o_orderdate < DATE '{end}'
          AND o_orderkey % {SAMPLE_MOD} = 0
    """)
    orders_df, order_counts = apply_rules(raw_orders, ORDERS_RULES, F)
    write_once(f"{vol}/orders/batch={batch}", orders_df)

    raw_lines = spark.sql(f"""
        SELECT l.* FROM samples.tpch.lineitem l
        JOIN samples.tpch.orders o ON l.l_orderkey = o.o_orderkey
        WHERE o.o_orderdate >= DATE '{start}' AND o.o_orderdate < DATE '{end}'
          AND o.o_orderkey % {SAMPLE_MOD} = 0
    """)

    # Delayed header story: 5 orders from batch 3 whose lines land early in batch 2
    early_keys = [r.o_orderkey for r in spark.sql(f"""
        SELECT o_orderkey FROM samples.tpch.orders
        WHERE o_orderdate >= DATE '{BATCHES[3]['start']}' AND o_orderdate < DATE '{BATCHES[3]['end']}'
          AND o_orderkey % {SAMPLE_MOD} = 0 AND {EARLY_ORDER_PREDICATE}
        ORDER BY o_orderkey LIMIT {EARLY_ORDER_LIMIT}
    """).collect()]

    lines_to_write = raw_lines
    if batch == 2 and early_keys:
        early_lines = spark.sql(f"""
            SELECT l.* FROM samples.tpch.lineitem l
            WHERE l.l_orderkey IN ({', '.join(map(str, early_keys))})
        """)
        lines_to_write = lines_to_write.unionByName(early_lines)
    elif batch == 3 and early_keys:
        lines_to_write = lines_to_write.filter(f"l_orderkey NOT IN ({', '.join(map(str, early_keys))})")

    lines_df, line_counts = apply_rules(lines_to_write, LINEITEM_RULES, F)
    write_once(f"{vol}/lineitem/batch={batch}", lines_df)

    # Expected values = raw valid rows minus injected invalid rows
    inv_orders = order_counts.get("orders_null_customer_key", 0) + order_counts.get("orders_negative_totalprice", 0)
    exp_orders = raw_orders.count() - inv_orders

    inv_lines = line_counts.get("lineitem_nonpositive_quantity", 0) + line_counts.get("lineitem_discount_over_one", 0)
    exp_lines = raw_lines.count() - inv_lines

    # Expected revenue on clean valid source lines
    kpis = spark.sql(f"""
        SELECT
            sum(l_extendedprice * (1 - l_discount)) AS net_rev,
            sum(l_extendedprice * l_discount) AS disc_given,
            sum(if(l_returnflag = 'R', 1, 0)) AS returns
        FROM samples.tpch.lineitem
        JOIN samples.tpch.orders ON l_orderkey = o_orderkey
        WHERE o_orderdate >= DATE '{start}' AND o_orderdate < DATE '{end}'
          AND o_orderkey % {SAMPLE_MOD} = 0
          AND NOT ({ORDERS_RULES[0][1]}) AND NOT ({ORDERS_RULES[1][1]})
          AND NOT ({LINEITEM_RULES[0][1]}) AND NOT ({LINEITEM_RULES[1][1]})
    """).collect()[0]

    expected = {
        "orders": exp_orders,
        "lineitem": exp_lines,
        "net_revenue": str(Decimal(str(kpis.net_rev or 0)).quantize(Decimal("0.01"))),
        "discount_given": str(Decimal(str(kpis.disc_given or 0)).quantize(Decimal("0.01"))),
        "returns": int(kpis.returns or 0),
    }
    injections = {**order_counts, **line_counts}
    return expected, injections, early_keys


def write_manifest(spark, vol: str, batch: int, expected: dict, injections: dict, early_keys: list, changes: list):
    """Write the immutable manifest JSON for the batch."""
    manifest = {
        "batch": batch,
        "shard_start": BATCHES[batch]["start"],
        "shard_end": BATCHES[batch]["end"],
        "snapshot_date": BATCHES[batch]["snapshot_date"],
        "expected_valid": expected,
        "injections": injections,
        "early_lines_order_keys": early_keys,
        "segment_changes": changes,
    }
    manifest_path = f"{vol}/_manifest/batch={batch}"
    (spark.createDataFrame([(json.dumps(manifest, sort_keys=True),)], "manifest STRING")
     .repartition(1).write.mode("overwrite").text(manifest_path))
    print(f"wrote manifest for batch {batch}")


def main():
    parser = argparse.ArgumentParser(description="Simulate landing batches")
    parser.add_argument("--catalog", default="meridian_t02")
    parser.add_argument("--batch", default="next")
    args = parser.parse_args()

    vol = f"/Volumes/{args.catalog}/landing/raw_files"
    manifest_dir = Path(f"{vol}/_manifest")
    landed_count = len(list(manifest_dir.glob("batch=*"))) if manifest_dir.exists() else 0
    next_batch = landed_count + 1

    if args.batch == "next":
        target_batch = next_batch
    else:
        target_batch = int(args.batch)
        if target_batch <= landed_count:
            print(f"Batch {target_batch} already landed (total landed: {landed_count}). Nothing to do.")
            return
        if target_batch > next_batch:
            raise ValueError(f"Cannot run batch {target_batch}: next expected batch is {next_batch}")

    if target_batch > FINAL_BATCH:
        print(f"All {FINAL_BATCH} batches already landed.")
        return

    from pyspark.sql import SparkSession, functions as F
    spark = SparkSession.builder.getOrCreate()

    # All customer keys referenced by sampled orders across the entire 1995 window
    all_cust_keys = [r.o_custkey for r in spark.sql(f"""
        SELECT DISTINCT o_custkey FROM samples.tpch.orders
        WHERE o_orderdate >= '1995-01-01' AND o_orderdate < '1996-01-01'
          AND o_orderkey % {SAMPLE_MOD} = 0
    """).collect()]

    land_dimensions(spark, vol, target_batch, all_cust_keys)
    changes = land_customers(spark, vol, target_batch, all_cust_keys)
    expected, injections, early_keys = land_orders_and_lines(spark, vol, target_batch, F)
    write_manifest(spark, vol, target_batch, expected, injections, early_keys, changes)
    print(f"Batch {target_batch} landing completed successfully.")


if __name__ == "__main__":
    main()
