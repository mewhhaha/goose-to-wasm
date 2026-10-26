#!/usr/bin/env python3
"""Exercise managed-source refresh and preservation without downloading tools."""

import argparse
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("goose_bootstrap", ROOT / "scripts" / "bootstrap.py")
BOOTSTRAP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BOOTSTRAP)


def git(directory, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=directory, stderr=subprocess.PIPE)


class ManagedSource(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.upstream = self.root / "upstream"
        self.integration = self.root / "integration"
        self.build = self.root / "build"
        for directory in (self.upstream, self.integration, self.build):
            directory.mkdir()
        runtime = self.upstream / "src" / "runtime"
        runtime.mkdir(parents=True)
        for name in BOOTSTRAP.RUNTIME_FILES:
            (runtime / name).write_text("/* runtime */\n")
        (self.upstream / "src" / "main.cpp").write_text("base\n")
        git(self.upstream, "init", "--quiet")
        git(self.upstream, "add", ".")
        git(self.upstream, "-c", "user.name=Bootstrap test", "-c", "user.email=test@example.invalid",
            "commit", "--quiet", "-m", "fixture")
        revision = git(self.upstream, "rev-parse", "HEAD").decode().strip()
        (self.integration / "patches").mkdir()
        (self.upstream / "src" / "main.cpp").write_text("checked\n")
        (self.integration / "patches" / "oracle.patch").write_bytes(git(self.upstream, "diff"))
        git(self.upstream, "add", ".")
        git(self.upstream, "-c", "user.name=Bootstrap test", "-c", "user.email=test@example.invalid",
            "commit", "--quiet", "-m", "oracle fixture")
        (self.upstream / "src" / "main.cpp").write_text("direct\n")
        self.patch = self.integration / "patches" / "direct.patch"
        self.patch.write_bytes(git(self.upstream, "diff"))
        (self.integration / "compiler").mkdir()
        self.header = self.integration / "compiler" / "direct_wasm.h"
        self.header.write_text("// first backend\n")
        self.original_root = BOOTSTRAP.ROOT
        self.original_pin = BOOTSTRAP.PIN
        BOOTSTRAP.ROOT = self.integration
        BOOTSTRAP.PIN = {
            "revision": revision, "repository": str(self.upstream),
            "patches": ["patches/oracle.patch", "patches/direct.patch"],
        }
        self.args = argparse.Namespace(without_direct=False, source_repo=self.upstream)

    def tearDown(self):
        BOOTSTRAP.ROOT = self.original_root
        BOOTSTRAP.PIN = self.original_pin
        self.temporary.cleanup()

    def prepare(self):
        with redirect_stdout(io.StringIO()):
            return BOOTSTRAP.prepare_source(self.args, self.build)

    def test_unchanged_inputs_reuse_the_checkout(self):
        source, identity = self.prepare()
        inode = source.stat().st_ino
        again, repeated = self.prepare()
        self.assertEqual(inode, again.stat().st_ino)
        self.assertEqual(identity, repeated)
        self.assertEqual((source / "src" / "main.cpp").read_text(), "direct\n")
        state = json.loads((self.build / "source.json").read_text())
        self.assertEqual(state["source_diff_sha256"], BOOTSTRAP.source_fingerprint(source))

    def test_changed_backend_refreshes_only_managed_content(self):
        source, _ = self.prepare()
        old_time = (source / "src" / "main.cpp").stat().st_mtime_ns
        self.header.write_text("// changed backend\n")
        updated, identity = self.prepare()
        self.assertEqual((updated / "src" / "direct_wasm.h").read_text(), self.header.read_text())
        self.assertEqual((updated / "src" / "main.cpp").stat().st_mtime_ns, old_time)
        self.assertEqual(identity["headers"]["direct_wasm.h"], BOOTSTRAP.digest(self.header))

    def test_manual_tracked_edit_is_preserved(self):
        source, _ = self.prepare()
        file = source / "src" / "main.cpp"
        file.write_text("user edit\n")
        with self.assertRaisesRegex(RuntimeError, "managed source has local edits"):
            self.prepare()
        self.assertEqual(file.read_text(), "user edit\n")

    def test_manual_copied_header_edit_is_preserved(self):
        source, _ = self.prepare()
        file = source / "src" / "direct_wasm.h"
        file.write_text("user backend edit\n")
        with self.assertRaisesRegex(RuntimeError, "managed source has local edits"):
            self.prepare()
        self.assertEqual(file.read_text(), "user backend edit\n")

    def test_invalid_new_patch_leaves_last_checkout_intact(self):
        source, _ = self.prepare()
        original = BOOTSTRAP.source_fingerprint(source)
        stamp = (self.build / "source.json").read_bytes()
        self.patch.write_text("not a patch\n")
        with self.assertRaises(subprocess.CalledProcessError):
            self.prepare()
        self.assertEqual(BOOTSTRAP.source_fingerprint(source), original)
        self.assertEqual((self.build / "source.json").read_bytes(), stamp)


if __name__ == "__main__":
    unittest.main()
