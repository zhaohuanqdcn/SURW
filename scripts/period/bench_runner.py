import polars as pl
import sys
import subprocess as sp
import random
import os
import sys
import json
import shutil
import time
import numpy as np
from tqdm import tqdm
import argparse

required_args = []

parser = argparse.ArgumentParser(prog='Benchmark Runner', description="Runs an algorithm on a benchmark program. Arguments may also be passed as environment variables")

config_key = "--bench-config"
env_key = config_key.lstrip("-").replace("-","_").upper()
parser.add_argument(config_key, metavar="<Benchmark Config File>", help=f'[ Environment variable: {env_key} ] JSON file with benchmark program paths, arguments, inputs etc.', default=os.environ.get(env_key))
required_args += [env_key.lower()]

config_key = "--tool-config"
env_key = config_key.lstrip("-").replace("-","_").upper()
parser.add_argument(config_key, help=f'[ Environment variable: {env_key} ] JSON file with algorithm, timeout etc.', default=os.environ.get(env_key))
required_args += [env_key.lower()]

config_key = "--program-key"
env_key = config_key.lstrip("-").replace("-","_").upper()
parser.add_argument(config_key, help=f'[ Environment variable: {env_key} ] Benchmark program to run. Should be a key in the Bencmark Config. JSON file', default=os.environ.get(env_key))
required_args += [env_key.lower()]

config_key = "--random-seed"
env_key = config_key.lstrip("-").replace("-","_").upper()
parser.add_argument(config_key, help=f'[ Environment variable: {env_key} ] Random seed for the trials', default=os.environ.get(env_key))

config_key = "--output-dir"
env_key = config_key.lstrip("-").replace("-","_").upper()
parser.add_argument(config_key, help=f'[ Environment variable: {env_key} ] Output directory', default=os.environ.get(env_key))
required_args += [env_key.lower()]

args = parser.parse_args()

for k, v in vars(args).items():
    if k in required_args and v is None:
        print(f"Missing {k}...")
        parser.print_help()
        exit(1)

assert(os.path.basename(os.getcwd()) == "layeredct")

if args.random_seed is None:
    args.random_seed = 0


f = open(args.bench_config)
subject_config = json.loads(f.read())
f.close()

name = subject_config[args.program_key]["name"]
stem = subject_config[args.program_key]["stem"]
prog_args = subject_config[args.program_key]["args"]
inputs = subject_config[args.program_key]["inputs"]
libs = subject_config[args.program_key]["libs"]
e = subject_config[args.program_key]["path"]

if '@@' in prog_args:
    prog_args = prog_args[:-2]

prog_args += ' '.join(inputs)

print()
print(f"Instrumenting {e}...")

sp.run(f"./instrument.sh {e}", shell=True, check=True)
inst = f"./{os.path.basename(e)}.inst"

print(f"Instrumented executable at {inst}")

df = None
mem_list = []
norm_weights = []
children = {}

def init_target_addr():
    global df, mem_list, norm_weights, children
    if os.path.getsize("var_count.csv") == 0:
        stats = {
            "program": args.program_key, "tool": args.tool_config,
            "iterations": 0, "time_seconds": 0, "found": True,
        }
        with open(f"{args.output_dir}/{args.random_seed}.json", "w") as f:
            f.write(json.dumps(stats))
        exit(0)
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


random.seed(args.random_seed)
tool_config_file = args.tool_config 

config = {}
with open(tool_config_file, 'r') as file:
    config = json.load(file)

prog = inst 

N = config['iteration']
timeout = config["timeout"]
log_file = f"{os.getcwd()}/{config['log_file']}"
method = config['method']
alg1 = config['alg1']
alg2 = config['alg2']

lib_args = f'{os.getcwd()}/zig-out/lib/libzigsched.so'

if len(libs) > 0:
    for lib_dir in libs.split(':'):
        files = os.listdir(lib_dir)
        so_files = [os.path.join(lib_dir, file) for file in files if file.endswith('.so')]
        lib_dir_args = ':'.join(so_files)
        lib_args +=  f':{lib_dir_args}'

stats = {
        "program": args.program_key,
        "tool": args.tool_config,
}

# initial run
print("starting initial dry run...")
command = [ f"LOG_FILE={log_file}", \
            f"METHOD=lock_addr" 
                if "radbench" in e.lower() or "qsort" in e.lower() 
                else "", \
            f"LD_PRELOAD={lib_args}", \
            f"{prog}"
        ]
command = " ".join(command)
command = f"{command} {prog_args}" 
print(command)
result = sp.run(command, shell=True, capture_output=True)
if result.returncode != 0:
    print(f"dry run failed with exit code {result.returncode}")
    if method == 'memory_addr': 
        stats["iterations"] = 0
        stats["time_seconds"] = 0 
        stats["found"] = True
        outf = open(f"{args.output_dir}/{args.random_seed}.json", "w")
        outf.write(json.dumps(stats))
        outf.close()
        exit()

alg_args = []
if 'pct' in (alg1, alg2):
    max_event, max_thread = process_log_file(log_file)
    max_event = int(max_event * 1.2)
    alg_args.append(f"MAX_EVENTS={max_event}")
    alg_args.append(f"MAX_THREADS={max_thread}")
    alg_args.append(f"MAX_DEPTH={config['depth']}")

if "radbench" in e.lower() or 'qsort' in e.lower():
    method = 'lock_addr'

method_args = []
target_addr = None
next = 0
if method in ['memory_addr', 'lock_addr']:
    get_count_from_log(log_file, "var")
    init_target_addr()
if method == 'sched_yield':
    get_count_from_log(log_file, "yield")
if method == 'always_true':
    get_count_from_log(log_file, "event")

if "safestack" in prog.lower():
    N *= 100

print(f"init completed. starting {N} iterations...")

start = time.time()
for i in tqdm(range(N), desc="Processing", unit="items"):
    if 'addr' in method and len(mem_list) > 1:
        target_addr = choose_target_addr()
        method_args = [f"TARGET_ADDR={target_addr}"]
    
    common_arg = [ 
                f"RANDOM_SEED={random.randint(0, 2**20)}", \
                f"METHOD={method} ALG1={alg1} ALG2={alg2}", \
                f"LD_PRELOAD={lib_args}", \
                f"{prog}"
            ]
    command = alg_args + method_args + common_arg

    command = " ".join(command)
    command = f"{command} {prog_args}" 
    result = sp.run(command, shell=True, capture_output=True)
    
    if result.returncode < 0:
        end = time.time()
        stats["iterations"] = i + 1
        stats["time_seconds"] = end - start 
        stats["found"] = True
        print(f"first crash after {i + 1} iterations")

        outf = open(f"{args.output_dir}/{args.random_seed}.json", "w")
        outf.write(json.dumps(stats))
        outf.close()

        exit(0)

end = time.time()
stats["iterations"] = N
stats["time_seconds"] = end - start 
stats["found"] = False 

outf = open(f"{args.output_dir}/{args.random_seed}.json", "w")
outf.write(json.dumps(stats))
outf.close()
