"""Land related Parquet batches; replace only our interrupted writes.

_completed markers track atomic batch completion in DBFS/Volumes:
- started: touched before dataset write to detect interrupted/partial writes
- done: touched after dataset write completes successfully
- batch=N: sentinel file touched once all entities for batch N are verified
"""
import argparse
import json
import re
from pathlib import Path
from batch_plan import BATCHES, NEXT_SEGMENT, SAMPLE_MOD, get_segment_changes


def resolve_batch(volume, requested):
    completed = Path(volume) / "_completed"
    if requested == "next":
        return next((b for b in BATCHES if not (completed / f"batch={b}").is_file()), 3)
    if requested not in ("1", "2", "3"):
        raise ValueError("batch must be 1, 2, 3, or next")
    batch = int(requested)
    if any(not (completed / f"batch={b}").is_file() for b in range(1, batch)):
        raise ValueError("Earlier batches must complete first")
    return batch


def write_batch(df, path):
    dataset = Path(path)
    markers = dataset.parent.parent / "_completed"
    markers.mkdir(parents=True, exist_ok=True)
    done = markers / f"{dataset.parent.name}.{dataset.name}"
    started = Path(f"{done}.started")
    if done.is_file():
        return
    if dataset.exists() and not started.is_file():
        raise RuntimeError(f"Unmarked existing dataset: {path}")
    started.touch()
    df.write.mode("overwrite").parquet(str(path))
    done.touch()


def freeze_budget(volume, budget):
    marker = Path(volume) / "_completed" / "config.json"
    marker.parent.mkdir(parents=True, exist_ok=True)
    config = {"rows_per_batch": budget, "sample_mod": SAMPLE_MOD}
    if marker.exists() and json.loads(marker.read_text()) != config:
        raise ValueError("Use the original budget for this replay")
    marker.write_text(json.dumps(config))


def sample_orders(spark, budget):
    from pyspark.sql import functions as F, Window
    orders = spark.table("samples.tpch.orders").where(
        f"o_orderdate >= DATE '1995-01-01' AND o_orderdate < DATE '1996-01-01' "
        f"AND o_custkey % {SAMPLE_MOD} = 0")
    period = F.when(F.col("o_orderdate") < F.lit("1995-07-01").cast("date"), 1).when(
        F.col("o_orderdate") < F.lit("1995-10-01").cast("date"), 2).otherwise(3)
    demo = [r.o_custkey for r in orders.groupBy("o_custkey").agg(F.countDistinct(period).alias("periods"))
            .where("periods = 3").orderBy("o_custkey").limit(2).collect()]
    if len(demo) != 2:
        raise ValueError("Need two customers with orders in all three history periods")
    window = F.when(F.col("o_orderdate") < F.lit("1995-05-01").cast("date"), 1).when(
        F.col("o_orderdate") < F.lit("1995-09-01").cast("date"), 2).otherwise(3)
    orders = orders.withColumn("landing_batch", window)
    reserved = orders.where(F.col("o_custkey").isin(demo)).groupBy("landing_batch").count().collect()
    if any(r["count"] > budget for r in reserved):
        raise ValueError("Increase the header budget to retain demonstration-customer orders")
    rank = Window.partitionBy("landing_batch").orderBy(
        F.when(F.col("o_custkey").isin(demo), 0).otherwise(1), "o_orderkey")
    return orders.withColumn("rn", F.row_number().over(rank)).where(F.col("rn") <= budget).drop(
        "rn", "landing_batch"), demo


def land_dimensions(spark, volume, lines):
    from pyspark.sql import functions as F
    for entity, key, foreign_key in (("part", "p_partkey", "l_partkey"),
                                     ("supplier", "s_suppkey", "l_suppkey")):
        df = spark.table(f"samples.tpch.{entity}").join(
            lines.select(foreign_key).distinct(), F.col(key) == F.col(foreign_key), "left_semi")
        write_batch(df, f"{volume}/{entity}/batch=1")
    for entity in ("nation", "region"):
        write_batch(spark.table(f"samples.tpch.{entity}"), f"{volume}/{entity}/batch=1")


def land_customers(spark, volume, orders, demo, batch):
    from pyspark.sql import functions as F
    df = spark.table("samples.tpch.customer").join(
        orders.select("o_custkey").distinct(), F.col("c_custkey") == F.col("o_custkey"), "left_semi")
    if batch > 1:
        df = df.where(F.col("c_custkey").isin(get_segment_changes(batch, demo)))
    cycle = F.create_map(*[F.lit(v) for pair in NEXT_SEGMENT.items() for v in pair])
    for _ in range(batch - 1):
        df = df.withColumn("c_mktsegment", F.element_at(cycle, F.col("c_mktsegment")))
    df = df.withColumn("effective_date", F.lit(BATCHES[batch]["snapshot_date"]).cast("date"))
    write_batch(df, f"{volume}/customer/batch={batch}")


def land_orders_and_lines(spark, volume, orders, lines, demo, batch):
    from pyspark.sql import functions as F, Window
    spec = BATCHES[batch]
    current = orders.where(f"o_orderdate >= DATE '{spec['start']}' AND o_orderdate < DATE '{spec['end']}'")
    targets = current.where(~F.col("o_custkey").isin(demo)).orderBy("o_orderkey").limit(1).collect()
    if not targets:
        raise ValueError("Need a nondemonstration customer for null-key injection")
    bad_key = targets[0].o_orderkey
    corrupt = current.withColumn("o_custkey", F.when(F.col("o_orderkey") == bad_key,
                                 F.lit(None).cast("long")).otherwise(F.col("o_custkey")))
    write_batch(corrupt, f"{volume}/orders/batch={batch}")
    # Skip batch 3's null-customer header; its other five selected headers arrive later.
    early = [r.o_orderkey for r in orders.where("o_orderdate >= DATE '1995-09-01'")
             .where(~F.col("o_custkey").isin(demo)).orderBy("o_orderkey").limit(6).collect()][1:]
    if len(early) != 5:
        raise ValueError("Need five clean delayed headers")
    current_lines = lines.join(current.select("o_orderkey"),
                               F.col("l_orderkey") == F.col("o_orderkey"), "left_semi")
    if batch == 3:
        current_lines = current_lines.where(~F.col("l_orderkey").isin(early))
    ranked = current_lines.withColumn("rn", F.row_number().over(Window.orderBy("l_orderkey", "l_linenumber")))
    if ranked.where("rn = 23").count() != 1:
        raise ValueError("Need 23 lines to exercise all injections")
    corrupt = ranked.withColumn("l_quantity", F.when(F.col("rn") == 5, -F.col("l_quantity"))
                                .otherwise(F.col("l_quantity"))).withColumn("l_discount",
        F.when(F.col("rn") == 11, F.lit(1.1).cast("decimal(12,2)")).otherwise(F.col("l_discount")))
    corrupt = corrupt.unionByName(corrupt.where("rn = 23")).drop("rn")
    if batch == 2:
        corrupt = corrupt.unionByName(lines.where(F.col("l_orderkey").isin(early)))
    write_batch(corrupt, f"{volume}/lineitem/batch={batch}")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--warehouse", required=True)
    parser.add_argument("--batch", default="next")
    parser.add_argument("--rows-per-batch", type=int, default=2000)
    return parser.parse_args()


def stop_warehouse(warehouse_id):
    """Free Edition pipeline capacity is exhausted if the warehouse stays running."""
    from databricks.sdk import WorkspaceClient
    WorkspaceClient().warehouses.stop(warehouse_id).result()


def main(args=None):
    if args is None:
        args = parse_args()
    if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", args.catalog) or args.rows_per_batch <= 0:
        raise ValueError("Use a simple catalog identifier and positive header budget")
    volume = f"/Volumes/{args.catalog}/landing/raw_files/trading"
    freeze_budget(volume, args.rows_per_batch)
    batch = resolve_batch(volume, args.batch)
    if (Path(volume) / "_completed" / f"batch={batch}").is_file():
        print(f"Batch {batch} already complete")
        return
    from pyspark.sql import SparkSession, functions as F
    spark = SparkSession.builder.getOrCreate()
    orders, demo = sample_orders(spark, args.rows_per_batch)
    lines = spark.table("samples.tpch.lineitem").join(
        orders.select("o_orderkey"), F.col("l_orderkey") == F.col("o_orderkey"), "left_semi")
    if batch == 1:
        land_dimensions(spark, volume, lines)
    land_customers(spark, volume, orders, demo, batch)
    land_orders_and_lines(spark, volume, orders, lines, demo, batch)
    entities = ("orders", "lineitem", "customer", "part", "supplier", "nation", "region") if batch == 1 else (
        "orders", "lineitem", "customer")
    assert all((Path(volume) / "_completed" / f"{e}.batch={batch}").is_file() for e in entities)
    (Path(volume) / "_completed" / f"batch={batch}").touch()
    print(f"Batch {batch} complete; demonstration customers {demo}")


if __name__ == "__main__":
    args = parse_args()
    main(args)
    stop_warehouse(args.warehouse)
