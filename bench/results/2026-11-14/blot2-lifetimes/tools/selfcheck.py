#!/usr/bin/env python3
"""selfcheck.py OUT.json ROUNDS LABEL=COMPILER...: the compiler checking a
frozen copy of the final sources (--target native --check), interleaved,
pinned to CPU 7; wall, user, peak RSS and the phase times from --wasm-stats."""
import json, os, resource, subprocess, sys, time
W = '/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a17bf72e44110d4f2'
out_path, rounds = sys.argv[1], int(sys.argv[2])
compilers = [a.split('=', 1) for a in sys.argv[3:]]
src = W + '/build/frozen-final/selfhost'
rows = []
for k in range(rounds):
    for label, compiler in (compilers if k % 2 == 0 else compilers[::-1]):
        stats = W + '/build/tmp/selfcheck-%s.json' % label
        t0 = time.perf_counter()
        child = subprocess.Popen(['taskset', '-c', '7', compiler, src + '/main.goose', '--target', 'native', '--check',
                                  '--stdlib', W + '/stdlib', '--wasm-stats', stats], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _, status, usage = os.wait4(child.pid, 0)
        wall = time.perf_counter() - t0
        d = json.load(open(stats))
        row = {'compiler': label, 'round': k, 'exit': os.waitstatus_to_exitcode(status), 'wall_s': round(wall, 3),
               'user_s': round(usage.ru_utime, 3), 'max_rss_mib': round(usage.ru_maxrss / 1024, 1),
               'typecheck_s': round(d['typecheck_ns'] / 1e9, 3), 'lifetime_s': round(d['lifetime_ns'] / 1e9, 3),
               'load': round(os.getloadavg()[0], 1)}
        print(json.dumps(row), flush=True); rows.append(row)
json.dump({'compilers': dict(compilers), 'source': src, 'rows': rows}, open(out_path, 'w'), indent=1)
