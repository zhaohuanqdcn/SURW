import polars as pl
import sys


df = pl.scan_csv(sys.argv[1], separator="|", has_header=False, new_columns = ["thread", "op", "instr"])

df = df.group_by(["thread"]).agg(pl.count()).sort(["thread"])

df = df.collect()

f = open("fork.in", "r")
for line in f:
    children = eval(line)

counts = {}
for thr, cnt in zip(df["thread"], df["count"]):
    counts[thr] = cnt

def get_count(thr):
    result = counts[thr]
    for c in children.get(thr, []):
        result += get_count(c)
    return result

with open("estimate.in", 'w') as f:
    for thr in df["thread"]:
        f.write(str(thr) + '\n' + str(get_count(thr)) + '\n')
