# Selectively Uniform Concurrency Testing

A user-space controlled scheduling library that wraps the `pthreads` library.
It implements multiple stateless sampling algorithms.
Written mainly in Zig.

## Dependencies

The library requires a recent version of Ubuntu on an x86 CPU. 
To install Docker, Python and E9Path, run
```
sudo snap install docker
sudo groupadd docker
sudo usermod -aG docker $USER
sudo apt install -y python3
git submodule init
git submodule update --remote --recursive
```

Install Python dependencies
```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Disable ASLR

The scheduling library requires disabled ASLR. To do so, run
```
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space
```
_Note: your system will be more vulnerable to exploits while ASLR is disabled. ASLR will be reinstated on reboot._

## Setup in Docker

The easiest way to build and run the targets is with Docker!

To install required Python3 dependencies, run
```
pip install requirements.txt
```

If Docker is running, [SCTBench, ConVul, RaceBenchData and LightFTP] can be all built with a single command:
```
./build_all.sh
```
The building process may take a 1-3 hours.

## Rerun Experiments in Docker

The raw data are saved in the `stats/` folder.
To regenerate tables and diagrams, run
```
python3 scripts/analyze/eval_period.py
python3 scripts/analyze/eval_racebench.py
python3 scripts/analyze/plot_lftp_a.py
python3 scripts/analyze/plot_lftp_b.py
```

Experiments can be rerun with 
```
python3 scripts/eval/run_period.py
python3 scripts/eval/run_racebench.py
python3 scripts/eval/run_lftp.py
```
All experiments should finish <3 days on a typical 8 core CPU.

## Manual Setup

Install zig
```
export ZIG_VER=0.11.0
export ZIG_DIR=zig-linux-x86_64-$ZIG_VER
wget https://ziglang.org/download/$ZIG_VER/$ZIG_DIR.tar.xz
tar -xvf zig-linux*
export PATH=$PATH:/opt/$ZIG_DIR
zig zen
```

Build e9patch
```
cd e9patch; ./build.sh; cd ../
```

Build the scheduling library (add `-Doptimize=ReleaseFast` for release):
```
zig build
```

Once everything is built, you can run tests with:
```
zig test -lc src/main.zig
```

## Running Toy Examples

To test on the toy example `toy-examples/uniform.c`, run
```
gcc -g ./toy-examples/uniform.c -o uniform
python3 scripts/run_one.py configs/urw-sched.json ./uniform
python3 scripts/analyze/plot_toy.py
```

This will run the program 10,000 iterations with SURW and collect the execution result. 
On expectation, each result is sampled ~40 times.
`dist.png` visualizes the frequency the different execution results. 
As the number of iterations increases, the distribution eventually converges to uniformity.


## Manual Workflow

By default, scheduling decisions are only made at `pthreads` and `sched_yield()` calls.
To add pre-emption points at memory operations, instrument the program binary with
```
./instrument.sh ./path/to/program
```
This generates an instrumented binary `./program.inst`.

The instrumented program could be run with
```
python3 scripts/run_one.py <config file> ./program.inst <program args>
```

Some common algorithms are specified in `configs/`:
- SURW on memory accesses: `configs/rp-urw.json`
- SURW on `sched_yield()` calls: `configs/urw-sched.json`
- PCT: `configs/pct-3.json` and `configs/pct-10.json`
- POS: `configs/pos.json`
- Random Walk: `configs/rw.json`
- Non-Selective: `configs/basicurw.json`
- Non-Uniform: `configs/rp-rw.json`

## Alternative Configurations

The library supports different scheduling strategies specified in a JSON file.
The configuration file supports two algorithms, 
where `alg1` specifies the algorithm to be selectively applied on the set of desired events,
and `alg2` specifies the algorithm used on other events (i.e., `pickFrom()` from the paper).
The method `method` field dictates the type of events that are interesting 
(i.e., when `alg1` is invoked over `alg2`).
For example, `configs/urw-sched.json` sets `alg1=urw`, `alg2=rp` and `method=sched_yield`, 
which implements SURW as described in the paper with interesting events being `sched_yield()` calls.

Supported algorithms are:
- `ns`: no context switch if possible
- `rw`: naive random walk
- `rp`: per-event random priority
- `pos`: partial order sampling
- `pct`: PCT (define `depth` field as well)
- `urw`: uniform random walk

Supported methods are:
- `always_true`: always run `alg1`
- `always_false`: always run `alg2`
- `sched_yield`: on `sched_yield()` library calls
- `memory_addr`: on target memory address accesses (read / write)
- `lock_addr`: on lock accesses (acqire = read / release = write)

Note that not all combinations are currently supported in this research prototype.
For example, `pct` can only be `alg2` and `urw` can only be `alg1`.

[Not Recommended] To run one individual schedule manually, invoke
```
LOG_FILE=<path to text log file> RANDOM_SEED=<random seed> \
METHOD=<method> ALG1=<algorithm> ALG2=<algorithm> \
LD_PRELOAD=$(pwd)/zig-out/bin/libzigsched.so \
./program.inst <program args>
```
Note that SURW and PCT requires a profiling run.
For more example usage, please refer to `scripts/run_one.py`.
