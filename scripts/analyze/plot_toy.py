import matplotlib.pyplot as plt

def process(file_path):
    cov_count = {}
    with open(file_path, 'r') as file:
        for line in file:
            value = eval(line.strip())
            cov_count[value] = cov_count.get(value, 0) + 1
    return cov_count

plt.figure(figsize=(6, 3))

count = process(f"./dist.txt")
vals = list(count.values())
print(f'Total number of behavior: {len(vals)} / 252')

plt.bar(range(len(vals)), vals, width=1, color="skyblue")
plt.ylabel('Frequency')
plt.setp(plt.gca().get_xticklabels(), visible=False)     
plt.grid(True, linestyle='--', linewidth=0.5)
plt.gca().set_facecolor('#f8f8f8')
for spine in plt.gca().spines.values():
    spine.set_linewidth(0.5)
    spine.set_color('grey')

plt.savefig(f"dist.png")
print("plot saved to dist.png")