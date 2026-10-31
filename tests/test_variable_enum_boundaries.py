#!/usr/bin/env python3
"""Keep variable enum ownership, payload scope and frontend lifetime gates explicit."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


class VariableEnumBoundaries(unittest.TestCase):
    def compile(self, work, source, target, level):
        path = work / "main.goose"
        path.write_text(source)
        output = work / ("oracle.c" if target == "native" else "program.wasm")
        output.unlink(missing_ok=True)
        command = [str(GOOSE), str(path), "--offline", f"-O{level}", "--target", target, "-o", str(output)]
        if target == "native": command.append("--standalone")
        return subprocess.run(command, capture_output=True, text=True, timeout=60), output

    def test_unsupported_payload_shapes_remain_a_separate_slice(self):
        cases = (
            'enum E { Empty, Data { a: i64[], b: i64[] } } fn main() { let e: E.. = E.Data { [1], [2] }; match e { Data p => print(p.a.len), _ => {} } }',
            'enum E { Empty, Data { values: i64[>..] } } fn main() { let e: E.. = E.Data { [1] }; match e { Data => print(1), _ => {} } }',
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

    def test_rendering_requires_the_later_recursive_renderer(self):
        source = 'enum E { Empty, Data { x: i64 } } fn main() { let e: E.. = E.Data { 1 }; print(e); }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                native, _ = self.compile(Path(directory), source, "native", level)
                self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                self.assertNotEqual(direct.returncode, 0)
                self.assertFalse(output.exists())
                self.assertIn("variable-mode enum rendering is not supported", direct.stdout + direct.stderr)

    def test_containing_variable_enums_remain_explicitly_gated(self):
        cases = (
            ('enum E { Data { x: i64 } } struct Box { tag: u8, value: E.. } '
             'fn main() { let b = Box { 1, E.Data { 2 } }; match b.value { Data p => print(p.x) } }',
             "final variable-array field"),
            ('enum E { Data { x: i64 } } fn main() { let xs: E..[] = [E.Data { 2 }]; print(xs.len); }',
             "only fixed-mode enums"),
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for source, diagnostic in cases:
                for level in (0, 2):
                    native, _ = self.compile(Path(directory), source, "native", level)
                    self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                    direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                    self.assertNotEqual(direct.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn(diagnostic, direct.stdout + direct.stderr)

    def test_whole_variable_enum_assignment_stays_frozen(self):
        source = 'enum E { Empty, Data { x: i64 } } fn main() { var e: E.. = E.Data { 1 }; e = E.Empty; }'
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                for target in ("native", "wasm-direct"):
                    result, output = self.compile(Path(directory), source, target, level)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("frozen at construction", result.stdout + result.stderr)

    def test_payload_view_cannot_escape_private_owned_parameter(self):
        source = ('enum E { Data { x: i64 } } fn bad(e: E..) -> const i64& { '
                  'return match e { Data &p => p.x }; } fn main() { bad(E.Data { 1 }); }')
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                for target in ("native", "wasm-direct"):
                    result, output = self.compile(Path(directory), source, target, level)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("dies with this function", result.stdout + result.stderr)

    def test_observing_nonempty_named_replacement_requires_packed_images(self):
        source = '''extern fn bench_input() -> i64;
enum E { Old { lead: u8, value: u64 }, New { value: u64 }, Empty }
var fallback: u64 = 0;
recursive fn replace(n: i64) -> E.., u64 {
    var e: E.. = E.Old { 1, 0 };
    let kept: u64& = match e { Old &p => p.value, _ => fallback };
    if n > 0 { return e, 0; } return E.New { 0x0102030405060708 }, kept;
}
fn main() { let e, value = replace(bench_input()); print(value); }'''
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            for level in (0, 2):
                native, _ = self.compile(Path(directory), source, "native", level)
                self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                direct, output = self.compile(Path(directory), source, "wasm-direct", level)
                self.assertNotEqual(direct.returncode, 0)
                self.assertFalse(output.exists())
                self.assertIn("requires packed enum image layout", direct.stdout + direct.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
