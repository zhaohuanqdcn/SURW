import polars as pl
import sys
import subprocess as sp
import random
import os
import sys
import json
from tqdm import tqdm

df = None
mem_list = []
norm_weights = []
children = {}

def init_target_addr():
    global df, mem_list, norm_weights, children
    df = pl.read_csv("var_count.csv", separator=",", has_header=False, new_columns = ["mem_addr", "thread", "count", "write"])
    grouped_sum = df.group_by("mem_addr").agg(pl.sum("count").alias("sum")).sort("mem_addr")
    mem_list = grouped_sum["mem_addr"].to_numpy()
    weights = grouped_sum["sum"].to_numpy()
    norm_weights = weights / weights.sum()
    f = open("fork.in", "r")
    for line in f:
        children = eval(line)

def get_count(thr, counts):
    result = counts[thr]
    for c in children.get(thr, []):
        result += get_count(c, counts)
    return result

def choose_target_addr():
    global df, mem_list, norm_weights, children
    idx = random.choices(range(len(mem_list)), weights=norm_weights, k=1)[0]
    target_addr = mem_list[idx]
    
    data = df.filter(pl.col("mem_addr") == target_addr).sort("thread")
    counts = {}
    for row in data.to_dicts():
        counts[row["thread"]] = row["count"]
    with open("estimate.in", 'w') as f:
        for thr in data["thread"]:
            f.write(str(thr) + '\n' + str(get_count(thr, counts)) + '\n')
    return target_addr

def process_log_file(file_path):
    df = pl.scan_csv(file_path, separator="|", has_header=False, new_columns = ["thread", "op", "instr"])
    threads = df.select("thread").unique()
    return df.collect().height, threads.collect().height

def get_count_from_log(file_path, type):
    sp.run(["python3", f"{os.getcwd()}/scripts/get_forks.py", file_path], capture_output=True)
    sp.run(["python3", f"{os.getcwd()}/scripts/get_{type}_count.py", file_path], capture_output=True)

random.seed(42)

if len(sys.argv) < 3:
    print("Usage: python3 scripts/run_one.py config_path program args")
    exit(-1)

config = {}
config_file = sys.argv[1]
with open(config_file, 'r') as file:
    config = json.load(file)

prog = " ".join(sys.argv[2:])

N = config['iteration']
timeout = config["timeout"]
log_file = f"{os.getcwd()}/{config['log_file']}"
method = config['method']
alg1 = config['alg1']
alg2 = config['alg2']

# initial run
print("starting initial dry run...")
command = [ f"LOG_FILE={log_file}", \
            f"LD_PRELOAD={os.getcwd()}/zig-out/lib/libzigsched.so", \
            f"{prog}"
        ]
result = sp.run(" ".join(command), shell=True, capture_output=True)
if result.returncode != 0:
    print(f"dry run failed with exit code {result.returncode}")
    exit(-1)

alg_args = []
if 'pct' in (alg1, alg2):
    max_event, max_thread = process_log_file(log_file)
    max_event = int(max_event * 1.2)
    alg_args.append(f"MAX_EVENTS={max_event}")
    alg_args.append(f"MAX_THREADS={max_thread}")
    alg_args.append(f"MAX_DEPTH={config['depth']}")

method_args = []
target_addr = None
if method == 'memory_addr':
    get_count_from_log(log_file, "var")
    init_target_addr()
if method == 'sched_yield':
    get_count_from_log(log_file, "yield")

print(f"init completed. starting {N} iterations...")

for i in tqdm(range(N), desc="Processing", unit="items"):
    if method == 'memory_addr' and len(mem_list) > 1:
        target_addr = choose_target_addr()
        method_args = [f"TARGET_ADDR={target_addr}"]
    
    common_arg = [ 
                f"RANDOM_SEED={random.randint(0, 2**20)}", \
                f"METHOD={method} ALG1={alg1} ALG2={alg2}", \
                f"LD_PRELOAD={os.getcwd()}/zig-out/lib/libzigsched.so", \
                f"{prog}"
            ]
    command = alg_args + method_args + common_arg

    result = sp.run(" ".join(command), shell=True, capture_output=True)
    
    if result.returncode != 0:
        print(f"first crash after {i} iterations")
        exit(-1)
