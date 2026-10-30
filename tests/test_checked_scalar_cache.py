#!/usr/bin/env python3
"""Checked scalar callers reuse current callee contracts and request ownership."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_compiler_session as session

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("incremental_bench", ROOT / "bench/incremental.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class ScalarCallers(session.SessionHarness):
    SERVER_FLAGS = ("--native-worker", "--syntax-cache", "--checked-scalar-cache")

    def setUp(self):
        super().setUp()
        self.source.write_text(bench.program(1, 32))

    def fresh(self, *, sources=None, level=0, debug=False):
        output = self.work / "fresh.wasm"
        payload = {"source": str(self.source), "output": str(output), "offline": True,
                   "optimization": level, "debug": debug,
                   "sources": {str(k): v for k, v in (sources or {}).items()}}
        result = subprocess.run([str(session.GOOSE), "--wasm-session"], input=json.dumps(payload) + "\n",
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        reply = json.loads(result.stdout)
        return reply, output.read_bytes() if reply["ok"] else None

    def same_fresh(self, *, sources=None, level=0, debug=False):
        reply, module = self.fresh(sources=sources, level=level, debug=debug)
        self.assertTrue(reply["ok"], reply)
        self.assertEqual(self.output.read_bytes(), module)

    def same_error(self, sources):
        response = self.request(sources=sources, extra=["--no-cache"], success=False)
        fresh, _ = self.fresh(sources=sources)
        self.assertFalse(fresh["ok"], fresh)
        self.assertEqual(response["error"], "native compiler worker failed:\n" + fresh["error"])
        return response["error"]

    def test_chain_edit_rechecks_one_body_and_rebinds_callers(self):
        cold = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(cold["checked_scalar_caller_hits"], 0)
        warm = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(warm["checked_scalar_caller_hits"], 31)
        for delta in (2, 10, 100):
            edit = {self.source: bench.program(delta, 32)}
            report = self.request(sources=edit)["backend_stats"]
            self.assertEqual(report["checked_scalar_caller_hits"], 31)
            self.assertEqual(report["checked_scalar_cache_misses"], 1)
            self.assertEqual(report["checked_scalar_cache_refused"], 0)
            self.same_fresh(sources=edit)
            result = subprocess.run([session.NODE, str(ROOT / "scripts/run_wasm.mjs"), str(self.output)],
                                    input="3\n", text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, bench.expected(delta, 32))

    def test_o2_and_debug_see_new_callee_bodies(self):
        for level in (0, 2):
            for debug in (False, True):
                with self.subTest(level=level, debug=debug):
                    extra = ["--no-cache", f"-O{level}", *(["--debug"] if debug else [])]
                    self.request(extra=extra)
                    edit = {self.source: bench.program(10, 32)}
                    report = self.request(sources=edit, extra=extra)["backend_stats"]
                    self.assertEqual(report["checked_scalar_caller_hits"], 31)
                    self.same_fresh(sources=edit, level=level, debug=debug)

    def test_diamonds_and_argument_order_reuse_current_specializations(self):
        self.source.write_text((ROOT / "tests/fixtures/scalar_callers.goose").read_text())
        self.request(extra=["--no-cache"])
        warm = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(warm["checked_scalar_caller_hits"], 6)
        edit = {self.source: self.source.read_text().replace("x + 1", "x + 10")}
        stats = self.request(sources=edit)["backend_stats"]
        self.assertEqual(stats["checked_scalar_caller_hits"], 6)
        self.assertEqual(stats["checked_scalar_cache_misses"], 1)
        self.assertEqual(stats["checked_scalar_cache_refused"], 0)
        self.same_fresh(sources=edit)
        self.run_output("54 0 67 585\n")

    def test_overload_addition_and_signature_changes_fall_back(self):
        self.request(extra=["--no-cache"])
        # Appending an overload keeps every original declaration position fixed.
        original = self.source.read_text()
        overload = {self.source: original + 'fn step0(x: f64) -> f64 { x + 2.0 }\n'}
        stats = self.request(sources=overload)["backend_stats"]
        self.assertEqual(stats["checked_scalar_caller_hits"], 0)
        self.same_fresh(sources=overload)
        changed = {self.source: original.replace('fn step0(x: i64) -> i64', 'fn step0(x: i64) -> i32')}
        self.same_error(changed)

    def test_unsupported_effects_and_recursion_fall_back(self):
        self.request(extra=["--no-cache"])
        original = self.source.read_text()
        edit = {self.source: original.replace('return x + 1;', 'return x + amount;') + 'let amount: i64 = 10;\n'}
        stats = self.request(sources=edit)["backend_stats"]
        self.assertEqual(stats["checked_scalar_caller_hits"], 0)
        self.same_fresh(sources=edit)
        cycle = {self.source: original.replace('return x + 1;', 'return step31(x);')}
        self.same_error(cycle)

    def test_changed_callee_errors_preserve_call_chain_and_order(self):
        self.source.write_text('fn left(x: i64) -> i64 { x + 1 }\n'
                               'fn right(x: i64) -> i64 { x + 2 }\n'
                               'fn parent(x: i64) -> i64 { left(x) + right(x) }\n'
                               'fn main() { print(parent(3)); }\n')
        self.request(extra=["--no-cache"])
        original = self.source.read_text()
        bad = {self.source: original.replace('x + 1', 'x + true').replace('x + 2', 'x + false')}
        self.same_error(bad)
        restored = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(restored["checked_scalar_caller_hits"], 1)
        self.run_output("9\n")

    def test_namespace_shadow_and_parameter_shadow_revalidate(self):
        self.helper.write_text('namespace local; fn parent(x: i64) -> i64 { target(x) + 1 }\n')
        self.source.write_text('import helper; fn target(x: i64) -> i64 { x + 1 }\n'
                               'fn main() { print(local::parent(3)); }\n')
        self.request(extra=["--no-cache"])
        self.assertEqual(self.request(extra=["--no-cache"])["backend_stats"]["checked_scalar_caller_hits"], 1)
        shadow = {self.helper: self.helper.read_text() + 'fn target(x: i64) -> i64 { x + 10 }\n'}
        report = self.request(sources=shadow)["backend_stats"]
        self.assertEqual(report["checked_scalar_caller_hits"], 0)
        self.same_fresh(sources=shadow)
        self.run_output("14\n")
        bad = {self.helper: 'namespace local; fn parent(target: i64) -> i64 { target(target) + 1 }\n'}
        self.same_error(bad)

    def test_checkfree_dependency_is_revalidated(self):
        self.source.write_text('checkfree fn base(x: i64) -> i64 { x + 1 }\n'
                               'checkfree fn parent(x: i64) -> i64 { base(x) * 3 }\n'
                               'fn main() { print(parent(3)); }\n')
        self.request(extra=["--no-cache"])
        self.assertEqual(self.request(extra=["--no-cache"])["backend_stats"]["checked_scalar_caller_hits"], 1)
        changed = {self.source: self.source.read_text().replace('checkfree fn base', 'fn base')}
        self.assertIn("not checkfree", self.same_error(changed))

    def test_import_reordering_preserves_graph_origins(self):
        self.helper.write_text('fn base(x: i64) -> i64 { x + 1 }\n'
                               'fn parent(x: i64) -> i64 { base(x) * 3 }\n')
        (self.work / "other.goose").write_text('fn unused() {}\n')
        self.source.write_text('import helper; import other; fn main() { print(parent(3)); }\n')
        self.request(extra=["--no-cache"])
        edit = {self.source: self.source.read_text().replace('import helper; import other;', 'import other; import helper;')}
        stats = self.request(sources=edit)["backend_stats"]
        self.assertEqual(stats["checked_scalar_caller_hits"], 1)
        self.same_fresh(sources=edit)
        self.run_output("12\n")

    def test_excluded_caller_shapes_check_normally(self):
        for body in ('base(x + 1)', 'base(1)', 'if x > 0 { base(x) } else { x }'):
            with self.subTest(body=body):
                self.source.write_text('fn base(x: i64) -> i64 { x + 1 }\n'
                                       f'fn parent(x: i64) -> i64 {{ {body} }}\n'
                                       'fn main() { print(parent(3)); }\n')
                self.request(extra=["--no-cache"])
                stats = self.request(extra=["--no-cache"])["backend_stats"]
                self.assertEqual(stats["checked_scalar_caller_hits"], 0)
                self.same_fresh()
        self.source.write_text('type Amount = i64;\nfn base(x: i64) -> i64 { x + 1 }\n'
                               'fn parent(x: Amount) -> Amount { base(x) * 3 }\n'
                               'fn main() { print(parent(3)); }\n')
        self.request(extra=["--no-cache"])
        stats = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(stats["checked_scalar_caller_hits"], 0)
        self.same_fresh()

    def test_zero_argument_callee_values_do_not_become_cached_constants(self):
        self.source.write_text('fn base() -> i64 { 1 }\nfn parent() -> i64 { base() * 3 }\n'
                               'fn main() { print(parent()); }\n')
        self.request(extra=["--no-cache"])
        edit = {self.source: self.source.read_text().replace('-> i64 { 1 }', '-> i64 { 100 }')}
        stats = self.request(sources=edit)["backend_stats"]
        self.assertEqual(stats["checked_scalar_caller_hits"], 1)
        self.assertEqual(stats["checked_scalar_cache_misses"], 1)
        self.same_fresh(sources=edit)
        self.run_output("300\n")

    def test_graph_beyond_depth_budget_compiles_through_fallback(self):
        self.source.write_text(bench.program(1, 130))
        self.request(extra=["--no-cache"])
        stats = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertLess(stats["checked_scalar_caller_hits"], 129)
        self.same_fresh()

    def test_existing_qualified_modules_match_fresh(self):
        session.CompilerSession.test_qualified_fixture_modules_match_fresh_compilers(self)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=session.GOOSE)
    parser.add_argument("--node", default=session.NODE)
    args, remaining = parser.parse_known_args()
    session.GOOSE = args.goose.resolve(); session.NODE = args.node
    unittest.main(argv=[sys.argv[0], *remaining])
