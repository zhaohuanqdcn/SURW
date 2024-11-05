import polars as pl
import sys
import subprocess as sp
import random
import os
import sys
import json
import struct
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
prog_args += ' '.join(libs)

print()
print(f"Instrumenting {e}...")

sp.run(f"./instrument.sh {e}", shell=True, check=True)
inst = f"./{os.path.basename(e)}.inst"

print(f"Instrumented executable at {inst}")

df = None
total = 0
mem_list = []
sum_list = []
children = {}

def init_target_addr():
    global df, total, mem_list, sum_list, children
    df = pl.read_csv("var_count.csv", separator=",", has_header=False, new_columns = ["mem_addr", "thread", "count", "write"])
    grouped_sum = df.group_by("mem_addr").agg(pl.sum("count").alias("sum")).sort("mem_addr")
    total = df.select("count").sum()["count"][0]
    mem_list = grouped_sum["mem_addr"].to_numpy()
    sum_list = grouped_sum["sum"].to_numpy()
    # print(total, total / len(mem_list))
    f = open("fork.in", "r")
    for line in f:
        children = eval(line)

def get_count(thr, counts):
    result = counts[thr]
    for c in children.get(thr, []):
        result += get_count(c, counts)
    return result

def choose_target_addr():
    global df, total, mem_list, sum_list
    idx = random.choice(range(len(mem_list)))
    curr_total = 0
    for i in range(len(mem_list) - idx):
        if curr_total >= int(total / len(mem_list)):
            break 
        curr_total += sum_list[idx + i]
    target_addr = [mem_list[idx + x] for x in range(i + 1)]

    data = df.filter(pl.col("mem_addr").is_in(target_addr)).group_by("thread").agg(pl.col("count").sum().alias("total_count")).sort("thread")
    counts = {}
    for row in data.to_dicts():
        counts[row["thread"]] = row["total_count"]
    with open("estimate.in", 'w') as f:
        for thr in data["thread"]:
            f.write(str(thr) + '\n' + str(get_count(thr, counts)) + '\n')
    return target_addr[0], target_addr[-1]

def process_log_file(file_path):
    df = pl.scan_csv(file_path, separator="|", has_header=False, new_columns = ["thread", "op", "instr"])
    threads = df.select("thread").unique()
    return df.collect().height, threads.collect().height

def get_count_from_log(file_path, type):
    sp.run(["python3", f"{os.getcwd()}/scripts/get_forks.py", file_path], capture_output=True)
    sp.run(["python3", f"{os.getcwd()}/scripts/get_{type}_count.py", file_path], capture_output=True)

def l2s(l):
    ss = []
    for i, v in enumerate(l):
        if v > 0:
            ss.append("[%d]=%s" % (i,v))
    return ",".join(ss)

def show(data):
    print("(sum %d, unique %d): %s" % (sum(data), sum(map(bool, data)), l2s(data)))

def get_triggered_bugs(stat_path):
    if not os.path.exists(stat_path):
        return []
    with open(stat_path, "rb") as f:
        data = f.read()
    os.remove(stat_path)
    bug_num = (len(data) // 8 - 1) // 2
    assert len(data) == 8 * (bug_num * 2 + 1)
    unpacked = list(struct.iter_unpack("<Q", data))
    unpacked = [x[0] for x in unpacked]
    unpacked = unpacked[1:]
    trigger_num = unpacked[0:bug_num]
    show(trigger_num)
    return [i for i in range(bug_num) if trigger_num[i]>0]


random.seed(args.random_seed)
tool_config_file = args.tool_config 

config = {}
with open(tool_config_file, 'r') as file:
    config = json.load(file)

prog = inst 

N = int(config['iteration'] / 20)
timeout = config["timeout"]
log_file = f"{os.getcwd()}/{config['log_file']}"
method = config['method']
alg1 = config['alg1']
alg2 = config['alg2']
command = [
            f"LOG_FILE={log_file}", \
            f"LD_PRELOAD={os.getcwd()}/zig-out/lib/libzigsched.so", \
            f"ALG2=rp", \
            f"{prog}"
        ]

stat_file = ".rb_stat"
stats = {
        "program": args.program_key,
        "tool": args.tool_config,
        }

sel_instr = ["cholesky", "fluidanimate", "raytrace"]

for tc in range(20):
    # initial run
    print(f"starting initial dry run for input-{tc}...")
    command_tc = " ".join(command)
    command_tc = f"{command_tc} {prog_args}".replace("#", str(tc)) 
    
    for si in range(10):
        try:
            result = sp.run(command_tc, shell=True, capture_output=True, timeout=60)
            # no timeout: finish dry run
            if result.returncode != 0:
                print(f"dry run failed with exit code {result.returncode}")
        except sp.TimeoutExpired:
            # timeout: retry with selective instr
            if any([name in prog for name in sel_instr]):
                print(f"dry run {si} timeout. selective instr will be used")
                sp.run(["python3", f"{os.getcwd()}/scripts/get_event_subset.py", log_file, e], capture_output=True)
                sp.run(f"SEL_INSTR=out.csv ./instrument.sh {e}", shell=True, check=True)
                continue
            else:
                print(f"dry run timeout.")
        break

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

    print(f"starting {N} iterations for input-{tc}......")

    for i in tqdm(range(N), desc="Processing", unit="items"):
        if method == 'memory_addr':
            target_addr, end_addr = choose_target_addr()
            # print(target_addr, end_addr)
            method_args = [f"TARGET_ADDR={target_addr}", f"END_ADDR={end_addr}"]
        
        common_arg = [ 
                    f"RANDOM_SEED={random.randint(0, 2**20)}", \
                    f"METHOD={method} ALG1={alg1} ALG2={alg2}", \
                    f"LD_PRELOAD={os.getcwd()}/zig-out/lib/libzigsched.so", \
                    f"{prog}"
                ]
        command_tc = alg_args + method_args + common_arg

        command_tc = " ".join(command_tc)
        command_tc = f"{command_tc} {prog_args}".replace("#", str(tc)) 
        try:
            result = sp.run(command_tc, shell=True, capture_output=True, timeout=5)
        except sp.TimeoutExpired:
            continue

        # if result.returncode != 0:
        #     print("bug triggered with ", target_addr, end_addr)
    
    bugs = get_triggered_bugs(stat_file)
    # print(f"Bugs found with input-{tc}: {bugs}")
    stats[tc] = bugs
    
outf = open(f"{args.output_dir}/{args.random_seed}.json", "w")
json.dump(stats, outf)
outf.close()
