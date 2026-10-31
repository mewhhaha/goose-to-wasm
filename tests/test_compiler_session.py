#!/usr/bin/env python3
"""Execute native-worker builds, unsaved imports, isolation, and restart paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"
NODE = "node"


class SessionHarness(unittest.TestCase):
    SERVER_FLAGS = ("--native-worker", "--lexical-cache")
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.source = self.work / "main.goose"
        self.helper = self.work / "helper.goose"
        self.source.write_text('import helper;\nfn main() { print(value()); }\n')
        self.helper.write_text('fn value() -> i64 { 41 }\n')
        self.output = self.work / "program.wasm"
        self.log = tempfile.TemporaryFile(mode="w+t")
        self.addCleanup(self.log.close)
        self.server = subprocess.Popen([sys.executable, str(ROOT / "scripts/goose_wasm.py"),
                                        "serve", *self.SERVER_FLAGS], cwd=ROOT, text=True,
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log)
        self.addCleanup(self.stop)
        self.sequence = 0

    def stop(self):
        self.server.stdin.close()
        try:
            self.server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.server.kill()
            self.server.wait()
        self.server.stdout.close()

    def request(self, *, sources=None, extra=(), source=None, compiler=None, success=True):
        self.sequence += 1
        args = ["build", str(source or self.source), "--goose", str(compiler or GOOSE),
                "--offline", *([] if any(x in ("-O0", "-O1", "-O2") for x in extra) else ["-O0"]),
                "--cache-dir", str(self.work / "cache"),
                "-o", str(self.output), *extra]
        request = {"id": self.sequence, "args": args}
        if sources is not None:
            request["sources"] = {str(k): v for k, v in sources.items()}
        self.server.stdin.write(json.dumps(request) + "\n")
        self.server.stdin.flush()
        line = self.server.stdout.readline()
        self.assertTrue(line, "server stopped before replying")
        reply = json.loads(line)
        self.assertEqual(reply["id"], self.sequence)
        self.assertEqual(reply["ok"], success, reply)
        return reply["result"] if success else reply

    def run_output(self, expected):
        result = subprocess.run([NODE, str(ROOT / "scripts/run_wasm.mjs"), str(self.output)],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)


class CompilerSession(SessionHarness):
    def test_overlays_cache_isolation_errors_and_removal(self):
        first = self.request()
        pid = first["compiler_worker_pid"]
        self.run_output("41\n")
        overlay = self.request(sources={self.helper: 'fn value() -> i64 { 42 }\n'})
        self.assertEqual(overlay["compiler_worker_pid"], pid)
        self.assertTrue(overlay["compiler_process_reused"])
        self.assertEqual(overlay["cache"], "disabled")
        self.assertFalse(overlay["cache_stored"])
        self.assertEqual(overlay["backend_stats"]["parsed_files"], 2)
        self.assertEqual(overlay["backend_stats"]["parsed_cache_hits"], 0)
        self.assertFalse(overlay["backend_stats"]["frontend_reused"])
        self.run_output("42\n")
        prior = self.output.read_bytes()
        bad = self.request(sources={self.helper: 'fn value() -> i64 { "bad\\q" }\n'}, success=False)
        self.assertIn("helper.goose", bad["error"])
        self.assertEqual(self.output.read_bytes(), prior)
        fixed = self.request(sources={self.helper: '\ufefffn value() -> i64 { 43 }\n'})
        self.assertEqual(fixed["compiler_worker_pid"], pid)
        self.run_output("43\n")
        restored = self.request()  # No implicit carry-over of the last overlay.
        self.assertEqual(restored["cache"], "hit")
        self.run_output("41\n")
        self.assertEqual(self.helper.read_text(), 'fn value() -> i64 { 41 }\n')
        self.helper.write_text('fn value() -> i64 { 44 }\n')
        edited = self.request()
        self.assertEqual(edited["compiler_worker_pid"], pid)
        self.assertEqual(edited["cache"], "miss")
        self.run_output("44\n")

    def test_fresh_compiler_equivalence_and_alternating_options(self):
        pid = None
        for level, debug, initial, maximum in ((0, False, 1, 8), (2, True, 2, 16), (0, False, 1, 8)):
            extra = [f"-O{level}", "--initial-pages", str(initial), "--maximum-pages", str(maximum), "--no-cache"]
            if debug:
                extra.append("--debug")
            report = self.request(extra=extra)
            if pid is None:
                pid = report["compiler_worker_pid"]
            self.assertEqual(report["compiler_worker_pid"], pid)
            fresh = self.work / "fresh.wasm"
            command = [str(GOOSE), str(self.source), "--target", "wasm-direct", "--offline", f"-O{level}",
                       "--wasm-initial-pages", str(initial), "--wasm-max-pages", str(maximum), "-o", str(fresh)]
            if debug:
                command += ["-D", "GS_DEBUG=1"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.output.read_bytes(), fresh.read_bytes())
        alternate = self.work / "other.goose"
        alternate.write_text('fn main() { print(99); }\n')
        report = self.request(source=alternate, extra=["--no-cache"])
        self.assertEqual(report["compiler_worker_pid"], pid)
        self.run_output("99\n")
        self.request(extra=["--no-cache"])
        self.run_output("41\n")

    def test_root_overlays_dependency_graph_and_semantic_recovery(self):
        disk = self.source.read_text()
        root_only = self.request(sources={self.source: 'fn main() { print(88); }\n'})
        self.assertEqual(root_only["backend_stats"]["source_files"], 1)
        self.run_output("88\n")
        graph = self.request(sources={self.source: 'import helper; fn main() { print(value() + 1); }\n',
                                      self.helper: 'fn value() -> i64 { 42 }\n'})
        self.assertEqual(graph["backend_stats"]["source_files"], 2)
        self.run_output("43\n")
        previous = self.output.read_bytes()
        semantic = self.request(sources={self.source: 'fn main() { print(missing); }\n'}, success=False)
        self.assertIn("missing", semantic["error"])
        self.assertEqual(self.output.read_bytes(), previous)
        backend = self.request(sources={self.source: 'extern fn foreign(values: i64[:]) -> i64; fn main() { var xs = [1, 2]; print(foreign(xs[..])); }\n'},
                               success=False)
        self.assertIn("wasm-direct", backend["error"])
        self.assertEqual(self.output.read_bytes(), previous)
        growable = self.request(sources={self.source: 'fn main() { var xs: i64[>..] = []; xs.push(1); print(xs); }\n'})
        self.assertEqual(growable["backend_stats"]["region_count"], 1)
        self.run_output("[1]\n")
        returned = self.request(sources={self.source: 'fn make(n: i64) -> i64[>..] { return [n, n + 1]; } fn main() { let a = make(3); let b = make(7); print(a, " ", b); }\n'})
        self.assertEqual(returned["backend_stats"]["region_count"], 2)
        self.run_output("[3, 4] [7, 8]\n")
        arguments = self.request(sources={self.source: 'fn count(xs: i64[>..]) -> i64 { xs.push(9); return xs.len; } fn main() { print(count([1]), " ", count([2])); }\n'})
        self.assertEqual(arguments["backend_stats"]["region_count"], 1)
        self.run_output("2 2\n")
        multiple = self.request(sources={self.source: 'fn make(n: i64) -> i64[>..], i64[2], i64[>..] { var xs: i64[>..] = [n]; return xs, [1, 2], [n + 1]; } fn main() { let a, b, c = make(3); print(a, " ", b, " ", c); }\n'})
        self.assertEqual(multiple["backend_stats"]["region_count"], 2)
        self.run_output("[3] [1, 2] [4]\n")
        controlled = self.request(sources={self.source: 'fn main() { let xs: i64[>..] = loop { var local: i64[>..] = [1]; break copy(local); }; print(xs); }\n'})
        self.assertEqual(controlled["backend_stats"]["region_count"], 2)
        self.run_output("[1]\n")
        assigned = self.request(sources={self.source: 'fn main() { var xs: i64[>..] = [1]; xs = [2, 3]; print(xs); }\n'})
        self.assertEqual(assigned["backend_stats"]["region_count"], 1)
        self.run_output("[2, 3]\n")
        restored = self.request()
        self.assertEqual(restored["compiler_worker_pid"], root_only["compiler_worker_pid"])
        self.run_output("41\n")
        self.assertEqual(self.source.read_text(), disk)

    def test_stats_cannot_overwrite_imports_on_misses_or_hits(self):
        original = self.helper.read_bytes()
        for extra in (["--no-cache"], [], []):
            self.request(extra=extra)
            output = self.output.read_bytes()
            failure = self.request(extra=[*extra, "--stats", str(self.helper)], success=False)
            self.assertIn("source dependency", failure["error"])
            self.assertEqual(self.helper.read_bytes(), original)
            self.assertEqual(self.output.read_bytes(), output)

    def test_lexical_reuse_and_import_edit(self):
        cold = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertTrue(cold["lexical_cache_enabled"])
        self.assertEqual(cold["scanned_source_files"], 2)
        self.assertEqual(cold["lexical_reused_tokens"], 0)
        baseline = self.output.read_bytes()
        warm = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(warm["scanned_source_files"], 0)
        self.assertEqual(warm["lexical_scanned_tokens"], 0)
        self.assertEqual(warm["lexical_reused_files"], 2)
        self.assertGreater(warm["lexical_reused_tokens"], 0)
        self.assertEqual(self.output.read_bytes(), baseline)
        edited = self.request(sources={self.helper: 'fn value() -> i64 { 42 }\n'})["backend_stats"]
        self.assertEqual(edited["scanned_source_files"], 1)
        self.assertEqual(edited["lexical_reused_files"], 1)
        self.assertEqual(edited["parsed_files"], 2)
        self.assertEqual(edited["parsed_cache_hits"], 0)
        self.assertFalse(edited["frontend_reused"])
        self.run_output("42\n")
        restored = self.request(extra=["--no-cache"])["backend_stats"]
        self.assertEqual(restored["scanned_source_files"], 1)
        self.assertEqual(restored["lexical_reused_files"], 1)
        self.run_output("41\n")

    def test_cached_errors_match_cold_diagnostics(self):
        cases = [
            'fn main() { "bad\\q"; }\nfn later() -> i64 { 4 }\n',
            'fn main() { let x = """\n  wrong\n    """; }\nfn later() {}\n',
            'fn main() { let x = ; { } }\nfn later( { }\n',
            'fn main() { /* unterminated\n',
            'fn main() { print(missing); }\n',
        ]
        for text in cases:
            with self.subTest(text=text):
                overlays = {self.source: text}
                first = self.request(sources=overlays, success=False)
                second = self.request(sources=overlays, success=False)
                self.assertEqual(first["error"], second["error"])
                # A new process has no transitions from the erroneous parse.
                fresh = self.work / "error.wasm"
                payload = {"source": str(self.source), "output": str(fresh), "offline": True,
                           "sources": {str(k): v for k, v in overlays.items()}}
                cold = subprocess.run([str(GOOSE), "--wasm-session"], input=json.dumps(payload) + "\n",
                                      capture_output=True, text=True, timeout=60)
                reply = json.loads(cold.stdout)
                self.assertFalse(reply["ok"], reply)
                self.assertEqual(second["error"], "native compiler worker failed:\n" + reply["error"])
        self.request(extra=["--no-cache"])
        self.run_output("41\n")

    @unittest.skipIf(os.name == "nt", "POSIX executable wrappers and process signals")
    def test_worker_failure_and_changed_compiler_restart(self):
        wrapper = self.work / "compiler"
        contents = (f"#!{sys.executable}\nimport os, sys\n"
                    f"os.execv({str(GOOSE)!r}, [{str(GOOSE)!r}, *sys.argv[1:]])\n")
        wrapper.write_text(contents)
        wrapper.chmod(0o755)
        first = self.request(compiler=wrapper, extra=["--no-cache"])
        pid = first["compiler_worker_pid"]
        replacement = self.work / "replacement"
        replacement.write_text(contents + "# new compiler identity\n")
        replacement.chmod(0o755)
        replacement.replace(wrapper)
        second = self.request(compiler=wrapper, extra=["--no-cache"])
        self.assertNotEqual(second["compiler_worker_pid"], pid)
        self.assertFalse(second["compiler_process_reused"])
        self.assertNotEqual(second["compiler_sha256"], first["compiler_sha256"])
        old_output = self.output.read_bytes()
        os.kill(second["compiler_worker_pid"], signal.SIGKILL)
        # poll() may observe the death immediately; otherwise the interrupted
        # request reports an error and the following request starts a worker.
        self.sequence += 1
        request = {"id": self.sequence, "args": ["build", str(self.source), "--goose", str(wrapper),
                   "--offline", "--no-cache", "-o", str(self.output)]}
        self.server.stdin.write(json.dumps(request) + "\n"); self.server.stdin.flush()
        reply = json.loads(self.server.stdout.readline())
        if not reply["ok"]:
            self.assertEqual(self.output.read_bytes(), old_output)
        recovered = self.request(compiler=wrapper, extra=["--no-cache"])
        self.assertNotEqual(recovered["compiler_worker_pid"], second["compiler_worker_pid"])
        self.run_output("41\n")

    def test_native_protocol_recovers_and_protects_inputs(self):
        process = subprocess.Popen([str(GOOSE), "--wasm-session"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        base = {"id": "build", "source": str(self.source), "output": str(self.output), "offline": True}
        requests = ["{", '{"id":1e309}', json.dumps(base), json.dumps({**base, "output": str(self.helper)}),
                    json.dumps({**base, "initial_pages": 1.5}),
                    json.dumps({**base, "initial_pages": 2, "maximum_pages": 1}),
                    json.dumps({**base, "sources": {str(self.work / 'missing.goose'): 'fn main() {}'}}),
                    json.dumps({**base, "source": str(self.source) + '\0ignored'}),
                    json.dumps({**base, "output": str(self.helper) + '\0ignored'}),
                    json.dumps({**base, "id": 9007199254740991}),
                    json.dumps(base)]
        output, errors = process.communicate("\n".join(requests) + "\n", timeout=60)
        self.assertEqual(process.returncode, 0, errors)
        replies = [json.loads(line) for line in output.splitlines()]
        self.assertEqual([r["ok"] for r in replies], [False, False, True, False, False, False, False, False, False, True, True])
        self.assertEqual(replies[-2]["id"], 9007199254740991)
        self.assertEqual(self.helper.read_text(), 'fn value() -> i64 { 41 }\n')
        self.run_output("41\n")

    @unittest.skipIf(os.name == "nt", "POSIX source link aliases")
    def test_symlink_overlays_retargeting_and_alias_output_protection(self):
        target = self.work / "target.goose"
        self.helper.rename(target)
        self.helper.symlink_to(target)
        baseline = self.request()
        overlaid = self.request(sources={target: 'fn value() -> i64 { 42 }\n'})
        self.assertEqual(overlaid["compiler_worker_pid"], baseline["compiler_worker_pid"])
        self.run_output("42\n")
        other = self.work / "other.goose"
        other.write_text('fn value() -> i64 { 43 }\n')
        self.helper.unlink(); self.helper.symlink_to(other)
        disk = self.request()
        self.assertEqual(disk["compiler_worker_pid"], baseline["compiler_worker_pid"])
        self.run_output("43\n")
        alias = self.work / "alias.wasm"
        alias.symlink_to(target)
        hardlink = self.work / "hardlink.wasm"
        os.link(other, hardlink)
        process = subprocess.Popen([str(GOOSE), "--wasm-session"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        messages = [{"source": str(self.source), "output": str(path), "offline": True,
                     "sources": {str(target): 'fn value() -> i64 { 99 }\n'}} for path in (alias, hardlink)]
        output, errors = process.communicate("\n".join(json.dumps(m) for m in messages) + "\n", timeout=60)
        self.assertEqual(process.returncode, 0, errors)
        self.assertEqual([json.loads(line)["ok"] for line in output.splitlines()], [False, False])
        self.assertEqual(target.read_text(), 'fn value() -> i64 { 41 }\n')
        self.assertEqual(other.read_text(), 'fn value() -> i64 { 43 }\n')

    def test_qualified_fixture_modules_match_fresh_compilers(self):
        from run_differential import cases
        fixtures = sorted({(case.fixture, case.debug) for case in cases()})
        for fixture, debug in fixtures:
            for level in (0, 2):
                with self.subTest(fixture=fixture, debug=debug, level=level):
                    source = ROOT / "tests/fixtures" / (fixture + ".goose")
                    extra = [f"-O{level}", "--no-cache", *(["--debug"] if debug else [])]
                    self.request(source=source, extra=extra)
                    fresh = self.work / "fresh.wasm"
                    command = [str(GOOSE), str(source), "--target", "wasm-direct", "--offline",
                               f"-O{level}", "-o", str(fresh), *(["-D", "GS_DEBUG=1"] if debug else [])]
                    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(self.output.read_bytes(), fresh.read_bytes())
                    self.request(source=source, extra=extra)
                    self.assertEqual(self.output.read_bytes(), fresh.read_bytes())

    @unittest.skipUnless(Path("/proc/self/statm").exists(), "Linux RSS measurement")
    def test_repeated_frontends_release_owned_state(self):
        self.source.write_text("\n".join(f"fn unused{i}() -> i64 {{ {i} }}" for i in range(5000)) +
                               '\nfn main() { print(41); }\n')
        rss = []
        digest = None
        pid = None
        for i in range(35):
            result = self.request(extra=["--no-cache"])
            pid = result["compiler_worker_pid"] if pid is None else pid
            self.assertEqual(result["compiler_worker_pid"], pid)
            actual = hashlib.sha256(self.output.read_bytes()).hexdigest()
            digest = actual if digest is None else digest
            self.assertEqual(actual, digest)
            self.assertFalse(result["backend_stats"]["frontend_reused"])
            rss.append(int(Path(f"/proc/{pid}/statm").read_text().split()[1]) * os.sysconf("SC_PAGE_SIZE"))
        self.assertLess(max(rss[5:]), max(rss[:5]) + 64 * 1024 * 1024, rss)
        self.run_output("41\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--node", default=NODE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    NODE = args.node
    unittest.main(argv=[sys.argv[0], *remaining])
