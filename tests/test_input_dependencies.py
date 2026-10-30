#!/usr/bin/env python3
"""Configuration reads, negative module probes, and cache publication races."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts/goose_wasm.py"
GOOSE = ROOT / "build/bin/goose"
spec = importlib.util.spec_from_file_location("goose_driver", DRIVER)
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class SnapshotObservations(unittest.TestCase):
    def test_reads_probes_duplicates_and_incomplete_transcripts(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temp:
            work = Path(temp)
            source, config, missing = (work / n for n in ("main.goose", "main.build", "absent.goose"))
            source.write_text("fn main() {}")
            config.write_text("")
            transcript = [{"path": str(source), "text": source.read_text()},
                          {"path": str(config), "kind": "build", "exists": True,
                           "text": "", "complete": True},
                          {"path": str(missing), "kind": "probe", "exists": False}]
            snapshot, ok = driver.dependency_snapshot(transcript, [work])
            self.assertTrue(ok)
            self.assertTrue(driver.valid_dependencies(snapshot))
            self.assertFalse(driver.dependency_snapshot(transcript[:1], [work])[1])
            incomplete = [*transcript, {**transcript[1], "complete": False}]
            self.assertFalse(driver.dependency_snapshot(incomplete, [work])[1])
            conflicting = [*transcript, {**transcript[1], "text": "# another read"}, transcript[1]]
            self.assertFalse(driver.dependency_snapshot(conflicting, [work])[1])
            self.assertFalse(driver.dependency_snapshot([*transcript, {**transcript[2], "exists": True}], [work])[1])
            missing.write_text("fn value() {}")
            self.assertFalse(driver.valid_dependencies(snapshot))
            missing.unlink()
            config.write_text("# edit")
            self.assertFalse(driver.valid_dependencies(snapshot))

    def test_failed_read_requires_real_absence(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temp:
            work = Path(temp)
            config = work / "main.build"
            record = {"path": str(config), "kind": "build", "exists": False, "complete": True}
            snapshot, ok = driver.dependency_snapshot([record], [work])
            self.assertTrue(ok)
            config.mkdir()
            self.assertFalse(driver.dependency_snapshot([record], [work])[1])
            self.assertFalse(driver.valid_dependencies(snapshot))
            config.rmdir()
            config.symlink_to("missing-target")
            self.assertFalse(driver.dependency_snapshot([record], [work])[1])


class InputCases:
    WORKER = False

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.source = self.work / "main.goose"
        self.config = self.work / "main.build"
        self.source.write_text("fn main() { print(3); }\n")
        self.output = self.work / "out.wasm"
        self.sequence = 0
        self.env = dict(os.environ)
        if self.WORKER:
            self.log = tempfile.TemporaryFile(mode="w+t")
            self.addCleanup(self.log.close)
            self.start()
            self.addCleanup(self.stop)

    def start(self):
        self.server = subprocess.Popen([sys.executable, str(DRIVER), "serve", "--native-worker", "--syntax-cache"],
                                       text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log,
                                       env=self.env)

    def stop(self):
        self.server.stdin.close()
        self.server.wait(timeout=15)
        self.server.stdout.close()

    def build(self, extra=(), success=True, compiler=None):
        args = ["build", str(self.source), "--goose", str(compiler or GOOSE), "--offline",
                "--cache-dir", str(self.work / "cache"), "-o", str(self.output), "--json", *extra]
        if self.WORKER:
            self.sequence += 1
            self.server.stdin.write(json.dumps({"id": self.sequence, "args": args}) + "\n")
            self.server.stdin.flush()
            reply = json.loads(self.server.stdout.readline())
            self.assertEqual(reply["ok"], success, reply)
            return reply["result"] if success else reply["error"]
        result = subprocess.run([sys.executable, str(DRIVER), *args], text=True, capture_output=True, timeout=90,
                                env=self.env)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return json.loads(result.stdout) if success else result.stderr

    def test_missing_empty_invalid_and_bom_sidecars(self):
        self.assertTrue(self.build()["cache_stored"])
        self.assertEqual(self.build()["cache"], "hit")
        self.config.write_text("")
        self.assertEqual(self.build()["cache"], "miss")
        self.assertEqual(self.build()["cache"], "hit")
        previous = self.output.read_bytes()
        self.config.write_text("this is not a valid build file;")
        self.assertIn("expected", self.build(success=False))
        self.assertEqual(self.output.read_bytes(), previous)
        self.config.write_bytes(b"\xef\xbb\xbf")
        self.assertEqual(self.build()["cache"], "hit")
        self.config.unlink()
        self.assertEqual(self.build()["cache"], "miss")
        self.assertEqual(self.build()["cache"], "hit")

    def test_imported_sidecar_edit_and_same_mtime(self):
        package = self.work / "helper"
        package.mkdir()
        (package / "helper.goose").write_text("fn value() -> i64 { 4 }\n")
        config = package / "helper.build"
        config.write_text("//first")
        self.source.write_text('import helper from "./helper"; fn main() { print(value()); }\n')
        self.build()
        self.assertEqual(self.build()["cache"], "hit")
        st = config.stat()
        config.write_text("//other")
        os.utime(config, ns=(st.st_atime_ns, st.st_mtime_ns))
        self.assertEqual(self.build()["cache"], "miss")
        config.write_text("invalid sidecar syntax;")
        self.build(success=False)

    def test_sidecar_symlink_retarget(self):
        first, second = self.work / "first.txt", self.work / "second.txt"
        first.write_text("")
        second.write_text("invalid build file;")
        self.config.symlink_to(first.name)
        self.build()
        self.assertEqual(self.build()["cache"], "hit")
        self.config.unlink()
        self.config.symlink_to(second.name)
        self.build(success=False)

    def test_cyclic_sidecar_and_import_probe_compile_without_retention(self):
        self.config.symlink_to(self.config.name)
        for _ in range(2):
            self.assertFalse(self.build()["cache_stored"])
        fallback = self.work / "fallback"
        fallback.mkdir()
        (fallback / "helper.goose").write_text("fn value() -> i64 { 5 }\n")
        self.source.write_text("import helper; fn main() { print(value()); }\n")
        candidate = self.work / "helper.goose"
        candidate.symlink_to(candidate.name)
        for _ in range(2):
            self.assertFalse(self.build(["--stdlib", str(fallback)])["cache_stored"])
        self.config.unlink()
        candidate.unlink()
        self.assertTrue(self.build(["--stdlib", str(fallback)])["cache_stored"])

    def test_symlink_parent_components_watch_the_actual_import(self):
        search = self.work / "search"
        external = self.work / "external"
        search.mkdir()
        (external / "subdir").mkdir(parents=True)
        (search / "link").symlink_to(external / "subdir", target_is_directory=True)
        actual, decoy = external / "helper.goose", search / "helper.goose"
        actual.write_text("fn value() -> i64 { 4 }\n")
        decoy.write_bytes(actual.read_bytes())
        self.env["GOOSE_STDLIB"] = str(search / "link" / "..")
        if self.WORKER:
            self.stop()
            self.start()
        self.source.write_text("import helper; fn main() { print(value()); }\n")
        first = self.build()
        self.assertTrue(first["cache_stored"])
        self.assertEqual(self.build()["cache"], "hit")
        st = actual.stat()
        actual.write_text("fn value() -> i64 { 5 }\n")
        os.utime(actual, ns=(st.st_atime_ns, st.st_mtime_ns))
        changed = self.build()
        self.assertEqual(changed["cache"], "miss")
        self.assertNotEqual(first["module_sha256"], changed["module_sha256"])
        self.assertEqual(decoy.read_text(), "fn value() -> i64 { 4 }\n")

    def test_stats_cannot_create_or_replace_a_traced_input(self):
        for exists in (False, True):
            if exists:
                self.config.write_text("")
            self.build()
            previous = self.output.read_bytes()
            for flags in ([], ["--no-cache"]):
                self.assertIn("source dependency", self.build([*flags, "--stats", str(self.config)], success=False))
                self.assertEqual(self.config.exists(), exists)
                if exists:
                    self.assertEqual(self.config.read_bytes(), b"")
                self.assertEqual(self.output.read_bytes(), previous)
        fallback = self.work / "fallback"
        fallback.mkdir()
        (fallback / "helper.goose").write_text("fn value() -> i64 { 5 }\n")
        self.source.write_text("import helper; fn main() { print(value()); }\n")
        candidate = self.work / "helper.goose"
        self.build(["--stdlib", str(fallback)])
        for flags in ([], ["--no-cache"]):
            self.assertIn("source dependency", self.build(["--stdlib", str(fallback), *flags,
                                                         "--stats", str(candidate)], success=False))
            self.assertFalse(candidate.exists())

    def test_unused_embedded_input_disables_artifact_storage(self):
        data = self.work / "data.txt"
        data.write_text("abc")
        self.source.write_text('fn unused() { let bytes = embed_file("data.txt"); } fn main() { print(3); }\n')
        for _ in range(2):
            report = self.build()
            self.assertEqual(report["cache"], "miss")
            self.assertFalse(report["cache_stored"])
        data.unlink()
        self.assertIn("embed_file", self.build(success=False))

    def test_package_wide_extern_scan_disables_artifact_storage(self):
        package = self.work / "helper"
        package.mkdir()
        (package / "helper.goose").write_text("fn value() -> i64 { 4 }\n")
        extra = package / "optional.goose"
        extra.write_text('extern "extra" { fn foreign() -> i32; }\n')
        (package / "helper.build").write_text('dylibs = ["extra=liboptional"];\n')
        self.source.write_text('import helper from "./helper"; fn main() { print(value()); }\n')
        for _ in range(2):
            report = self.build()
            self.assertEqual(report["cache"], "miss")
            self.assertFalse(report["cache_stored"])
        extra.write_text("// no extern declarations\n")
        self.assertIn("no extern block", self.build(success=False))


class DirectInputs(InputCases, unittest.TestCase):
    def wrapper(self, before, after):
        wrapper = self.work / "compiler-wrapper"
        wrapper.write_text(f"#!{sys.executable}\nimport subprocess, sys\nfrom pathlib import Path\n"
                           f"{before}\ntry:\n    result = subprocess.run([{str(GOOSE)!r}, *sys.argv[1:]])\n"
                           f"finally:\n    {after}\nsys.exit(result.returncode)\n")
        wrapper.chmod(0o755)
        return wrapper

    def test_compile_configuration_then_restore_prior_bytes_is_not_cached(self):
        self.config.write_text("//before")
        wrapper = self.wrapper(f"Path({str(self.config)!r}).write_text('//during')",
                               f"Path({str(self.config)!r}).write_text('//before')")
        for _ in range(2):
            report = self.build(compiler=wrapper)
            self.assertFalse(report["cache_stored"])
            self.assertEqual(report["cache"], "miss")
        self.assertEqual(self.config.read_text(), "//before")

    def test_shadow_created_after_module_selection_is_not_cached(self):
        fallback = self.work / "fallback"
        fallback.mkdir()
        (fallback / "helper.goose").write_text("fn value() -> i64 { 3 }\n")
        self.source.write_text("import helper; fn main() { print(value()); }\n")
        shadow = self.work / "helper.goose"
        wrapper = self.wrapper("pass", f"Path({str(shadow)!r}).write_text('fn value() -> i64 {{ 9 }}')")
        first = self.build(["--stdlib", str(fallback)], compiler=wrapper)
        self.assertFalse(first["cache_stored"])
        second = self.build(["--stdlib", str(fallback)], compiler=wrapper)
        self.assertEqual(second["cache"], "miss")
        self.assertNotEqual(first["module_sha256"], second["module_sha256"])

    def test_raw_worker_cannot_overwrite_configuration_or_missing_probe(self):
        fallback = self.work / "fallback"
        fallback.mkdir()
        (fallback / "helper.goose").write_text("fn value() -> i64 { 3 }\n")
        self.source.write_text("import helper; fn main() { print(value()); }\n")
        candidate = self.work / "helper.goose"
        for target in (self.config, candidate):
            payload = {"source": str(self.source), "output": str(target), "stdlib": str(fallback), "offline": True}
            result = subprocess.run([str(GOOSE), "--wasm-session"], input=json.dumps(payload) + "\n",
                                    text=True, capture_output=True, timeout=60)
            reply = json.loads(result.stdout)
            self.assertFalse(reply["ok"], reply)
            self.assertIn("source input", reply["error"])
            self.assertFalse(target.exists())

    def test_raw_worker_protects_imports_and_missing_probes_through_symlink_parent_components(self):
        external, search = self.work / "external", self.work / "search"
        (external / "subdir").mkdir(parents=True)
        search.mkdir()
        (search / "link").symlink_to(external / "subdir", target_is_directory=True)
        imported = external / "helper.goose"
        imported.write_text("fn value() -> i64 { 3 }\n")
        original = imported.read_bytes()
        self.source.write_text("import helper; fn main() { print(value()); }\n")
        payload = {"source": str(self.source), "output": str(imported),
                   "stdlib": str(search / "link" / ".."), "offline": True}
        result = subprocess.run([str(GOOSE), "--wasm-session"], input=json.dumps(payload) + "\n",
                                text=True, capture_output=True, timeout=60)
        reply = json.loads(result.stdout)
        self.assertFalse(reply["ok"], reply)
        self.assertIn("source input", reply["error"])
        self.assertEqual(imported.read_bytes(), original)
        imported.unlink()
        fallback = self.work / "fallback"
        fallback.mkdir()
        (fallback / "helper.goose").write_bytes(original)
        env = dict(os.environ, GOOSE_STDLIB=str(fallback))
        result = subprocess.run([str(GOOSE), "--wasm-session"], input=json.dumps(payload) + "\n",
                                text=True, capture_output=True, timeout=60, env=env)
        reply = json.loads(result.stdout)
        self.assertFalse(reply["ok"], reply)
        self.assertIn("source input", reply["error"])
        self.assertFalse(imported.exists())


class WorkerInputs(InputCases, unittest.TestCase):
    WORKER = True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
