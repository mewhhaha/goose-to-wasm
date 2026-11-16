#!/usr/bin/env python3
"""runtime.py COMPILER OUT.json: the kernel time of the four benchmark fixtures built for 32-bit and for
64-bit memory, under Wasmtime and V8. The fixtures time their own kernel (bench_clock) after two warm-up
calls and print the checksum and the nanoseconds; five runs each, all recorded. Run from the repository
root with the venv's python."""
import json, subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, 'bench')
from benchmark import WORKLOADS as BENCHMARKS  # the official inputs

compiler, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
work = Path(tempfile.mkdtemp(prefix='m64rt-'))
rows = []
for name in ('array_updates', 'integer_mod', 'float_recurrence', 'recursive_fibonacci'):
    stdin = f"{BENCHMARKS[name]['input']} 2\n".encode()
    for memory, options in (('32-bit', []), ('64-bit', ['--wasm-memory64'])):
        module = work / f'{name}.{memory}.wasm'
        subprocess.run([str(compiler), f'bench/fixtures/{name}.goose', '--stdlib', 'stdlib', '--target', 'wasm-direct', '-O2', *options, '-o', str(module)], check=True)
        for engine, command in (('wasmtime', [sys.executable, 'scripts/run_wasmtime.py', str(module)]), ('v8', ['node', 'scripts/run_wasm.mjs', str(module)])):
            times, checksum = [], None
            for _ in range(5):
                result = subprocess.run(command, input=stdin, capture_output=True, check=True)
                checksum, elapsed = result.stdout.split()[:2]
                times.append(int(elapsed))
            rows.append({'fixture': name, 'memory': memory, 'engine': engine, 'module_bytes': module.stat().st_size,
                         'checksum': checksum.decode(), 'kernel_ns': times})
            print(name, memory, engine, checksum.decode(), [round(t / 1e6, 1) for t in times], flush=True)
out.write_text(json.dumps({'inputs': {n: BENCHMARKS[n]['input'] for n in ('array_updates', 'integer_mod', 'float_recurrence', 'recursive_fibonacci')}, 'warmups': 2, 'rows': rows}, indent=1) + '\n')
