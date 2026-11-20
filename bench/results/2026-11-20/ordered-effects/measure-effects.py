"""Measure and verify compiler checks on generated shrink, growth and store workloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [str(ROOT / 'scripts'), str(ROOT / 'bench'),
                 str(ROOT / 'bench/results/2026-11-18/selfhost-wasm-runtime/tools')]
from measure import measured


def program(shape, count):
    if shape == 'stores':
        lines = ['struct Holder { view: const i64[:] }', 'var items: i64[4] = [5, 6, 7, 8];']
        for index in range(count):
            lines.append(f'var h{index}: Holder = Holder {{ view: items[0..1] }};')
        actions = [f'h{i}.view = items[2..4];' for i in range(count)]
        result = f'h{count-1}.view[0]'
        expected = '7\n'
    else:
        lines = [f'var g{i}: i64[>..] = [];' for i in range(count)]
        actions = []
        for i in range(count):
            if shape == 'distinct' or i == 0:
                actions.append(f'g{i}.clear();')
            else:
                actions.append(f'g{i}.push({i});')
        result = f'g{count-1}.len'
        expected = '0\n'
        if shape == 'mixed' and count > 1:
            expected = '2\n'
    lines.extend(['fn edit() {', *actions, '}', 'fn replay() { edit(); edit(); }',
                  f'fn main() {{ replay(); print({result}); }}'])
    return '\n'.join(lines) + '\n', expected


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('before', 'after', 'host', 'stdlib', 'work'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--cpu', type=int, required=True)
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--width', type=int, nargs='+', default=[32, 128, 512, 1024])
    args = parser.parse_args()
    if args.rounds < 1 or min(args.width) < 1:
        parser.error('Rounds and program widths must be positive.')
    os.sched_setaffinity(0, {args.cpu})
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    host = args.host.resolve()
    modules = {'before': args.before.resolve(), 'after': args.after.resolve()}
    commands = {k: [host, module, '--cache', work / f'{k}.cwasm', '--'] for k, module in modules.items()}
    seed = 48491
    rng = random.Random(seed)
    report = dict(cpu=args.cpu, seed=seed, rounds=args.rounds, host=digest(host),
                  modules={k: digest(p) for k, p in modules.items()}, cases=[])
    artifact = work / 'output.wasm'
    for shape in ('distinct', 'mixed', 'stores'):
        for count in args.width:
            text, expected = program(shape, count)
            source = work / f'{shape}-{count}.goose'
            source.write_text(text)
            flags = [source, '--stdlib', args.stdlib.resolve(), '--target', 'wasm-direct', '-O2']
            row = dict(shape=shape, width=count, source_sha256=digest(source), stdout=expected, samples=[])
            for command in commands.values():
                artifact.unlink(missing_ok=True)
                emit = subprocess.run([*command, *flags, '-o', artifact], capture_output=True, timeout=120, check=True)
                run = subprocess.run([host, artifact], capture_output=True, timeout=60, check=True)
                if emit.stdout or emit.stderr or run.stdout.decode() != expected or run.stderr:
                    raise ValueError(f'Unexpected program output for {source}')
                if row.setdefault('output_sha256', digest(artifact)) != digest(artifact):
                    raise ValueError(f'Compiler output differs for {source}')
            for index in range(args.rounds):
                order = list(commands)
                rng.shuffle(order)
                for key in order:
                    command = [*commands[key], *flags, '--check']
                    res, wall, counters = measured(
                        lambda: subprocess.run(command, capture_output=True, timeout=180, check=True), child=True)
                    if res.stdout or res.stderr:
                        raise ValueError(f'Unexpected checker output for {source}')
                    row['samples'].append(dict(compiler=key, round=index + 1, wall_ns=wall, counters=counters))
            report['cases'].append(row)
            (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(shape, count, flush=True)


if __name__ == '__main__':
    main()
