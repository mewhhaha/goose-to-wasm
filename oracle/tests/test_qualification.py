#!/usr/bin/env python3
"""A passing corpus cannot qualify a compiler replaced during its run."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run_tests


class QualificationIntegrity(unittest.TestCase):
    def test_compiler_replacement_invalidates_passing_cases(self):
        for changed in (False, True):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                compiler = work / "compiler"
                compiler.write_bytes(b"compiler before")
                case = SimpleNamespace(name="passing-case", reject=False)

                def passing_case(args, selected, level):
                    if changed:
                        compiler.write_bytes(b"compiler after")
                    return {"name": selected.name, "ok": True, "seconds": 0}

                argv = ["run_tests.py", "--goose", str(compiler), "--driver", __file__,
                        "--output-dir", str(work / "results"), "--level", "0", "--jobs", "1",
                        "--emcc", sys.executable, "--node", sys.executable]
                stderr = io.StringIO()
                with patch.object(sys, "argv", argv), patch.object(run_tests, "cases", return_value=[case]), \
                     patch.object(run_tests, "run_case", side_effect=passing_case), \
                     contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
                    status = run_tests.main()
                report = json.loads((work / "results/report.json").read_text())
                self.assertEqual(report["passed"], 1)
                self.assertEqual(report["failed"], 0)
                self.assertEqual(report["compiler_unchanged"], not changed)
                self.assertEqual(report["qualified"], not changed)
                self.assertEqual(status, int(changed))
                self.assertEqual("compiler changed" in stderr.getvalue(), changed)


if __name__ == "__main__":
    unittest.main()
