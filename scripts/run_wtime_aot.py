#!/usr/bin/env python3
"""Compile and run direct Goose WebAssembly ahead of time with wtime-aot.

Matches the CLI and `--timing-json` contract of `scripts/run_wasmtime.py` and
`scripts/run_wasm.mjs` so benchmarks and scripts can select `wtime-aot`
(`--backend rust`, full Goose/WASI host + LLVM -O3) or `wtime-aot-x64`
(`--backend x64`, pure-Rust static Linux x86-64 ELF, zero LLVM) alongside V8
and Wasmtime.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CACHE = ROOT / "build" / "wtime-aot-cache"
BACKENDS = ("rust", "x64")


def find_wtime_aot(explicit: Path | str | None = None) -> Path:
    """Resolve the `wtime-aot` executable from flag, env, PATH, or sibling repo."""
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    env_bin = os.environ.get("WTIME_AOT_BIN")
    if env_bin:
        candidates.append(Path(env_bin))
    on_path = shutil.which("wtime-aot")
    if on_path:
        candidates.append(Path(on_path))
    home = Path.home()
    candidates.extend([
        home / ".local" / "bin" / "wtime-aot",
        home / ".local" / "lib" / "pen-runtime" / "wtime-aot",
        ROOT.parent / "wtime" / "tools" / "wtime-aot" / "target" / "release" / "wtime-aot",
    ])
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    raise FileNotFoundError(
        "wtime-aot executable not found; install wtime v0.1.1+, add it to PATH, "
        "set WTIME_AOT_BIN, or pass --wtime-aot"
    )


def find_wtime_aot_rt(explicit: Path | str | None = None) -> Path | None:
    """Resolve optional `wtime-aot-rt` crate path for `--backend rust`."""
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    env_rt = os.environ.get("WTIME_AOT_RT")
    if env_rt:
        candidates.append(Path(env_rt))
    candidates.append(ROOT.parent / "wtime" / "tools" / "wtime-aot" / "rt")
    for candidate in candidates:
        if (candidate / "Cargo.toml").is_file():
            return candidate.resolve()
    return None


def ensure_cache_dir(cache_dir: Path) -> Path:
    cache_dir = cache_dir.resolve()
    cache_dir.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(cache_dir, 0o700)
    except OSError:
        pass
    return cache_dir


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def wtime_aot_identity(
    explicit_bin: Path | str | None = None,
    *,
    backend: str = "rust",
    target_cpu: str = "native",
    toolchain: str | None = None,
    rt: Path | str | None = None,
) -> dict:
    """Return auditable provenance metadata for the resolved `wtime-aot` binary."""
    binary = find_wtime_aot(explicit_bin)
    info = {
        "binary": str(binary),
        "sha256": sha256(binary),
        "backend": backend,
        "target_cpu": target_cpu,
    }
    if toolchain:
        info["toolchain"] = toolchain
    rt_path = find_wtime_aot_rt(rt) if backend == "rust" else None
    if rt_path is not None:
        info["rt"] = str(rt_path)
    return info


def prepare_binary(
    module: Path,
    *,
    backend: str = "rust",
    cache_dir: Path | None = None,
    wtime_aot: Path | str | None = None,
    rt: Path | str | None = None,
    toolchain: str | None = None,
    target_cpu: str = "native",
    jobs: int | None = None,
    timeout: int = 600,
) -> tuple[Path, int]:
    """Compile (or hit cache for) `module.wasm` via `wtime-aot build`, returning `(bin, ns)`."""
    if backend not in BACKENDS:
        raise ValueError(f"unsupported wtime-aot backend: {backend!r} (expected one of {BACKENDS})")
    module = Path(module).resolve()
    if not module.is_file():
        raise FileNotFoundError(f"module not found: {module}")
    aot_bin = find_wtime_aot(wtime_aot)
    cache = ensure_cache_dir(
        Path(cache_dir) if cache_dir is not None
        else Path(os.environ.get("WTIME_AOT_CACHE", str(DEFAULT_CACHE)))
    )
    command = [
        str(aot_bin), "build", str(module),
        "--cache", str(cache),
        "--backend", backend,
        "--target-cpu", target_cpu,
    ]
    if backend == "rust":
        rt_path = find_wtime_aot_rt(rt)
        if rt_path is not None:
            command += ["--rt", str(rt_path)]
        if toolchain:
            command += ["--toolchain", toolchain]
    if jobs is not None:
        command += ["--jobs", str(jobs)]

    started = time.perf_counter_ns()
    proc = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    elapsed_ns = time.perf_counter_ns() - started
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(f"wtime-aot build ({backend}) exited {proc.returncode}: {detail}")
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if not lines:
        raise RuntimeError(f"wtime-aot build ({backend}) produced no artifact path")
    artifact = Path(lines[-1])
    if not artifact.is_file():
        raise RuntimeError(f"wtime-aot build artifact missing: {artifact}")
    return artifact, elapsed_ns


def binary_command(
    artifact: Path,
    *,
    timing_json: Path | None = None,
    allow_files: list[Path] | None = None,
    allow_env: list[str] | None = None,
    program_arguments: list[str] | None = None,
) -> list[str]:
    """Build the command line to execute a compiled `wtime-aot` standalone binary."""
    cmd = [str(artifact)]
    if timing_json is not None:
        cmd += ["--timing-json", str(timing_json)]
    for directory in allow_files or []:
        cmd += ["--allow-files", str(directory)]
    for name in allow_env or []:
        cmd += ["--allow-env", name]
    if program_arguments is not None:
        cmd += ["--", *program_arguments]
    return cmd


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        usage="%(prog)s module.wasm [--backend rust|x64] [--cache DIR] [--timing-json PATH] [-- program arguments]",
    )
    parser.add_argument("module", type=Path)
    parser.add_argument("--backend", choices=BACKENDS, default="rust")
    parser.add_argument("--wtime-aot", type=Path, default=None, help="explicit path to wtime-aot binary")
    parser.add_argument("--rt", type=Path, default=None, help="explicit path to wtime-aot/rt crate (--backend rust)")
    parser.add_argument("--cache", type=Path, default=None, help="wtime-aot build cache directory")
    parser.add_argument("--toolchain", default=None, help="Rust toolchain for --backend rust (default: wtime-aot default)")
    parser.add_argument("--target-cpu", default="native")
    parser.add_argument("--jobs", type=int, default=None)
    parser.add_argument("--timing-json", type=Path, default=None)
    parser.add_argument("--allow-files", type=Path, action="append", default=None,
                        help="grant directory file access (default: current working directory)")
    parser.add_argument("--no-default-allow-files", action="store_true",
                        help="do not automatically grant current working directory file access")
    parser.add_argument("--allow-env", action="append", default=[],
                        help="grant environment variable access (repeatable, or '*')")
    parser.add_argument("--prepare-only", action="store_true",
                        help="compile/cache the binary and print its path without executing it")

    own = sys.argv[1:]
    program_arguments: list[str] | None = None
    if "--" in own:
        at = own.index("--")
        own, program_arguments = own[:at], own[at + 1:]
    args = parser.parse_args(own)

    try:
        artifact, build_ns = prepare_binary(
            args.module,
            backend=args.backend,
            cache_dir=args.cache,
            wtime_aot=args.wtime_aot,
            rt=args.rt,
            toolchain=args.toolchain,
            target_cpu=args.target_cpu,
            jobs=args.jobs,
        )
        if args.prepare_only:
            print(artifact)
            return 0

        allow_files: list[Path]
        if args.allow_files is not None:
            allow_files = list(args.allow_files)
        elif args.no_default_allow_files:
            allow_files = []
        else:
            allow_files = [Path.cwd()]

        run_argv = [str(args.module), *program_arguments] if program_arguments is not None else None
        cmd = binary_command(
            artifact,
            timing_json=args.timing_json,
            allow_files=allow_files,
            allow_env=args.allow_env,
            program_arguments=run_argv,
        )
        proc = subprocess.run(cmd, check=False)
        if args.timing_json is not None and args.timing_json.is_file():
            try:
                timing = json.loads(args.timing_json.read_text(encoding="utf-8"))
                inst_ns = int(timing.get("compile_instantiate_ns", 0)) + int(build_ns)
                start_ns = int(timing.get("start_function_ns", 0))
                timing.update({
                    "engine": "wtime-aot",
                    "backend": args.backend,
                    "compile_ns": int(build_ns),
                    "compile_instantiate_ns": inst_ns,
                    "start_function_ns": start_ns,
                    "engine_total_ns": inst_ns + start_ns,
                })
                args.timing_json.write_text(json.dumps(timing, indent=2) + "\n", encoding="utf-8")
            except (OSError, ValueError, TypeError):
                pass
        return proc.returncode
    except (OSError, RuntimeError, ValueError) as error:
        print(f"wtime-aot host: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
