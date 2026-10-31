#!/usr/bin/env python3
"""Check packed-layout overflow and the bounded recursive overlap proof."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


class PackedLayoutBoundaries(unittest.TestCase):
    def compile(self, directory, source, target, level):
        path = directory / "main.goose"
        path.write_text(source)
        output = directory / ("program.c" if target == "native" else "program.wasm")
        output.unlink(missing_ok=True)
        command = [str(GOOSE), str(path), "--offline", f"-O{level}", "--target", target, "-o", str(output)]
        if target == "native": command.append("--standalone")
        return subprocess.run(command, capture_output=True, text=True, timeout=60), output

    def test_packed_fixed_array_byte_count_cannot_wrap(self):
        declarations = (
            "struct P { a: u8, b: u16 } var values: P[6148914691236517206];",
            "enum E { Data { a: u8, b: u16 } } var values: E.Data[6148914691236517206];",
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            for declaration in declarations:
                for level in (0, 2):
                    result, output = self.compile(Path(name), declaration + " fn main() { print(values.len); }", "wasm-direct", level)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertFalse(output.exists())
                    self.assertIn("fixed array exceeds the configured linear-memory limit", result.stdout + result.stderr)

    def test_zero_length_record_fields_remain_frontend_invalid(self):
        source = "struct Record { data: u8[0], value: u64 } fn main() {}"
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            for target in ("native", "wasm-direct"):
                for level in (0, 2):
                    result, output = self.compile(Path(name), source, target, level)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("cannot be a zero-length array", result.stdout + result.stderr)

    def test_noncanonical_children_remain_outside_overlap_proof(self):
        cases = (
            ("", "flag: bool", "false"),
            ("", "number: f64", "1.0"),
            ("", "point: u64&", "fallback"),
            ("", "data: u8[..2]", "[1]"),
            ("struct Empty {}", "empty: Empty", "Empty {}"),
            ("enum Inner { A, B { n: u8 } }", "inner: Inner", "Inner.A"),
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            for extra, field, initial in cases:
                source = f'''{extra}
struct Record {{ {field}, value: u64 }}
enum E {{ Old {{ record: Record }}, New {{ value: u64 }} }}
var fallback: u64 = 0;
recursive fn replace(named: bool) -> E.., u64 {{
    var e: E.. = E.Old {{ Record {{ {initial}, 0 }} }};
    let kept: u64& = match e {{ Old &p => p.record.value, _ => fallback }};
    if named {{ return e, 0; }} return E.New {{ 0x0102030405060708 }}, kept;
}}
fn main() {{ let e, n = replace(false); print(n); }}'''
                for level in (0, 2):
                    native, _ = self.compile(Path(name), source, "native", level)
                    self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                    direct, output = self.compile(Path(name), source, "wasm-direct", level)
                    self.assertNotEqual(direct.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("requires packed enum image layout", direct.stdout + direct.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
