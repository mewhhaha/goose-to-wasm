"""Fixed-size memories still reject oversized frames at the Goose source line."""
import subprocess
import sys
import unittest

from tests import goose_stats

sys.path.insert(0, str(goose_stats.ROOT / "scripts"))
from run_wasmtime import run_module


PROGRAM = """extern fn bench_input() -> i64;
recursive fn descend(n: i64) -> i64 {
    var values: u8[4096] = [0; 4096];
    values[0] = n as u8;
    if n <= 0 { return values[0] as i64; }
    return descend(n - 1) + values[0] as i64;
}
fn main() { print(descend(bench_input())); }
"""


class FixedMemoryFrames(goose_stats.Compile, unittest.TestCase):
    def test_growth_and_exhaustion(self):
        source = self.work / "stack.goose"
        source.write_text(PROGRAM)
        for width in (32, 64):
            for initial in (1, 4):
                with self.subTest(width=width, initial=initial):
                    module = self.work / "stack.wasm"
                    command = [goose_stats.GOOSE, source, "--target", "wasm-direct", "-O2",
                               "--wasm-initial-pages", str(initial), "--wasm-max-pages", "4",
                               "-o", module]
                    if width == 64:
                        command.append("--wasm-memory64")
                    subprocess.run(command, check=True, capture_output=True)
                    data = module.read_bytes()
                    success = run_module(data, "10\n")
                    self.assertEqual((success["exit_code"], success["stdout"]), (0, b"55\n"))
                    failure = run_module(data, "100\n")
                    self.assertEqual(failure["exit_code"], 1)
                    self.assertIn("activation stack exhausted (line 2)", failure["stderr"])
                    if initial == 1:
                        def deny_growth(store, exports):
                            store.set_limits(memory_size=65536)
                            exports["_start"](store)

                        denied = run_module(data, "10\n", invoke_start=deny_growth)
                        self.assertEqual(denied["exit_code"], 1)
                        self.assertIn("linear memory exhausted (line 2)", denied["stderr"])
