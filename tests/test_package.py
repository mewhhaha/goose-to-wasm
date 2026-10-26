#!/usr/bin/env python3
"""Verify the release manifest and compile/run from an extracted package."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import select
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT / "build/goose-to-wasm.tar.gz")
    parser.add_argument("--output", type=Path, default=ROOT / "build/package-qualification.json")
    args = parser.parse_args()
    if platform.system() != "Linux":
        parser.error("release package qualification currently targets Linux")
    node = shutil.which("node")
    if not node:
        raise RuntimeError("Node is required for package qualification")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix="package-check-", dir=args.output.parent) as temporary:
        directory = Path(temporary).resolve()
        with tarfile.open(args.archive, "r:gz") as archive:
            members = archive.getmembers()
            assert len({item.name for item in members}) == len(members), "duplicate archive entries"
            for item in members:
                name = PurePosixPath(item.name)
                assert item.isfile() and name.parts[0] == "goose-to-wasm"
                assert not name.is_absolute() and ".." not in name.parts
                assert "\\" not in item.name and str(name) == item.name, "noncanonical archive path"
            content = {item.name.removeprefix("goose-to-wasm/"): archive.extractfile(item).read()
                       for item in members}
            manifest = json.loads(content["MANIFEST.json"])
            assert set(manifest) == set(content) - {"MANIFEST.json"}, "manifest/archive coverage differs"
            for item in members:
                name = item.name.removeprefix("goose-to-wasm/")
                data = content[name]
                if name in manifest:
                    assert manifest[name]["sha256"] == hashlib.sha256(data).hexdigest(), name
                    assert manifest[name]["bytes"] == len(data), name
                    assert manifest[name]["mode"] == item.mode, name
                target = directory / item.name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                target.chmod(item.mode)
        package = directory / "goose-to-wasm"
        work = directory / "consumer"
        work.mkdir()
        env = dict(os.environ, PATH="", CC="unavailable-cc", EMCC="unavailable-emcc",
                   XDG_CACHE_HOME=str(work / "user-cache"), GOOSE_HOME=str(work / "goose-home"))
        env.pop("GOOSE_STDLIB", None)
        source = work / "hello.goose"
        source.write_text('import std;\nfn main() { print(abs(-7), " package"); }\n')
        artifact = work / "hello.wasm"

        def run(name, command, expected=None):
            result = subprocess.run(list(map(str, command)), cwd=work, env=env,
                                    capture_output=True, text=True, timeout=60)
            assert result.returncode == 0, name + ": " + result.stdout + result.stderr
            if expected is not None:
                assert result.stdout == expected, (name, result.stdout, expected)
            records.append({"name": name, "status": "pass", "stdout": result.stdout})

        run("raw-compiler-without-C-toolchain", [package / "bin/goose", source,
                                                "--target", "wasm-direct", "--offline", "-o", artifact])
        run("V8", [node, package / "scripts/run_wasm.mjs", artifact], "7 package\n")
        run("Wasmtime", [sys.executable, package / "scripts/run_wasmtime.py", artifact], "7 package\n")
        artifact.unlink()
        run("packaged-driver-defaults", [sys.executable, package / "bin/goose-wasm", "build", source,
                                         "--offline", "--no-cache", "-o", artifact])
        run("driver-V8", [node, package / "scripts/run_wasm.mjs", artifact], "7 package\n")
        stats = work / "build-stats.json"
        arguments = ["build", str(source), "--offline", "-o", str(artifact), "--stats", str(stats)]
        server = subprocess.Popen([sys.executable, str(package / "bin/goose-wasm"), "serve"],
                                  cwd=work, env=env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            serial = 0
            def request():
                nonlocal serial
                serial += 1
                server.stdin.write(json.dumps({"id": serial, "args": arguments}) + "\n")
                server.stdin.flush()
                ready, _, _ = select.select([server.stdout], [], [], 60)
                assert ready, "packaged server did not reply within 60 seconds"
                response = json.loads(server.stdout.readline())
                assert response.get("id") == serial, response
                return response

            response = request()
            assert response["ok"], response
            first = response["result"]
            assert first["cache"] == "miss" and first["compiler_mode"] == "session", first
            assert first["full_frontend_ran"] and first["full_backend_ran"]
            worker_pid = first["native_session_pid"]
            records.append({"name": "packaged-resident-worker-startup", "status": "pass", "result": first})
            before, timestamp = artifact.read_bytes(), artifact.stat().st_mtime_ns
            response = request()
            assert response["ok"] and response["result"]["cache"] == "hit", response
            assert not response["result"]["full_frontend_ran"]
            assert artifact.read_bytes() == before and artifact.stat().st_mtime_ns == timestamp
            records.append({"name": "packaged-unchanged-cache-hit", "status": "pass"})
            source.write_text('import std;\nfn main() { print(abs(-8), " package"); }\n')
            response = request()
            assert response["ok"], response
            edited = response["result"]
            assert edited["cache"] == "miss" and edited["native_session_reused"], edited
            assert edited["native_session_pid"] == worker_pid
            assert edited["full_frontend_ran"] and edited["full_backend_ran"]
            assert artifact.read_bytes() != before
            records.append({"name": "packaged-actual-source-edit", "status": "pass", "result": edited})
            run("edited-driver-V8", [node, package / "scripts/run_wasm.mjs", artifact], "8 package\n")
            run("edited-driver-Wasmtime", [sys.executable, package / "scripts/run_wasmtime.py", artifact], "8 package\n")
            before, before_stats = artifact.read_bytes(), stats.read_bytes()
            source.write_text("fn main() { missing_name }\n")
            rejected = request()
            assert not rejected["ok"] and "missing_name" in rejected["error"], rejected
            assert artifact.read_bytes() == before and stats.read_bytes() == before_stats
            records.append({"name": "packaged-failed-edit-preserves-artifact-and-stats", "status": "pass"})
            source.write_text('import std;\nfn main() { print(abs(-9), " package"); }\n')
            response = request()
            assert response["ok"] and response["result"]["native_session_pid"] == worker_pid, response
            assert response["result"]["native_session_reused"] and response["result"]["cache"] == "miss"
            records.append({"name": "packaged-worker-error-recovery", "status": "pass"})
            run("recovered-driver-V8", [node, package / "scripts/run_wasm.mjs", artifact], "9 package\n")
            assert (work / "user-cache/goose-to-wasm/entries").is_dir(), "packaged default did not use user cache"
            assert not (package / "build").exists(), "packaged build wrote a checkout-style build directory"
        finally:
            server.stdin.close()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.terminate()
                server.wait(timeout=10)
                raise
            server.stdout.close()
            error = server.stderr.read()
            server.stderr.close()
            assert server.returncode == 0, error
        report = {"schema": "goose-package-qualification-v1", "files_verified": len(manifest),
                  "archive_sha256": hashlib.sha256(args.archive.read_bytes()).hexdigest(),
                  "compiler_sha256": hashlib.sha256((package / "bin/goose").read_bytes()).hexdigest(),
                  "failures": 0, "observations": len(records), "results": records}
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
