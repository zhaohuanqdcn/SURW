import os
import json
import pandas as pd
from statistics import mean, stdev
from lifelines.statistics import logrank_test

dir_path = "./stats/period"
subjects = ['CS/twostage', 'CS/twostage_20', 'CS/twostage_50', 'CS/twostage_100',
            'CS/reorder_3', 'CS/reorder_4', 'CS/reorder_5', 'CS/reorder_10', 'CS/reorder_20', 'CS/reorder_50', 'CS/reorder_100',
            'CS/stack', 'CS/token_ring', 'CS/lazy01', 'CS/deadlock01', # 'CS/queue', 
            'CS/bluetooth_driver', 'CS/account', # 'CS/circular_buffer', 'CS/carter01', 
            'CS/wronglock', 'CS/wronglock_3', # 'CB/aget-bug2', 'CB/pbzip2-0.9.4',
            'CB/stringbuffer-jdk1.4',
            'Chess/InterlockedWorkStealQueue', 'Chess/InterlockedWorkStealQueueWithState', 'Chess/StateWorkStealQueue', 'Chess/WorkStealQueue', 
            'Inspect_benchmarks/bbuf', 'Inspect_benchmarks/boundedBuffer', 'Inspect_benchmarks/qsort_mt',
            # 'Inspect_benchmarks/ctrace-test', 
            # 'Splash2/barnes', 'Splash2/fft', 'Splash2/lu',
            'RADBench/bug4', 'RADBench/bug5', 'RADBench/bug6', # 'RADBench/bug2', 'RADBench/bug3', 
            'SafeStack',
            # 'ConVul-CVE-Benchmarks/CVE-2009-3547', 'ConVul-CVE-Benchmarks/CVE-2011-2183', 
            'ConVul-CVE-Benchmarks/CVE-2013-1792',
            # 'ConVul-CVE-Benchmarks/CVE-2015-7550', 
            'ConVul-CVE-Benchmarks/CVE-2016-1972', 'ConVul-CVE-Benchmarks/CVE-2016-1973', 
            'ConVul-CVE-Benchmarks/CVE-2016-7911', 'ConVul-CVE-Benchmarks/CVE-2016-9806', 
            'ConVul-CVE-Benchmarks/CVE-2017-15265', 'ConVul-CVE-Benchmarks/CVE-2017-6346'
]

configs = ['rp-urw', 'pct3', 'pct10', 'pos', 'rw', 'rp-rw', 'basicurw']
names = ['SURW', 'PCT-3', 'PCT-10', 'POS', 'RW', 'N-U', 'N-S']

def compute_stats(directory):
    
    full_data = {
        'durations': [],
        'event_observed': [],
        'group': []
    }

    tool_count = {}

    json_files = [f for f in os.listdir(directory) if f.endswith('.json')]
    
    for json_file in json_files:
        json_path = os.path.join(directory, json_file)
        with open(json_path, 'r') as file:
            data = json.load(file)
            tool = data['tool'][8:-5]
            iteration = data['iterations']
            if tool not in ['pos', 'rw']:
                iteration += 1
            time = data['time_seconds']
            success = data["found"]

            if tool not in tool_count:
                tool_count[tool] = []
            if success:
                tool_count[tool].append(iteration)
            
            full_data['durations'].append(iteration)
            full_data['event_observed'].append(1 if success == True else 0)
            full_data['group'].append(tool)

    stats = {}
    for tool, count in tool_count.items():
        tool_mean = mean(count) if len(count) > 1 else 0
        # Compute stdev, handle case with a single iteration value
        tool_stdev = stdev(count) if len(count) > 1 else 0
        stats[tool] = {'success': len(count), 'mean': tool_mean, 'stdev': tool_stdev}

    return stats, full_data

f = open("stats/period/out.tex", "w")

total = {c: set() for c in configs}
means = {c: 0 for c in configs}

for s in subjects:
    directory = os.path.join(dir_path, s)
    if not os.path.exists(directory):
        continue
    stats, full_data = compute_stats(directory)

    # find the min mean on the row
    min_avg = stats["rp-urw"]["mean"]
    best_tool = "rp-urw"
    for c in configs:
        if c not in stats:
            row.append("")
            continue
        if stats[c]["mean"] < min_avg and stats[c]["mean"] > 0:
            min_avg = stats[c]["mean"]
            best_tool = c

    # perform log-rank test with min mean
    row = [s]
    df = pd.DataFrame(full_data)
    for c in configs:
        if c not in stats:
            row.append("")
            continue
        results = logrank_test(
            df[df['group'] == best_tool]['durations'],
            df[df['group'] == c]['durations'],
            event_observed_A = df[df['group'] == best_tool]['event_observed'],
            event_observed_B = df[df['group'] == c]['event_observed']
        )
        significant = results.p_value < 0.05
        stat = stats[c]
        
        if stat['success'] > 0:
            total[c].add(s)
            means[c] += stat['success']

        if stat['mean'] == 0:
            cell = "-"
        elif stat['success'] == 20:
            cell = f"{stat['mean']:.0f} \pm {stat['stdev']:.0f}"
        else:
            cell = f"{stat['mean']:.0f} \pm {stat['stdev']:.0f}^*"
        if not significant and cell != "-":
            row.append(f"$\\bm{{{cell}}}$")
        else:
            row.append(f"${cell}$")
    f.write(" & ".join(row) + " \\\\\n")

f.close()

print("--------------------------------------------------------")
print("results of SCTBench/ConVul saved at stats/period/out.tex")

titles = ["# of bugs".ljust(10)]
for c, name in zip(configs, names):
    titles.append(name.center(8))
print('|'.join(titles))

row = ["Total".ljust(10)]
for c in configs:
    row.append(str(len(total[c])).center(8))
print('|'.join(row))

row = ["Mean".ljust(10)]
for c in configs:
    row.append(str(means[c] / 20).center(8))
print('|'.join(row))

print("--------------------------------------------------------")