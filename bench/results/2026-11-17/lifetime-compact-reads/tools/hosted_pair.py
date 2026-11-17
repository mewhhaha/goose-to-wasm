#!/usr/bin/env python3
"""hosted_pair.py OUT.json COMPILER BEFORE_SOURCES AFTER_SOURCES: the compiler's sources before and after, each
built as a 64-bit Wasm module by COMPILER (256 GiB declared), run under Wasmtime (host/rust) checking and
compiling selfhost/main.goose: three interleaved runs each, wall seconds. A source directory holds selfhost/
and has native/ beside it. Wasmtime compiles each module once before the timed runs."""
import json, os, subprocess, sys, tempfile, time
out, compiler, sources = sys.argv[1], os.path.abspath(sys.argv[2]), {'before': sys.argv[3], 'after': sys.argv[4]}
work = tempfile.mkdtemp(prefix='hp-'); host = os.path.abspath('host/rust/target/release/goose-wasmtime'); std = ['--stdlib', 'stdlib']
modules = {}
for name, source in sources.items():
    modules[name] = os.path.join(work, name + '.wasm')
    subprocess.run([compiler, os.path.join(source, 'selfhost/main.goose'), *std, '--target', 'wasm-direct', '-O2', '--wasm-memory64', '--wasm-max-pages', '4194304', '-o', modules[name]], check=True)
    subprocess.run([host, modules[name], '--cache', modules[name] + '.cwasm', '--', 'examples/squares.goose', *std, '--check'], check=True, stdin=subprocess.DEVNULL)
jobs = {'check': ['--check'], 'to 32-bit Wasm': ['--target', 'wasm-direct', '-O2', '--wasm-max-pages', '65535', '-o', os.path.join(work, 'x.wasm')]}
rows = []
for job, arguments in jobs.items():
    times = {name: [] for name in modules}
    for _ in range(3):
        for name, module in modules.items():
            started = time.perf_counter()
            done = subprocess.run([host, module, '--cache', module + '.cwasm', '--', 'selfhost/main.goose', *std, *arguments], capture_output=True, stdin=subprocess.DEVNULL)
            assert done.returncode == 0, done.stderr[-300:]
            times[name].append(round(time.perf_counter() - started, 3))
    rows.append({'job': job, **times}); print(job, times, flush=True)
json.dump({'host': 'host/rust, wasmtime 50.0.1', 'module_bytes': {name: os.path.getsize(path) for name, path in modules.items()}, 'rows': rows}, open(out, 'w'), indent=1)
