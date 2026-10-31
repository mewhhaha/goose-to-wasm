#!/usr/bin/env python3
"""Keep static environments distinct from escaping borrows and nonlocal exits."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


class StaticCaptureBoundaries(unittest.TestCase):
    def compile(self, work, source, target, level):
        path = work / "main.goose"; path.write_text(source)
        output = work / ("oracle.c" if target == "native" else "program.wasm")
        output.unlink(missing_ok=True)
        command = [str(GOOSE), str(path), "--offline", f"-O{level}", "--target", target, "-o", str(output)]
        if target == "native": command.append("--standalone")
        return subprocess.run(command, capture_output=True, text=True, timeout=60), output

    def test_variable_nonlocal_targets_require_additional_landing_support(self):
        source = '''fn target() -> i64[] {
    recursive fn leave() { return [7, 8] from target; }
    leave(); return [];
}
fn main() { print(target()); }'''
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                native, _ = self.compile(Path(directory), source, "native", level)
                self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                self.assertNotEqual(direct.returncode, 0)
                self.assertFalse(output.exists())
                self.assertIn("this owned nonlocal target requires additional staging and landing support", direct.stdout + direct.stderr)

    def test_owned_nonlocal_forwarding_requires_closed_producer_arguments(self):
        source = '''recursive fn copy_view(xs: const i64[:]) -> i64[>..] { return xs; }
fn target() -> i64[>..] {
    var xs: i64[>..] = [7, 8];
    recursive fn leave() { return copy_view(xs[..]) from target; }
    leave(); return [];
}
fn main() { print(target()); }'''
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                native, _ = self.compile(Path(directory), source, "native", level)
                self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                self.assertNotEqual(direct.returncode, 0)
                self.assertFalse(output.exists())
                self.assertIn("owned nonlocal source requires a pure read or a closed producer", direct.stdout + direct.stderr)

    def test_callback_local_borrowed_results_require_a_root_proof(self):
        cases = (
            'fn observe(xs: const i64[:], n: i64) -> i64 { xs[0] + n } '
            'fn churn() -> i64 { var fill: i64[>..] = [99, 98]; fill.len - 2 } '
            'fn apply<F>() -> i64 { observe(F([7, 8]), churn()) } '
            'fn main() { print(apply() { xs: i64[>..] => xs[..] }); }',
            'fn size(xs: const i64[:]) -> i64 { xs.len } fn apply<F>() -> i64 { size(F()) } '
            'fn main() { print(apply() { var xs: i64[>..] = [7, 8]; xs[..] }); }',
            'struct View { xs: const i64[:] } fn size(v: View) -> i64 { v.xs.len } '
            'fn apply<F>() -> i64 { size(F([7, 8])) } '
            'fn main() { print(apply() { xs: i64[>..] => View { xs: xs[..] } }); }',
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for source in cases:
                for level in (0, 2):
                    native, _ = self.compile(Path(directory), source, "native", level)
                    self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                    direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                    self.assertNotEqual(direct.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("function-value result may borrow callback-local storage", direct.stdout + direct.stderr)

    def test_function_values_cannot_be_stored_by_the_frontend(self):
        source = 'fn named() -> i64 { 1 } fn main() { let stored = named; print(stored()); }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                for target in ("native", "wasm-direct"):
                    result, output = self.compile(Path(directory), source, target, level)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("function values are compile-time only and cannot be stored", result.stdout + result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
