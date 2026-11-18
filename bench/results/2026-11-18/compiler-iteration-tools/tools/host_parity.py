"""Compare the contracts and guest-visible output of two complete memory64 runs."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("stage", type=Path)
p.add_argument("output", type=Path)
args = p.parse_args()
known = json.loads((Path(__file__).resolve().parents[5] / "tests/conformance/known-gaps-memory64.json").read_text())
report = {"runs": {}, "times": json.loads((args.stage / "host-times.json").read_text())}
observations = {}
for host in ("rust", "python"):
    path = args.stage / f"memory64-{host}/report.json"
    data = json.loads(path.read_text())
    if data["input_sha256"] != data["input_sha256_after"]:
        raise ValueError(f"{host} inputs changed during the run")
    rows = {}
    for row in data["results"]:
        key = (row["case"], row["level"])
        if key in rows:
            raise ValueError(f"duplicate contract {key}")
        semantic = {k: v for k, v in row.items() if not k.endswith("_command")}
        for name in ("compile_command", "parse_command", "run_command"):
            if name in row:
                cmd = data["commands"][row[name]]
                semantic[name] = [cmd[k] for k in ("exit_code", "stdout", "stderr", "error")]
        rows[key] = semantic
    gaps = {key for key, row in rows.items() if row["status"] != "pass"}
    if gaps != {tuple(k) for k in known["gaps"]}:
        raise ValueError(f"{host}: unexpected gaps")
    pins = {k: v for k, v in data["input_sha256"].items() if k != data["configuration"]["host"]}
    if host == "rust":
        reference_pins = pins
    elif pins != reference_pins:
        raise ValueError("contract inputs differ between hosts")
    observations[host] = rows
    report["runs"][host] = {"report_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "summary": data["summary"], "commands": len(data["commands"]),
                            "runtime_rows": sum("run_command" in v for v in rows.values()),
                            "configuration": data["configuration"], "host_sha256": data["input_sha256"].get(data["configuration"]["host"]),
                            "shared_pin_count": len(pins), "compiler_sha256": pins[data["configuration"]["compiler"]]}
if observations["rust"].keys() != observations["python"].keys():
    raise ValueError("different contract sets")
diffs = []
for key, rust in observations["rust"].items():
    python = observations["python"][key]
    if rust != python:
        diffs.append({"case": key, "different": [k for k in rust if rust[k] != python[k]],
                      "rust": rust.get("run_command"), "python": python.get("run_command")})
report["compared"] = len(observations["rust"])
report["differences"] = diffs
args.output.write_text(json.dumps(report, indent=2) + "\n")
print(report["compared"], "contracts;", len(diffs), "differences")
for sample in diffs[:8]:
    print(str(sample)[:550])
raise SystemExit(bool(diffs))
