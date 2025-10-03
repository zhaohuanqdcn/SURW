import polars as pl
import sys
import subprocess
import re

def get_all_from_binary(binary_path):
    command = ['objdump', '-d', binary_path]
    result = subprocess.run(command, stdout=subprocess.PIPE, text=True)
    address_pattern = re.compile(r'^\s*([0-9a-fA-F]+):\s', re.MULTILINE)
    addresses = address_pattern.findall(result.stdout)
    return addresses

df = pl.scan_csv(sys.argv[1], separator="|", has_header=False, new_columns = ["thread", "op", "instr"])

df = df.with_columns(
    pl.col("op").str.split("(").list.first().alias("op_name"),
    pl.col("op").str.split("(").list.get(1).str.split(")").list.first().alias("mem_addr"),
    pl.col("instr").str.split("(").list.get(1).alias("instr_addr"),
).select(["thread", "op_name", "mem_addr", "instr_addr"])

read_only = (df
    .group_by(["mem_addr", "op_name"]).agg(pl.count())
    .with_columns((pl.col("op_name") == "w").alias("contains_write"))
    .group_by("mem_addr").agg(pl.sum("contains_write"))
    .filter(pl.col("contains_write") == 0)
    .select("mem_addr")
)

ro_mem = set(read_only.collect().to_dict()["mem_addr"].to_list())

# instr that only accesses read_only memories
read_only = (df
    .group_by("instr_addr")
    .agg(pl.col("mem_addr").unique().alias("mem_addr_list"))
    .with_columns(
        pl.col("mem_addr_list").map_elements(lambda x: set(x).issubset(ro_mem)).alias("read_only")
    )
    .filter(pl.col("read_only"))
    .select("instr_addr").collect()
)

high_use = (df
    .group_by("instr_addr")
    .agg(pl.count()).filter(pl.col("count") > 500)
    .select("instr_addr").collect()
)

hu_inst = high_use.to_dict()["instr_addr"].to_list()
ro_inst = read_only.to_dict()["instr_addr"].to_list()
new_excluded = set(hu_inst + ro_inst)
print("new excluded instructions: ", new_excluded)
if len(new_excluded) == 0:
    print("no new instr to be excluded")
    exit(0)

with open("exclude.csv", "a") as f:
    for addr in new_excluded:
        f.write(f'{addr}\n')

excluded = set()
with open("exclude.csv", "r") as f:
    excluded = set([line.strip() for line in f])
    
binary_path = sys.argv[2]
with open("out.csv", "w") as f:
    for addr in get_all_from_binary(binary_path):
        if addr not in excluded:
            f.write(f'0x{addr}\n')