"""Compare function bodies after complete independent builds of three small edits."""

import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys

repo, stage, trial = [Path(p).resolve() for p in sys.argv[1:4]]
sys.path.insert(0, str(repo / "bench"))
from selfhost_comparison import SOURCE, WASM_FLAGS, identity

sys.path.insert(0, str(repo / "tests"))
from goose_stats import sections, uleb


def bodies(code):
    count, offset = uleb(code, 0)
    result = []
    for _ in range(count):
        size, start = uleb(code, offset)
        result.append(code[start : start + size])
        offset = start + size
    assert offset == len(code)
    return result


def sections_by_id(data):
    parts = dict(sections(data))
    assert len(parts) == sum(1 for _ in sections(data))
    return parts


os.sched_setaffinity(0, {7})
resource.setrlimit(
    resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
)
out = trial / "edits"
out.mkdir()
project = out / "source"
shutil.copytree(stage / "source", project)
driver = project / "selfhost/driver.goose"
original = driver.read_bytes()
baseline = sections_by_id((stage / "build-1/compiler.wasm").read_bytes())
base_code = bodies(baseline[10])
native = stage / "build-1/compiler-native"
host = repo / "host/rust/target/release/goose-wasmtime"
edits = {
    "same-length help text": (b"Usage: goose-selfhost", b"Usage: goose-compiler"),
    "longer help text": (
        b"Usage: goose-selfhost",
        b"Usage: goose compiler for WebAssembly",
    ),
    "expansion limit": (
        b"expansion_limit: i64 = 100000,",
        b"expansion_limit: i64 = 100001,",
    ),
}
report = {}
for label, (before, after) in edits.items():
    assert original.count(before) == 1
    driver.write_bytes(original.replace(before, after))
    native_file, wasm_file = out / "native.wasm", out / "wasmtime.wasm"
    for path in (native_file, wasm_file):
        path.unlink(missing_ok=True)
    subprocess.run(
        [native, *SOURCE, *WASM_FLAGS, "-o", native_file], cwd=project, check=True
    )
    subprocess.run(
        [
            host,
            trial / "bundled32.wasm",
            "--cache",
            trial / "bundled32.cwasm",
            "--",
            *SOURCE,
            *WASM_FLAGS,
            "-o",
            wasm_file,
        ],
        cwd=project,
        check=True,
    )
    assert identity(native_file) == identity(wasm_file)
    edited = sections_by_id(native_file.read_bytes())
    code = bodies(edited[10])
    assert len(code) == len(base_code) and edited.keys() == baseline.keys()
    changed = [i for i, body in enumerate(code) if body != base_code[i]]
    report[label] = dict(
        before=before.decode(),
        after=after.decode(),
        output=identity(native_file),
        changed_sections=[i for i in baseline if baseline[i] != edited[i]],
        function_count=len(code),
        changed_bodies=len(changed),
        changed_body_indices=changed,
    )
    assert report[label]["changed_sections"]
    print(label, len(changed), len(code), flush=True)
driver.write_bytes(original)
(trial / "edits.json").write_text(json.dumps(report, indent=2) + "\n")
