#!/usr/bin/env python3
"""Qualify --wasm-bundled-host and unsafe owner-control reinterpretation."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from tests import goose_stats

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew")).resolve()
STDLIB = Path(os.environ.get("GOOSE_STDLIB", COMPILER.parent / "stdlib")).resolve()
ROWS = "var rows:u8[>..]=[1,77,51];\n"
READ = 'print(rows.len," ",rows[0]);'
FOREIGN = 'extern fn inspect(out:u8[>..]&) -> i64 = "{}";\n'


def code_section(wasm):
    return dict(goose_stats.sections(wasm))[10]


def publication_accesses(wasm):
    code = code_section(wasm)
    functions, offset = goose_stats.uleb(code, 0)
    accesses = 0
    for _ in range(functions):
        length, offset = goose_stats.uleb(code, offset)
        body = code[offset:offset + length]
        offset += length
        accesses += sum(op in (0x23, 0x24) and index == 11 for op, index in goose_stats.instruction_operands(body))
    return accesses


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class OrdinaryOwnerModes(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.work = Path(work.name)

    def compile(self, source, bits, bundled, optimization="-O2"):
        entry = self.work / "main.goose"
        entry.write_text(source)
        out = self.work / f"owner-{bits}-{int(bundled)}.wasm"
        args = [COMPILER, entry, "--stdlib", STDLIB, "--target", "wasm-direct", optimization, "-o", out]
        if bits == 64:
            args.append("--wasm-memory64")
        if bundled:
            args.append("--wasm-bundled-host")
        subprocess.run(args, check=True, capture_output=True)
        return out

    def test_bundled_import_and_foreign_fallback(self):
        reads = 'print(rows.len," ",rows[0]," ",rows[1]);'
        cases = [
            ("bundled stdout", "import os;\n" + ROWS + 'fn main(){write_stdout("");' + reads + "}", True),
            ("unknown symbol", FOREIGN.format("observer") + ROWS + "fn main(){let x=inspect(rows);" + reads + "}", False),
            ("wrong system signature", FOREIGN.format("system") + ROWS + "fn main(){let x=inspect(rows);" + reads + "}", False),
            ("user declared stdlib symbol", FOREIGN.format("gs_os_arg") + ROWS + "fn main(){let x=inspect(rows);" + reads + "}", False),
        ]
        for name, source, specializes in cases:
            for bits, optimization in ((32, "-O0"), (32, "-O2"), (64, "-O2")):
                with self.subTest(case=name, bits=bits, optimization=optimization):
                    general = self.compile(source, bits, False, optimization).read_bytes()
                    bundled = self.compile(source, bits, True, optimization).read_bytes()
                    if bits == 32 and optimization == "-O2":
                        # Shared owner decoding in the general mode adds one function.
                        general_functions, _ = goose_stats.uleb(code_section(general), 0)
                        bundled_functions, _ = goose_stats.uleb(code_section(bundled), 0)
                        self.assertEqual(general_functions - bundled_functions, int(specializes))
                    elif specializes:
                        self.assertLess(len(bundled), len(general))
                    else:
                        self.assertEqual(bundled, general)

    def test_publication_in_global_initializer_preserves_mapping(self):
        source = """recursive fn pair() -> i64, i64 { return 2, 3; }
recursive fn print_tuple() { let a, b = pair(); print(a + b); }
var result: i64[>..] = if 1 < 2 { [1, 2] } else { [3, 4] };
fn main() { print_tuple(); print(result); }
"""
        for bits in (32, 64):
            for optimization in ("-O0", "-O2"):
                with self.subTest(bits=bits, optimization=optimization):
                    general = self.compile(source, bits, False, optimization)
                    bundled = self.compile(source, bits, True, optimization)
                    if bits == 64 or optimization == "-O0":
                        self.assertEqual(bundled.read_bytes(), general.read_bytes())
                    else:
                        self.assertEqual(publication_accesses(bundled.read_bytes()), publication_accesses(general.read_bytes()))
                    for module in (general, bundled):
                        result = subprocess.run(["node", ROOT / "scripts/run_wasm.mjs", module], check=True, capture_output=True)
                        self.assertEqual(result.stdout, b"5\n[1, 2]\n")

    def test_bundled_no_publication_omits_control_marks(self):
        source = """var result: i64[>..] = [];
fn main() {
    for i in 0..8 {
        if i == 4 { continue; }
        result.push(i);
        if i == 6 { break; }
    }
    print(result);
}
"""
        for bits in (32, 64):
            with self.subTest(bits=bits):
                general = self.compile(source, bits, False)
                bundled = self.compile(source, bits, True)
                self.assertLess(publication_accesses(bundled.read_bytes()), publication_accesses(general.read_bytes()))
                result = subprocess.run(["node", ROOT / "scripts/run_wasm.mjs", bundled], check=True, capture_output=True)
                self.assertEqual(result.stdout, b"[0, 1, 2, 3, 5, 6]\n")

    def test_reinterpreted_control_reads_its_image_prefix(self):
        for bits in (32, 64):
            source = ROWS + f"""fn main() {{
    let p:u8[>..]&? = &rows;
    let words:u{bits}[6]& = p as! u{bits}[6]&;
    words[4] = words[0]; words[5] = 1;
    {READ}
}}
"""
            for bundled in (False, True):
                with self.subTest(bits=bits, bundled=bundled):
                    out = self.compile(source, bits, bundled)
                    result = subprocess.run(["node", ROOT / "scripts/run_wasm.mjs", out], check=True, capture_output=True)
                    self.assertEqual(result.stdout, b"1 77\n")


if __name__ == "__main__":
    unittest.main()
