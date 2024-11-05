import subprocess as sp
import os
import json

cmd_args = {
    "blackscholes": "3 DIR/input/input-# /dev/null",
    "bodytrack": "DIR/install/sequenceB_1 4 1 5 1 0 3 0 DIR/input/input-#",
    "canneal": "3 100 100 DIR/input/input-# 2",
    "cholesky": "-p4 DIR/input/input-#",
    "dedup": "-c -p -v -t 3 -i DIR/input/input-# -o /dev/null", 
    "ferret": "DIR/install/corel lsh DIR/input/input-# 5 5 1 /dev/null",
    "fluidanimate": "4 1 DIR/input/input-# /dev/null",
    "pigz": "-k -p 4 -d DIR/input/input-# -c -f",
    "raytrace": "-files DIR/input/input-# -automove -nthreads 4 -frames 1 -res 1 1",
    "raytrace2": "-s -p4 -g=DIR/install/teapot.geo DIR/input/input-#",
    "streamcluster": "10 20 32 0 1024 1000 DIR/input/input-# /dev/null 4",
    "volrend": "4 DIR/install/head-scaleddown4 DIR/input/input-#",
    "water_nsquared": "DIR/install/input.template DIR/input/input-#",
    "water_spatial": "DIR/install/input.template DIR/input/input-#",
    "x264": "--quiet --qp 20 --partitions b8x8,i4x4 --ref 5 --direct auto --b-pyramid --weightb --mixed-refs --no-fast-pskip --me umh --subme 7 --analyse b8x8,i4x4 --threads 3 -o /dev/null DIR/input/input-#"
}

special_case_names = { 
    "raytrace": "rtview",
    "raytrace2": "raytrace",
    "ferret": "ferret-pthreads",
}




config = {}
for target in cmd_args.keys():
    for version in range(1, 6):
        key = f"{target}.{version}"
        path = f"/workdir/RaceBenchData/{key}"
        e = f"{path}/install/{special_case_names.get(target, target)}"
        libs = []
        args = cmd_args.get(target).replace("DIR", path)
        inputs = []

        config[key] = { "name": key, "path" : e, "stem" : key, "libs" : libs, "args" : args, "inputs" : inputs}

with open('racebench_subject_config.json', 'w') as fp:
    json.dump(config, fp)
