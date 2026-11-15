#!/usr/bin/env python3
"""watch_rss.py LIMIT_MIB STDERR_FILE -- cmd...: run a command, stop it when its
resident set passes LIMIT_MIB (this session shares one memory limit and has no
swap), and report wall, CPU and peak RSS."""
import json, os, resource, subprocess, sys, time
limit = int(sys.argv[1]); err = open(sys.argv[2], 'wb'); cmd = sys.argv[4:]
t0 = time.monotonic(); p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=err)
stopped = False; peak = 0
while p.poll() is None:
    try:
        rss = int(open('/proc/%d/statm' % p.pid).read().split()[1]) * os.sysconf('SC_PAGE_SIZE') // (1 << 20)
    except Exception:
        break
    peak = max(peak, rss)
    if rss > limit:
        p.kill(); stopped = True; break
    time.sleep(0.5)
p.wait(); ru = resource.getrusage(resource.RUSAGE_CHILDREN)
print(json.dumps({'cmd': cmd, 'exit': p.returncode, 'stopped_at_limit': stopped, 'limit_mib': limit, 'wall_s': round(time.monotonic() - t0, 1),
                  'user_s': round(ru.ru_utime, 1), 'sys_s': round(ru.ru_stime, 1), 'peak_rss_mib_sampled': peak}))
