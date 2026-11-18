"""Verify bounded failure, fresh-instance growth and ordinary traps with a 192-byte arena."""

import argparse
import hashlib
from pathlib import Path
import struct
import sys
import wasmtime

from recovery import Partition, compile_with_recovery

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("repo", type=Path)
a = parser.parse_args()
sys.path.insert(0, str(a.repo.resolve() / "scripts"))
from run_wasmtime import create_config, create_engine, PreparedModule, run_module


def example(request, capacity_trap):
    raw = struct.pack("<4I", 1024, 1088, 1152, 1216)
    escaped = "".join(f"\\{b:02x}" for b in raw)
    signal = ""
    if capacity_trap:
        signal = f"(global.set $fail (local.get $limit)) (global.set $need (i64.const {request}))"
    wat = f"""
    (module
      (memory (export "memory") 1)
      (global (export "goose.region_count") i32 (i32.const 3))
      (global (export "goose.region_table") i32 (i32.const 32))
      (global $fail (export "trial.failed_limit") (mut i32) (i32.const 0))
      (global $need (export "trial.request_bytes") (mut i64) (i64.const 0))
      (data (i32.const 32) "{escaped}")
      (func (export "_start") (local $limit i32)
        (local.set $limit (i32.sub (i32.load (i32.const 36)) (i32.const 12)))
        (i32.store (local.get $limit) (i32.const 1072))
        (i32.store offset=4 (local.get $limit) (i32.const 1024))
        (if (i32.gt_u (i32.const {1072 + request}) (local.get $limit))
          (then {signal} (unreachable)))))
    """
    return bytes(wasmtime.wat2wasm(wat))


engine = create_engine(create_config())
for request, capacity_trap, code, tries in [
    (32, True, 0, 2),
    (2048, True, 1, 1),
    (32, False, 1, 1),
]:
    data = example(request, capacity_trap)
    prepared = PreparedModule(
        engine,
        wasmtime.Module(engine, data),
        hashlib.sha256(data).hexdigest(),
        None,
        {},
    )
    original = run_module(data, b"", prepared=prepared)
    partition = Partition(4)
    result, attempts = compile_with_recovery(data, prepared, ["test"], partition)
    assert result["exit_code"] == code and len(attempts) == tries, (result, attempts)
    assert partition.bounds[0] == 1024 and partition.bounds[-1] == 1216
    assert original["exit_code"] == 1
    if code:
        assert result["stderr"] == original["stderr"]
    print(request, capacity_trap, code, tries)

# A learned partition may only be installed in another instance with the same geometry.
import tempfile
from recovery import read_layout, save_layout

data = example(32, True)
digest = hashlib.sha256(data).hexdigest()
prepared = PreparedModule(engine, wasmtime.Module(engine, data), digest, None, {})
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    learned = Partition(4)
    _, attempts = compile_with_recovery(data, prepared, ["test"], learned)
    assert len(attempts) == 2
    save_layout(folder, digest, learned.bounds)
    assert read_layout(folder, "other-module") is None
    for saved, tries in [
        (read_layout(folder, digest), 1),
        ([1024, 1200, 1184, 1216], 2),
        ([0, 2000], 2),
    ]:
        result, attempts = compile_with_recovery(
            data, prepared, ["test"], Partition(4, saved)
        )
        assert result["exit_code"] == 0 and len(attempts) == tries
    (folder / (digest + ".json")).write_text("truncated")
    assert read_layout(folder, digest) is None
