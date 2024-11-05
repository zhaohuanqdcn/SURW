import numpy as np
import matplotlib.pyplot as plt
from scipy.stats import entropy

N = 10000

def process(file_path):
    cov_count = {}
    cov_size = []
    line_no = 0
    with open(file_path, 'r') as file:
        for line in file:
            sched = line.split(' | ')[0].strip()
            cov_count[sched] = cov_count.get(sched, 0) + 1
            cov_size.append(len(cov_count))
            line_no += 1
            if line_no >= N:
                break
    return cov_count, cov_size

dir_path = './stats/lightftp'
configs = ['urw-sched', 'rw', 'pct10', 'pct3']
path = "."
colors = ["skyblue", "orange", "lightgreen", "mediumseagreen"]
titles = ["SURW", "RW", "PCT-10", "PCT-3"]

plt.figure(figsize=(10, 6))

N_trial = 20

counts = [[] for i in range(len(configs))]
cov_sizes = [[] for i in range(len(configs))]

for i in range(len(configs)):
    for s in range(N_trial):
        file_path = f'{dir_path}/{configs[i]}/{s}.txt'
        cov_count, cov_size = process(file_path)
        cov_sizes[i].append(cov_size)
        counts[i].append(cov_count)
    
    cov_sizes[i] = np.array(cov_sizes[i])
    mean = cov_sizes[i].mean(axis=0)
    std_dev = cov_sizes[i].std(axis=0)
    plt.plot(range(N), mean, label=titles[i], color=colors[i], linewidth=2)
    plt.fill_between(range(N), mean - std_dev, mean + std_dev, alpha=0.2, color=colors[i])

plt.setp(plt.gca().get_yticklabels(), fontsize=15, rotation=45) 
plt.setp(plt.gca().get_xticklabels(), fontsize=15) 
plt.xlim(0, N)
plt.xlabel('# of schedules sampled', fontsize=20)
plt.ylabel('# of distinct interleavings', fontsize=20)
legend = plt.legend(fontsize=20, loc='best', fancybox=True, framealpha=0.8)
for line in legend.get_lines():
    line.set_linewidth(2.5) 
plt.grid(True, linestyle='--', linewidth=0.5)
plt.gca().set_facecolor('#f8f8f8')
plt.subplots_adjust(left=0.11, right=0.95, top=0.95, bottom=0.1)
plt.savefig(f"{dir_path}/coverage_sched.png")

print("--------------------------------------------------------")
print(f"plot saved at {dir_path}/coverage_sched.png")

entropies = [[] for i in range(len(configs))]
for i in range(len(configs)):
    for s in range(N_trial):
        dist = np.array(list(counts[i][s].values()))
        entropies[i].append(entropy(dist))
    print(f'{titles[i]}: entropy ({np.mean(entropies[i])} +/- {np.std(entropies[i])})')

print("--------------------------------------------------------")