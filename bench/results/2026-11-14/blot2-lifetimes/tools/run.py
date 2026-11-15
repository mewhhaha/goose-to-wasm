#!/usr/bin/env python3
"""run.py [--timeout S] [--cwd D] [--stderr F] [--stdout F] [--json F] -- cmd...
Runs a command, reports wall, user, sys, max RSS and minor faults of it."""
import argparse, json, os, resource, subprocess, sys, time
ap = argparse.ArgumentParser()
ap.add_argument('--timeout', type=float, default=None)
ap.add_argument('--cwd', default=None)
ap.add_argument('--stderr', default=None)
ap.add_argument('--stdout', default=None)
ap.add_argument('--json', default=None)
ap.add_argument('--label', default='')
ap.add_argument('cmd', nargs=argparse.REMAINDER)
a = ap.parse_args()
cmd = a.cmd[1:] if a.cmd and a.cmd[0] == '--' else a.cmd
err = open(a.stderr, 'wb') if a.stderr else subprocess.DEVNULL
out = open(a.stdout, 'wb') if a.stdout else subprocess.DEVNULL
t0 = time.monotonic()
p = subprocess.Popen(cmd, cwd=a.cwd, stdin=subprocess.DEVNULL, stdout=out, stderr=err)
timed_out = False
try:
    p.wait(timeout=a.timeout)
except subprocess.TimeoutExpired:
    timed_out = True
    p.terminate()
    try:
        p.wait(timeout=30)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
wall = time.monotonic() - t0
_, status, ru = os.wait4(p.pid, 0) if False else (None, p.returncode, resource.getrusage(resource.RUSAGE_CHILDREN))
row = {'label': a.label, 'cmd': cmd, 'cwd': a.cwd, 'exit': p.returncode, 'timed_out': timed_out, 'wall_s': round(wall, 3),
       'user_s': round(ru.ru_utime, 3), 'sys_s': round(ru.ru_stime, 3), 'max_rss_mib': round(ru.ru_maxrss / 1024, 1),
       'minflt': ru.ru_minflt, 'majflt': ru.ru_majflt}
print(json.dumps(row))
if a.json:
    with open(a.json, 'a') as f: f.write(json.dumps(row) + '\n')
