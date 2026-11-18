"""Distinct equal-hash literals survive table growth and identical literals share storage."""

import json
import subprocess
import unittest

from tests import goose_stats


class DataSegments(goose_stats.Compile, unittest.TestCase):
    def test_colliding_and_repeated_literals(self):
        # These equal-length strings have the same 32-bit FNV-1a hash.
        words = ["rejdsjmb", "wyrqlnhb"]
        words += [f"literal-{i:02}" for i in range(48)]
        words += ["", "wyrqlnhb", "rejdsjmb"]
        literals = ", ".join(map(json.dumps, words))
        program = "fn main() { for word in [" + literals + "] { print(word); } }"
        module, _ = self.compile(2, text=program)
        data = dict(goose_stats.sections(module.read_bytes()))[11]
        for word in words[:2]:
            self.assertEqual(data.count(word.encode()), 1)
        actual = subprocess.check_output([goose_stats.NODE, goose_stats.ROOT / "scripts/run_wasm.mjs", module])
        self.assertEqual(actual.decode().splitlines(), words)
