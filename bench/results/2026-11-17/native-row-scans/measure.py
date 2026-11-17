#!/usr/bin/env python3
"""Time the frozen Row workload and count bounded Row decoder entries separately."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path("bench/results/2026-11-17/varint-foreach/native_rows.goose")
HOST = Path("bench/host_input.c")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cpu", type=int, default=6)
    args = parser.parse_args()
    cc = shutil.which("gcc")
    flags = ["-O2", "-rdynamic", "-fno-strict-aliasing"]
    links = ["-lm", "-ldl", "-pthread"]
    compiler = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    def command(*argv, **kwargs):
        return subprocess.check_output([str(x) for x in argv], cwd=ROOT, text=True, **kwargs)

    report = {
        "source": str(SOURCE), "source_sha256": sha(ROOT / SOURCE),
        "host_input_sha256": sha(ROOT / HOST), "compiler": {},
        "gcc": command(cc, "--version").splitlines()[0], "gcc_sha256": sha(cc),
        "target": command(cc, "-dumpmachine").strip(), "cpu": args.cpu,
        "thread_siblings": Path(f"/sys/devices/system/cpu/cpu{args.cpu}/topology/thread_siblings_list").read_text().strip(),
        "goose_flags": ["--stdlib", "stdlib", "--target", "native", "-O2"],
        "gcc_flags": flags, "link_flags": links,
        "timed_pairs_columns": ["construct_ns", "foreach_ns"],
        "skip_calls_columns": ["construct_calls", "foreach_calls"], "measurement": {},
    }
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
        work = Path(name)
        # Same input and dynamic symbol, replacing only the value of the clock.
        counting_host = work / "counting-host.c"
        counting_host.write_text('#define bench_clock unused_bench_clock\n#include "bench/host_input.c"\n'
                                 '#undef bench_clock\nextern int64_t row_visits;\nint64_t bench_clock(void){return row_visits;}\n')
        for label, binary in compiler.items():
            src = work / (label + ".c")
            command(binary, SOURCE, *report["goose_flags"], "-o", src)
            exe = work / label
            command(cc, *flags, src, HOST, "-o", exe, *links)
            source = src.read_text()
            counted, matches = re.subn(r"(static const uint8_t \*g_self_skip_\d+\(const uint8_t \*start,const uint8_t \*end\)\{)",
                                        r"int64_t row_visits;\n\1row_visits++;", source)
            if matches != 1:
                raise ValueError(f"Expected one Row decoder in {src}, got {matches}")
            counted_src = work / (label + "-count.c")
            counted_src.write_text(counted)
            count_exe = work / (label + "-count")
            command(cc, *flags, counted_src, counting_host, "-I.", "-o", count_exe, *links)
            report["compiler"][label] = {
                "sha256": sha(binary), "generated_c_sha256": sha(src), "executable_sha256": sha(exe),
                "counted_c_sha256": sha(counted_src), "counted_executable_sha256": sha(count_exe),
                "counted_host_sha256": sha(counting_host),
            }

        def run(label, count):
            stdout = command("taskset", "-c", args.cpu, work / label, input=f"{count}\n")
            checksum, build, walk = map(int, stdout.splitlines())
            if checksum != count * (count - 1) // 2:
                raise ValueError(f"Incorrect checksum for {label} with {count} rows")
            return [build, walk]

        for n in [1001, 2002, 4004, 8008]:
            row = dict(warmups=2, pairs=[], skip_calls={}, expected_checksum=n*(n-1)//2)
            for _ in range(row["warmups"]):
                for label in compiler:
                    run(label, n)
            for i in range(7):
                order = list(compiler)
                if i % 2:
                    order.reverse()
                row["pairs"].append({label: run(label, n) for label in order})
            for label in compiler:
                row["skip_calls"][label] = run(label+"-count", n)
            report["measurement"][n] = row
            args.output.write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
