#!/usr/bin/env python3
"""Langbench provenance, independent correctness and fail-closed report checks."""

import copy
import importlib.util
import os
from pathlib import Path
import signal
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("langbench_trial", ROOT / "bench/langbench.py")
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)


def reference(n, ceiling):
    """Independent binary64 grid oracle, deliberately used only on tiny inputs."""
    counts = []
    scale = 2.5 / n
    for y in range(n):
        imaginary = -1.25 + (float(y) + 0.5) * scale
        for x in range(n):
            real = -2.0 + (float(x) + 0.5) * scale
            z_real = z_imaginary = 0.0
            count = 0
            for _ in range(ceiling):
                square_real = z_real * z_real
                square_imaginary = z_imaginary * z_imaginary
                if square_real + square_imaginary > 4.0:
                    break
                z_imaginary = (2.0 * z_real) * z_imaginary + imaginary
                z_real = (square_real - square_imaginary) + real
                count += 1
            counts.append(count)
    return sum(counts)


class LangbenchContract(unittest.TestCase):
    def test_pinned_workload_and_unchanged_c(self):
        manifest = BENCH.load_manifest()
        self.assertEqual(BENCH.REVISION, "f00181bd514606b140bf76ac461694a438c88270")
        self.assertEqual(manifest["profiles"]["official"],
                         {"n": 2048, "max_iter": 1000, "threads": 1, "checksum": 1038538536})
        self.assertEqual(manifest["upstream"]["license"], "MIT")
        self.assertEqual(set(manifest["profiles"]), {"small", "medium", "official"})
        self.assertEqual(BENCH.sha256(BENCH.DATA / "mandelbrot.c"),
                         "a469f798cdd4e8603a28b487636bf74a35e5dc558cd3c33d8ba5cb2cec952b7d")
        self.assertIn("checksum: 1038538536", (BENCH.DATA / "workload.yaml").read_text())

    def test_independent_small_grid_oracle(self):
        for n, ceiling, expected in [(1, 1, 1), (8, 25, 636), (17, 65, 6174)]:
            with self.subTest(n=n):
                self.assertEqual(reference(n, ceiling), expected)

    def test_protocols_and_strict_checksum_gate(self):
        for cell, output in [("c-gcc", "636 42\n"), ("goose-native", "636\n42\n")]:
            self.assertEqual(BENCH.parse_result(output, 0, 636, cell),
                             {"checksum": 636, "timed_region_ns": 42})
            for candidate, status, expected in [(output, 1, 636), (output, 0, 637),
                                                (output + "noise\n", 0, 636),
                                                (output.replace("42", "0"), 0, 636),
                                                (output.replace("42", "-1"), 0, 636)]:
                with self.subTest(cell=cell, output=candidate):
                    with self.assertRaises(ValueError):
                        BENCH.parse_result(candidate, status, expected, cell)
        with self.assertRaises(ValueError):
            BENCH.parse_result("636 42\n", 0, 636, "goose-wasm-v8")
        with self.assertRaises(ValueError):
            BENCH.parse_result("636\n42\n", 0, 636, "c-clang")

    def test_statistics_keep_raw_samples(self):
        self.assertEqual(BENCH.summarize([2, 3, 9, 10]),
                         {"n": 4, "median": 6.0, "mad": 3.5,
                          "min": 2, "max": 10, "samples": [2, 3, 9, 10]})
        self.assertIsNone(BENCH.summarize([]))

    def report(self):
        return {"profiles": ["official"], "samples": 2, "compile_samples": 1,
                "builds": [{"cell": "c-gcc", "round": 0, "status": "passed", "wall_seconds": 1}],
                "runs": [{"profile": "official", "cell": "c-gcc", "status": "passed",
                          "phase": phase, "round": round_index, "timed_region_ns": 20, "wall_seconds": 0.1}
                         for phase, round_index in [("warmup", 0), ("measurement", 0), ("measurement", 1)]]}

    def test_duplicate_rounds_or_warmups_cannot_qualify(self):
        for field, index, key, value in [("runs", 2, "phase", "warmup"),
                                         ("runs", 2, "round", 0),
                                         ("runs", 0, "round", 1),
                                         ("builds", 0, "round", 1)]:
            report = self.report()
            report[field][index][key] = value
            self.assertFalse(BENCH.summaries(report)[0]["qualified"])

    def test_missing_and_failed_cells_never_disappear(self):
        report = self.report()
        rows = BENCH.summaries(report)
        self.assertEqual([row["cell"] for row in rows], list(BENCH.CELLS))
        self.assertTrue(rows[0]["qualified"])
        for row in rows[1:]:
            self.assertFalse(row["qualified"])
            self.assertEqual(row["valid_samples"], 0)
        for where in ("builds", "runs"):
            failed = copy.deepcopy(report)
            failed[where][0]["status"] = "failed"
            self.assertFalse(BENCH.summaries(failed)[0]["qualified"])
        report["runs"].pop()
        row = BENCH.summaries(report)[0]
        self.assertFalse(row["qualified"])
        self.assertEqual(row["valid_samples"], 1)

    def test_warmup_does_not_enter_measured_distribution(self):
        report = self.report()
        report["runs"][0]["timed_region_ns"] = 999999
        row = BENCH.summaries(report)[0]
        self.assertEqual(row["timed_region_ns"]["samples"], [20, 20])

    def test_existing_output_directory_is_never_reused(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            args = SimpleNamespace(profiles=["small"], cpu=None, output_dir=Path(directory))
            with self.assertRaises(FileExistsError):
                BENCH.trial(args)

    def test_timeout_stops_descendants_holding_the_output_pipe(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            pidfile = Path(directory) / "child.pid"
            script = ("import subprocess, sys, time; from pathlib import Path; "
                      "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
                      "Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(30)")
            result = BENCH.invoke([sys.executable, "-c", script, str(pidfile)], timeout=1)
            self.assertEqual(result["status"], "failed")
            self.assertIn("timeout", result["error"])
            self.assertLess(result["wall_seconds"], 5)
            self.assertTrue(pidfile.is_file())
            child_pid = int(pidfile.read_text())
            status = Path(f"/proc/{child_pid}/stat")
            try:
                state = status.read_text().split(") ", 1)[1].split()[0]
            except (FileNotFoundError, ProcessLookupError):
                return
            if state != "Z":
                os.kill(child_pid, signal.SIGKILL)
            self.assertEqual(state, "Z", "timed-out compiler descendant is still running")


if __name__ == "__main__":
    unittest.main()
