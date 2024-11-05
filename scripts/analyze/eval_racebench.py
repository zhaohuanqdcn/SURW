import os
import json
import numpy as np

configs = ['rp-urw', 'pct3', 'pct10', 'pos', 'rw']
names = ["SURW", "PCT-3", "PCT-10", "POS", "RW"]

dir_path = "./stats/racebench"

targets = [
            'blackscholes', 
            'bodytrack', 
            'canneal', 
            'cholesky', 
            'dedup', 
            'ferret', 
            'fluidanimate', 
            'pigz', 
            'raytrace', 
            'raytrace2', 
            'streamcluster', 
            'volrend', 
            'water_nsquared', 
            'water_spatial', 
            'x264'
        ]

def compute_stats(directory):
    stats = {}

    json_files = [f for f in os.listdir(directory) if f.endswith('.json')]
    
    for json_file in json_files:
        json_path = os.path.join(directory, json_file)
        with open(json_path, 'r') as file:
            data = json.load(file)
            tool = data['tool'][8:-5]
            if tool not in stats:
                stats[tool] = {'all_bugs': set(), 'bug_count': []}
            bugs = set()
            for i in range(20):
                bugs.update(data.get(str(i), []))
            stats[tool]['all_bugs'].update(bugs)
            stats[tool]['bug_count'].append(len(bugs))
    
    for tool, stat in stats.items():
        stat['average_bugs'] = np.mean(stat['bug_count'])

    return stats

results = {}
for t in targets:
    results[t] = {}
    for i in range(1, 6):
        s = f"{t}.{i}"
        directory = os.path.join(dir_path, s)
        if not os.path.exists(directory):
            continue
        stats = compute_stats(directory)

        for tool, stat in stats.items():
            if tool not in results[t]:
                results[t][tool] = 0
            results[t][tool] += stat['average_bugs']

print("--------------------------------------------------------")
print("results for RaceBenchData:")
print("--------------------------------------------------------")

titles = ["targets".ljust(15)]
for c, name in zip(configs, names):
    titles.append(name.center(8))
print('|'.join(titles))

totals = {c: 0 for c in configs}

for target, res in results.items():
    if len(res) == 0:
        continue
    row = [f"{int(res[c])}".center(8) for c in configs]
    print(f"{target}".ljust(15) + '|' + '|'.join(row))
    for c in configs:
        totals[c] += res[c]

totals = [str(int(totals[c])).center(8) for c in configs]
print(f"Total".ljust(15) + '|' + '|'.join(totals))


print("--------------------------------------------------------")
