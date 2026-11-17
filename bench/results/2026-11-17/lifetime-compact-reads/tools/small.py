#!/usr/bin/env python3
"""small.py NAME=COMPILER...: three small programs as --check, 60 interleaved runs each: minimum and median CPU
milliseconds and page faults of the child itself (os.wait4). An empty main is written to a temporary file."""
import os, statistics, subprocess, sys, tempfile
compilers = {a.split('=', 1)[0]: os.path.abspath(a.split('=', 1)[1]) for a in sys.argv[1:]}
empty = os.path.join(tempfile.mkdtemp(prefix='small-'), 'empty.goose'); open(empty, 'w').write('fn main() {}\n')
for path in [empty, 'examples/squares.goose', 'examples/tour.goose']:
    cpu = {n: [] for n in compilers}; faults = {n: 0 for n in compilers}
    for _ in range(60):
        for name, exe in compilers.items():
            child = subprocess.Popen(['taskset', '-c', '2', exe, path, '--stdlib', 'stdlib', '--check'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            _, status, usage = os.wait4(child.pid, 0); assert os.waitstatus_to_exitcode(status) == 0, (name, path)
            cpu[name].append(1000 * (usage.ru_utime + usage.ru_stime)); faults[name] = usage.ru_minflt + usage.ru_majflt
    for name in compilers:
        print(f"{name} {os.path.basename(path)} cpu ms: median {statistics.median(cpu[name]):.2f} min {min(cpu[name]):.2f} page faults {faults[name]}", flush=True)
