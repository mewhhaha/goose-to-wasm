#!/usr/bin/env python3
"""selfbench.py [-n N] [--args ...] EXE...: time each compiler checking selfhost/main.goose, N interleaved runs pinned
to one core; prints min and median CPU seconds (user+sys) and max RSS."""
import os, resource, statistics, subprocess, sys
args = sys.argv[1:]; n = 5; extra = ['--check']
if args[0] == '-n': n = int(args[1]); args = args[2:]
if args[0] == '--args': extra = args[1].split(); args = args[2:]
times = {e: [] for e in args}; rss = {e: 0 for e in args}
for _ in range(n):
    for exe in args:
        # One child's own usage (os.wait4): RUSAGE_CHILDREN's peak RSS is the largest of every child so far.
        child = subprocess.Popen(['taskset', '-c', '2', exe, 'selfhost/main.goose', '--stdlib', 'stdlib', *extra], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _, status, usage = os.wait4(child.pid, 0); child.returncode = os.waitstatus_to_exitcode(status)
        assert child.returncode == 0, exe
        times[exe].append(usage.ru_utime + usage.ru_stime); rss[exe] = max(rss[exe], usage.ru_maxrss)
base = statistics.median(times[args[0]])
for exe in args:
    t = times[exe]
    print(f"{os.path.basename(exe):14} min {min(t):6.2f}  median {statistics.median(t):6.2f}  ({statistics.median(t) / base:5.3f})  max {max(t):6.2f}  rss {rss[exe] // 1024} MiB")
