import os
import docker
import tarfile
from concurrent.futures import ThreadPoolExecutor, as_completed

dir_path = "./stats/lightftp"

configs = ['urw-sched', 'pct10', 'pct3', 'rw']

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
                os.rename(extr_file_path, base_name + '.txt')
        os.remove(tar_path)


def start_container(config, cid):
    client = docker.from_env()

    env_vars = {
        'TOOL_CONFIG': f'configs/{config}.json',
        'RANDOM_SEED': str(cid),
    }
    
    container = client.containers.run("zig-lftp",
                                      privileged=True,
                                      environment=env_vars,
                                      detach=True, tty=True)
    
    container.wait()
    # logs = container.logs().decode('utf-8')
    # print(f"Container {cid} logs:\n{logs}\n")
    
    stream, _ = container.get_archive(f"/opt/sched-fuzz/layeredct/output-{cid}.txt")
    file_path = f"{dir_path}/{config}/{cid}.tar"
    with open(file_path, 'wb') as tar_file:
        for chunk in stream:
            tar_file.write(chunk)
    
    container.remove()


for c in configs:
    if not os.path.exists(f'{dir_path}/{c}'):
        os.mkdir(f'{dir_path}/{c}')

with ThreadPoolExecutor(max_workers=20) as executor:
    futures = [executor.submit(start_container, c, i) for i in range(20) for c in configs]
    for future in as_completed(futures):
        future.result() 

for c in configs:
    process_tar_files(f"{dir_path}/{c}")
