#!/usr/bin/env python3
"""bounds.py COMPILER OUT.json: where 64-bit memory's cost on recursive_fibonacci comes from under Wasmtime.

Builds the fixture for 32-bit and 64-bit memory, runs each with Cranelift's Spectre-hardened heap bounds
check on (the default) and off, five runs each, and counts the compare and conditional-move instructions of
the compiled recursive function. Run from the repository root with the venv's python; needs objdump."""
import json, re, statistics, subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, 'scripts')
import run_wasmtime, wasmtime

compiler, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
work = Path(tempfile.mkdtemp(prefix='bounds-'))
rows = []
for memory, options in (('32-bit', []), ('64-bit', ['--wasm-memory64'])):
    module = work / f'fib.{memory}.wasm'
    subprocess.run([str(compiler), 'bench/fixtures/recursive_fibonacci.goose', '--stdlib', 'stdlib', '--target', 'wasm-direct', '-O2', *options, '-o', str(module)], check=True)
    data = module.read_bytes()
    for hardened in (True, False):
        times = []
        for _ in range(5):
            config = run_wasmtime.create_config()
            if not hardened:
                config.cranelift_flag_set('enable_heap_access_spectre_mitigation', 'false')
            result = run_wasmtime.run_module(data, b"35 2\n", timing=False, config=config)
            times.append(int(result['stdout'].split()[1]))
        config = run_wasmtime.create_config()
        if not hardened:
            config.cranelift_flag_set('enable_heap_access_spectre_mitigation', 'false')
        compiled = work / f'fib.{memory}.{hardened}.cwasm'
        compiled.write_bytes(bytes(wasmtime.Module(wasmtime.Engine(config), data).serialize()))
        text = subprocess.run(['objdump', '-d', str(compiled)], capture_output=True, text=True).stdout
        # The recursive function is the one that calls itself.
        counts = {}
        for name, body in re.findall(r'<(wasm\[0\]::function\[\d+\])>:\n(.*?)(?=\n\n|\Z)', text, re.S):
            if re.search(r'call\s+\w+ <' + re.escape(name) + '>', body):
                counts = {'instructions': len(body.splitlines()), 'cmp': len(re.findall(r'\bcmp', body)), 'cmov': len(re.findall(r'\bcmov', body))}
        rows.append({'memory': memory, 'spectre_hardened_bounds': hardened, 'kernel_ns': times, 'median_ms': round(statistics.median(times) / 1e6, 1), 'recursive_function': counts})
        print(rows[-1], flush=True)
out.write_text(json.dumps({'wasmtime': __import__('importlib.metadata').metadata.version('wasmtime'), 'rows': rows}, indent=1) + '\n')
