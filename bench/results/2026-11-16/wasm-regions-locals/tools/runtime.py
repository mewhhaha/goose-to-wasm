#!/usr/bin/env python3
"""runtime.py OUT.json NAME=COMPILER ...: kernel times of six programs for each compiler given, built for
32-bit and for 64-bit memory, under Wasmtime and V8. The four benchmark fixtures of bench/fixtures and two
programs of this directory that use growable arrays. Each program times its own kernel (bench_clock) after
two warm-up calls and prints the checksum and the nanoseconds; five runs each, all recorded. A compiler
that does not know --wasm-memory64 is skipped for it. Run from the repository root with the venv's python."""
import json, subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, 'bench')
from benchmark import WORKLOADS

here = Path(__file__).resolve().parent
out = Path(sys.argv[1])
compilers = [argument.split('=', 1) for argument in sys.argv[2:]]
work = Path(tempfile.mkdtemp(prefix='rt-'))
programs = [(name, Path('bench/fixtures') / f'{name}.goose', WORKLOADS[name]['input']) for name in ('array_updates', 'integer_mod', 'float_recurrence', 'recursive_fibonacci')]
programs += [('array_push', here / 'array_push.goose', 4000000), ('array_locals', here / 'array_locals.goose', 4000000)]
rows = []
for name, source, count in programs:
    stdin = f"{count} 2\n".encode()
    for memory, options in (('32-bit', []), ('64-bit', ['--wasm-memory64'])):
        for label, compiler in compilers:
            module = work / f'{name}.{memory}.{label}.wasm'
            built = subprocess.run([str(Path(compiler).resolve()), str(source), '--stdlib', 'stdlib', '--target', 'wasm-direct', '-O2', '--wasm-max-pages', '8192', *options, '-o', str(module)], capture_output=True)
            if built.returncode:
                continue
            for engine, command in (('wasmtime', [sys.executable, 'scripts/run_wasmtime.py', str(module)]), ('v8', ['node', 'scripts/run_wasm.mjs', str(module)])):
                times, checksum = [], None
                for _ in range(5):
                    result = subprocess.run(command, input=stdin, capture_output=True, check=True)
                    checksum, elapsed = result.stdout.split()[:2]
                    times.append(int(elapsed))
                rows.append({'program': name, 'memory': memory, 'compiler': label, 'engine': engine, 'module_bytes': module.stat().st_size,
                             'checksum': checksum.decode(), 'kernel_ns': times})
                print(name, memory, label, engine, checksum.decode(), [round(t / 1e6, 1) for t in times], flush=True)
out.write_text(json.dumps({'inputs': {name: count for name, _, count in programs}, 'warmups': 2, 'rows': rows}, indent=1) + '\n')
