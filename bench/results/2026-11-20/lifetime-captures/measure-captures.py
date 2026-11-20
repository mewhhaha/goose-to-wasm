"""Measure full compiler checks on programs sharing globals or callees."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'scripts'))
helper = ROOT / 'bench/results/2026-11-18/selfhost-wasm-runtime/tools/measure.py'
spec = importlib.util.spec_from_file_location('hardware', helper)
hardware = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hardware)
hardware.EVENTS = {'instructions': 1, 'cycles': 0}


def program(shape, width):
    if shape == 'shared-callees':
        lines = ['fn link0(x: i64) -> i64 { return x; }']
        for i in range(1, width + 1):
            lines.append(f'fn link{i}(x: i64) -> i64 {{ return link{i-1}(x); }}')
        for i in range(width):
            lines.append(f'fn caller{i}() -> i64 {{ return link{width}({i}); }}')
        lines.append('fn main() { var total = 0;')
        lines.extend(f'total += caller{i}();' for i in range(width))
        lines.append('print(total); }')
        return '\n'.join(lines) + '\n', f'{width*(width-1)//2}\n'
    names = [f'g{i:03d}' for i in range(width)]
    used = names
    if shape == 'sparse' and width > 2:
        used = [names[0], names[-1]]
    lines = [f'var {name}: const u8[:] = "abc";' for name in names]
    lines.append('fn read_shared(i: i64) -> i64 { var total = i;')
    lines.extend(f'total += {name}.len;' for name in used)
    lines.append('return total; }')
    lines.extend(f'let result{i:03d} = read_shared({i});' for i in range(width))
    lines.append(f'fn main() {{ print(result000, " ", result{width-1:03d}); }}')
    total = 3 * len(used)
    return '\n'.join(lines) + '\n', f'{total} {total+width-1}\n'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('before', 'after', 'host', 'stdlib', 'work'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--cpu', type=int, required=True)
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--shape', choices=['dense', 'sparse', 'shared-callees'], nargs='+',
                        default=['dense', 'sparse', 'shared-callees'])
    parser.add_argument('--width', type=int, nargs='+', default=[32, 128, 512])
    parser.add_argument('--forced', type=Path, help='additional diagnostic compiler')
    args = parser.parse_args()
    if args.rounds < 1 or min(args.width) < 1:
        parser.error('Rounds and widths must be positive.')
    os.sched_setaffinity(0, {args.cpu})
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    modules = {'before': args.before.resolve(), 'after': args.after.resolve()}
    if args.forced:
        modules['forced'] = args.forced.resolve()
    host = args.host.resolve()
    commands = {k: [host, mod, '--cache', work / (k + '.cwasm'), '--'] for k, mod in modules.items()}
    seed = 43128
    rng = random.Random(seed)
    report = dict(cpu=args.cpu, seed=seed, rounds=args.rounds, modules={k: digest(v) for k, v in modules.items()},
                  host=digest(host), cases=[])
    for cmd in commands.values():
        subprocess.run([*cmd, '--version'], capture_output=True, check=True)
    for shape in args.shape:
        for width in args.width:
            source = work / f'{shape}-{width}.goose'
            text, expected = program(shape, width)
            source.write_text(text)
            flags = [source, '--stdlib', args.stdlib.resolve(), '--target', 'wasm-direct', '-O2']
            row = dict(shape=shape, width=width, source_sha256=digest(source), stdout=expected, rows=[])
            for key, cmd in commands.items():
                output = work / f'{shape}-{width}-{key}.wasm'
                output.unlink(missing_ok=True)
                proc = subprocess.run([*cmd, *flags, '--wasm-memory64', '--wasm-max-pages', '262144', '-o', output],
                                      capture_output=True, timeout=180, check=True)
                actual = subprocess.run([host, output], capture_output=True, timeout=60, check=True)
                if proc.stdout or proc.stderr or actual.stdout.decode() != expected or actual.stderr:
                    raise ValueError(f'Unexpected output in {shape} {width} {key}')
                if row.setdefault('output_sha256', digest(output)) != digest(output):
                    raise ValueError(f'Different module in {shape} {width} {key}')
            for index in range(args.rounds):
                order = list(commands)
                rng.shuffle(order)
                for key in order:
                    cmd = [*commands[key], *flags, '--check']
                    proc, elapsed, counts = hardware.measured(
                        lambda: subprocess.run(cmd, capture_output=True, timeout=100, check=True), True)
                    if proc.stdout or proc.stderr:
                        raise ValueError(f'Unexpected check output in {key}')
                    row['rows'].append(dict(compiler=key, round=index+1, wall_ns=elapsed, counters=counts))
            report['cases'].append(row)
            (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(shape, width, flush=True)


if __name__ == '__main__':
    main()
