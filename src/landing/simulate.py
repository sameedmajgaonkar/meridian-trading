"""Landing simulator — generates deterministic parquet batches in landing volume."""
import argparse
from pathlib import Path
from bad_data import BATCHES, NEXT_SEGMENT, SAMPLE_MOD, get_segment_changes


def write_batch(df, path: str):
    if Path(path).exists():
        print(f"skip {path}: already landed")
        return
    df.write.parquet(path)
    print(f"landed {path}")


def land_dimensions(spark, vol: str, batch: int):
    if batch != 1:
        return
    for t in ("nation", "region"):
        write_batch(spark.table(f"samples.tpch.{t}"), f"{vol}/{t}/batch=1")
    write_batch(spark.sql(f"SELECT * FROM samples.tpch.part WHERE p_partkey % {SAMPLE_MOD} = 0"), f"{vol}/part/batch=1")
    write_batch(spark.sql(f"SELECT * FROM samples.tpch.supplier WHERE s_suppkey % {SAMPLE_MOD} = 0"), f"{vol}/supplier/batch=1")


def land_customers(spark, vol: str, batch: int, all_keys: list[int]):
    snap = BATCHES[batch]["snapshot_date"]
    path = f"{vol}/customer/batch={batch}"
    if batch == 1:
        df = spark.table("samples.tpch.customer").filter(f"c_custkey % {SAMPLE_MOD} = 0") \
                  .selectExpr("*", f"DATE '{snap}' AS effective_date")
        write_batch(df, path)
        return
    keys = get_segment_changes(batch, all_keys)
    base = spark.table("samples.tpch.customer").filter(f"c_custkey IN ({','.join(map(str, set(keys)))})").collect()
    cust_map = {r.c_custkey: r.asDict() for r in base}
    rows = []
    for k in keys:
        d = cust_map[k].copy()
        d["c_mktsegment"] = NEXT_SEGMENT[d["c_mktsegment"]]
        if batch == 3 and k in all_keys[:2]:
            d["c_mktsegment"] = NEXT_SEGMENT[d["c_mktsegment"]]
        d["effective_date"] = snap
        rows.append(d)
    write_batch(spark.createDataFrame(rows), path)


def land_orders_and_lines(spark, vol: str, batch: int):
    start, end = BATCHES[batch]["start"], BATCHES[batch]["end"]
    early_keys = [r.o_orderkey for r in spark.sql(f"""
        SELECT o_orderkey FROM samples.tpch.orders
        WHERE o_orderdate >= '{BATCHES[3]['start']}' AND o_orderdate < '{BATCHES[3]['end']}'
          AND o_orderkey % {SAMPLE_MOD} = 0 ORDER BY o_orderkey LIMIT 5""").collect()]

    raw_orders = spark.sql(f"""
        SELECT * FROM samples.tpch.orders
        WHERE o_orderdate >= DATE '{start}' AND o_orderdate < DATE '{end}' AND o_orderkey % {SAMPLE_MOD} = 0""")
    orders = raw_orders.selectExpr("*", "row_number() OVER (ORDER BY o_orderkey) AS rn")
    orders = orders.selectExpr("*", "IF(rn = 3, CAST(NULL AS BIGINT), o_custkey) AS new_custkey") \
                   .drop("o_custkey", "rn").withColumnRenamed("new_custkey", "o_custkey")
    write_batch(orders, f"{vol}/orders/batch={batch}")

    raw_lines = spark.sql(f"""
        SELECT l.* FROM samples.tpch.lineitem l JOIN samples.tpch.orders o ON l.l_orderkey = o.o_orderkey
        WHERE o.o_orderdate >= DATE '{start}' AND o.o_orderdate < DATE '{end}' AND o.o_orderkey % {SAMPLE_MOD} = 0""")
    if batch == 2:
        early_lines = spark.table("samples.tpch.lineitem").filter(f"l_orderkey IN ({','.join(map(str, early_keys))})")
        raw_lines = raw_lines.unionByName(early_lines)
    elif batch == 3:
        raw_lines = raw_lines.filter(f"l_orderkey NOT IN ({','.join(map(str, early_keys))})")

    lines = raw_lines.selectExpr("*", "row_number() OVER (ORDER BY l_orderkey, l_linenumber) AS rn")
    lines = lines.selectExpr("*",
        "IF(rn = 5, -l_quantity, l_quantity) AS new_qty",
        "IF(rn = 11, l_discount + 1.0, l_discount) AS new_disc"
    ).drop("l_quantity", "l_discount").withColumnRenamed("new_qty", "l_quantity").withColumnRenamed("new_disc", "l_discount")
    dup_row = lines.filter("rn = 23")
    lines = lines.unionByName(dup_row).drop("rn")
    write_batch(lines, f"{vol}/lineitem/batch={batch}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="meridian_t02")
    p.add_argument("--batch", default="next")
    args = p.parse_args()
    vol = f"/Volumes/{args.catalog}/landing/raw_files"
    landed = [int(p.name.split("=")[1]) for p in Path(f"{vol}/orders").glob("batch=*") if p.name.split("=")[1].isdigit()]
    current = max(landed) if landed else 0
    batch = current + 1 if args.batch == "next" else int(args.batch)
    if batch > 3 or (args.batch != "next" and batch <= current):
        print(f"Batch {batch} already landed or exceeds 3. Done.")
        return
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.getOrCreate()
    all_keys = [r.c_custkey for r in spark.table("samples.tpch.customer").filter(f"c_custkey % {SAMPLE_MOD} = 0").select("c_custkey").collect()]
    land_dimensions(spark, vol, batch)
    land_customers(spark, vol, batch, all_keys)
    land_orders_and_lines(spark, vol, batch)
    print(f"Batch {batch} landing finished.")


if __name__ == "__main__":
    main()
