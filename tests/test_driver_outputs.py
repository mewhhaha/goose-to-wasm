#!/usr/bin/env python3
"""The build driver refuses outputs that alias an imported source, on either backend."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts/goose_wasm.py"
GOOSE = ROOT / "build/bin/goose"
STDLIB = None
HELPER = b"fn value() -> i64 { return 41; }\n"
OVERWRITE = "goose-wasm: an output would overwrite an input\n"
DISTINCT = "goose-wasm: output, C output and stats must use different paths\n"


class DriverOutputs(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        (self.work / "main.goose").write_text("import helper;\nfn main() { print(value()); }\n")
        self.helper = self.work / "helper.goose"
        self.helper.write_bytes(HELPER)

    def build(self, backend, *extra):
        command = [sys.executable, str(DRIVER), "build", "main.goose", "--backend", backend, "--goose", str(GOOSE)]
        if STDLIB is not None:
            command += ["--stdlib", str(STDLIB)]
        return subprocess.run([*command, *extra], cwd=self.work, capture_output=True, text=True, timeout=120)

    def assert_refused(self, backend, message, *extra):
        # A previous artifact and the imported source must both survive the refusal.
        previous = self.work / ("program.wasm" if backend == "direct" else "program")
        previous.write_bytes(b"previous artifact")
        result = self.build(backend, *extra)
        self.assertEqual((result.returncode, result.stderr), (1, message))
        self.assertEqual(self.helper.read_bytes(), HELPER)
        self.assertEqual(previous.read_bytes(), b"previous artifact")

    def test_native_outputs_cannot_replace_an_import(self):
        (self.work / "linked.json").hardlink_to(self.helper)
        (self.work / "alias").symlink_to(self.helper)
        for extra in (["-o", "helper.goose"], ["-o", "alias"], ["-o", "program", "--stats", "helper.goose"],
                      ["-o", "program", "--emit-c", "helper.goose"], ["-o", "program", "--stats", "linked.json"],
                      ["-o", "program", "--emit-c", "linked.json"]):
            with self.subTest(extra=extra):
                self.assert_refused("native", OVERWRITE, *extra)

    def test_direct_outputs_cannot_replace_an_import(self):
        # A symbolic link resolves to helper.goose, which the .wasm suffix rule refuses already.
        (self.work / "linked.wasm").hardlink_to(self.helper)
        (self.work / "linked.json").hardlink_to(self.helper)
        (self.work / "alias.json").symlink_to(self.helper)
        for extra in (["-o", "linked.wasm"], ["-o", "program.wasm", "--stats", "helper.goose"],
                      ["-o", "program.wasm", "--stats", "linked.json"], ["-o", "program.wasm", "--stats", "alias.json"]):
            with self.subTest(extra=extra):
                self.assert_refused("direct", OVERWRITE, *extra)

    def test_outputs_must_be_distinct(self):
        self.assert_refused("native", DISTINCT, "-o", "program", "--stats", "program")
        self.assert_refused("native", DISTINCT, "-o", "program", "--emit-c", "program")
        self.assert_refused("direct", DISTINCT, "-o", "program.wasm", "--stats", "program.wasm")
        (self.work / "stats.json").write_text("{}")
        (self.work / "linked-stats.json").hardlink_to(self.work / "stats.json")
        self.assert_refused("native", DISTINCT, "-o", "program", "--stats", "stats.json",
                            "--emit-c", "linked-stats.json")

    def test_distinct_outputs_still_build(self):
        native = self.build("native", "-o", "program", "--stats", "native.json", "--emit-c", "program.c")
        self.assertEqual(native.returncode, 0, native.stderr)
        direct = self.build("direct", "-o", "program.wasm", "--stats", "direct.json")
        self.assertEqual(direct.returncode, 0, direct.stderr)
        self.assertEqual(self.helper.read_bytes(), HELPER)
        run = subprocess.run([str(self.work / "program")], capture_output=True, text=True, timeout=60)
        self.assertEqual((run.returncode, run.stdout), (0, "41\n"))
        self.assertTrue((self.work / "program.c").read_text())
        for stats in ("native.json", "direct.json"):
            self.assertIn('"schema": "goose-build-v3"', (self.work / stats).read_text())
        self.assertEqual((self.work / "program.wasm").read_bytes()[:4], b"\0asm")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--stdlib", type=Path)
    args, remaining = parser.parse_known_args()
    GOOSE, STDLIB = args.goose.resolve(), args.stdlib
    unittest.main(argv=[sys.argv[0], *remaining])
