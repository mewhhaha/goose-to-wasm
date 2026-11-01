"""Diagnose CRC emitter cost in persistent workers; not a cold-build benchmark."""
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

root = Path.cwd()
sys.path.insert(0, str(root / "bench"))
import langarena as arena

output = root / "build/performance/next-emitter-probe"
output.mkdir(parents=True, exist_ok=True)
variants = {"baseline": "runtime-next-baseline", "candidate": "runtime-next-address"}
reports = {"baseline": "next-baseline", "candidate": "next-address"}
qualified = {}
for label, name in reports.items():
    report = json.loads((root / "build/performance" / name / "report.json").read_text())
    qualified[label] = next(r for r in report["observations"] if r["kind"] == "build" and r["task"] == "Hash::CRC32")
source = qualified["baseline"]["driver_stats"]["source"]
jobs, rows, pids = {}, [], {}
try:
    for label in variants:
        log = (output / (label + ".stderr")).open("w")
        process = subprocess.Popen([sys.executable, str(root / "scripts/goose_wasm.py"), "serve", "--native-worker", "--lexical-cache"],
                                   cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
        jobs[label] = (process, log)
    rng = random.Random(761204)
    sequence = 0
    for sample in range(-2, 12):
        order = list(variants)
        rng.shuffle(order)
        for label in order:
            process, _ = jobs[label]
            sequence += 1
            artifact = output / (label + ".wasm")
            compiler = root / "build" / variants[label] / "bin/goose"
            args = ["build", source, "--goose", str(compiler), "--offline", "-O2", "--no-cache",
                    "--cache-dir", str(output / (label + "-cache")), "-o", str(artifact)]
            process.stdin.write(json.dumps({"id": sequence, "args": args}) + "\n")
            process.stdin.flush()
            reply = json.loads(process.stdout.readline())
            assert reply["id"] == sequence and reply["ok"], reply
            result = reply["result"]
            assert arena.sha256(artifact) == qualified[label]["artifact_sha256"]
            pid = result["compiler_worker_pid"]
            if label in pids:
                assert pids[label] == pid and result["compiler_process_reused"]
            pids[label] = pid
            assert not result["backend_stats"]["frontend_reused"]
            if sample >= 0:
                rows.append({"variant": label, "sample": sample, "stats": result["backend_stats"]})
finally:
    for process, log in jobs.values():
        process.stdin.close()
        process.wait(timeout=30)
        process.stdout.close()
        log.close()
summary = {}
for label in variants:
    samples = [r["stats"] for r in rows if r["variant"] == label]
    summary[label] = {key.removesuffix("_ns") + "_milliseconds": arena.summarize([r[key] / 1e6 for r in samples])
                      for key in ("backend_ns", "frontend_ns", "parse_ns", "resolve_ns", "typecheck_ns", "optimize_ns", "bce_ns")}
result = {"status": "passed", "method": "Two warmups per persistent compiler worker, then 12 shuffled pairs. Lexical cache enabled; artifact cache and typed-frontend reuse disabled. Every module matches its qualified artifact. Times are milliseconds.",
          "source": source, "source_sha256": arena.sha256(Path(source)), "harness_sha256": arena.sha256(Path(__file__)),
          "compiler_sha256": {k: arena.sha256(root / "build" / v / "bin/goose") for k, v in variants.items()},
          "observations": rows, "summary": summary}
(output / "report.json").write_text(json.dumps(result, indent=2) + "\n")
for label in variants:
    print(label, "backend ms", summary[label]["backend_milliseconds"]["median"], "MAD", summary[label]["backend_milliseconds"]["mad"])
