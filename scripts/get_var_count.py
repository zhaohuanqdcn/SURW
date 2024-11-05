import polars as pl
import sys


df = pl.scan_csv(sys.argv[1], separator="|", has_header=False, new_columns = ["thread", "op", "instr"])

df = df.with_columns(
    pl.col("op").str.split("(").list.first().alias("op_name"),
    pl.col("op").str.split("@").list.get(1).str.split(")").list.first().alias("mem_addr"),
    pl.col("instr").str.split("@").list.get(1).alias("instr_addr"),
).select(["thread", "op_name", "mem_addr"])

threads = df.select("thread").unique()

total_thread = threads.collect().height

df = (df
    .group_by(["thread", "mem_addr", "op_name"]).agg(pl.count())
    .with_columns((pl.col("op_name") == "w").alias("contains_write"))
    .group_by(["thread", "mem_addr"]).agg(
        pl.sum("count"),
        pl.sum("contains_write"))
)

multi_use = (df
    .group_by(["mem_addr"])
    .agg([pl.col("thread").unique().alias("threads"), pl.sum("contains_write")])
    .with_columns(pl.col("threads").map_elements(lambda x: len(x) >= max(2, int(total_thread / 2))).alias("multi_use"))
    .filter(pl.col("multi_use"))
    .filter(pl.col("contains_write") > 0)
    .select("mem_addr")
)

df = df.join(multi_use, on="mem_addr")

mems = df.select("mem_addr").unique().sort("mem_addr")

combinations = mems.join(threads, how="cross")

df = (combinations
    .join(df, on=["mem_addr", "thread"], how="left")
    .fill_null(0)
    .sort(["mem_addr", "thread"])
)

df = df.collect()
# print(df)
df.write_csv("var_count.csv", include_header=False)

