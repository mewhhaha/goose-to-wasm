#!/usr/bin/env python3
"""Native C built as several units, or beside a cached runtime unit, runs as
the single translation unit does (native/units.h)."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts/goose_wasm.py"
GOOSE = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goose")).resolve()
STDLIB = None
# Shared globals, a queue and workers, so units share state, queues and
# worker entry points.
THREADS = """
struct Job { n: i64 }
var total = 0;
var log: u8[>..] = [];
reusable var pool: i64[>..] = [];

fn note(n: i64) { total += n; if n % 50 == 0 { log.push('x'); } }
fn slot(n: i64) -> i64 { return pool.alloc_index(n); }

thread_fn producer(from: i64, count: i64) {
    total = 1000;
    for n in count { qput(Job { n: from * 100 + n }); }
}

fn main() {
    var ids: i64[>..] = [];
    for p in 3 { ids.push(thread_spawn(producer, p, 40)); }
    var got = 0;
    while got < 120 {
        let j, ok = qget<Job>(1);
        if ok { got++; note(j.n); }
    }
    for id in ids { thread_wait(id); }
    print(got, " ", total, " ", log, " ", slot(7), " ", pool.len);
}
"""


class NativeUnits(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        (self.work / "threads.goose").write_text(THREADS)

    def build(self, source, name, *extra):
        stats = self.work / (name + ".json")
        command = [sys.executable, DRIVER, "build", source, "--backend", "native", "--goose", GOOSE,
                   "-o", self.work / name, "--stats", stats, "--cache-dir", self.work / "cache", *extra]
        if STDLIB is not None:
            command += ["--stdlib", STDLIB]
        result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=600)
        self.assertEqual(result.returncode, 0, result.stderr)
        run = subprocess.run([str(self.work / name)], capture_output=True, text=True, timeout=60)
        return json.loads(stats.read_text()), (run.returncode, run.stdout)

    def test_units_match_one_translation_unit(self):
        for source in (self.work / "threads.goose", ROOT / "examples/functions.goose", ROOT / "examples/vm.goose",
                       ROOT / "examples/tour.goose"):
            with self.subTest(source=source.name):
                whole, expected = self.build(source, "whole", "--jobs", "1")
                self.assertEqual((whole["native_units"], whole["runtime_unit"]), (1, "embedded"))
                self.assertEqual(expected[0], 0, expected)
                for jobs in ("2", "3", "auto"):
                    stats, result = self.build(source, "units-" + jobs, "--jobs", jobs)
                    self.assertEqual(result, expected, jobs)
                    self.assertIn(stats["runtime_unit"], ("compiled", "cached"))
                    if jobs != "auto":
                        self.assertEqual(stats["native_units"], int(jobs))

    def test_runtime_unit_is_cached(self):
        first, expected = self.build(ROOT / "examples/squares.goose", "first")
        second, result = self.build(ROOT / "examples/squares.goose", "second")
        self.assertEqual((first["native_units"], first["runtime_unit"]), (1, "compiled"))
        self.assertEqual((second["native_units"], second["runtime_unit"]), (1, "cached"))
        self.assertEqual(result, expected)
        self.assertEqual(len(list((self.work / "cache").glob("*.o"))), 1)
        # Uncached, a small program compiles whole; asked for units, it compiles the runtime unit too.
        third, result = self.build(ROOT / "examples/squares.goose", "third", "--no-cache")
        self.assertEqual((third["native_units"], third["runtime_unit"]), (1, "embedded"))
        self.assertEqual(result, expected)
        fourth, result = self.build(ROOT / "examples/squares.goose", "fourth", "--no-cache", "--jobs", "2")
        self.assertEqual((fourth["native_units"], fourth["runtime_unit"]), (2, "compiled"))
        self.assertEqual(result, expected)
        self.assertEqual(len(list((self.work / "cache").glob("*.o"))), 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--stdlib", type=Path)
    args, remaining = parser.parse_known_args()
    GOOSE, STDLIB = args.goose.resolve(), args.stdlib
    unittest.main(argv=[sys.argv[0], *remaining])
