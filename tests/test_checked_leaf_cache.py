#!/usr/bin/env python3
"""Checked scalar leaf reuse, invalidation, diagnostics, and fresh equivalence."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_compiler_session as session

ROOT = Path(__file__).resolve().parents[1]


class CheckedLeaves(session.SessionHarness):
    SERVER_FLAGS = ("--native-worker", "--syntax-cache", "--checked-leaf-cache")

    def fresh(self, *, sources=None, level=0, debug=False):
        output = self.work / "fresh.wasm"
        payload = {"source": str(self.source), "output": str(output), "optimization": level,
                   "debug": debug, "offline": True, "sources": {str(k): v for k, v in (sources or {}).items()}}
        result = subprocess.run([str(session.GOOSE), "--wasm-session"], input=json.dumps(payload) + "\n",
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        reply = json.loads(result.stdout)
        return reply, output.read_bytes() if reply["ok"] else None

    def test_warm_and_caller_edit_skip_leaf_checking(self):
        cold = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual((cold["checked_leaf_cache_hits"], cold["checked_leaf_cache_stored"]), (0, 1))
        self.assertFalse(cold["semantic_reused"])
        warm = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(warm["checked_leaf_cache_hits"], 1)
        self.assertTrue(warm["semantic_reused"])
        self.assertFalse(warm["frontend_reused"])
        edit = {self.source: 'import helper; fn main() { print(value() + 1); }\n'}
        changed = self.request(sources=edit)["backend_stats"]
        self.assertEqual(changed["checked_leaf_cache_hits"], 1)
        reply, expected = self.fresh(sources=edit)
        self.assertTrue(reply["ok"], reply)
        self.assertEqual(self.output.read_bytes(), expected)
        self.run_output("42\n")

    def test_leaf_edit_and_resolved_alias_invalidate(self):
        self.request(extra=["--no-cache"])
        changed = self.request(sources={self.helper: 'fn value() -> i64 { 42 }\n'})["backend_stats"]
        self.assertEqual((changed["checked_leaf_cache_hits"], changed["checked_leaf_cache_misses"]), (0, 1))
        self.run_output("42\n")
        self.helper.write_text('fn value(x: Amount) -> Amount { x + 1 }\n')
        self.source.write_text('import helper; type Amount = i64; fn main() { print(value(3)); }\n')
        self.request(extra=["--no-cache"])
        self.assertEqual(self.request(extra=["--no-cache"])["backend_stats"]["checked_leaf_cache_hits"], 1)
        edit = {self.source: self.source.read_text().replace("= i64", "= f64")}
        report = self.request(sources=edit)["backend_stats"]
        self.assertEqual(report["checked_leaf_cache_hits"], 0)
        self.run_output("4.0\n")
        bad = {self.source: self.source.read_text().replace("= i64", "= bool")}
        cached = self.request(sources=bad, success=False)
        cold, _ = self.fresh(sources=bad)
        self.assertFalse(cold["ok"])
        self.assertEqual(cached["error"], "native compiler worker failed:\n" + cold["error"])
        self.request(extra=["--no-cache"])
        self.run_output("4\n")

    def test_scalar_matrix_matches_fresh_at_both_levels_and_debug(self):
        text = (ROOT / "tests/fixtures/checked_leaves.goose").read_text()
        self.source.write_text(text)
        expected_output = "65 70 true\n25 63 4.25\n7 6 7 9\n-inf 1.25 -2.0\n"
        for level in (0, 2):
            for debug in (False, True):
                with self.subTest(level=level, debug=debug):
                    extra = ["--no-cache", f"-O{level}", *(["--debug"] if debug else [])]
                    self.request(extra=extra)
                    warm = self.request(extra=extra)["backend_stats"]
                    self.assertEqual(warm["checked_leaf_cache_hits"], 10)
                    self.assertEqual(warm["checked_leaf_cache_refused"], 0)
                    reply, module = self.fresh(level=level, debug=debug)
                    self.assertTrue(reply["ok"], reply)
                    self.assertEqual(self.output.read_bytes(), module)
                    self.run_output(expected_output)

    def test_excluded_bodies_recheck_and_preserve_diagnostics(self):
        bodies = [
            'let amount: i64 = 41; fn value() -> i64 { amount }\n',
            'extern fn bench_input() -> i64; fn value() -> i64 { bench_input() }\n',
            'fn value() -> i64 { 41 as i64 }\n',
            'fn value() -> i64 { let x = 41; x }\n',
            'let amount: i64 = 42; fn value() -> i64 { if true { 41 } else { amount } }\n',
            'fn value() -> i64 { var x = 0; for i in 4 { x += i; } x }\n',
        ]
        for text in bodies:
            with self.subTest(text=text):
                self.helper.write_text(text)
                self.request(extra=["--no-cache"])
                report = self.request(extra=["--no-cache"])["backend_stats"]
                self.assertEqual(report["checked_leaf_cache_hits"], 0)
                self.assertEqual(report["checked_leaf_cache_misses"], 0)
                reply, module = self.fresh()
                self.assertTrue(reply["ok"], reply)
                self.assertEqual(self.output.read_bytes(), module)
        self.helper.write_text('fn value() -> i64 { missing }\n')
        failed = self.request(extra=["--no-cache"], success=False)
        cold, _ = self.fresh()
        self.assertFalse(cold["ok"])
        self.assertEqual(failed["error"], "native compiler worker failed:\n" + cold["error"])

    def test_import_reordering_remaps_runtime_diagnostics(self):
        other = self.work / "other.goose"
        other.write_text('fn unused() -> i64 { 1 }\n')
        self.helper.write_text('\n' * 6 + 'fn value(x: i64) -> i64 { return 8 / x; }\n')
        self.source.write_text('import helper; import other; fn main() { print(value(0)); }\n')
        self.request(extra=["--no-cache"])
        edit = {self.source: self.source.read_text().replace('import helper; import other;', 'import other; import helper;')}
        warm = self.request(sources=edit)["backend_stats"]
        self.assertEqual(warm["checked_leaf_cache_hits"], 2)
        reply, module = self.fresh(sources=edit)
        self.assertTrue(reply["ok"], reply)
        self.assertEqual(self.output.read_bytes(), module)
        result = subprocess.run([session.NODE, str(ROOT / "scripts/run_wasm.mjs"), str(self.output)],
                                capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("division", result.stderr)
        self.assertIn("line 7", result.stderr)

    def test_shifted_function_rechecks_and_failure_recovers(self):
        self.request(extra=["--no-cache"])
        self.helper.write_text('\nfn value() -> i64 { 41 }\n')
        stats = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(stats["checked_leaf_cache_hits"], 0)
        previous = self.output.read_bytes()
        self.request(sources={self.helper: '\nfn value() -> i64 { "wrong" }\n'}, success=False)
        self.assertEqual(self.output.read_bytes(), previous)
        recovered = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(recovered["checked_leaf_cache_hits"], 1)
        self.run_output("41\n")

    def test_retention_is_bounded_across_edits(self):
        stats = None
        evicted = 0
        for i in range(270):
            stats = self.request(sources={self.helper: f'fn value() -> i64 {{ {i} }}\n'})["backend_stats"]
            self.assertLessEqual(stats["checked_leaf_cache_entries"], 256)
            self.assertLessEqual(stats["checked_leaf_cache_estimated_bytes"], 16 * 1024 * 1024)
            evicted += stats["checked_leaf_cache_evictions"]
        self.assertGreater(evicted, 0)
        self.run_output("269\n")

    def test_cache_is_independent_of_syntax_reuse_and_flag_is_per_request(self):
        base = {"source": str(self.source), "output": str(self.output), "offline": True}
        requests = [base, {**base, "checked_leaf_cache": True}, {**base, "checked_leaf_cache": True}, base]
        result = subprocess.run([str(session.GOOSE), "--wasm-session"],
                                input="".join(json.dumps(r) + "\n" for r in requests),
                                text=True, capture_output=True, timeout=60)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(replies), 4, result.stderr)
        for reply in replies:
            self.assertTrue(reply["ok"], reply)
        self.assertFalse(replies[0]["stats"]["semantic_reused"])
        self.assertEqual(replies[1]["stats"]["checked_leaf_cache_hits"], 0)
        self.assertEqual(replies[2]["stats"]["checked_leaf_cache_hits"], 1)
        self.assertFalse(replies[2]["stats"]["syntax_cache_enabled"])
        self.assertFalse(replies[3]["stats"]["checked_leaf_cache_enabled"])
        self.run_output("41\n")

    def test_debug_traps_are_emitted_after_cached_semantics(self):
        self.helper.write_text('fn value(x: i8) -> i8 { x + 1 }\n')
        self.source.write_text('import helper; fn main() { print(value(127)); }\n')
        self.request(extra=["--no-cache"])
        self.run_output("-128\n")
        stats = self.request(extra=["--no-cache", "--debug"])["backend_stats"]
        self.assertEqual(stats["checked_leaf_cache_hits"], 1)
        reply, module = self.fresh(debug=True)
        self.assertTrue(reply["ok"], reply)
        self.assertEqual(self.output.read_bytes(), module)
        result = subprocess.run([session.NODE, str(ROOT / "scripts/run_wasm.mjs"), str(self.output)],
                                capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overflow", result.stderr)

    def test_qualified_fixtures_match_fresh(self):
        session.CompilerSession.test_qualified_fixture_modules_match_fresh_compilers(self)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=session.GOOSE)
    parser.add_argument("--node", default=session.NODE)
    args, remaining = parser.parse_known_args()
    session.GOOSE = args.goose.resolve(); session.NODE = args.node
    unittest.main(argv=[sys.argv[0], *remaining])
