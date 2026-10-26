#!/usr/bin/env python3
"""Failure and concurrency contracts for build publication and child processes."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_support import BuildError, OutputLocks, publish_files, run_process
import goose_wasm as driver


class BuildContracts(unittest.TestCase):
    def setUp(self):
        (ROOT / "build").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="build-contract-", dir=ROOT / "build")
        self.directory = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_failed_preparation_keeps_every_old_output(self):
        module, stats = self.directory / "program.wasm", self.directory / "stats.json"
        module.write_bytes(b"old module")
        stats.mkdir()
        with self.assertRaises(BuildError):
            publish_files({module: (b"new module", False), stats: (b"new stats", False)})
        self.assertEqual(module.read_bytes(), b"old module")
        self.assertEqual(sorted(p.name for p in self.directory.iterdir()), ["program.wasm", "stats.json"])

    def test_second_rename_failure_rolls_back_first_output(self):
        module, stats = self.directory / "program.wasm", self.directory / "stats.json"
        module.write_bytes(b"old module")
        stats.write_bytes(b"old stats")
        replace = os.replace
        calls = 0
        def failing_replace(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("simulated second rename failure")
            return replace(source, destination)
        with mock.patch("build_support.os.replace", side_effect=failing_replace):
            with self.assertRaisesRegex(OSError, "second rename"):
                publish_files({module: (b"new module", False), stats: (b"new stats", False)})
        self.assertEqual(module.read_bytes(), b"old module")
        self.assertEqual(stats.read_bytes(), b"old stats")

    def test_unchanged_publication_preserves_timestamp(self):
        output = self.directory / "program.wasm"
        output.write_bytes(b"unchanged")
        timestamp = output.stat().st_mtime_ns
        publish_files({output: (b"unchanged", False)})
        self.assertEqual(output.stat().st_mtime_ns, timestamp)

    @unittest.skipUnless(os.name == "posix", "POSIX executable mode")
    def test_native_output_repairs_missing_execute_permission(self):
        output = self.directory / "program"
        output.write_bytes(b"same binary")
        output.chmod(0o600)
        publish_files({output: (b"same binary", True)})
        self.assertTrue(output.stat().st_mode & 0o111)

    def test_cache_rejects_malformed_records_and_traversal_digest(self):
        cache = self.directory / "cache"
        (cache / "entries").mkdir(parents=True)
        entry = cache / "entries" / "key.json"
        for value in [None, [], 2, "invalid", {"schema": driver.SCHEMA},
                      {"schema": driver.SCHEMA, "dependencies": None}]:
            entry.write_text(json.dumps(value))
            self.assertIsNone(driver.cache_lookup(cache, "key"))

    def test_sidecar_changes_invalidate_module_namespace(self):
        source = self.directory / "main.goose"
        source.write_text("fn main() {}")
        before = driver.search_directories([source])
        sidecar = self.directory / "main.build"
        sidecar.write_text('exclude = ["one"]\n')
        added = driver.search_directories([source])
        self.assertNotEqual(before, added)
        sidecar.write_text('exclude = ["two"]\n')
        self.assertNotEqual(added, driver.search_directories([source]))

    def test_explicit_git_source_disables_metadata_pruning(self):
        source = self.directory / "main.goose"
        source.write_text("fn main() {}")
        git = self.directory / ".git"
        git.mkdir()
        dependency = git / "package.goose"
        dependency.write_text("fn value() -> i64 { 1 }")
        ordinary = driver.search_directories([source])
        explicit = driver.search_directories([source, dependency])
        self.assertNotEqual(ordinary, explicit)
        (git / "candidate.goose").write_text("fn value() -> i64 { 2 }")
        self.assertNotEqual(explicit, driver.search_directories([source, dependency]))

    @unittest.skipUnless(os.name == "posix", "POSIX named pipes")
    def test_fifo_dependency_and_sidecar_do_not_block_validation(self):
        source = self.directory / "main.goose"
        source.write_text("fn main() {}")
        snapshot, coherent = driver.dependency_snapshot(
            [{"path": str(source), "text": source.read_text()}], [])
        self.assertTrue(coherent)
        source.unlink()
        os.mkfifo(source)
        # Use a subprocess deadline so a regressed blocking open fails the
        # test instead of hanging the complete integration suite indefinitely.
        snapshot_file = self.directory / "snapshot.json"
        snapshot_file.write_text(json.dumps(snapshot))
        script = ("import sys,json;from pathlib import Path;sys.path.insert(0,sys.argv[1]);"
                  "import goose_wasm as g;"
                  "assert not g.valid_dependencies(json.loads(Path(sys.argv[2]).read_text()));"
                  "assert g.search_directories([Path(sys.argv[3])]) is None")
        sidecar = self.directory / "main.build"
        os.mkfifo(sidecar)
        result = subprocess.run([sys.executable, "-c", script, str(ROOT / "scripts"),
                                 str(snapshot_file), str(source)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_competing_writer_waits_for_same_target(self):
        output = self.directory / "program.wasm"
        script = ("import sys;from pathlib import Path;"
                  "sys.path.insert(0,sys.argv[1]);from build_support import OutputLocks;"
                  "\nwith OutputLocks([Path(sys.argv[2])],0.1): print('acquired')")
        with OutputLocks([output], 2):
            result = subprocess.run([sys.executable, "-c", script, str(ROOT / "scripts"), str(output)],
                                    capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("timed out waiting for output lock", result.stderr)
        result = subprocess.run([sys.executable, "-c", script, str(ROOT / "scripts"), str(output)],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(os.name == "posix", "POSIX process-group cleanup")
    def test_timeout_terminates_compiler_descendants(self):
        marker = self.directory / "should-not-exist"
        child = "import time,pathlib,sys;time.sleep(0.5);pathlib.Path(sys.argv[1]).write_text('survived')"
        parent = "import subprocess,sys,time;subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]]);time.sleep(30)"
        with self.assertRaisesRegex(BuildError, "exceeded"):
            run_process([sys.executable, "-c", parent, child, str(marker)], 0.1)
        time.sleep(0.6)
        self.assertFalse(marker.exists(), "timed-out compiler left a running child")


if __name__ == "__main__":
    unittest.main()
