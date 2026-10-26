#!/usr/bin/env python3
"""Contract tests for pinned inputs, checksum gates, and observable build edits."""

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import os
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("langarena_harness", ROOT / "bench" / "langarena.py")
ARENA = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ARENA)


class LangArenaContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = ARENA.load_manifest()
        cls.cases = {case["name"]: case for case in cls.manifest["cases"]}
        (ROOT / "build").mkdir(exist_ok=True)

    def temporary(self):
        return tempfile.TemporaryDirectory(prefix="langarena-contract-", dir=ROOT / "build")

    def test_full_catalog_and_disclosed_adaptations(self):
        self.assertEqual(len(self.cases), 50)
        self.assertEqual(sum(case["port"] is not None for case in self.cases.values()), 7)
        self.assertIn("harness-only", self.cases["CLBG::Fannkuchredux"]["port"]["classification"])
        self.assertIn("not standard", self.cases["Hash::SHA256"]["notes"])
        for name in ("Matmul::T4", "Matmul::T8", "Matmul::T16"):
            self.assertEqual(self.cases[name]["required_capability"], "threads-and-queues")

    def test_warmup_state_contributes_to_official_sieve_checksum(self):
        case = self.cases["Etc::Sieve"]
        self.assertEqual(ARENA.port_stdin(case, "test"), "1000 3 1\n")
        # There are 168 primes <=1000 and the last is 997. The original state
        # accumulates all three measured calls AND the one warmup call.
        self.assertEqual(case["test"]["checksum"], (997 + 168) * (3 + 1))

    def test_explicit_brainfuck_warmup_is_not_replaced_by_default(self):
        case = self.cases["Brainfuck::Array"]
        self.assertEqual(case["run"]["iterations"], 1)
        self.assertEqual(ARENA.warmup_count(case["run"]), 1000)

    def test_port_parameter_order_and_both_official_profiles(self):
        self.assertEqual(ARENA.port_stdin(self.cases["CLBG::Mandelbrot"], "run"), "400 400 100 20\n")
        self.assertEqual(ARENA.port_stdin(self.cases["CLBG::Fannkuchredux"], "run"), "8 700 140\n")
        for case in self.cases.values():
            if case["port"]:
                for profile in ("test", "run"):
                    values = list(map(int, ARENA.port_stdin(case, profile).split()))
                    self.assertEqual(len(values), len(case["port"]["fields"]) + 2)

    def test_cumulative_mandelbrot_capacity_is_checked(self):
        case = copy.deepcopy(self.cases["CLBG::Mandelbrot"])
        case["run"]["iterations"] = 101
        with self.assertRaisesRegex(ValueError, "120"):
            ARENA.port_stdin(case, "run")

    def test_port_storage_bound_is_checked(self):
        case = copy.deepcopy(self.cases["Etc::Sieve"])
        case["test"]["limit"] = 3000001
        with self.assertRaisesRegex(ValueError, "bound"):
            ARENA.port_stdin(case, "test")

    def test_checksum_and_revision_exit_are_independent_checks(self):
        good = "4660\n12345\n"
        self.assertEqual(ARENA.parse_port_result(good, 0, 4660)["checksum"], 4660)
        self.assertEqual(ARENA.parse_port_result(good, 1, 4660, revision=1)["revision_exit"], 1)
        for stdout, code, checksum, revision in [
            (good, 1, 4660, 0), (good, 0, 4660, 1), (good, 0, 4661, 0),
            ("4660\n0\n", 0, 4660, 0), ("4660\nnan\n", 0, 4660, 0),
            ("4660\n10\nextra\n", 0, 4660, 0), ("-1\n10\n", 0, 4660, 0),
        ]:
            with self.subTest(stdout=stdout, code=code, revision=revision):
                with self.assertRaises(ValueError):
                    ARENA.parse_port_result(stdout, code, checksum, revision)

    def test_whole_suite_requires_exact_task_and_success_summary(self):
        good = "start: 123\nEtc::Sieve: OK in 0.001s\nSummary: 0.0010s, 1, 1, 0\n"
        self.assertEqual(ARENA.parse_whole_result(good, 0, "Etc::Sieve")["timed_region_seconds"], 0.001)
        for text in (good.replace("1, 1, 0", "2, 2, 0"), good + "Warning: missing task\n",
                     good.replace("OK", "ERR[actual=0, expected=4660]"),
                     good.replace("Etc::Sieve", "Sort::Quick"), good.replace("Summary:", "Missing:")):
            with self.assertRaises(ValueError):
                ARENA.parse_whole_result(text, 0, "Etc::Sieve")

    def test_marker_edit_restores_source_on_failure(self):
        with self.temporary() as directory:
            source = Path(directory) / "case.goose"
            original = (ARENA.PORT_MARKER + "\nfn main() { print(ARENA_REVISION); }\n").encode()
            source.write_bytes(original)
            with self.assertRaisesRegex(RuntimeError, "simulated"):
                with ARENA.edited_marker(source, ARENA.PORT_MARKER, "let ARENA_REVISION = 1;"):
                    self.assertIn("ARENA_REVISION = 1", source.read_text())
                    raise RuntimeError("simulated compiler failure")
            self.assertEqual(source.read_bytes(), original)

    def test_marker_edit_rejects_missing_or_ambiguous_marker(self):
        with self.temporary() as directory:
            source = Path(directory) / "case.goose"
            for count in (0, 2):
                original = (ARENA.PORT_MARKER + "\n") * count
                source.write_text(original)
                with self.assertRaises(ValueError):
                    with ARENA.edited_marker(source, ARENA.PORT_MARKER, "changed"):
                        self.fail("ambiguous edit was applied")
                self.assertEqual(source.read_text(), original)

    def test_whole_staging_changes_only_marker_path(self):
        with self.temporary() as directory:
            upstream = Path(directory) / "upstream"
            src = upstream / "goose" / "src"
            src.mkdir(parents=True)
            original = 'fn marker() { write_file("/tmp/recompile_marker", "RECOMPILE_MARKER_0"); }\n'
            (src / "bench.goose").write_text(original)
            (src / "main.goose").write_text("import bench; fn main() { marker(); }\n")
            entry = ARENA.stage_whole(upstream, Path(directory) / "stage")
            self.assertEqual((src / "bench.goose").read_text(), original)
            self.assertEqual(entry.read_bytes(), (src / "main.goose").read_bytes())
            self.assertEqual((entry.parent / "bench.goose").read_text(), original.replace('"/tmp/recompile_marker"', '"recompile_marker"'))

    def test_modified_pinned_configuration_is_rejected(self):
        with self.temporary() as directory:
            data = Path(directory)
            for filename in ("manifest.json", "test.json", "run.json"):
                shutil.copyfile(ARENA.DATA / filename, data / filename)
            with patch.object(ARENA, "DATA", data):
                ARENA.load_manifest()
                path = data / "test.json"
                config = json.loads(path.read_text())
                config[0]["checksum"] += 1
                path.write_text(json.dumps(config))
                with self.assertRaisesRegex(ValueError, "configuration has changed"):
                    ARENA.load_manifest()

    def test_target_refusal_is_not_any_compiler_failure(self):
        self.assertTrue(ARENA.known_whole_refusal("direct", "error: wasm-direct: only fixed-size owned arrays are supported"))
        self.assertTrue(ARENA.known_whole_refusal("c-wasm", "WebAssembly target does not support threads or typed queues"))
        self.assertFalse(ARENA.known_whole_refusal("direct", "compiler crashed"))
        self.assertFalse(ARENA.known_whole_refusal("native", "only fixed-size owned arrays"))

    def test_failed_and_refused_builds_do_not_get_successful_timings(self):
        report = {"observations": [
            {"kind": "build", "status": "unsupported", "wall_seconds": 0.001},
            {"kind": "build", "status": "failed", "wall_seconds": 0.002},
        ]}
        ARENA.derive_summaries(report)
        self.assertEqual(report["compile_summary"], [])
        self.assertEqual(report["runtime_summary"], [])

    def test_cold_build_command_cannot_use_content_cache(self):
        for backend in ("native", "direct", "c-wasm"):
            args = SimpleNamespace(current_backend=backend, goose=Path("compiler"), cc="cc", emcc="emcc", output_dir=Path("out"))
            command = ARENA.build_command(args, Path("source"), Path("output"), Path("stats"), port=True)
            self.assertIn("--no-cache", command)
            self.assertEqual("--c-source" in command, backend != "direct")

    @unittest.skipIf(os.name == "nt", "POSIX process-group qualification")
    def test_timeout_terminates_descendants_holding_output_pipes(self):
        with self.temporary() as directory:
            program = ("import subprocess,sys,time; "
                       "subprocess.Popen([sys.executable,'-c','import time; time.sleep(10)']); "
                       "print('child started',flush=True); time.sleep(10)")
            result = ARENA.execute([sys.executable, "-c", program], Path(directory),
                                   cwd=ROOT, timeout=0.5)
            self.assertEqual(result["returncode"], -1)
            self.assertIn("process group terminated", result["error"])
            self.assertIn("child started", result["stdout"])
            self.assertLess(result["wall_seconds"], 3)


if __name__ == "__main__":
    unittest.main()
