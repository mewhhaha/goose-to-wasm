#!/usr/bin/env python3
"""Package a verified compiler, drivers, hosts, and corresponding source.

No build or network request occurs here. Stale compiler/header/patch identities
are rejected before publication. The archive and its file manifest are stable
for identical inputs and SOURCE_DATE_EPOCH (default zero).
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import subprocess
import sys
import tarfile
import tempfile

from bootstrap import source_fingerprint

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(directory, prefix, files):
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if ".git" in relative.parts or "__pycache__" in relative.parts:
            continue
        if path.is_symlink():
            raise ValueError(f"release inputs must be ordinary files: {path}")
        if path.is_file():
            files[str(PurePosixPath(prefix, *relative.parts))] = (path.read_bytes(), 0o755 if path.stat().st_mode & 0o111 else 0o644)


def collect_source(source, files):
    # Match the verified Git fingerprint's scope. Ignored build products or
    # unrelated local files must not silently enter the corresponding source.
    names = subprocess.check_output(["git", "ls-files", "--cached", "--others",
                                     "--exclude-standard", "-z"], cwd=source).split(b"\0")
    for name in sorted(set(filter(None, names))):
        relative = Path(os.fsdecode(name))
        path = source / relative
        if path.is_symlink():
            raise ValueError(f"release source must be an ordinary file: {path}")
        if path.is_file():
            files[str(PurePosixPath("source/upstream", *relative.parts))] = (
                path.read_bytes(), 0o755 if path.stat().st_mode & 0o111 else 0o644)


def linux_abi(binary):
    dynamic = subprocess.check_output(["readelf", "--dynamic", "--wide", str(binary)], text=True)
    versions = subprocess.check_output(["readelf", "--version-info", "--wide", str(binary)], text=True)
    return {"format": "ELF", "needed_libraries": sorted(set(re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic))),
            "required_symbol_versions": sorted(set(re.findall(r"Name: ([A-Za-z][A-Za-z0-9_.]+)", versions)))}


def package(build, destination, epoch):
    if platform.system() != "Linux":
        raise ValueError("this release packager is qualified for Linux; other hosts must build from source")
    if not destination.name.endswith(".tar.gz"):
        raise ValueError("the release output must end in .tar.gz")
    protected = [build / "bin", build / "source"] + [ROOT / name for name in
                 ("compiler", "patches", "oracle", "docs", "examples", "scripts")]
    identity_files = {build / "toolchain.json", build / "source.json", ROOT / "toolchain.json",
                      ROOT / "LICENSE", ROOT / "requirements.txt"}
    for output in (destination, destination.with_suffix(destination.suffix + ".json")):
        path = output.resolve()
        if path in {p.resolve() for p in identity_files} or any(
                path == directory.resolve() or directory.resolve() in path.parents for directory in protected):
            raise ValueError(f"release output would overwrite a compiler or source input: {output}")
    identity = json.loads((build / "toolchain.json").read_text())
    state = json.loads((build / "source.json").read_text())
    pins = json.loads((ROOT / "toolchain.json").read_text())
    source = build / "source"
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if revision != pins["revision"]:
        raise ValueError("corresponding source is not at the pinned upstream revision")
    binary = build / "bin" / ("goose.exe" if os.name == "nt" else "goose")
    if identity.get("build_type") != "Release" or not identity.get("direct_enabled"):
        raise ValueError("a Release build with the direct backend is required")
    if identity.get("pin") != pins or identity["compiler_sha256"] != digest(binary):
        raise ValueError("compiler identity or toolchain pins changed since bootstrap")
    headers = {p.name: digest(p) for p in sorted((ROOT / "compiler").glob("*.h"))}
    patches = {name: digest(ROOT / name) for name in pins["patches"]}
    if identity.get("headers") != headers or identity.get("patches") != patches:
        raise ValueError("compiler is stale: rebuild after changing backend headers or patches")
    if source_fingerprint(source) != state["source_diff_sha256"]:
        raise ValueError("corresponding compiler source has changed since bootstrap")
    if identity.get("runtime_sha256") != digest(source / "src/runtime_inline.h"):
        raise ValueError("embedded runtime source does not match the built compiler")
    installed = {str(p.relative_to(build / "bin/stdlib")): digest(p)
                 for p in (build / "bin/stdlib").rglob("*.goose")}
    original = {str(p.relative_to(source / "stdlib")): digest(p)
                for p in (source / "stdlib").rglob("*.goose")}
    if installed != original:
        raise ValueError("installed standard library differs from the corresponding source")
    if digest(build / "bin/include/goose.h") != digest(source / "src/runtime/goose.h"):
        raise ValueError("installed C ABI header differs from the corresponding source")

    files = {}
    collect(build / "bin", "bin", files)
    collect_source(source, files)
    for directory in ("compiler", "patches", "oracle/patches", "docs", "examples"):
        collect(ROOT / directory, "source/integration/" + directory, files)
    for name in ("goose_wasm.py", "build_support.py", "run_wasm.mjs", "run_wasmtime.py", "check_engines.py"):
        path = ROOT / "scripts" / name
        files["scripts/" + name] = (path.read_bytes(), 0o644)
        files["source/integration/scripts/" + name] = (path.read_bytes(), 0o644)
    for name in ("bootstrap.py", "package_release.py"):
        files["source/integration/scripts/" + name] = ((ROOT / "scripts" / name).read_bytes(), 0o644)
    for name in ("goose_wasm.py", "host_paths.js.in", "node_entry.js.in", "INTEGRATION-LICENSE"):
        files["oracle/" + name] = ((ROOT / "oracle" / name).read_bytes(), 0o644)
        files["source/integration/oracle/" + name] = ((ROOT / "oracle" / name).read_bytes(), 0o644)
    for name in ("LICENSE", "requirements.txt", "toolchain.json"):
        files[name] = ((ROOT / name).read_bytes(), 0o644)
        files["source/integration/" + name] = ((ROOT / name).read_bytes(), 0o644)
    collect(ROOT / "examples", "examples", files)
    collect(ROOT / "docs", "docs", files)
    launcher = '''#!/usr/bin/env python3
from pathlib import Path
import runpy
import sys
scripts = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(scripts))
runpy.run_path(str(scripts / "goose_wasm.py"), run_name="__main__")
'''
    files["bin/goose-wasm"] = (launcher.encode(), 0o755)
    installation = '''# Goose to Wasm compiler package

Add this package's `bin` directory to PATH. The compiler is a native executable;
the driver needs Python 3.10+. Direct compilation needs no C compiler or SDK.

```sh
goose-wasm build examples/squares.goose --offline -o squares.wasm
node scripts/run_wasm.mjs squares.wasm
python -m pip install -r requirements.txt
python scripts/run_wasmtime.py squares.wasm
```

For minimum command startup cost, invoke `bin/goose` directly:

```sh
bin/goose examples/squares.goose --target wasm-direct -O2 -o squares.wasm
```

For repeated edits, `goose-wasm serve` accepts the documented JSON-lines build
protocol and retains a native worker. Each changed program runs a complete
frontend; unchanged module-cache hits are separate. See docs/INCREMENTAL.md.

docs/TARGET.md defines supported language constructs, resource limits, and the
host ABI. The bundled hosts target the engine versions in toolchain.json.
They are embedding examples for those explicit host services, not a promise of
arbitrary native-library or standard WASI compatibility.

BUILD.json records the exact compiler/source identity. MANIFEST.json lists the
SHA-256, byte count, and mode of every packaged file except the manifest itself.
source/upstream contains the compiler source used for this executable, including
the applied backend. source/integration contains the separately reviewable
backend, patches, and bootstrap script. Upstream and integration license notices
are included. BUILD.json also lists the native executable's required Linux
libraries and symbol versions; older distributions may need a source rebuild.
The bundled source can be rebuilt without Git or fetching:

```sh
cmake -S source/upstream -B rebuilt -DCMAKE_BUILD_TYPE=Release -DGOOSE_BUILTIN_LIBS=
cmake --build rebuilt --parallel 2
```

No installation or service starts automatically.
'''
    files["README.md"] = (installation.encode(), 0o644)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    modified = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT))
    metadata = {"schema": "goose-release-v1", "source_commit": head, "source_modified": modified,
                "platform": platform.system(), "architecture": platform.machine(),
                "host_abi": linux_abi(binary),
                "compiler_sha256": digest(binary), "headers": headers, "patches": patches,
                "source_diff_sha256": state["source_diff_sha256"], "runtime_sha256": identity["runtime_sha256"],
                "toolchain": pins}
    files["BUILD.json"] = ((json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode(), 0o644)
    manifest = {name: {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), "mode": mode}
                for name, (data, mode) in sorted(files.items())}
    files["MANIFEST.json"] = ((json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode(), 0o644)
    prefix = "goose-to-wasm"
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".goose-release-", suffix=".tar.gz", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch) as compressed:
                with tarfile.open(mode="w", fileobj=compressed, format=tarfile.PAX_FORMAT) as archive:
                    for name, (data, mode) in sorted(files.items()):
                        entry = tarfile.TarInfo(prefix + "/" + name)
                        entry.size = len(data)
                        entry.mode = mode
                        entry.mtime = epoch
                        archive.addfile(entry, io.BytesIO(data))
            raw.flush()
            os.fsync(raw.fileno())
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return {"archive": str(destination), "bytes": destination.stat().st_size,
            "sha256": digest(destination), "files": len(files), **metadata}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build")
    parser.add_argument("--output", type=Path, default=ROOT / "build/goose-to-wasm.tar.gz")
    args = parser.parse_args()
    try:
        epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
        if not 0 <= epoch <= 0xFFFFFFFF:
            raise ValueError("SOURCE_DATE_EPOCH must be a nonnegative 32-bit second count")
        report = package(args.build_dir.resolve(), args.output.resolve(), epoch)
        args.output.with_suffix(args.output.suffix + ".json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        return 0
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"goose-wasm package: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
