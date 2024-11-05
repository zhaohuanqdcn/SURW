import polars as pl
import sys


df = pl.scan_csv(sys.argv[1], separator="|", has_header=False, new_columns = ["thread", "op", "instr"])


forks = df.with_columns(
    pl.col("op").str.split("(").list.first().alias("op_name"),
    pl.col("op").str.split("(").list.get(1).str.split(")").list.first().alias("child"),
).select(["thread", "op_name", "child"])

forks = (forks
        .filter(pl.col("op_name") == "fork")
        .select(["thread", "child"])
        .sort(["thread", "child"])
        .collect())

children = {}
for p, c in zip(forks['thread'], forks['child']):
    if p not in children:
        children[p] = []
    children[p].append(int(c))

with open("fork.in", "w") as f:
    f.write(str(children))