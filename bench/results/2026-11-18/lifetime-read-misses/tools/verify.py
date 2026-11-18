"""Cross-check native counts, emitted artifacts, and the prior cache-miss census."""
import argparse
import hashlib
import json
from pathlib import Path

tools = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("stage", type=Path)
p.add_argument("frozen", type=Path)
p.add_argument("grouped_build", type=Path)
args = p.parse_args()

def load(path):
    return json.loads(path.read_text())

def sha(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()

previous = load(tools.parents[1] / "lifetime-read-groups/counts.json")
counts = load(args.stage / "counts.json")
control = load(args.frozen / "builds.json")
grouped = load(args.grouped_build / "builds.json")
expected = sha(args.frozen / "emitted.wasm")
if control["source_commit"] != previous["workload_commit"] or control["source_commit"] != counts["workload_commit"]:
    raise ValueError("expected same frozen project for both censuses")
if control["emitter"] != grouped["emitter"]:
    raise ValueError("probe sources must use the same emitter")
fields = [
    "calls", "compact_offers", "already_sent", "frames_visited", "unused",
    "own_merges", "own_insertions", "own_existing", "own_unions",
    "caller_merges", "caller_insertions", "caller_existing", "caller_unions",
    "own_changed_by_union", "caller_changed_by_union",
]
report = {
    "emitter": control["emitter"], "clang": control["clang"], "expected_emission_sha256": expected,
    "workload_commit": control["source_commit"], "checker_source_archives": {}, "probes": {},
}
for label, source in [("released", control), ("grouped", grouped)]:
    report["checker_source_archives"][label] = {key: source[key] for key in ("source_commit", "source_archive_sha256")}
    probe = args.stage / f"{label}-counts"
    raw = (probe / "native.out").read_text().removeprefix("MISS_COUNTS ")
    native = dict(zip(fields, json.loads(raw), strict=True))
    del native["unused"]
    wasm = [r for r in counts["runs"] if r["label"] == label]
    assert wasm and all(r["counts"] == json.loads(raw) for r in wasm)
    for prefix in ("own", "caller"):
        assert native[f"{prefix}_merges"] == native[f"{prefix}_insertions"] + native[f"{prefix}_existing"]
        assert native[f"{prefix}_changed_by_union"] <= native[f"{prefix}_unions"] <= native[f"{prefix}_existing"]
    if label == "grouped":
        assert native["calls"] == previous["variants"]["retained_leaf_version"]["counters"]["ordinary_construct_calls"]
    checks = {}
    for mode in ("counts", "phases", "outer"):
        folder = args.stage / f"{label}-{mode}"
        measured = load(args.stage / f"{mode}.json")["modules"][label]
        assert sha(folder / "probe.wasm") == measured["wasm_sha256"]
        emitted = sha(folder / "emitted.wasm")
        if emitted != expected:
            raise ValueError(f"{label}-{mode} emitted different Wasm")
        checks[mode] = emitted
    report["probes"][label] = {
        "native_sha256": sha(probe / "probe-native"), "native_and_wasmtime_counts": native,
        "emitted_wasm_sha256": checks,
    }
(args.stage / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
