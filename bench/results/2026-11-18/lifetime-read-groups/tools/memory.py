"""Peak RSS for a full self-check in one fresh Linux process per observation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("baseline", type=Path)
p.add_argument("candidate", type=Path)
p.add_argument("report", type=Path)
p.add_argument("--cpu", required=True, type=int)
args = p.parse_args()
root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
stages = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
measure = root / "bench/results/2026-11-18/compiler-iteration-tools/tools/slots.py"
report = {"cpu": args.cpu, "samples": [], "digest": {}}
for name, stage in stages.items():
    report["digest"][name] = json.loads((stage / "builds.json").read_text())["samples"][0]["artifacts"]
source = stages["baseline"] / "source"
os.sched_setaffinity(0, {args.cpu})
with tempfile.TemporaryDirectory(dir=args.report.resolve().parent) as temp:
    work = Path(temp)
    for index, order in enumerate((("baseline", "candidate"), ("candidate", "baseline"))):
        for name in order:
            for host in ("wasmtime", "native"):
                program = stages[name] / "build-1/compiler-native"
                command = [program, "selfhost/main.goose", "--stdlib", "stdlib", "--check"]
                if host == "wasmtime":
                    command = [sys.executable, measure, stages["baseline"], stages[name], work / "run.json",
                               "--cpu", str(args.cpu), "--preparation-only"]
                with (work / "stdout").open("wb") as out, (work / "stderr").open("wb") as err:
                    with subprocess.Popen(command, cwd=source, stdout=out, stderr=err) as child:
                        _, status, usage = os.wait4(child.pid, 0)
                        child.returncode = os.waitstatus_to_exitcode(status)
                if child.returncode or (work / "stderr").stat().st_size or (host == "native" and (work / "stdout").stat().st_size):
                    raise RuntimeError((child.returncode, (work / "stderr").read_text()))
                row = dict(round=index + 1, label=name, host=host, max_rss_kib=usage.ru_maxrss)
                if host == "wasmtime":
                    run = json.loads((work / "run.json").read_text())
                    assert len(run["samples"]) == 1 and run["samples"][0]["mode"] == "check"
                    row["preparation_ns"] = run["compilers"]["candidate"]["preparation_ns"]
                report["samples"].append(row)
                args.report.write_text(json.dumps(report, indent=2) + "\n")
                print(row, flush=True)
