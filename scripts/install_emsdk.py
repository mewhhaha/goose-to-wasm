#!/usr/bin/env python3
"""Install the immutable Emscripten SDK used by the C-to-Wasm reference path."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
PIN = json.loads((ROOT / "toolchain.json").read_text(encoding="utf-8"))


def run(command: list[str], *, cwd: Path | None = None, capture: bool = False) -> str:
    print("+ " + subprocess.list2cmdline(command), flush=True)
    output = None
    if capture:
        output = subprocess.PIPE
    result = subprocess.run(command, cwd=cwd, check=True, text=True, stdout=output)
    return result.stdout or ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-dir", type=Path, default=ROOT / "build" / "emsdk")
    parser.add_argument("--jobs", type=int, default=min(2, os.cpu_count() or 1))
    args = parser.parse_args()
    try:
        if args.jobs < 1:
            raise RuntimeError("--jobs must be positive")
        sdk = args.sdk_dir.expanduser().resolve()
        if sdk.exists():
            if not (sdk / ".git").exists():
                raise RuntimeError(f"refusing to replace an unmanaged SDK directory: {sdk}")
            revision = run(["git", "rev-parse", "HEAD"], cwd=sdk, capture=True).strip()
            if revision != PIN["emsdk_revision"]:
                raise RuntimeError("existing SDK is at a different revision; choose a fresh --sdk-dir")
            changes = run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=sdk, capture=True)
            if changes:
                raise RuntimeError("existing SDK has tracked local edits; choose a fresh --sdk-dir")
        else:
            sdk.parent.mkdir(parents=True, exist_ok=True)
            run(["git", "init", str(sdk)])
            run(["git", "remote", "add", "origin", PIN["emsdk_repository"]], cwd=sdk)
            run(["git", "fetch", "--depth", "1", "origin", PIN["emsdk_revision"]], cwd=sdk)
            run(["git", "checkout", "--detach", PIN["emsdk_revision"]], cwd=sdk)
        manager = [sys.executable, str(sdk / "emsdk.py")]
        os.environ["EMCC_CORES"] = str(args.jobs)
        os.environ["EMSDK_NUM_CORES"] = str(args.jobs)
        run([*manager, "install", PIN["emscripten"]], cwd=sdk)
        run([*manager, "activate", PIN["emscripten"]], cwd=sdk)
        emcc = sdk / "upstream" / "emscripten" / "emcc"
        if os.name == "nt":
            emcc = emcc.with_suffix(".bat")
        version = run([str(emcc), "--version"], capture=True)
        match = re.search(r"\bemcc .*?\b(\d+\.\d+\.\d+)\b", version)
        if not match or match[1] != PIN["emscripten"]:
            raise RuntimeError("installed emcc does not report the pinned version")
        metadata = {
            "sdk_revision": PIN["emsdk_revision"],
            "emscripten": PIN["emscripten"],
            "sdk": str(sdk),
            "emcc": str(emcc),
            "version_output": version.strip(),
        }
        (sdk / "goose-to-wasm-sdk.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print(f"Installed {emcc}")
        print(f"Pass --emcc {emcc} to the driver, or activate {sdk / 'emsdk_env.sh'}.")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"install-emsdk: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
