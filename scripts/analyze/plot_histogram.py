import matplotlib.pyplot as plt

def process(file_path):
    cov_count = {}
    with open(file_path, 'r') as file:
        for line in file:
            value = eval(line.strip())
            cov_count[value] = cov_count.get(value, 0) + 1
    return cov_count

plt.figure(figsize=(21, 7))
plt.subplots_adjust(left=0.1, right=0.98, top=0.9, bottom=0.05)
path = "stats/toy-examples/uniform"
config = ["urw", "rw", "pct"]
colors = ["skyblue", "orange", "lightgreen"]
titles = ["URW", "Random Walk", "PCT-10"]
for i in range(3):
    count = process(f"{path}/dist-{config[i]}.txt")
    vals = list(count.values())
    vals.sort(reverse=True)
    plt.subplot(1, 3, i + 1)
    print(len(vals))
    plt.bar(range(len(vals)), vals, width=1, color=colors[i])
    
    # plt.yscale('log')
    plt.ylim([0, 1e3])
    plt.xlim([0, 250])
    plt.title(titles[i], fontsize=28)
    if i == 0:
        plt.ylabel('Frequency', fontsize=28)
        plt.setp(plt.gca().get_yticklabels(), fontsize=18, rotation=45) 
    else:
        plt.setp(plt.gca().get_yticklabels(), visible=False) 
    
    plt.setp(plt.gca().get_xticklabels(), visible=False)     
    
    plt.grid(True, linestyle='--', linewidth=0.5)
    plt.gca().set_facecolor('#f8f8f8')
    for spine in plt.gca().spines.values():
        spine.set_linewidth(0.5)
        spine.set_color('grey')

plt.savefig(f"{path}/dist.png")