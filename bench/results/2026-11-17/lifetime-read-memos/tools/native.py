#!/usr/bin/env python3
"""native.py OUT.json BEFORE AFTER: the compiler checking and compiling selfhost/main.goose, before and after.

Seven interleaved runs of each compiler for each of three jobs (--check, to 32-bit Wasm, to C), pinned to one
core: CPU seconds (user + system), wall seconds and peak RSS, all recorded. Outputs are compared. Run from the
repository root."""
import hashlib, json, os, resource, statistics, subprocess, sys, tempfile, time
out, compilers = sys.argv[1], {'before': os.path.abspath(sys.argv[2]), 'after': os.path.abspath(sys.argv[3])}
work = tempfile.mkdtemp(prefix='native-')
jobs = {'check': ['--check'], 'to 32-bit Wasm': ['--target', 'wasm-direct', '-O2', '--wasm-max-pages', '65535', '-o', '{out}.wasm'],
        'to C': ['--target', 'native', '-O2', '-o', '{out}.c']}
rows = []
for job, arguments in jobs.items():
    record = {name: {'cpu': [], 'wall': [], 'rss_kib': 0, 'sha256': None} for name in compilers}
    for _ in range(7):
        for name, exe in compilers.items():
            target = os.path.join(work, name); final = [a.replace('{out}', target) for a in arguments]
            before = resource.getrusage(resource.RUSAGE_CHILDREN); started = time.perf_counter()
            done = subprocess.run(['taskset', '-c', '2', exe, 'selfhost/main.goose', '--stdlib', 'stdlib', *final], capture_output=True)
            wall = time.perf_counter() - started; after = resource.getrusage(resource.RUSAGE_CHILDREN)
            assert done.returncode == 0, done.stderr[-300:]
            r = record[name]; r['cpu'].append(round(after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime, 3)); r['wall'].append(round(wall, 3))
            r['rss_kib'] = max(r['rss_kib'], after.ru_maxrss)
            produced = [a for a in final if a.startswith(target)]
            if produced: r['sha256'] = hashlib.sha256(open(produced[0], 'rb').read()).hexdigest()
    b, a = statistics.median(record['before']['cpu']), statistics.median(record['after']['cpu'])
    rows.append({'job': job, 'before': record['before'], 'after': record['after'], 'median_cpu_ratio': round(a / b, 3), 'same_output': record['before']['sha256'] == record['after']['sha256']})
    print(job, 'cpu median', b, '->', a, round(a / b, 3), 'same output', rows[-1]['same_output'], flush=True)
json.dump({'compilers': {name: {'path': os.path.relpath(exe), 'sha256': hashlib.sha256(open(exe, 'rb').read()).hexdigest()} for name, exe in compilers.items()},
           'source': subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip(), 'rows': rows}, open(out, 'w'), indent=1)
