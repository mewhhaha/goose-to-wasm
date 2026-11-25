#!/usr/bin/env python3
"""Tests for the wtime-aot runner (`scripts/run_wtime_aot.py`) and benchmark wiring."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "bench"))

import run_wtime_aot as runner
import benchmark as bench_mod
import examples as examples_mod
import langarena as arena_mod
import langbench as langbench_mod
import selfhost_comparison as selfhost_mod


def _find_goose_compiler() -> Path | None:
    for candidate in (
        ROOT / "build" / "bin" / "goosew",
        ROOT / "build" / "dev" / "bin" / "goosew",
        ROOT / "build" / "native" / "goose",
    ):
        if candidate.is_file():
            return candidate
    return None


def _has_wtime_aot() -> bool:
    try:
        runner.find_wtime_aot()
        return True
    except FileNotFoundError:
        return False


class WtimeAotWiringTests(unittest.TestCase):
    def test_benchmark_engine_choices_include_wtime_aot(self):
        self.assertIn("wtime-aot", bench_mod.ENGINES)
        self.assertIn("wtime-aot-x64", bench_mod.ENGINES)
        self.assertIn("wtime-aot", examples_mod.ENGINES)
        self.assertIn("wtime-aot-x64", examples_mod.ENGINES)
        self.assertIn("wtime-aot", selfhost_mod.ALL_ENGINES)
        self.assertIn("goose-wasm-wtime-aot", langbench_mod.OPTIONAL_WTIME_AOT_CELLS)
        self.assertIn("goose-wasm-wtime-aot-x64", langbench_mod.OPTIONAL_WTIME_AOT_CELLS)

    def test_langarena_engine_command_routes_wtime_aot(self):
        class Args:
            node = "node"
            output_dir = Path("/tmp/langarena-test")
            wtime_aot = None
            wtime_aot_cache = None
            wtime_aot_target_cpu = "native"
            wtime_aot_toolchain = None

        cmd_rust = arena_mod.engine_command(Args(), Path("prog.wasm"), "wtime-aot", Path("t.json"))
        self.assertIn("run_wtime_aot.py", str(cmd_rust[1]))
        self.assertIn("--backend", cmd_rust)
        self.assertEqual(cmd_rust[cmd_rust.index("--backend") + 1], "rust")
        self.assertIn("--timing-json", cmd_rust)

        cmd_x64 = arena_mod.engine_command(Args(), Path("prog.wasm"), "wtime-aot-x64")
        self.assertEqual(cmd_x64[cmd_x64.index("--backend") + 1], "x64")

    def test_examples_render_includes_wtime_aot_columns(self):
        sample_summary = {"n": 5, "median": 0.002, "mad": 0.0001, "min": 0.001, "max": 0.003,
                          "p25": 0.0015, "p75": 0.0025, "samples": [0.002] * 5}
        report = {
            "status": "passed-smoke",
            "started_utc": "2026-11-24T22:00:00+00:00",
            "configuration": {"compile_samples": 1, "samples": 1, "warmups": 0,
                              "engines": ["wasmtime", "wtime-aot", "wtime-aot-x64"]},
            "environment": {"supplied_machine_label": "test-cpu", "cpu": "test-cpu"},
            "examples": [{"name": "squares"}],
            "compile_summary": [{"name": "squares", "backend": "direct", "wall_seconds": sample_summary}],
            "runtime_summary": [
                {"name": "squares", "backend": "direct", "engine": eng,
                 "process_wall_seconds": sample_summary,
                 "entry_function_seconds": sample_summary,
                 "engine_compile_instantiate_seconds": sample_summary}
                for eng in ("wasmtime", "wtime-aot", "wtime-aot-x64")
            ],
        }
        md = examples_mod.render(report)
        self.assertIn("Direct / wtime-aot", md)
        self.assertIn("Direct / wtime-aot (x64)", md)


def _minimal_goose_i64_wasm() -> bytes:
    """Minimal valid Wasm module importing goose::print_i64 + goose::newline and exporting _start."""
    def leb(n: int) -> bytes:
        out = bytearray()
        while True:
            b = n & 0x7F
            n >>= 7
            if n:
                b |= 0x80
            out.append(b)
            if not n:
                return bytes(out)

    def sec(sid: int, payload: bytes) -> bytes:
        return bytes([sid]) + leb(len(payload)) + payload

    # types: 0: (i64)->(), 1: ()->()
    types = bytes([2, 0x60, 1, 0x7E, 0, 0x60, 0, 0])
    # imports: goose.print_i64 (type 0), goose.newline (type 1)
    imp = bytearray([2])
    for mod, name, tidx in ((b"goose", b"print_i64", 0), (b"goose", b"newline", 1)):
        imp += leb(len(mod)) + mod + leb(len(name)) + name + bytes([0x00, tidx])
    funcs = bytes([1, 1])  # 1 defined fn (_start) of type 1
    mem = bytes([1, 0x00, 1])  # 1 page memory
    exp = bytearray([2])
    exp += leb(6) + b"memory" + bytes([0x02, 0])
    exp += leb(6) + b"_start" + bytes([0x00, 2])
    # _start: i64.const 42; call 0; call 1; end
    body = bytes([0, 0x42, 42, 0x10, 0, 0x10, 1, 0x0B])
    code = bytes([1]) + leb(len(body)) + body
    return (
        b"\x00asm\x01\x00\x00\x00"
        + sec(1, types)
        + sec(2, bytes(imp))
        + sec(3, funcs)
        + sec(5, mem)
        + sec(7, bytes(exp))
        + sec(10, code)
    )


@unittest.skipUnless(_has_wtime_aot() and _find_goose_compiler() is not None,
                     "requires installed wtime-aot and built goose compiler")
class WtimeAotLiveExecutionTests(unittest.TestCase):
    def test_run_wtime_aot_rust_and_x64_with_timing_json(self):
        goose = _find_goose_compiler()
        stdlib = goose.parent / "stdlib"
        if not stdlib.is_dir():
            stdlib = ROOT / "stdlib"
        expected = (ROOT / "examples" / "expected" / "squares.out").read_text(encoding="utf-8")

        with tempfile.TemporaryDirectory(prefix="goose-wtime-aot-test-") as td_s:
            td = Path(td_s)
            cache = td / "cache"

            # 1. --backend rust on real compiled Goose example (full Goose import table)
            wasm = td / "squares.wasm"
            subprocess.run(
                [str(goose), str(ROOT / "examples" / "squares.goose"),
                 "--stdlib", str(stdlib), "--target", "wasm-direct", "-O2", "-o", str(wasm)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            timing_rust = td / "timing-rust.json"
            proc_rust = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "run_wtime_aot.py"),
                 str(wasm), "--backend", "rust", "--cache", str(cache),
                 "--timing-json", str(timing_rust)],
                cwd=ROOT, input="", capture_output=True, text=True, timeout=120, check=False,
            )
            self.assertEqual(proc_rust.returncode, 0, msg=proc_rust.stderr)
            self.assertEqual(proc_rust.stdout, expected)
            data_rust = json.loads(timing_rust.read_text(encoding="utf-8"))
            self.assertEqual(data_rust["engine"], "wtime-aot")
            self.assertEqual(data_rust["backend"], "rust")
            self.assertEqual(
                data_rust["engine_total_ns"],
                data_rust["compile_instantiate_ns"] + data_rust["start_function_ns"],
            )

            # 2. --backend x64 (pure-Rust static ELF, zero LLVM) with Goose i64 + timing JSON
            mini = td / "mini.wasm"
            mini.write_bytes(_minimal_goose_i64_wasm())
            timing_x64 = td / "timing-x64.json"
            proc_x64 = subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "run_wtime_aot.py"),
                 str(mini), "--backend", "x64", "--cache", str(cache),
                 "--timing-json", str(timing_x64)],
                cwd=ROOT, input="", capture_output=True, text=True, timeout=120, check=False,
            )
            self.assertEqual(proc_x64.returncode, 0, msg=proc_x64.stderr)
            self.assertEqual(proc_x64.stdout, "42\n")
            data_x64 = json.loads(timing_x64.read_text(encoding="utf-8"))
            self.assertEqual(data_x64["engine"], "wtime-aot")
            self.assertEqual(data_x64["backend"], "x64")
            self.assertEqual(
                data_x64["engine_total_ns"],
                data_x64["compile_instantiate_ns"] + data_x64["start_function_ns"],
            )

    def test_benchmark_py_smoke_with_wtime_aot(self):
        goose = _find_goose_compiler()
        with tempfile.TemporaryDirectory(prefix="goose-bench-wtime-aot-") as td_s:
            out = Path(td_s) / "bench"
            proc = subprocess.run(
                [sys.executable, str(ROOT / "bench" / "benchmark.py"),
                 "--smoke", "--samples", "1", "--compile-samples", "1",
                 "--warmups", "0", "--kernel-warmups", "1",
                 "--workloads", "integer_mod",
                 "--backends", "direct",
                 "--engines", "wasmtime", "wtime-aot",
                 "--goose", str(goose),
                 "--output-dir", str(out)],
                cwd=ROOT, capture_output=True, text=True, check=False,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stdout + "\n" + proc.stderr)
            report = json.loads((out / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "passed")
            engines = {row["engine"] for row in report["runtime"]}
            self.assertEqual(engines, {"wasmtime", "wtime-aot"})
            self.assertEqual(len(report["aot_prepare"]), 1)

    def test_examples_py_smoke_with_wtime_aot(self):
        goose = _find_goose_compiler()
        with tempfile.TemporaryDirectory(prefix="goose-examples-wtime-aot-") as td_s:
            out = Path(td_s) / "examples"
            proc = subprocess.run(
                [sys.executable, str(ROOT / "bench" / "examples.py"),
                 "squares",
                 "--smoke", "--samples", "1", "--compile-samples", "1", "--warmups", "0",
                 "--backends", "direct",
                 "--engines", "wasmtime", "wtime-aot",
                 "--goose", str(goose),
                 "--output-dir", str(out)],
                cwd=ROOT, capture_output=True, text=True, check=False,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stdout + "\n" + proc.stderr)
            report = json.loads((out / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "passed-smoke")
            engines = {row["engine"] for row in report["runtime_summary"]}
            self.assertEqual(engines, {"wasmtime", "wtime-aot"})
            readme = (out / "README.md").read_text(encoding="utf-8")
            self.assertIn("Direct / wtime-aot", readme)


if __name__ == "__main__":
    unittest.main()
