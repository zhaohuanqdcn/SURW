import os
import docker
import tarfile
from concurrent.futures import ThreadPoolExecutor, as_completed

dir_path = "./stats/racebench"

configs = ['rp-urw', 'pct3', 'pct10', 'pos', 'rw']

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

subjects = [f"{t}.{i}" for t in targets for i in range(1, 6)]


def process_tar_files(directory):
    tar_files = [f for f in os.listdir(directory) if f.endswith('.tar')]
    
    for tar_file in tar_files:
        tar_path = os.path.join(directory, tar_file)
        
        with tarfile.open(tar_path, 'r') as tar:
            tar.extractall(path=directory)
            # For each member in the tar archive, rename it if necessary
            for member in tar.getmembers():
                extr_file_path = os.path.join(directory, member.name)
                base_name, _ = os.path.splitext(tar_path)
                json_file_path = base_name + '.json'
                os.rename(extr_file_path, json_file_path)
        os.remove(tar_path)


def start_container(target, config, cid):
    out_path = f"{dir_path}/{target}/{config}-{cid}.json"
    if os.path.exists(out_path): # result exists
        return
    
    client = docker.from_env()

    env_vars = {
        'PROGRAM_KEY': target,
        'TOOL_CONFIG': f'configs/{config}.json',
        'RANDOM_SEED': str(cid),
    }
    
    container = client.containers.run("zig-racebench",
                                      environment=env_vars,
                                      privileged=True,
                                      detach=True, tty=True)
    
    container.wait()
    # logs = container.logs().decode('utf-8')
    # print(f"Container {cid} logs:\n{logs}\n")
    
    stream, _ = container.get_archive(f"/opt/out/{cid}.json")
    file_path = f"{dir_path}/{target}/{config}-{cid}.tar"
    with open(file_path, 'wb') as tar_file:
        for chunk in stream:
            tar_file.write(chunk)
    
    container.remove()

for s in subjects:
    print("running subject: ", s)
    if not os.path.exists(f'{dir_path}/{s}'):
        os.mkdir(f'{dir_path}/{s}')

max_workers = os.cpu_count()
with ThreadPoolExecutor(max_workers=max_workers) as executor:
    futures = [executor.submit(start_container, s, c, 0) for c in configs for s in subjects]
    for future in as_completed(futures):
        future.result() 

for s in subjects:
    process_tar_files(f"{dir_path}/{s}")
