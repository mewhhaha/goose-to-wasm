#!/usr/bin/env python3
"""Keep unsupported dynamic receiving lifetimes explicit at O0 and O2."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


class DynamicBoundaries(unittest.TestCase):
    def test_owned_parameter_storage_cannot_escape_the_call(self):
        cases = {
            "element": ('i64&', 'values[0]'),
            "slice": ('i64[:]', 'values[..]'),
            "owner": ('i64[>..]&', 'values'),
        }
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            work = Path(directory)
            for name, (result, expression) in cases.items():
                path = work / (name + ".goose")
                path.write_text(f'fn bad(values: i64[>..]) -> {result} {{ return {expression}; }}\n'
                                'fn main() { bad([1]); }\n')
                for level in (0, 2):
                    for target in ("native", "wasm-direct"):
                        with self.subTest(name=name, level=level, target=target):
                            output = work / (target + str(level)); output.unlink(missing_ok=True)
                            command = [str(GOOSE), str(path), "--offline", f"-O{level}", "--target", target, "-o", str(output)]
                            if target == "native": command.append("--standalone")
                            rejected = subprocess.run(command, capture_output=True, text=True, timeout=60)
                            self.assertNotEqual(rejected.returncode, 0)
                            self.assertFalse(output.exists())
                            self.assertIn("dies with this function", rejected.stdout + rejected.stderr)

    def test_valid_language_requires_unimplemented_receiving_lifetimes(self):
        cases = {
            "copy-temporary": 'fn main() { var values: i64[>..] = [1]; copy(values); }',
            "anonymous-result": '''fn make() -> i64[>..] {
    var values: i64[>..] = [1]; values.push(2); return values;
}
fn main() { print(make().len); }''',
            "mixed-owned-results": '''fn make() -> i64[>..], i64 { return [1], 2; }
fn main() { let values, n = make(); print(values[n % values.len]); }''',
        }
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            work = Path(directory)
            for name, source in cases.items():
                path = work / (name + ".goose"); path.write_text(source)
                for level in (0, 2):
                    with self.subTest(name=name, level=level):
                        common = [str(GOOSE), str(path), "--offline", f"-O{level}"]
                        oracle = subprocess.run(common + ["--target", "native", "--standalone", "-o", str(work / "oracle.c")],
                                                capture_output=True, text=True, timeout=60)
                        self.assertEqual(oracle.returncode, 0, oracle.stdout + oracle.stderr)
                        output = work / "program.wasm"; output.unlink(missing_ok=True)
                        direct = subprocess.run(common + ["--target", "wasm-direct", "-o", str(output)],
                                                capture_output=True, text=True, timeout=60)
                        self.assertNotEqual(direct.returncode, 0, name)
                        self.assertFalse(output.exists())
                        self.assertIn("not supported", direct.stdout + direct.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
