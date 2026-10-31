#!/usr/bin/env python3
"""Check the nonresizable standalone variant ownership boundary."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


class VariableVariantBoundaries(unittest.TestCase):
    def compile(self, work, source, target, level):
        path = work / "main.goose"
        path.write_text(source)
        output = work / ("oracle.c" if target == "native" else "program.wasm")
        output.unlink(missing_ok=True)
        command = [str(GOOSE), str(path), "--offline", f"-O{level}", "--target", target, "-o", str(output)]
        if target == "native": command.append("--standalone")
        return subprocess.run(command, capture_output=True, text=True, timeout=60), output

    def test_other_variant_shapes_remain_refused(self):
        cases = (
            'enum E { Data { values: i64[>..] } } fn main() { let p = E.Data { [1] }; print(p.values.len); }',
            'enum E { Data { values: i64[], id: i64 } } fn main() { let p = E.Data { [1], 2 }; print(p.id); }',
            'enum E { Data { a: i64[], b: i64[] } } fn main() { let p = E.Data { [1], [2] }; print(p.a.len); }',
            'enum E { Data { values: i64[] } } fn main() { let xs: E.Data[] = [E.Data { [1] }]; print(xs.len); }',
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for source in cases:
                for level in (0, 2):
                    native, _ = self.compile(Path(directory), source, "native", level)
                    self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                    direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                    self.assertNotEqual(direct.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("wasm-direct:", direct.stdout + direct.stderr)
                    self.assertIn("not supported", direct.stdout + direct.stderr)

    def test_whole_variable_variant_assignment_stays_frozen(self):
        source = 'enum E { Data { id: i64, values: i64[] } } fn main() { var p = E.Data { 1, [2] }; p = E.Data { 3, [4] }; }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                for target in ("native", "wasm-direct"):
                    result, output = self.compile(Path(directory), source, target, level)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("frozen at construction", result.stdout + result.stderr)

    def test_private_parameter_prefix_and_tail_views_cannot_escape(self):
        prefix = 'enum E { Data { id: i64, values: i64[] } } '
        cases = (
            prefix + 'fn bad(p: E.Data) -> const i64& { return p.id; } fn main() { bad(E.Data { 1, [2] }); }',
            prefix + 'fn bad(p: E.Data) -> const i64[:] { return p.values[..]; } fn main() { bad(E.Data { 1, [2] }); }',
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for source in cases:
                for level in (0, 2):
                    for target in ("native", "wasm-direct"):
                        result, output = self.compile(Path(directory), source, target, level)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(output.exists())
                        self.assertIn("dies with this function", result.stdout + result.stderr)

    def test_variable_variant_rendering_is_explicit(self):
        source = 'enum E { Data { id: i64, values: i64[] } } fn main() { print(E.Data { 1, [2] }); }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                native, _ = self.compile(Path(directory), source, "native", level)
                self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                self.assertNotEqual(direct.returncode, 0)
                self.assertFalse(output.exists())
                self.assertIn("variable-variant rendering is not supported", direct.stdout + direct.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
