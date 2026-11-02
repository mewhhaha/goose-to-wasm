"""Check genuinely non-raw image workloads, including hot metadata accesses."""
from datetime import datetime, timezone
import itertools
import json
from pathlib import Path
import random
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bench"))
import benchmark as common

OUT = ROOT / "build/native-gap/mode-pairs"
OUT.mkdir(parents=True, exist_ok=True)
COMPILERS = {"baseline": ROOT / "build/native-gap/baseline/bin/goose",
             "candidate": ROOT / "build/native-gap/images/bin/goose"}
DECLARATIONS = {
    "raw": "var rows:u8[>..]=[7;128];",
    "u8": "var rows:u8[u8]=[7;128];",
    "u32": "var rows:u8[u32]=[7;128];",
    "u64": "var rows:u8[u64]=[7;128];",
    "uleb": "var rows:u8[varint]=[7;128];",
    "limited": "var capacity=128; var rows:u8[..]=[..capacity];",
}
SOURCE = '''extern fn bench_input()->i64;
extern fn bench_clock()->i64;
extern fn bench_sink(n:i64);
DECLARATION
fn prepare() { for i in 128 { rows[i]=7; } }
recursive fn kernel(n:i64)->i64 {
    var result=0;
    for i in n {
        rows[i & 127]=(i & 255) as u8;
        result+=rows[(i+1) & 127] as i64;
    }
    return result;
}
fn main() {
    INITIALIZE
    let n=bench_input();
    for warmup in 10 { prepare(); bench_sink(kernel(32768)); }
    prepare(); let start=bench_clock(); let result=kernel(n);
    bench_sink(result); let finish=bench_clock();
    print("RESULT ",result); print("NANOSECONDS ",finish-start);
}
'''
args = SimpleNamespace(goose=COMPILERS["candidate"], node="node", cc="gcc", emcc="emcc",
                       machine_label="AMD Ryzen 7 3800X, shared desktop host")
N = 1000000
cycles, remainder = divmod(N - 127, 256)
EXPECTED = 127 * 7 + cycles * 32640 + remainder * (remainder - 1) // 2
report = {"status": "running", "started_utc": datetime.now(timezone.utc).isoformat(),
          "environment": common.metadata(args), "samples": 5, "iterations": N, "expected": EXPECTED,
          "method": "Fresh processes; ten prepared 32768-iteration guest kernel warmups before one timed million-iteration kernel. "
                    "The kernel mutates payload bytes and repeatedly accesses the actual physical metadata. Preparation and printing are outside clocks. "
                    "Every checksum is independently derived in Python. These are hot metadata controls, not example entry or process timings.",
          "compiler_sha256": {name: common.digest(path) for name, path in COMPILERS.items()},
          "sources": {}, "builds": [], "runs": [], "summary": []}
artifacts = {}
for name, declaration in DECLARATIONS.items():
    source = OUT / "source" / (name + ".goose")
    source.parent.mkdir(exist_ok=True)
    initialize = ""
    if name == "limited":
        initialize = "for i in 128 { rows.push(7); }"
    source.write_text(SOURCE.replace("DECLARATION", declaration).replace("INITIALIZE", initialize))
    report["sources"][str(source)] = common.digest(source)
    for variant, compiler in COMPILERS.items():
        directory = OUT / "compile" / name / variant
        artifact, stats = directory / "program.wasm", directory / "stats.json"
        command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", source, "--backend", "direct",
                   "--goose", compiler, "--offline", "--no-cache", "-O2", "-o", artifact, "--stats", stats]
        _, wall = common.run(command, directory=directory, name="build")
        row = {"name": name, "variant": variant, "command": list(map(str, command)), "wall_seconds": wall,
               "artifact": str(artifact), "sha256": common.digest(artifact), "stats": json.loads(stats.read_text())}
        report["builds"].append(row)
        artifacts[name, variant] = artifact

def checkpoint():
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")

rng = random.Random(44381)
for phase, count in [("warmup", 1), ("measure", 5)]:
    jobs = list(itertools.product(range(count), DECLARATIONS, ["v8", "wasmtime"]))
    rng.shuffle(jobs)
    for sample, name, engine in jobs:
        variants = list(COMPILERS)
        rng.shuffle(variants)
        for variant in variants:
            directory = OUT / "runtime" / phase / name / engine / str(sample) / variant
            command = ["node", ROOT / "scripts/run_wasm.mjs", artifacts[name, variant]]
            if engine == "wasmtime":
                command = [sys.executable, ROOT / "scripts/run_wasmtime.py", artifacts[name, variant]]
            result, wall = common.run(command, directory=directory, name="run", stdin=str(N) + "\n")
            lines = result.stdout.splitlines()
            assert lines[0] == "RESULT " + str(EXPECTED), result.stdout
            assert lines[1].startswith("NANOSECONDS "), result.stdout
            seconds = int(lines[1].split()[1]) / 1e9
            assert 0 < seconds < wall
            report["runs"].append({"phase": phase, "name": name, "engine": engine, "variant": variant,
                "sample": sample, "command": list(map(str, command)), "kernel_seconds": seconds, "wall_seconds": wall})
        checkpoint()
        print(phase, name, engine, sample, flush=True)
for name, engine in itertools.product(DECLARATIONS, ["v8", "wasmtime"]):
    indexed = {(r["sample"], r["variant"]): r for r in report["runs"] if r["phase"] == "measure" and r["name"] == name and r["engine"] == engine}
    values = {v: common.summary([indexed[s, v]["kernel_seconds"] for s in range(5)]) for v in COMPILERS}
    ratios = [indexed[s, "baseline"]["kernel_seconds"] / indexed[s, "candidate"]["kernel_seconds"] for s in range(5)]
    report["summary"].append({"name": name, "engine": engine, **values, "paired_speedup": common.summary(ratios)})
assert all(common.digest(path) == report["compiler_sha256"][name] for name, path in COMPILERS.items())
assert all(common.digest(Path(path)) == sha for path, sha in report["sources"].items())
assert all(common.digest(Path(row["artifact"])) == row["sha256"] for row in report["builds"])
report["status"] = "passed"
report["finished_utc"] = datetime.now(timezone.utc).isoformat()
checkpoint()
print("PASS", OUT / "report.json")
