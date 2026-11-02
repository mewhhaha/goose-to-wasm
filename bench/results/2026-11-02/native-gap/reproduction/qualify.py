"""Retain the focused semantic and integration gates for the array-access change."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/native-gap/qualification"
OUT.mkdir(parents=True, exist_ok=True)
compiler = ROOT / "build/bin/goose"
compiler_sha = hashlib.sha256(compiler.read_bytes()).hexdigest()
names = [
    "test_backend_extensions", "test_static_data", "test_fill_loops", "test_strip_loops",
    "test_regions", "test_prefix_resolution", "test_dynamic_boundaries", "test_static_capture_boundaries",
    "test_variable_enum_boundaries", "test_variable_variant_boundaries", "test_owned_struct_boundaries",
    "test_packed_layout_boundaries", "test_array_images", "test_sparse_array_images", "test_record_images",
    "test_enum_tags", "test_enum_images", "test_enum_image_returns", "test_static_limited_images",
    "test_record_padding", "test_padding_boundaries", "test_varint_records", "test_varint_boundaries",
    "test_varint_capture_boundaries", "test_varint_arrays", "test_varint_array_boundaries", "test_varint_grow",
    "test_varint_grow_boundaries", "test_uleb_lengths", "test_uleb_accessor_helpers", "test_combined_varints", "test_combined_varint_boundaries",
    "test_encoded_record_tails", "test_encoded_record_tail_boundaries", "test_aggregate_print",
    "test_aggregate_print_boundaries", "test_uleb_length_boundaries", "test_compiler_session",
    "test_incremental", "test_input_dependencies", "test_langarena",
]
commands = [[sys.executable, "tests/" + name + ".py"] for name in names]
commands += [
    [sys.executable, "scripts/check_engines.py", "--output", str(OUT / "engine-probes.json")],
    [sys.executable, "scripts/check_capabilities.py"],
    [sys.executable, "examples/run.py", "--backends", "native", "c-wasm", "direct", "--levels", "0", "2", "--output-dir", str(OUT / "examples")],
]
report = {"status": "running", "compiler_sha256": compiler_sha, "commands": []}
for command in commands:
    name = Path(command[1]).stem
    started = time.monotonic()
    with (OUT / (name + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    report["commands"].append({"name": name, "command": command, "exit_status": result.returncode,
                               "wall_seconds": time.monotonic() - started, "log": name + ".log"})
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(name, result.returncode, flush=True)
    if result.returncode:
        report["status"] = "failed"
        (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        sys.exit(1)
assert compiler_sha == hashlib.sha256(compiler.read_bytes()).hexdigest()
report["status"] = "passed"
(OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print("PASS", len(commands), "qualification commands", flush=True)
