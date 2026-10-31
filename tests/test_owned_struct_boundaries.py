#!/usr/bin/env python3
"""Keep the supported variable-tail struct shape and frontend lifetimes explicit."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


class OwnedStructBoundaries(unittest.TestCase):
    def compile(self, work, source, target, level):
        path = work / "main.goose"
        path.write_text(source)
        output = work / ("oracle.c" if target == "native" else "program.wasm")
        output.unlink(missing_ok=True)
        command = [str(GOOSE), str(path), "--offline", f"-O{level}", "--target", target, "-o", str(output)]
        if target == "native": command.append("--standalone")
        return subprocess.run(command, capture_output=True, text=True, timeout=60), output

    def test_other_owned_shapes_remain_explicitly_refused(self):
        cases = {
            "nonfinal-nested": ('struct Inner { values: i64[] } struct Outer { inner: Inner, id: i64 } '
                       'fn main() { let x = Outer { Inner { [1] }, 2 }; print(x.inner.values.len); }',
                       "final variable-array field"),
            "nonfinal": ('struct Packet { values: i64[], id: i64 } '
                         'fn main() { let x = Packet { [1], 2 }; print(x.id); }',
                         "final variable-array field"),
            "multiple": ('struct Packet { a: i64[], b: i64[] } '
                         'fn main() { let x = Packet { [1], [2] }; print(x.a.len); }',
                         "not supported"),
            "elements": ('struct Packet { values: i64[] } '
                         'fn main() { let xs: Packet[] = [Packet { [1] }]; print(xs.len); }',
                         "fixed-size structs"),
            "variable-prefix-frame": ('struct Inner { values: i64[] } struct Outer { inner: Inner, values: i64[>..] } '
                             'fn main() { let x = Outer { Inner { [2] }, [3] }; print(x.inner.values.len); }',
                             "fixed-size structs"),
        }
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            work = Path(directory)
            for name, (source, diagnostic) in cases.items():
                for level in (0, 2):
                    with self.subTest(name=name, level=level):
                        native, _ = self.compile(work, source, "native", level)
                        self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                        direct, output = self.compile(work, source, "wasm-direct", level)
                        self.assertNotEqual(direct.returncode, 0)
                        self.assertFalse(output.exists())
                        self.assertIn("wasm-direct:", direct.stdout + direct.stderr)
                        self.assertIn(diagnostic, direct.stdout + direct.stderr)

    def test_variable_struct_rendering_is_not_a_shallow_snapshot(self):
        source = 'struct Packet { id: i64, values: i64[] } fn main() { print(Packet { 1, [2] }); }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                native, _ = self.compile(Path(directory), source, "native", level)
                self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                self.assertNotEqual(direct.returncode, 0)
                self.assertFalse(output.exists())
                self.assertIn("variable-struct rendering is not supported", direct.stdout + direct.stderr)

    def test_whole_variable_struct_assignment_stays_frozen(self):
        source = 'struct Packet { id: i64, values: i64[] } fn main() { var x = Packet { 1, [2] }; x = Packet { 3, [4] }; }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                for target in ("native", "wasm-direct"):
                    result, output = self.compile(Path(directory), source, target, level)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("frozen at construction", result.stdout + result.stderr)

    def test_by_value_parameter_prefix_and_tail_views_cannot_escape(self):
        prefix = 'struct Packet { id: i64, values: i64[] } '
        cases = (
            prefix + 'fn bad(p: Packet) -> const i64& { return p.id; } fn main() { bad(Packet { 1, [2] }); }',
            prefix + 'fn bad(p: Packet) -> const i64[:] { return p.values[..]; } fn main() { bad(Packet { 1, [2] }); }',
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for source in cases:
                for level in (0, 2):
                    for target in ("native", "wasm-direct"):
                        result, output = self.compile(Path(directory), source, target, level)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(output.exists())
                        self.assertIn("dies with this function", result.stdout + result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
