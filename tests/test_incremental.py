#!/usr/bin/env python3
"""Integration checks for dependency-checked module caching and build serving."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts" / "goose_wasm.py"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--node", default="node")
    args = parser.parse_args()
    from test_build_support import BuildContracts
    contracts = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(BuildContracts))
    if not contracts.wasSuccessful():
        return 1
    compiler = args.goose.resolve()
    (ROOT / "build").mkdir(exist_ok=True)
    passed = []
    with tempfile.TemporaryDirectory(prefix="incremental-test-", dir=ROOT / "build") as temp:
        directory = Path(temp)
        source = directory / "main.goose"
        helper = directory / "helper" / "helper.goose"
        helper.parent.mkdir()
        source.write_text('import std;\nimport helper from "./helper";\nfn main() { print(helper::value()); }\n')
        helper.write_text('namespace helper;\nfn value() -> i64 { return 41; }\n')
        output = directory / "program.wasm"
        cache = directory / "cache"
        command = ["build", str(source), "--goose", str(compiler), "--cache-dir", str(cache),
                   "-o", str(output), "--json"]

        def build(extra=(), expect_success=True):
            result = subprocess.run([sys.executable, str(DRIVER), *command, *extra],
                                    text=True, capture_output=True, check=False)
            if expect_success and result.returncode:
                raise AssertionError(result.stderr)
            if not expect_success:
                assert result.returncode != 0, "invalid source unexpectedly compiled"
                return result
            return json.loads(result.stdout)

        def run(expected):
            result = subprocess.run([args.node, str(ROOT / "scripts" / "run_wasm.mjs"), str(output)],
                                    text=True, capture_output=True, check=False)
            assert result.returncode == 0, result.stderr
            assert result.stdout == expected, (result.stdout, expected)

        initial = build()
        assert initial["cache"] == "miss"
        run("41\n")
        passed.append("initial compile executes correctly")
        timestamp = output.stat().st_mtime_ns
        hit = build()
        assert hit["cache"] == "hit"
        assert output.stat().st_mtime_ns == timestamp
        passed.append("unchanged hit preserves output timestamp")

        st = helper.stat()
        helper.write_text(helper.read_text().replace("41", "42"))
        os.utime(helper, ns=(st.st_atime_ns, st.st_mtime_ns))
        edited = build()
        assert edited["cache"] == "miss", "same-size, same-mtime dependency edit was missed"
        run("42\n")
        passed.append("imported dependency contents invalidate even with restored mtime")

        assert build()["cache"] == "hit"
        added = directory / "new_module.goose"
        added.write_text("namespace new_module;\n")
        assert build()["cache"] == "miss"
        passed.append("new module search candidate invalidates cache")

        sidecar = helper.with_suffix(".build")
        sidecar.write_text('exclude = ["unused-one"];\n')
        assert build()["cache"] == "miss"
        assert build()["cache"] == "hit"
        st = sidecar.stat()
        sidecar.write_text('exclude = ["unused-two"];\n')
        os.utime(sidecar, ns=(st.st_atime_ns, st.st_mtime_ns))
        assert build()["cache"] == "miss", "same-size/mtime sidecar edit was missed"
        sidecar.unlink()
        build()
        passed.append("package sidecar contents invalidate even with restored size and mtime")

        good = helper.read_text()
        old_bytes = output.read_bytes()
        helper.write_text("namespace helper; fn value() -> i64 { invalid !!! }\n")
        build(expect_success=False)
        assert output.read_bytes() == old_bytes
        helper.write_text(good)
        assert build()["cache"] == "hit"
        passed.append("failed edit preserves valid output and cache")

        assert build(["-O0"])["cache"] == "miss"
        assert build(["-O0"])["cache"] == "hit"
        assert build(["--no-cache"])["cache"] == "disabled"
        passed.append("optimization flags and explicit no-cache are honored")

        isolated = dict(os.environ, PATH="", CC="/missing-c-compiler", EMCC="/missing-emcc")
        result = subprocess.run([sys.executable, str(DRIVER), *command, "--no-cache"],
                                env=isolated, text=True, capture_output=True, check=False)
        assert result.returncode == 0, result.stderr
        run("42\n")
        passed.append("direct route works without C compiler, Emscripten, or tools on PATH")

        # The frontend strips a UTF-8 BOM; the cache hashes that same content.
        helper.write_bytes(b"\xef\xbb\xbf" + good.encode())
        assert build()["cache"] == "hit"
        run("42\n")
        helper.write_text(good)
        passed.append("UTF-8 BOM normalization matches the semantic frontend")

        # Keep both target files unchanged while retargeting only the import.
        first = helper.with_name("first.goose")
        second = helper.with_name("second.goose")
        helper.rename(first)
        second.write_text(good.replace("42", "44"))
        helper.symlink_to(first.name)
        assert build()["cache"] == "miss"
        assert build()["cache"] == "hit"
        helper.unlink()
        helper.symlink_to(second.name)
        assert build()["cache"] == "miss"
        run("44\n")
        helper.unlink()
        helper.write_text(good)
        first.unlink()
        second.unlink()
        build()
        passed.append("retargeted imported symlink invalidates an unchanged old target")

        # An existing namespace link may acquire a new local module that
        # shadows the library. The link text and old dependency stay unchanged.
        project = directory / "namespace-project"
        project.mkdir()
        fallback = directory / "namespace-fallback"
        (fallback / "__pycache__").mkdir(parents=True)
        linked = directory / ".goose-linked-namespace"
        linked.mkdir()
        (project / "__pycache__").symlink_to(linked, target_is_directory=True)
        (fallback / "__pycache__" / "bar.goose").write_text("fn value() -> i64 { return 41; }\n")
        namespace_source = project / "main.goose"
        namespace_source.write_text("import __pycache__.bar;\nfn main() { print(value()); }\n")
        namespace_command = command.copy()
        namespace_command[1] = str(namespace_source)
        namespace_command += ["--stdlib", str(fallback)]

        def namespace_build():
            result = subprocess.run([sys.executable, str(DRIVER), *namespace_command],
                                    text=True, capture_output=True, check=False)
            assert result.returncode == 0, result.stderr
            return json.loads(result.stdout)

        assert namespace_build()["cache"] == "miss"
        run("41\n")
        assert namespace_build()["cache"] == "hit"
        (linked / "bar.goose").write_text("fn value() -> i64 { return 42; }\n")
        assert namespace_build()["cache"] == "miss", "new module behind a directory symlink was missed"
        run("42\n")
        assert namespace_build()["cache"] == "hit"
        build()
        passed.append("new module behind a directory symlink invalidates a shadowed library dependency")

        # A cache entry is never trusted merely because its filename is a digest.
        entries = list((cache / "entries").glob("*.json"))
        for entry_path in entries:
            entry = json.loads(entry_path.read_text())
            blob = cache / "blobs" / (entry["module_sha256"] + ".wasm")
            blob.write_bytes(b"corrupt")
        assert build()["cache"] == "miss"
        run("42\n")
        passed.append("corrupted cached module is rebuilt")

        server = subprocess.Popen([sys.executable, str(DRIVER), "serve"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            def request(identifier, arguments):
                server.stdin.write(json.dumps({"id": identifier, "args": arguments}) + "\n")
                server.stdin.flush()
                response = json.loads(server.stdout.readline())
                assert response["id"] == identifier
                return response
            assert request(1, command)["result"]["cache"] == "hit"
            helper.write_text(good.replace("42", "43"))
            response = request(2, command)
            assert response["ok"] and response["result"]["cache"] == "miss"
            assert response["result"]["compiler_mode"] == "session"
            worker_pid = response["result"]["native_session_pid"]
            run("43\n")
            assert request(3, command)["result"]["cache"] == "hit"
            assert not request(4, ["version"])["ok"]
            assert request(5, command)["ok"]
            passed.append("persistent server invalidates edits and survives bad requests")

            # Each changed source is checked against a fresh compiler process.
            # Repeated syntax/type failures must leave both output and worker
            # usable; no source, type or diagnostic state may leak between ASTs.
            baseline_output = directory / "fresh-process.wasm"
            for index in range(24):
                old_bytes = output.read_bytes()
                if index % 4 == 0:
                    helper.write_text("namespace helper; fn value() -> i64 { missing_name }\n")
                    failed = request(f"bad-{index}", command + ["--no-cache"])
                    assert not failed["ok"] and output.read_bytes() == old_bytes
                value = 100 + index
                helper.write_text(good.replace("42", str(value)))
                extra = ["--no-cache", "-O0" if index % 2 else "-O2"]
                if index % 3 == 0:
                    extra.append("--debug")
                response = request(f"edit-{index}", command + extra)
                assert response["ok"], response
                result = response["result"]
                assert result["native_session_reused"] and result["native_session_pid"] == worker_pid
                assert result["full_frontend_ran"] and result["full_backend_ran"]
                fresh = subprocess.run([sys.executable, str(DRIVER), *command, *extra,
                                        "--compiler-mode", "process", "-o", str(baseline_output)],
                                       text=True, capture_output=True, check=False)
                assert fresh.returncode == 0, (index, helper.exists(), list(helper.parent.iterdir()), fresh.stderr)
                assert output.read_bytes() == baseline_output.read_bytes(), "session differed from fresh compiler"
                if index % 6 == 0:
                    run(f"{value}\n")
            passed.append("24 actual edits and repeated errors match fresh compiler bytes across options")

            other = directory / "different.goose"
            other.write_text('struct Pair { a: i64, b: i64 } fn main(){ let p=Pair { 7, 9 }; print(p.a+p.b); }\n')
            alternative = command.copy()
            alternative[1] = str(other)
            response = request("different-source", alternative + ["--no-cache"])
            assert response["ok"], response
            run("16\n")
            assert request("original-source", command + ["--no-cache"])["ok"]
            run("123\n")
            passed.append("one native session handles independent source identities without leaked definitions")

            server.stdin.write('{invalid JSON}\n')
            server.stdin.flush()
            assert not json.loads(server.stdout.readline())["ok"]
            server.stdin.write('x' * 1_048_577 + '\n')
            server.stdin.flush()
            assert "exceeds" in json.loads(server.stdout.readline())["error"]
            assert request("after-bad-protocol", command)["ok"]
            passed.append("malformed and oversized server requests preserve framing and recovery")

            bad_link = directory / "loop.goose"
            bad_link.symlink_to(bad_link.name)
            bad_path_command = command.copy()
            bad_path_command[1] = str(bad_link)
            assert not request("bad-symlink-path", bad_path_command)["ok"]
            bad_link.unlink()
            assert request("after-bad-path", command)["ok"]
            passed.append("invalid symlink source paths do not terminate the build server")

            if os.name == "posix":
                import signal
                os.kill(worker_pid, signal.SIGKILL)
                time.sleep(0.05)
                result = request("restart-worker", command + ["--no-cache"])
                assert result["ok"], result
                assert result["result"]["native_session_pid"] != worker_pid
                assert not result["result"]["native_session_reused"]
                run("123\n")
                passed.append("terminated native worker restarts cleanly on the next build")
        finally:
            server.stdin.close()
            server.wait(timeout=30)
            server.stdout.close()
            error = server.stderr.read()
            server.stderr.close()
            assert server.returncode == 0, error

        # Concurrent callers publish complete, matching module/stats generations
        # to the same destination. This also exercises concurrent cache writes.
        concurrent_stats = directory / "concurrent-stats.json"
        competitors = []
        for index in range(6):
            chosen = source if index % 2 else other
            arguments = command.copy()
            arguments[1] = str(chosen)
            competitors.append(subprocess.Popen([sys.executable, str(DRIVER), *arguments,
                                                  "--no-cache", "--stats", str(concurrent_stats)],
                                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
        for process in competitors:
            stdout, stderr = process.communicate(timeout=60)
            assert process.returncode == 0, stderr
            assert json.loads(stdout)["cache"] == "disabled"
        metadata = json.loads(concurrent_stats.read_text())
        assert hashlib.sha256(output.read_bytes()).hexdigest() == metadata["module_sha256"]
        run("123\n" if metadata["source"] == str(source) else "16\n")
        passed.append("six concurrent writers publish consistent module/stats generations")

        if os.name == "posix":
            # A real compiler wrapper changes an imported source after the
            # frontend emitted it. The driver must retry before publishing.
            wrapper = directory / "race-compiler"
            marker = directory / "race-once"
            wrapper.write_text(f'''#!{sys.executable}
import pathlib,subprocess,sys
result=subprocess.run([{str(compiler)!r},*sys.argv[1:]])
marker=pathlib.Path({str(marker)!r})
if result.returncode==0 and not marker.exists():
    pathlib.Path({str(helper)!r}).write_text({good.replace('42','777')!r})
    marker.write_text('changed')
sys.exit(result.returncode)
''')
            wrapper.chmod(0o755)
            helper.write_text(good)
            raced = build(["--goose", str(wrapper), "--no-cache"])
            assert raced["compile_attempts"] >= 2
            run("777\n")
            passed.append("an imported source changed during compilation retries before publication")

        # Metadata outputs must never replace imported source files, including
        # on a module cache hit. The original valid output must survive failure.
        helper.write_text(good)
        build()
        before_module, before_helper = output.read_bytes(), helper.read_bytes()
        build(["--stats", str(helper)], expect_success=False)
        assert output.read_bytes() == before_module and helper.read_bytes() == before_helper
        passed.append("stats output cannot overwrite an imported dependency on a cache hit")

        package_source = ROOT / "tests" / "fixtures" / "native_sidecar" / "main.goose"
        package_command = command.copy()
        package_command[1] = str(package_source)
        result = subprocess.run([sys.executable, str(DRIVER), *package_command, "--no-cache"],
                                capture_output=True, text=True, check=False)
        assert result.returncode != 0 and "host adapter" in result.stderr, result.stderr
        assert output.read_bytes() == before_module
        passed.append("native package sidecars require an explicit direct-Wasm host adapter")

    for label in passed:
        print("PASS " + label)
    print(f"{len(passed)} incremental integration checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
