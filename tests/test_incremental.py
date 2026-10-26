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


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts" / "goose_wasm.py"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--node", default="node")
    args = parser.parse_args()
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
            run("43\n")
            assert request(3, command)["result"]["cache"] == "hit"
            assert not request(4, ["version"])["ok"]
            assert request(5, command)["ok"]
            passed.append("persistent server invalidates edits and survives bad requests")
        finally:
            server.stdin.close()
            server.wait(timeout=30)
            server.stdout.close()
            error = server.stderr.read()
            server.stderr.close()
            assert server.returncode == 0, error

    for label in passed:
        print("PASS " + label)
    print(f"{len(passed)} incremental integration checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
