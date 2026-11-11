#!/usr/bin/env python3
"""A differential run must schedule and execute observations before it can succeed."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tests/run_differential.py"
sys.path.insert(0, str(ROOT / "tests"))
import run_differential as differential

# Both cases matching this name support only -O2.
O2_ONLY = ["--filter", "enum-image/canceled_fixed", "--backends", "direct", "--engines", "v8"]


class DifferentialSelection(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        self.compiler = self.work / "goose"
        self.compiler.write_bytes(b"never executed")
        self.output = self.work / "report"

    def main(self, *argv, run_cases):
        command = ["run_differential.py", "--goose", str(self.compiler), "--output-dir", str(self.output), *argv]
        with mock.patch.object(sys, "argv", command), mock.patch.object(differential, "run_cases", run_cases):
            return differential.main()

    def test_matched_cases_without_a_supported_level_are_refused(self):
        matched = [case for case in differential.cases() if "enum-image/canceled_fixed" in case.name]
        self.assertEqual([case.levels for case in matched], [(2,), (2,)])
        result = subprocess.run([sys.executable, str(RUNNER), *O2_ONLY, "--levels", "0", "--goose", str(self.compiler),
                                 "--output-dir", str(self.output)], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--filter 'enum-image/canceled_fixed' matched 2 cases, none of which supports --levels 0",
                      result.stderr)
        self.assertFalse(self.output.exists())

    def test_zero_observations_fail(self):
        self.assertEqual(self.main(*O2_ONLY, "--levels", "2", run_cases=lambda *args: None), 1)
        report = json.loads((self.output / "report.json").read_text())
        self.assertEqual((report["cases"], report["scheduled_case_levels"], report["observations"]), (2, 2, 0))

    def test_scheduled_observations_can_pass(self):
        def run_cases(args, output, selected, rows, logs):
            rows.extend({"case": case.name, "status": "pass"} for case in selected)

        self.assertEqual(self.main(*O2_ONLY, "--levels", "0", "2", run_cases=run_cases), 0)
        report = json.loads((self.output / "report.json").read_text())
        self.assertEqual((report["cases"], report["scheduled_case_levels"], report["observations"]), (2, 2, 2))


if __name__ == "__main__":
    unittest.main()
