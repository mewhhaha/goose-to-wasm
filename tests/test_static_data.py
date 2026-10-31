#!/usr/bin/env python3
"""Check sparse data reconstruction, module structure, and memory limits."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"


def uleb(data, offset):
    value = shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7


def sections(data):
    assert data[:8] == b"\0asm\1\0\0\0"
    offset = 8
    while offset < len(data):
        kind = data[offset]
        length, start = uleb(data, offset + 1)
        yield kind, data[start:start + length]
        offset = start + length


class StaticData(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, source, *options):
        path = self.work / "main.goose"
        path.write_text(source)
        out = self.work / "program.wasm"
        result = subprocess.run([str(GOOSE), str(path), "--target", "wasm-direct",
                                 "--offline", "-o", str(out), *options],
                                capture_output=True, text=True, timeout=60)
        return result, out

    def test_segment_reconstruction_and_fragmentation(self):
        # Exercise the actual writer without depending on frontend optimizations
        # to produce particular literal byte patterns.
        source = self.work / "segments.cpp"
        source.write_text(r'''
#include <bit>
#include <cassert>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
using namespace std;
#include "compiler/wasm_binary.h"
using namespace goose::direct_wasm;

void check(const string &data) {
    auto segments = SparseDataSegments(data, 1024);
    assert(segments.size() <= 1024);
    string restored(data.size(), '\0');
    size_t previous = 0;
    for (auto &s : segments) {
        auto start = s.offset - 1024;
        assert(!s.bytes.empty() && s.bytes.front() && s.bytes.back());
        assert(start >= previous && start + s.bytes.size() <= data.size());
        restored.replace(start, s.bytes.size(), s.bytes);
        previous = start + s.bytes.size();
    }
    assert(restored == data);
}
int main() {
    assert(SparseDataSegments("", 1024).empty());
    assert(SparseDataSegments(string(1000000, '\0'), 1024).empty());
    check(""); check(string(1000000, '\0')); check(string(10000, 'x'));
    string sparse(1000000, '\0'); sparse[31] = 'a'; sparse[900000] = 'b';
    check(sparse);
    auto spans = SparseDataSegments(sparse, 1024);
    assert(spans.size() == 2 && spans[0].offset == 1055);
    assert(spans[0].bytes == "a" && spans[1].bytes == "b");
    string dense(10000, '\0');
    for (size_t i = 0; i < dense.size(); i += 2) dense[i] = 'x';
    check(dense); assert(SparseDataSegments(dense, 1024).size() == 1);
    string fragmented(200000, '\0');
    for (size_t i = 0; i < fragmented.size(); i += 64) fragmented[i] = char(255);
    check(fragmented);
    assert(SparseDataSegments(fragmented, 1024).size() == 1024);
    for (size_t gap = 0; gap < 40; gap++) {
        string data(gap + 2, '\0'); data.front() = 'a'; data.back() = 'b'; check(data);
    }
    uint32_t state = 1;
    for (int test = 0; test < 100; test++) {
        string data(10000, '\0');
        for (auto &c : data) {
            state = state * 1664525u + 1013904223u;
            if ((state >> 24) < 16) c = char(state >> 16);
        }
        check(data);
    }
}
''')
        binary = self.work / "segments"
        result = subprocess.run(["c++", "-std=c++20", "-O2", "-I", str(ROOT),
                                 str(source), "-o", str(binary)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run([str(binary)], check=True, timeout=30)

    def test_large_zero_global_has_small_file_and_full_memory(self):
        source = (ROOT / "tests/fixtures/static_data.goose").read_text()
        for level in ("-O0", "-O2"):
            with self.subTest(level=level):
                result, out = self.compile(source, level)
                self.assertEqual(result.returncode, 0, result.stderr)
                data = out.read_bytes()
                self.assertLess(len(data), 20000)
                payloads = dict(sections(data))
                # Memory section: one defined memory, explicit min/max limits.
                self.assertEqual(payloads[5][:2], b"\1\1")
                minimum, _ = uleb(payloads[5], 2)
                self.assertGreater(minimum * 65536, 1048576)
                count, _ = uleb(payloads[11], 0)
                self.assertGreater(count, 0)
                self.assertIn(b"A\0B", payloads[11])

    def test_all_zero_data_needs_no_segments(self):
        result, out = self.compile("fn main() {}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(dict(sections(out.read_bytes()))[11], b"\0")
        import wasmtime
        engine = wasmtime.Engine()
        module = wasmtime.Module(engine, out.read_bytes())
        store = wasmtime.Store(engine)
        linker = wasmtime.Linker(engine)
        for item in module.imports:
            linker.define_func(item.module, item.name, item.type, lambda *args: None)
        linker.instantiate(store, module).exports(store)["_start"](store)
        subprocess.run(["node", "-e", """
const fs = require('node:fs');
const m = new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const goose = Object.fromEntries(WebAssembly.Module.imports(m).map(i => [i.name, () => {}]));
new WebAssembly.Instance(m, {goose}).exports._start();
""", str(out)], check=True, capture_output=True, timeout=30)

    def test_zero_reservations_still_enforce_memory_limit(self):
        # Each array fits by itself, but the combined logical allocations and
        # base address exceed a single page. Omitted bytes still occupy memory.
        source = ("var a: u8[32700] = [0; 32700];\n"
                  "var b: u8[32700] = [0; 32700];\n"
                  "fn main() { print(a[0], b[0]); }\n")
        result, out = self.compile(source, "--wasm-initial-pages", "1", "--wasm-max-pages", "1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("static data exceeds", result.stderr)
        self.assertFalse(out.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
