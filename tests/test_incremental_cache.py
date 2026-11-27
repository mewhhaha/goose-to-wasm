#!/usr/bin/env python3
"""Tests for goosew --cache-dir content-addressed incremental build caching."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew")).resolve()
STDLIB = ROOT / "stdlib"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class IncrementalCache(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="goosew_cache_test_")
        self.addCleanup(self._tmp.cleanup)
        self.work = Path(self._tmp.name)
        self.cache = self.work / "cache"
        (self.work / "main.goose").write_text(
            "import helper;\n"
            "fn main() { print(helper::val()); }\n"
        )
        (self.work / "helper.goose").write_text(
            "namespace helper;\n"
            "fn val() -> i64 { return 42; }\n"
        )

    def run_goose(self, *args, cwd=None):
        cmd = [str(COMPILER), "--stdlib", str(STDLIB), *args]
        return subprocess.run(
            cmd,
            cwd=str(cwd or self.work),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )

    def test_wasm_hit_bit_identical_and_preserves_mtime(self):
        out_plain = self.work / "plain.wasm"
        out_cached = self.work / "cached.wasm"
        stats_miss = self.work / "miss.json"
        stats_hit = self.work / "hit.json"

        r0 = self.run_goose("main.goose", "-O0", "-o", str(out_plain))
        self.assertEqual(r0.returncode, 0, r0.stderr)

        r1 = self.run_goose(
            "main.goose", "-O0", "-o", str(out_cached),
            "--cache-dir", str(self.cache),
            "--wasm-stats", str(stats_miss),
        )
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertEqual(out_cached.read_bytes(), out_plain.read_bytes())
        st1 = json.loads(stats_miss.read_text())
        self.assertTrue(st1.get("cache_complete"))
        self.assertFalse(st1.get("cache_hit"))

        # Verify manifest & blob SHA-256 match Python hashlib.sha256.
        expected_blob_hex = hashlib.sha256(out_cached.read_bytes()).hexdigest()
        blob_file = self.cache / f"b_{expected_blob_hex}.bin"
        self.assertTrue(blob_file.is_file(), f"missing blob {blob_file}")
        self.assertEqual(blob_file.read_bytes(), out_cached.read_bytes())

        # Backdate output mtime to verify unchanged hit does not touch it.
        old_time = time.time() - 60.0
        os.utime(out_cached, (old_time, old_time))
        mtime_before = out_cached.stat().st_mtime_ns

        r2 = self.run_goose(
            "main.goose", "-O0", "-o", str(out_cached),
            f"--cache-dir={self.cache}",
            "--wasm-stats", str(stats_hit),
        )
        self.assertEqual(r2.returncode, 0, r2.stderr)
        st2 = json.loads(stats_hit.read_text())
        self.assertTrue(st2.get("cache_complete"))
        self.assertTrue(st2.get("cache_hit"))
        self.assertEqual(out_cached.stat().st_mtime_ns, mtime_before)
        self.assertEqual(out_cached.read_bytes(), out_plain.read_bytes())

        # Different output path still hits cache and writes bit-identical artifact.
        out_other = self.work / "other.wasm"
        r3 = self.run_goose(
            "main.goose", "-O0", "-o", str(out_other),
            "--cache-dir", str(self.cache),
            "--wasm-stats", str(stats_hit),
        )
        self.assertEqual(r3.returncode, 0, r3.stderr)
        self.assertTrue(json.loads(stats_hit.read_text()).get("cache_hit"))
        self.assertEqual(out_other.read_bytes(), out_plain.read_bytes())

    def test_same_size_same_mtime_edit_invalidates(self):
        out = self.work / "app.wasm"
        stats = self.work / "st.json"
        r1 = self.run_goose("main.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r1.returncode, 0, r1.stderr)
        first_bytes = out.read_bytes()

        # Edit helper.goose keeping exact byte length AND restoring exact mtime!
        helper = self.work / "helper.goose"
        st_orig = helper.stat()
        old_text = helper.read_text()
        new_text = old_text.replace("42", "99")
        self.assertEqual(len(old_text), len(new_text))
        helper.write_text(new_text)
        os.utime(helper, ns=(st_orig.st_atime_ns, st_orig.st_mtime_ns))

        r2 = self.run_goose("main.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
        self.assertNotEqual(out.read_bytes(), first_bytes)

    def test_shadowing_module_invalidates_negative_probe(self):
        # Program imports stdlib `base64` (absent locally at first), tested under --jobs 1 and --jobs 8.
        (self.work / "shadow_main.goose").write_text(
            "import base64;\n"
            "import helper;\n"
            "fn main() { var out: u8[>..] = []; base64::encode(out, \"hi\"); print(out.len + helper::val()); }\n"
        )
        out = self.work / "shadow.wasm"
        stats = self.work / "st.json"
        for jobs in ("1", "8"):
            cache_dir = self.work / f"cache_j{jobs}"
            shadow_file = self.work / "base64.goose"
            if shadow_file.exists():
                shadow_file.unlink()
            r1 = self.run_goose(
                "shadow_main.goose", "-O0", "--jobs", jobs,
                "-o", str(out), "--cache-dir", str(cache_dir), "--wasm-stats", str(stats),
            )
            self.assertEqual(r1.returncode, 0, r1.stderr)
            self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
            before = out.read_bytes()

            # Unchanged rebuild hits.
            r2 = self.run_goose(
                "shadow_main.goose", "-O0", "--jobs", jobs,
                "-o", str(out), "--cache-dir", str(cache_dir), "--wasm-stats", str(stats),
            )
            self.assertEqual(r2.returncode, 0, r2.stderr)
            self.assertTrue(json.loads(stats.read_text()).get("cache_hit"))

            # Adding a local base64.goose shadows stdlib/base64.goose and must invalidate!
            shadow_file.write_text("namespace base64;\nfn encode(out: u8[>..]&, src: const u8[:]) { out.append(\"SHADOW!\"); }\n")
            r3 = self.run_goose(
                "shadow_main.goose", "-O0", "--jobs", jobs,
                "-o", str(out), "--cache-dir", str(cache_dir), "--wasm-stats", str(stats),
            )
            self.assertEqual(r3.returncode, 0, r3.stderr)
            self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
            self.assertNotEqual(out.read_bytes(), before)
            shadow_file.unlink()

    def test_embed_file_and_flag_changes_invalidate(self):
        (self.work / "data.txt").write_text("hello-1")
        (self.work / "emb.goose").write_text(
            'let msg = embed_file("data.txt");\n'
            "fn main() { print(msg.len); }\n"
        )
        out = self.work / "emb.wasm"
        stats = self.work / "st.json"
        r1 = self.run_goose("emb.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r1.returncode, 0, r1.stderr)
        b1 = out.read_bytes()

        # Different optimization flag must miss and produce its own entry.
        r_o2 = self.run_goose("emb.goose", "-O2", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r_o2.returncode, 0, r_o2.stderr)
        self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))

        # Editing embedded file (same size!) must invalidate -O0 entry.
        (self.work / "data.txt").write_text("hello-2")
        r2 = self.run_goose("emb.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
        self.assertNotEqual(out.read_bytes(), b1)

    def test_check_mode_and_native_c_and_failure_preservation(self):
        stats = self.work / "st.json"
        # --check caches pass result.
        rc1 = self.run_goose("main.goose", "--check", "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(rc1.returncode, 0, rc1.stderr)
        self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
        rc2 = self.run_goose("main.goose", "--check", "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(rc2.returncode, 0, rc2.stderr)
        self.assertTrue(json.loads(stats.read_text()).get("cache_hit"))

        # Native C emission caches bit-identically.
        out_c = self.work / "app.c"
        rn1 = self.run_goose("main.goose", "--target", "c", "-O0", "-o", str(out_c), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(rn1.returncode, 0, rn1.stderr)
        c_bytes = out_c.read_bytes()
        out_c.unlink()
        rn2 = self.run_goose("main.goose", "--target", "c", "-O0", "-o", str(out_c), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(rn2.returncode, 0, rn2.stderr)
        self.assertTrue(json.loads(stats.read_text()).get("cache_hit"))
        self.assertEqual(out_c.read_bytes(), c_bytes)

        # Broken edit must fail without overwriting previous valid output or poisoning cache.
        (self.work / "helper.goose").write_text("namespace helper;\nfn val() -> i64 { return \"bad\"; }\n")
        rf = self.run_goose("main.goose", "--target", "c", "-O0", "-o", str(out_c), "--cache-dir", str(self.cache))
        self.assertNotEqual(rf.returncode, 0)
        self.assertEqual(out_c.read_bytes(), c_bytes)

    def test_corrupt_blob_or_manifest_recovers_cleanly(self):
        out = self.work / "rec.wasm"
        stats = self.work / "st.json"
        r1 = self.run_goose("main.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r1.returncode, 0, r1.stderr)
        good = out.read_bytes()

        # Corrupt the cached blob -> must miss, recompile, and repair cleanly.
        blobs = list(self.cache.glob("b_*.bin"))
        self.assertEqual(len(blobs), 1)
        blobs[0].write_bytes(b"corrupted!")
        out.unlink()
        r2 = self.run_goose("main.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
        self.assertEqual(out.read_bytes(), good)

        # Corrupt the manifest -> must miss, recompile, and repair cleanly.
        manifests = list(self.cache.glob("m_*.manifest"))
        self.assertEqual(len(manifests), 1)
        manifests[0].write_bytes(manifests[0].read_bytes()[:-10])
        r3 = self.run_goose("main.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(r3.returncode, 0, r3.stderr)
        self.assertFalse(json.loads(stats.read_text()).get("cache_hit"))
        self.assertEqual(out.read_bytes(), good)

    def test_output_collision_rejected_on_hit(self):
        out = self.work / "ok.wasm"
        r1 = self.run_goose("main.goose", "-O0", "-o", str(out), "--cache-dir", str(self.cache))
        self.assertEqual(r1.returncode, 0, r1.stderr)
        orig_helper = (self.work / "helper.goose").read_text()

        # On cache hit, refusing to overwrite a source file must still fire!
        for bad_out in ("helper.goose", "./helper.goose"):
            r2 = self.run_goose("main.goose", "-O0", "-o", bad_out, "--cache-dir", str(self.cache))
            self.assertEqual(r2.returncode, 1)
            self.assertIn("output would overwrite a source file", r2.stderr)
            self.assertEqual((self.work / "helper.goose").read_text(), orig_helper)


if __name__ == "__main__":
    unittest.main()
