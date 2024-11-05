import os
import docker
import tarfile
from concurrent.futures import ThreadPoolExecutor, as_completed

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

configs = ['rp-urw', 'pos', 'pct3', 'pct10', 'rw', 'rp-rw', 'basicurw']


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
    client = docker.from_env()

    env_vars = {
        'PROGRAM_KEY': target,
        'TOOL_CONFIG': f'configs/{config}.json',
        'RANDOM_SEED': str(cid),
    }
    
    container = client.containers.run("zig-period",
                                      environment=env_vars,
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

max_workers = max(os.cpu_count(), 20)
for s in subjects:
    print("running subject: ", s)
    if not os.path.exists(f'{dir_path}/{s}'):
        os.mkdir(f'{dir_path}/{s}')
    
    for c in configs:
        print("running config: ", c)
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(start_container, s, c, i) for i in range(20)]
            for future in as_completed(futures):
                future.result() 
    
    process_tar_files(f"{dir_path}/{s}")
