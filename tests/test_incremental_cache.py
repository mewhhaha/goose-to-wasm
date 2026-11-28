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

    def test_life_cert_comment_literal_scalar_and_inert_fn_edits(self):
        # Program with grow-shrink array, references, slices, an NF_FN_INERT helper,
        # and a non-inert mutator (bypasses pure fast path and exercises l_*.life).
        src = self.work / "life_main.goose"
        helper = self.work / "life_helper.goose"
        out = self.work / "life.wasm"
        out_plain = self.work / "life_plain.wasm"
        stats = self.work / "life_st.json"

        helper_v1 = (
            "namespace life_helper;\n"
            "fn score(s: const u8[:], k: i64) -> i64 {\n"
            "    var sum: i64 = k;\n"
            "    let n = s.len;\n"
            "    for i in 0..n { sum += s[i] as i64; }\n"
            "    return sum;\n"
            "}\n"
            "fn push_and_read(a: i64[>..<]&, tag: const u8[:]) -> i64 {\n"
            "    a.push(10);\n"
            "    a.push(20);\n"
            "    let r: i64& = a[0];\n"
            "    let first = r;\n"
            "    a.pop();\n"
            "    return first + score(tag, a.len);\n"
            "}\n"
        )
        main_v1 = (
            "import life_helper;\n"
            "fn main() {\n"
            "    var buf: i64[>..<] = [];\n"
            '    print(life_helper::push_and_read(buf, "ab"));\n'
            "}\n"
        )
        helper.write_text(helper_v1)
        src.write_text(main_v1)

        # Cold build writes exactly one .life certificate and matches uncached output.
        rp = self.run_goose("life_main.goose", "-O0", "-o", str(out_plain))
        self.assertEqual(rp.returncode, 0, rp.stderr)
        r1 = self.run_goose(
            "life_main.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r1.returncode, 0, r1.stderr)
        st1 = json.loads(stats.read_text())
        self.assertFalse(st1["cache_hit"])
        self.assertFalse(st1["life_cache_hit"])
        self.assertEqual(out.read_bytes(), out_plain.read_bytes())
        certs = list(self.cache.glob("l_*.life"))
        self.assertEqual(len(certs), 1)

        # Cross-mode --check and -O2 reuse the exact same .life cert!
        rc = self.run_goose(
            "life_main.goose", "--check",
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(rc.returncode, 0, rc.stderr)
        stc = json.loads(stats.read_text())
        self.assertFalse(stc["cache_hit"])
        self.assertTrue(stc["life_cache_hit"])

        ro2 = self.run_goose(
            "life_main.goose", "-O2", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(ro2.returncode, 0, ro2.stderr)
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(len(list(self.cache.glob("l_*.life"))), 1)

        # 1. EOF comment edit -> lifetime cache hit + bit-identical -O0 Wasm.
        helper.write_text(helper_v1 + "\n// trailing comment\n")
        r_cmt = self.run_goose(
            "life_main.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r_cmt.returncode, 0, r_cmt.stderr)
        self.assertFalse(json.loads(stats.read_text())["cache_hit"])
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(out.read_bytes(), out_plain.read_bytes())

        # 2. String literal + integer literal edit -> lifetime hit + fresh Wasm matching uncached.
        src.write_text(main_v1.replace('"ab"', '"xyz"'))
        helper.write_text(helper_v1.replace("10", "77"))
        rp2 = self.run_goose("life_main.goose", "-O0", "-o", str(out_plain))
        self.assertEqual(rp2.returncode, 0, rp2.stderr)
        r_lit = self.run_goose(
            "life_main.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r_lit.returncode, 0, r_lit.stderr)
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(out.read_bytes(), out_plain.read_bytes())

        # 3. Adding scalar let/var + if { let ... } inside non-inert fn + rewriting NF_FN_INERT fn -> hit!
        helper_v3 = (
            "namespace life_helper;\n"
            "fn score(s: const u8[:], k: i64) -> i64 {\n"
            "    var acc: i64 = k * 3 + 7;\n"
            "    let n = s.len;\n"
            "    for i in 0..n { if s[i] > 0 { acc ^= (s[i] as i64) * 5; } }\n"
            "    return acc;\n"
            "}\n"
            "fn push_and_read(a: i64[>..<]&, tag: const u8[:]) -> i64 {\n"
            "    var dbg: i64 = 12 + 34;\n"
            "    if dbg > 10 { let extra = dbg * 2; dbg = extra - 1; }\n"
            "    a.push(77);\n"
            "    a.push(20);\n"
            "    let r: i64& = a[0];\n"
            "    let first = r;\n"
            "    a.pop();\n"
            "    return (first + dbg) + score(tag, a.len);\n"
            "}\n"
        )
        helper.write_text(helper_v3)
        rp3 = self.run_goose("life_main.goose", "-O0", "-o", str(out_plain))
        self.assertEqual(rp3.returncode, 0, rp3.stderr)
        r_sc = self.run_goose(
            "life_main.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r_sc.returncode, 0, r_sc.stderr)
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(out.read_bytes(), out_plain.read_bytes())
        self.assertEqual(len(list(self.cache.glob("l_*.life"))), 1)

    def test_life_cert_soundness_rejects_all_lifetime_violations(self):
        src = self.work / "sound.goose"
        out = self.work / "sound.wasm"
        stats = self.work / "sound_st.json"

        # Seed cache with valid program using grow-shrink array, slice helper, and [r; 0] fill.
        good = (
            "struct Box { view: const u8[:] = \"\" }\n"
            "var GLOBAL_VIEW: const u8[:] = \"\";\n"
            "fn inspect(s: const u8[:]) -> i64 { return s.len; }\n"
            "fn check_fill(a: i64[>..<]&) -> i64 {\n"
            "    a.push(1);\n"
            "    let r: i64& = a[0];\n"
            "    let empty: i64&[0] = [r; 0];\n"
            "    let v = r;\n"
            "    a.pop();\n"
            "    return v + empty.len;\n"
            "}\n"
            "fn main() {\n"
            "    var xs: i64[>..<] = [];\n"
            "    var bs: u8[>..<] = [65, 66];\n"
            "    print(check_fill(xs) + inspect(bs[..]));\n"
            "}\n"
        )
        src.write_text(good)
        r0 = self.run_goose(
            "sound.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r0.returncode, 0, r0.stderr)
        self.assertEqual(len(list(self.cache.glob("l_*.life"))), 1)

        # Attack A: dereferencing `r` (`let bad = *r;`) AFTER `a.pop()` — NF_INERT read of ref!
        # Must MISS lifetime cache and REJECT!
        src.write_text(good.replace("    a.pop();\n", "    a.pop();\n    let bad = r;\n"))
        ra = self.run_goose("sound.goose", "--check", "--cache-dir", str(self.cache))
        self.assertNotEqual(ra.returncode, 0, "Attack A (deref after pop) must be rejected")

        # Attack B: editing an initially NF_FN_INERT helper `inspect` to escape its slice to a global!
        src.write_text(good.replace("fn inspect(s: const u8[:]) -> i64 { return s.len; }",
                                    "fn inspect(s: const u8[:]) -> i64 { GLOBAL_VIEW = s; return s.len; }"))
        rb = self.run_goose("sound.goose", "--check", "--cache-dir", str(self.cache))
        self.assertNotEqual(rb.returncode, 0, "Attack B (inert fn edited to escape slice) must be rejected")

        # Attack C: changing zero-count N_FILL `[r; 0]` -> `[r; 1]` (stores grow-shrink element ref in array)!
        src.write_text(good.replace("let empty: i64&[0] = [r; 0];", "let empty: i64&[1] = [r; 1];"))
        rc = self.run_goose("sound.goose", "--check", "--cache-dir", str(self.cache))
        self.assertNotEqual(rc.returncode, 0, "Attack C (zero-count fill changed to 1) must be rejected")

        # Attack D: passing `r` into a function after `a.pop()`!
        src.write_text(good.replace("    return v + empty.len;\n", "    return v + r + empty.len;\n"))
        rd = self.run_goose("sound.goose", "--check", "--cache-dir", str(self.cache))
        self.assertNotEqual(rd.returncode, 0, "Attack D (use of r in return after pop) must be rejected")

        # Valid original still hits lifetime cache after all rejected builds!
        src.write_text(good)
        rok = self.run_goose(
            "sound.goose", "--check",
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(rok.returncode, 0, rok.stderr)
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])

    def test_life_cert_corrupt_recovers_cleanly_and_preserves_provenance(self):
        # Program with NRVO-eligible local + static global + owner-list provenance.
        src = self.work / "prov.goose"
        out_c1 = self.work / "prov1.c"
        out_c2 = self.work / "prov2.c"
        out_w1 = self.work / "prov1.wasm"
        out_w2 = self.work / "prov2.wasm"
        stats = self.work / "prov_st.json"

        code = (
            'let STATIC_TAG: const u8[:] = "ok";\n'
            "fn make_buf(n: i64) -> i64[>..] {\n"
            "    var out: i64[>..] = [];\n"
            "    for i in 0..n { out.push(i); }\n"
            "    return out;\n"
            "}\n"
            "fn pick(a: i64[>..]&, b: i64[>..]&, cond: bool) -> i64 {\n"
            "    var r: i64& = a[0];\n"
            "    if cond { r .= b[0]; }\n"
            "    return r;\n"
            "}\n"
            "fn main() {\n"
            "    var x = make_buf(3);\n"
            "    var y = make_buf(4);\n"
            "    print(pick(x, y, true) + STATIC_TAG.len);\n"
            "}\n"
        )
        src.write_text(code)
        r0 = self.run_goose("prov.goose", "--target", "c", "-O0", "-o", str(out_c1))
        self.assertEqual(r0.returncode, 0, r0.stderr)
        rw0 = self.run_goose("prov.goose", "-O0", "-o", str(out_w1))
        self.assertEqual(rw0.returncode, 0, rw0.stderr)

        # Populate 32-bit Wasm .life cert via --check, and 64-bit C .life cert via --check --target c.
        rc1 = self.run_goose("prov.goose", "--check", "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(rc1.returncode, 0, rc1.stderr)
        rc_c = self.run_goose("prov.goose", "--check", "--target", "c", "--cache-dir", str(self.cache), "--wasm-stats", str(stats))
        self.assertEqual(rc_c.returncode, 0, rc_c.stderr)
        certs = sorted(self.cache.glob("l_*.life"))
        self.assertEqual(len(certs), 2)
        good_certs = {c: c.read_bytes() for c in certs}

        # Hit .life cert in native C and Wasm modes -> outputs must be bit-identical!
        r_c = self.run_goose(
            "prov.goose", "--target", "c", "-O0", "-o", str(out_c2),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r_c.returncode, 0, r_c.stderr)
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(out_c2.read_bytes(), out_c1.read_bytes())

        r_w = self.run_goose(
            "prov.goose", "-O0", "-o", str(out_w2),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r_w.returncode, 0, r_w.stderr)
        self.assertTrue(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(out_w2.read_bytes(), out_w1.read_bytes())

        # Corrupt all .life certs -> must fall back cleanly, repair Wasm cert, and keep bit-identical output!
        for c, raw in good_certs.items():
            c.write_bytes(raw[:-8] + b"0000000\n")
        src.write_text(code + "\n// force manifest miss after cert corruption\n")
        r_rec = self.run_goose(
            "prov.goose", "-O0", "-o", str(out_w2),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r_rec.returncode, 0, r_rec.stderr)
        self.assertFalse(json.loads(stats.read_text())["life_cache_hit"])
        self.assertEqual(out_w2.read_bytes(), out_w1.read_bytes())
        repaired = [c for c, raw in good_certs.items() if c.read_bytes() == raw]
        self.assertEqual(len(repaired), 1)

    def test_life_cert_writes_and_hits_with_warnings(self):
        src = self.work / "warn_life.goose"
        out = self.work / "warn_life.wasm"
        stats = self.work / "warn_life_st.json"
        code = (
            "fn f(x: u8) -> bool {\n"
            "    let bad = x < 0;\n"
            "    return bad;\n"
            "}\n"
            "fn main() {\n"
            "    var xs: i64[>..<] = [1, 2];\n"
            "    let r: i64& = xs[0];\n"
            "    print(r, f(5));\n"
            "}\n"
        )
        src.write_text(code)
        r1 = self.run_goose(
            "warn_life.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertIn("warning:", r1.stderr)
        st1 = json.loads(stats.read_text())
        self.assertFalse(st1.get("cache_hit", False))
        self.assertFalse(st1["life_cache_hit"])
        self.assertFalse(st1.get("cache_complete", False))
        self.assertEqual(len(list(self.cache.glob("l_*.life"))), 1)

        # Second run (and edited-comment run) must still emit warning AND hit .life cert!
        src.write_text(code + "\n// edit\n")
        r2 = self.run_goose(
            "warn_life.goose", "-O0", "-o", str(out),
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertIn("warning:", r2.stderr)
        st2 = json.loads(stats.read_text())
        self.assertFalse(st2.get("cache_hit", False))
        self.assertTrue(st2["life_cache_hit"])

        # --check with warnings must also hit .life cert and emit the warning.
        rc = self.run_goose(
            "warn_life.goose", "--check",
            "--cache-dir", str(self.cache), "--wasm-stats", str(stats),
        )
        self.assertEqual(rc.returncode, 0, rc.stderr)
        self.assertIn("warning:", rc.stderr)
        stc = json.loads(stats.read_text())
        self.assertFalse(stc.get("cache_hit", False))
        self.assertTrue(stc["life_cache_hit"])


if __name__ == "__main__":
    unittest.main()
