#!/usr/bin/env python3
"""native.py OUT.json NAME=COMPILER...: each compiler checking and compiling selfhost/main.goose.

Seven interleaved runs of each compiler for each of three jobs (--check, to 32-bit Wasm, to C), pinned to one
core. CPU seconds (user + system) and peak RSS are each child's own, from os.wait4: getrusage(RUSAGE_CHILDREN)
gives the largest peak of every child so far, which is how the 2026-11-17 read-memos page came to call a
65 MiB rise "unchanged". Outputs are compared with the first compiler's. Run from the repository root."""
import hashlib, json, os, statistics, subprocess, sys, tempfile, time
out = sys.argv[1]; compilers = {a.split('=', 1)[0]: os.path.abspath(a.split('=', 1)[1]) for a in sys.argv[2:]}
work = tempfile.mkdtemp(prefix='native-'); first = next(iter(compilers))
jobs = {'check': ['--check'], 'to 32-bit Wasm': ['--target', 'wasm-direct', '-O2', '--wasm-max-pages', '65535', '-o', '{out}.wasm'],
        'to C': ['--target', 'native', '-O2', '-o', '{out}.c']}
rows = []
for job, arguments in jobs.items():
    record = {name: {'cpu': [], 'wall': [], 'rss_mib': [], 'sha256': None} for name in compilers}
    for _ in range(7):
        for name, exe in compilers.items():
            target = os.path.join(work, name); final = [a.replace('{out}', target) for a in arguments]
            started = time.perf_counter()
            child = subprocess.Popen(['taskset', '-c', '2', exe, 'selfhost/main.goose', '--stdlib', 'stdlib', *final], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            _, status, usage = os.wait4(child.pid, 0); wall = time.perf_counter() - started; child.returncode = os.waitstatus_to_exitcode(status)
            assert child.returncode == 0, (name, job)
            r = record[name]; r['cpu'].append(round(usage.ru_utime + usage.ru_stime, 3)); r['wall'].append(round(wall, 3)); r['rss_mib'].append(usage.ru_maxrss // 1024)
            produced = [a for a in final if a.startswith(target)]
            if produced: r['sha256'] = hashlib.sha256(open(produced[0], 'rb').read()).hexdigest()
    base = statistics.median(record[first]['cpu'])
    row = {'job': job, **record, 'median_cpu': {n: statistics.median(record[n]['cpu']) for n in compilers},
           'median_cpu_ratio': {n: round(statistics.median(record[n]['cpu']) / base, 3) for n in compilers},
           'peak_rss_mib': {n: max(record[n]['rss_mib']) for n in compilers},
           'same_output': all(record[n]['sha256'] == record[first]['sha256'] for n in compilers)}
    rows.append(row); print(job, row['median_cpu'], row['median_cpu_ratio'], row['peak_rss_mib'], 'same output', row['same_output'], flush=True)
json.dump({'compilers': {name: {'path': os.path.relpath(exe), 'sha256': hashlib.sha256(open(exe, 'rb').read()).hexdigest()} for name, exe in compilers.items()},
           'source': subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip(), 'rows': rows}, open(out, 'w'), indent=1)
