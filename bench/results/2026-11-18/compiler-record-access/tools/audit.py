"""Validate changed Wasm outputs and compare their external interfaces."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import wasmtime

root = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(root / "scripts"))
from run_wasmtime import create_config


def signature(t):
    if isinstance(t, wasmtime.FuncType):
        return ("func", list(map(str, t.params)), list(map(str, t.results)))
    if isinstance(t, wasmtime.GlobalType):
        return ("global", str(t.content), t.mutable)
    if isinstance(t, wasmtime.MemoryType):
        return ("memory", t.is_64, t.is_shared, t.limits.min, t.limits.max, t.page_size)
    if isinstance(t, wasmtime.TableType):
        return ("table", str(t.element), t.limits.min, t.limits.max)
    raise ValueError(f"unrecognized external type {t}")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("equivalence", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
report = json.loads((args.equivalence / "report.json").read_text())
config = create_config()
config.cache = True
engine = wasmtime.Engine(config)
sizes = Counter()
results = []
for row in report["differing"]:
    assert row["mode"] == "wasm2" and row["baseline"]["exit"] == row["candidate"]["exit"] == 0
    assert all(row["baseline"][k] == row["candidate"][k] for k in ("stdout", "stderr"))
    key = hashlib.sha256((row["source"] + "\0wasm2").encode()).hexdigest()[:16]
    external = []
    pair = {}
    for role in ("baseline", "candidate"):
        data = (args.equivalence / role / key / "out.wasm").read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        assert digest == row[role]["output"]
        module = wasmtime.Module(engine, data)
        external.append(([(i.module, i.name, signature(i.type)) for i in module.imports],
                         [(e.name, signature(e.type)) for e in module.exports]))
        sizes[role] += len(data)
        pair[role] = digest
    assert external[0] == external[1], (row["source"], external)
    results.append(dict(source=row["source"], **pair))
args.output.write_text(json.dumps(dict(compared=len(report["results"]), changed_wasm=len(results),
                                      total_changed_module_bytes=dict(sizes), matching_interfaces=results),
                                  indent=2) + "\n")
