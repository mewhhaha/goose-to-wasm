"""Compare direct and compacted compiler modules rebuilding one frozen source tree."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile
from time import perf_counter_ns


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('direct', 'balanced', 'size', 'workload', 'host', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--cpu', type=int, required=True)
    parser.add_argument('--rounds', type=int, default=7)
    args = parser.parse_args()
    os.sched_setaffinity(0, {args.cpu})
    modules = {key: getattr(args, key).resolve() for key in ('direct', 'balanced', 'size')}
    workload = args.workload.resolve()
    host = args.host.resolve()
    rows = []
    seed = 124705
    shuffle = random.Random(seed)
    report = dict(cpu=args.cpu, seed=seed, rounds=args.rounds, host_sha256=digest(host),
                  expected_sha256=args.expected_sha256, modules={}, rows=rows)
    for key, path in modules.items():
        data = path.read_bytes()
        report['modules'][key] = dict(bytes=len(data), gzip_bytes=len(gzip.compress(data, compresslevel=9, mtime=0)),
                                      sha256=digest(path))
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        output = work / 'result.wasm'
        stats = work / 'engine.json'
        guest = ['selfhost/main.goose', '--stdlib', 'stdlib', '--target', 'wasm-direct', '-O2',
                 '--wasm-memory64', '--wasm-max-pages', '262144', '-o', str(output)]
        report['compiler_args'] = guest[:-1] + ['result.wasm']

        def run(key, cached):
            cache = ['--no-cache']
            if cached:
                cache = ['--cache', work / (key + '.cwasm')]
            output.unlink(missing_ok=True)
            cmd = [host, modules[key], *cache, '--timing-json', stats, '--', *guest]
            start = perf_counter_ns()
            process = subprocess.run(cmd, cwd=workload, capture_output=True, timeout=120, check=True)
            elapsed = perf_counter_ns() - start
            if process.stdout or process.stderr or digest(output) != args.expected_sha256:
                raise RuntimeError(f'{key} produced unexpected compiler output')
            return dict(profile=key, cached=cached, wall_ns=elapsed, engine=json.loads(stats.read_text()))

        for key in modules:
            run(key, True)
        for round_index in range(args.rounds):
            for cached in (False, True):
                order = list(modules)
                shuffle.shuffle(order)
                for key in order:
                    row = run(key, cached)
                    row['round'] = round_index + 1
                    rows.append(row)
            args.output.write_text(json.dumps(report, indent=2) + '\n')
            print('Completed round', round_index + 1, flush=True)


if __name__ == '__main__':
    main()
