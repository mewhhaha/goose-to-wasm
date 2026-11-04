"""Lossless compact qualification logs, including concurrency and failures."""

from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bench"))
sys.path.insert(0, str(ROOT / "tests"))
from command_logs import CommandLogs
import qualify_compiler
import qualify_wasmtime_host as host
import run_differential as differential


def contents(path):
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getmembers()
        assert all(member.isfile() for member in members)
        assert len(members) == len({member.name for member in members})
        return {member.name: archive.extractfile(member).read() for member in members}


class CompactLogs(unittest.TestCase):
    def test_binary_fidelity_concurrent_writes_and_single_file(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            logs = CommandLogs(root)
            expected = {f"runs/{index}/stdout": bytes(range(256)) + b"\x00\r\n\xff" * index
                        for index in range(64)}
            with ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda item: logs.write(root / item[0], item[1]), expected.items()))
            metadata = logs.close()
            self.assertEqual(contents(logs.path), expected)
            self.assertEqual(list(root.iterdir()), [logs.path])
            self.assertEqual(metadata["files"], len(expected))
            self.assertEqual(metadata["uncompressed_bytes"], sum(map(len, expected.values())))
            self.assertEqual(metadata["sha256"], hashlib.sha256(logs.path.read_bytes()).hexdigest())
            self.assertTrue(metadata["closed"] and metadata["complete"])
            self.assertEqual(logs.close(), metadata)

    def test_unsafe_names_duplicates_and_closed_writes_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            logs = CommandLogs(root)
            for name in ("..", "../escape", "runs/../../escape", root.parent / "outside", "."):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    logs.write(name, b"unsafe")
            logs.write("runs/one", b"original")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                logs.write(root / "runs/one", b"replacement")
            metadata = logs.close(complete=False)
            self.assertTrue(metadata["closed"])
            self.assertFalse(metadata["complete"])
            self.assertEqual(contents(logs.path), {"runs/one": b"original"})
            with self.assertRaisesRegex(ValueError, "closed"):
                logs.write("runs/two", b"late")

    def test_write_failure_is_recorded_and_close_does_not_claim_completeness(self):
        with tempfile.TemporaryDirectory() as temp:
            logs = CommandLogs(temp)
            with mock.patch.object(logs._archive, "addfile", side_effect=OSError("disk full")):
                with self.assertRaisesRegex(OSError, "disk full"):
                    logs.write("stdout", b"partial")
            metadata = logs.close()
            self.assertTrue(metadata["closed"])
            self.assertFalse(metadata["complete"])
            self.assertEqual(metadata["files"], 0)
            self.assertIn("disk full", metadata["error"])

    def test_host_raw_and_compact_files_are_identical_for_binary_process_output(self):
        command = ["fake-host", "argument with spaces"]
        result = subprocess.CompletedProcess(command, 9, bytes(range(256)), b"\xff\x00error\r\n")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            raw, compact = root / "raw", root / "compact"
            logs = CommandLogs(compact)
            with mock.patch.object(host.subprocess, "run", return_value=result):
                old = host.execute(command, raw / "runs/one")
                new = host.execute(command, compact / "runs/one", logs=logs)
            logs.close()
            self.assertEqual(old, new)
            expected = {path.relative_to(raw).as_posix(): path.read_bytes() for path in raw.rglob("*") if path.is_file()}
            self.assertEqual(contents(logs.path), expected)
            self.assertEqual(list(compact.iterdir()), [logs.path])

    def test_host_timeout_preserves_partial_bytes_and_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            logs = CommandLogs(root)
            error = subprocess.TimeoutExpired(["fake-host"], 30, output=b"\xffpartial", stderr=b"\x00error")
            with mock.patch.object(host.subprocess, "run", side_effect=error):
                result = host.execute(["fake-host"], root / "runs/timeout", logs=logs)
            logs.close()
            files = contents(logs.path)
            self.assertEqual(files["runs/timeout/stdout"], error.stdout)
            self.assertEqual(files["runs/timeout/stderr"], error.stderr)
            self.assertIsNone(result["exit_code"])
            self.assertIn("timed out", json.loads(files["runs/timeout/result.json"])["error"])

    def test_differential_preserves_process_bytes_and_existing_text_comparison(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            logs = CommandLogs(root)
            process = subprocess.CompletedProcess(["fake"], 3, b"\xc3\xa5\x00\r\n", b"error\r")
            with mock.patch.object(differential.subprocess, "run", return_value=process):
                result, _ = differential.execute(["fake"], cwd=root, logs=logs, directory=root, name="run")
            differential.save_log(root, "run", ["fake"], result, logs)
            logs.close()
            files = contents(logs.path)
            self.assertEqual(files["run.stdout"], b"\xc3\xa5\x00\r\n")
            self.assertEqual(files["run.stderr"], b"error\r")
            self.assertEqual(result.stdout, "å\x00\n")
            self.assertEqual(result.stderr, "error\n")
            self.assertEqual(json.loads(files["run.result.json"])["exit_code"], 3)
            self.assertEqual(list(root.iterdir()), [logs.path])

    def test_differential_timeout_and_oserror_log_command_and_partial_result(self):
        failures = [subprocess.TimeoutExpired(["fake"], 1, output=b"\xff", stderr=b"\x00"),
                    FileNotFoundError("missing command")]
        for error in failures:
            with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                logs = CommandLogs(root)
                with mock.patch.object(differential.subprocess, "run", side_effect=error):
                    with self.assertRaises(type(error)):
                        differential.execute(["fake"], cwd=root, logs=logs, directory=root, name="run")
                logs.close(complete=False)
                files = contents(logs.path)
                self.assertEqual(json.loads(files["run.command.json"]), ["fake"])
                self.assertEqual(files["run.stdout"], getattr(error, "stdout", None) or b"")
                self.assertIn(str(error), json.loads(files["run.result.json"])["error"])

    def test_failed_differential_closes_archive_and_reports_partial_coverage(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            goose = root / "fake-goose"
            goose.write_bytes(b"identity only")

            def fail(args, output, selected, rows, logs):
                logs.write("partial.stdout", b"retained")
                raise RuntimeError("interrupted qualification")

            argv = ["run_differential.py", "--goose", str(goose), "--output-dir", str(root), "--compact-logs"]
            with mock.patch.object(sys, "argv", argv), mock.patch.object(differential, "run_cases", side_effect=fail):
                self.assertEqual(differential.main(), 1)
            report = json.loads((root / "report.json").read_text())
            self.assertEqual(report["observations"], 0)
            self.assertEqual(report["failures"], 1)
            self.assertIn("interrupted qualification", report["error"])
            self.assertTrue(report["command_logs"]["closed"])
            self.assertFalse(report["command_logs"]["complete"])
            self.assertEqual(contents(root / "command-logs.tar.gz"), {"partial.stdout": b"retained"})

    def test_combined_report_keeps_six_archive_identities_out_of_semantic_fields(self):
        case = differential.Case("one", "one", stdout="answer\n", levels=(0, 2))
        reports, configurations = {}, {}
        for backend in qualify_compiler.BACKENDS:
            for level in qualify_compiler.LEVELS:
                key = backend, level
                configuration = qualify_compiler.expected_configuration(backend, level, "one")
                configurations[key] = configuration
                engines = qualify_compiler.ENGINES
                if backend == "native":
                    engines = ("native",)
                rows = [{"case": "one", "optimization": level, "debug": False, "backend": backend,
                         "engine": engine, "stdout": "answer\n", "status": "pass"} for engine in engines]
                reports[key] = {"configuration": configuration, "compiler_sha256": "compiler", "toolchain": {},
                                "platform": "platform", "python": "python", "cases": 1,
                                "failures": 0, "observations": len(rows), "results": rows,
                                "_report_sha256": str(key), "_command": [str(key)],
                                "command_logs": {"path": f"{backend}-O{level}/command-logs.tar.gz",
                                                 "complete": True, "closed": True, "sha256": "archive", "files": 4}}
        report, shards = qualify_compiler.combine(reports, [case], configurations, "compiler", True)
        self.assertEqual(report["observations"], 10)
        self.assertEqual(report["failures"], 0)
        self.assertNotIn("command_logs", report)
        self.assertNotIn("configuration", report)
        self.assertEqual(len(shards), 6)
        self.assertEqual(len({row["command_logs"]["path"] for row in shards.values()}), 6)


if __name__ == "__main__":
    unittest.main()
