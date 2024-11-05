import polars as pl
import subprocess as sp
import random
import os
import re
import sys
import json
import time
import shutil
from tqdm import tqdm
import argparse

required_args = []

parser = argparse.ArgumentParser(prog='Benchmark Runner', description="Runs an algorithm on a benchmark program. Arguments may also be passed as environment variables")

config_key = "--tool-config"
env_key = config_key.lstrip("-").replace("-","_").upper()
parser.add_argument(config_key, help=f'[ Environment variable: {env_key} ] JSON file with algorithm, timeout etc.', default=os.environ.get(env_key))
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

def clear_dir():
    # rm_command = ["rm", "-rf", f"{directory}/*"]
    # sp.run(rm_command, shell=True, stdout=sp.PIPE, text=True)
    for item in os.listdir(directory):
        item_path = os.path.join(directory, item)
        try:
            if os.path.isfile(item_path) or os.path.islink(item_path):
                os.unlink(item_path)
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path)
        except Exception as e:
            print(f"Failed to delete {item_path}. Reason: {e}")


def get_schedule_from_log(file):
    client_id = {}
    pattern = re.compile(r'log : S-id=(\d+) :  USER: test(\d+)')
    with open(server_log, "r") as f:
        for line in f:
            match = pattern.search(line)
            if match:
                s_id = int(match.group(1)) + 2100
                c_id = int(match.group(2))
                client_id[str(s_id)] = c_id
                for c in children.get(s_id, []):
                    client_id[str(c)] = c_id
    # print(client_id)
    sched = []
    with open(file, "r") as f:
        for line in f:
            if "sched_yield" in line:
                c_id = client_id[line.split('|')[0]]
                if c_id in target_client:
                    sched.append(str(c_id))
    return ''.join(sched)

def read_folder_contents():    
    return '+'.join(sorted(os.listdir(directory)))


random.seed(args.random_seed)
tool_config_file = args.tool_config 

config = {}
with open(tool_config_file, 'r') as file:
    config = json.load(file)

directory = "./ftpshare"
output_file = f"./output-{args.random_seed}.txt"
if os.path.exists(output_file):
    os.remove(output_file)

N = config['iteration']
timeout = config["timeout"]
log_file = f"{os.getcwd()}/{config['log_file']}"
alg1 = config['alg1']
alg2 = config['alg2']
method = 'sched_yield' if 'urw' in (alg1, alg2) else 'always_false'

target_client = [0, 0]
while target_client[0] == target_client[1]:
    target_client = random.choices(range(1, 5), k=2)

server_log = "server.log"
children = {}
with open("fork.in", "r") as f:
    for line in f:
        children = eval(line)

max_event = "60"
max_thread = "17"
max_depth = config['depth'] if 'pct' in (alg1, alg2) else '10'

print("generating client inputs...")
sp.run(["python3", "input_gen.py"], capture_output=True)

# add 200 more iterations in case of failures
print(f"starting {N + 200} iterations...")
for i in tqdm(range(N + 200), desc="Processing", unit="items"):  
    sf = open(server_log, "w")
    command1 = [
                f"LOG_FILE={log_file}", \
                f"MAX_EVENTS={max_event}", \
                f"MAX_THREADS={max_thread}", \
                f"MAX_DEPTH={max_depth}", \
                f"RANDOM_SEED={random.randint(0, 2**20)}", \
                f"METHOD={method} ALG1={alg1} ALG2={alg2}", \
                f"LD_PRELOAD={os.getcwd()}/zig-out/lib/libzigsched.so",  
                "./fftp", "Bin/fftp.conf"
            ]
    command2 = ["./client"]
    try:
        server = sp.Popen(" ".join(command1), shell=True, stdout=sf, stderr=sp.DEVNULL)
        time.sleep(0.2)
        client = sp.run(command2, timeout=5, capture_output=True)
        # print(client.returncode)
        if client.returncode != 0:
            server.terminate()
            clear_dir()
            sf.close()
            continue
        server.wait()
    except Exception:
        server.terminate()
        clear_dir()
        sf.close()
        try: # free port before restart
            output = sp.check_output("netstat -tulpn | grep :21", shell=True, text=True)
            pid = re.search(r'(\d+)/', output)
            if pid:
                pid = pid.group(1)
                sp.run(['kill', pid])
        except sp.CalledProcessError as e:
            if e.returncode == 1:
                continue # no matching port being used
            else:
                print("An error occurred:", e)
                exit(-1)
        continue   

    with open(output_file, "a") as f:
        sched = get_schedule_from_log(log_file)
        fs_state = read_folder_contents()
        f.write(f'{sched} | {fs_state}\n')

    clear_dir()