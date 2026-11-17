#!/usr/bin/env python3
"""blot2time.py OUT.txt NAME=COMPILER...: each compiler checking the blot2 copy (build/blot2-head), one at a time:
wall and CPU seconds, peak RSS and the number of diagnostic lines (os.wait4)."""
import os, subprocess, sys, time
out = open(sys.argv[1], 'w'); root = os.getcwd(); src = os.path.join(root, 'build/blot2-head/compiler-goose/src')
for arg in sys.argv[2:]:
    name, exe = arg.split('=', 1); err = os.path.join(root, 'build/tmp', f'blot2-{name}.err'); started = time.perf_counter()
    child = subprocess.Popen([os.path.abspath(exe), 'main.goose', '--stdlib', os.path.join(root, 'stdlib'), '--reachable-program', '--expansion-node-limit', '1000000', '--check'],
                             cwd=src, stdout=subprocess.DEVNULL, stderr=open(err, 'w'))
    _, status, usage = os.wait4(child.pid, 0); wall = time.perf_counter() - started
    line = f"{name}: wall {wall:.0f} s, cpu {usage.ru_utime + usage.ru_stime:.0f} s, peak RSS {usage.ru_maxrss // 1024} MiB, exit {os.waitstatus_to_exitcode(status)}, {sum(1 for _ in open(err))} diagnostic lines"
    print(line, flush=True); out.write(line + '\n'); out.flush()
