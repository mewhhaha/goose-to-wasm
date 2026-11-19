"""Build and run generated Goose programs that call every function in reverse order."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]
sys.path[:0] = [str(ROOT / "bench"), str(ROOT / "scripts"), str(ROOT / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
from selfhost_comparison import identity
from measure import measured


def source(count):
    declarations = (f"fn f{i:04}(value: i64) -> i64 {{ return value + {i + 1}; }}\n" for i in range(count))
    calls = (f"    total = f{i:04}(total);\n" for i in reversed(range(count)))
    return "".join(declarations) + "fn main() {\n    var total: i64 = 0;\n" + "".join(calls) + "    print(total);\n}\n"


def run(command, directory):
    completed = subprocess.run(command, cwd=directory, capture_output=True, check=True)
    if completed.stderr:
        raise ValueError(completed.stderr.decode(errors="replace"))
    return completed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("baseline", "indexed", "native", "host", "stdlib", "work"):
        parser.add_argument("--" + option, type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=5)
    args = parser.parse_args()
    work, host, native, stdlib = (p.resolve() for p in (args.work, args.host, args.native, args.stdlib))
    compilers = {"baseline": args.baseline.resolve(), "indexed": args.indexed.resolve()}
    work.mkdir(parents=True)
    os.sched_setaffinity(0, {args.cpu})
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    flags = ["--stdlib", stdlib, "--target", "wasm-direct", "-O0", "--wasm-memory64", "--wasm-max-pages", "262144"]
    commands = {}
    for name, module in compilers.items():
        cache = work / (name + ".cwasm")
        commands[name] = [host, module, "--cache", cache, "--"]
        run([*commands[name], "--version"], work)
        if cache.with_suffix(".cwasm.sha256").read_text().strip() != identity(module)["sha256"]:
            raise ValueError("Prepared cache does not match the compiler")
    report = dict(cpu=args.cpu, host=identity(host), native_compiler=identity(native),
                  compilers={name: identity(p) for name, p in compilers.items()},
                  arguments=[str(v) for v in flags], sizes={})
    output = work / "compiled.wasm"
    reference = work / "reference.wasm"
    for count in (512, 2048, 4096):
        fixture = work / f"reverse-{count}.goose"
        fixture.write_text(source(count))
        arguments = [fixture.name, *flags, "-o"]
        run([native, *arguments, reference], work)
        expected = identity(reference)
        stdout = run([host, reference], work).stdout.decode()
        if stdout != f"{count * (count + 1) // 2}\n":
            raise ValueError(f"Wrong runtime result for {count} functions")
        entry = dict(source=identity(fixture), expected=expected, stdout=stdout.strip(), samples=[])
        report["sizes"][str(count)] = entry
        for round_number in range(1, 4):
            order = list(commands)
            if round_number % 2 == 0:
                order.reverse()
            for name in order:
                output.unlink(missing_ok=True)
                before = resource.getrusage(resource.RUSAGE_CHILDREN)
                _, elapsed, counters = measured(lambda: run([*commands[name], *arguments, output], work), child=True)
                after = resource.getrusage(resource.RUSAGE_CHILDREN)
                if identity(output) != expected:
                    raise ValueError(f"Different compiler output for {name}, {count} functions")
                entry["samples"].append(dict(case=name, round=round_number, wall_ns=elapsed,
                                             cpu_s=after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                                             counters=counters))
        (work / "scaling.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{count:,} functions verified", flush=True)


if __name__ == "__main__":
    main()
