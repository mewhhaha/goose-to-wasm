#!/usr/bin/env python3
"""Qualify parsed-module reuse, semantic rebuilding, context, and recovery."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_compiler_session as session
from test_compiler_session import SessionHarness, ROOT


class SyntaxCache(SessionHarness):
    SERVER_FLAGS = ("--native-worker", "--lexical-cache", "--syntax-cache")

    def test_warm_syntax_and_one_import_edit(self):
        cold = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual((cold["parsed_files"], cold["parsed_cache_hits"]), (2, 0))
        self.assertTrue(cold["syntax_cache_enabled"])
        self.assertFalse(cold["parsed_syntax_reused"])
        baseline = self.output.read_bytes()
        warm = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual((warm["parsed_files"], warm["parsed_cache_hits"]), (0, 2))
        self.assertTrue(warm["parsed_syntax_reused"])
        self.assertFalse(warm["semantic_reused"])
        self.assertFalse(warm["frontend_reused"])
        self.assertEqual(warm["lexical_scanned_tokens"], 0)
        self.assertEqual(self.output.read_bytes(), baseline)
        edit = self.request(sources={self.helper: 'fn value() -> i64 { 42 }\n'})["backend_stats"]
        self.assertEqual((edit["parsed_files"], edit["parsed_cache_hits"]), (1, 1))
        self.run_output("42\n")
        restored = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual((restored["parsed_files"], restored["parsed_cache_hits"]), (1, 1))
        self.run_output("41\n")

    def test_changed_signature_is_checked_again(self):
        self.request(extra=["--no-cache"])
        changed = self.request(sources={self.helper: 'fn value() -> f64 { 2.5 }\n'})["backend_stats"]
        self.assertEqual((changed["parsed_files"], changed["parsed_cache_hits"]), (1, 1))
        self.run_output("2.5\n")
        previous = self.output.read_bytes()
        self.request(sources={self.helper: 'fn different() -> i64 { 2 }\n'}, success=False)
        self.assertEqual(self.output.read_bytes(), previous)
        self.request(extra=["--no-cache"])
        self.run_output("41\n")

    def test_root_roles_and_imported_main(self):
        self.helper.write_text('fn value() -> i64 { 41 }\nfn main() { print(17); }\n')
        self.request(extra=["--no-cache"])
        self.run_output("41\n")
        root = self.request(source=self.helper, extra=["--no-cache"])["backend_stats"]
        self.assertEqual((root["parsed_files"], root["parsed_cache_hits"]), (0, 1))
        self.run_output("17\n")
        imported = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual((imported["parsed_files"], imported["parsed_cache_hits"]), (0, 2))
        self.run_output("41\n")

    def test_import_reordering_reindexes_sources_and_globals(self):
        counter = self.work / "counter.goose"
        counter.write_text('var next: i64 = 0; fn bump() -> i64 { next += 1; next }\n')
        for name in ("a", "b"):
            (self.work / (name + ".goose")).write_text(
                f'import counter; namespace {name}; let number = bump(); fn get() -> i64 {{ number }}\n')
        text = 'import a; import b; fn main() { print(a::get(), " ", b::get()); }\n'
        self.source.write_text(text)
        self.request(extra=["--no-cache"])
        self.run_output("1 2\n")
        reverse = text.replace('import a; import b;', 'import b; import a;')
        edited = self.request(sources={self.source: reverse})["backend_stats"]
        self.assertEqual((edited["parsed_files"], edited["parsed_cache_hits"]), (1, 3))
        self.run_output("2 1\n")
        self.request(extra=["--no-cache"])
        self.run_output("1 2\n")

    def raw(self, messages):
        result = subprocess.run([str(session.GOOSE), "--wasm-session"],
                                input="\n".join(json.dumps(m) for m in messages) + "\n",
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_cross_file_collisions_keep_cold_diagnostics(self):
        other = self.work / "other.goose"
        for declaration in ('struct Shared { x: i64 }\n', 'let shared = 7;\n'):
            with self.subTest(declaration=declaration):
                other.write_text(declaration)
                self.helper.write_text(declaration + 'fn value() -> i64 { 41 }\n')
                base = {"source": str(self.source), "output": str(self.output), "offline": True}
                collision = {str(self.source): 'import helper; import other; fn main() { print(value()); }\n'}
                replies = self.raw([{**base, "syntax_cache": True},
                                    {**base, "syntax_cache": True, "sources": collision},
                                    {**base, "syntax_cache": False, "sources": collision},
                                    {**base, "syntax_cache": True}])
                self.assertEqual([r["ok"] for r in replies], [True, False, False, True])
                self.assertEqual(replies[1]["error"], replies[2]["error"])
                self.assertIn("already declared", replies[1]["error"])
                self.run_output("41\n")

    def test_parse_warnings_replay_and_failed_syntax_is_not_cached(self):
        self.helper.write_text('extern "bench_input" fn input() -> i64; fn value() -> i64 { 41 }\n')
        other = self.work / "other.goose"
        other.write_text('fn unused() -> i64 { 0 }\n')
        base = {"source": str(self.source), "output": str(self.output), "offline": True, "syntax_cache": True}
        bad = {str(self.helper): 'fn value() -> i64 { "bad\\q" }\nfn later() {}\n'}
        reindex = {str(self.source): 'import helper; import other; fn main() { print(value()); }\n'}
        replies = self.raw([base, base, {**base, "sources": reindex},
                            {**base, "sources": bad}, {**base, "sources": bad}, base])
        self.assertEqual([r["ok"] for r in replies], [True, True, True, False, False, True])
        self.assertIn("deprecated", replies[0]["diagnostics"])
        self.assertEqual(replies[0]["diagnostics"], replies[1]["diagnostics"])
        self.assertEqual(replies[0]["diagnostics"], replies[2]["diagnostics"])
        self.assertEqual(replies[3]["error"], replies[4]["error"])
        self.assertEqual(replies[-1]["stats"]["parsed_files"], 1)
        self.run_output("41\n")

    def test_all_qualified_fixtures_match_fresh_compilers(self):
        session.CompilerSession.test_qualified_fixture_modules_match_fresh_compilers(self)

    @unittest.skipUnless(Path("/proc/self/statm").exists(), "Linux RSS measurement")
    def test_repeated_syntax_imports_release_request_state(self):
        session.CompilerSession.test_repeated_frontends_release_owned_state(self)

    def test_dependency_graph_and_semantic_backend_recovery(self):
        session.CompilerSession.test_root_overlays_dependency_graph_and_semantic_recovery(self)

    def test_overlay_bom_normalization_matches_disk(self):
        text = '\ufeff\ufefffn value() -> i64 { 41 }\n'
        self.helper.write_text(text)
        base = {"source": str(self.source), "output": str(self.output), "offline": True, "syntax_cache": True}
        overlay = {**base, "sources": {str(self.helper): text}}
        replies = self.raw([base, overlay, overlay])
        self.assertEqual([r["ok"] for r in replies], [False, False, False])
        self.assertEqual(replies[0]["error"], replies[1]["error"])
        self.assertEqual(replies[1]["error"], replies[2]["error"])
        self.helper.write_text(text[1:])
        fixed = self.raw([base, {**base, "sources": {str(self.helper): text[1:]}}])
        self.assertEqual([r["ok"] for r in fixed], [True, True])
        self.assertEqual(fixed[1]["stats"]["parsed_files"], 0)
        self.run_output("41\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=session.GOOSE)
    parser.add_argument("--node", default=session.NODE)
    args, remaining = parser.parse_known_args()
    session.GOOSE = args.goose.resolve(); session.NODE = args.node
    unittest.main(argv=[sys.argv[0], *remaining])
