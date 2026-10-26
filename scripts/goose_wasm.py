#!/usr/bin/env python3
"""Build Goose with the direct backend or either differential reference path.

The direct path invokes one native compiler and writes WebAssembly bytes. It
never emits C or launches a C compiler. A persistent native worker makes actual
edit builds cheaper while still running a fresh, complete semantic frontend.
"""
from __future__ import annotations

import argparse
import errno
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

from build_support import BuildError, NativeSession, OutputLocks, publish_files, run_process


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "goose-direct-build-v2"
PACKAGED = (ROOT / "bin" / ("goose.exe" if os.name == "nt" else "goose")).is_file()
DEFAULT_BUILD = ROOT if PACKAGED else ROOT / "build"
DEFAULT_CACHE = (Path(os.environ.get("LOCALAPPDATA" if os.name == "nt" else "XDG_CACHE_HOME",
                                   str(Path.home() / ".cache"))) / "goose-to-wasm"
                 if PACKAGED else ROOT / "build" / "cache")


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise BuildError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def locate(value: str | Path, label: str) -> Path:
    found = shutil.which(str(value))
    path = Path(found or value).expanduser().resolve()
    if not path.is_file():
        raise BuildError(f"{label} not found: {value}")
    return path


def atomic_write(path: Path, data: bytes, *, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        if executable:
            os.chmod(temporary, 0o755)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def invoke(command: list[str], *, verbose: bool = False, timeout: float = 120) -> float:
    if verbose:
        print("+ " + subprocess.list2cmdline(command), file=sys.stderr, flush=True)
    elapsed, stdout, stderr = run_process(command, timeout)
    if verbose:
        sys.stderr.write((stdout + stderr).decode("utf-8", errors="replace"))
    return elapsed


class BuildContext:
    """Process-lifetime tool identity memoization; source contents are always read."""
    def __init__(self, *, persistent: bool = False) -> None:
        self.tools: dict[str, tuple[tuple[int, ...], str]] = {}
        self.persistent = persistent
        self.worker: NativeSession | None = None
        self.worker_key = None

    def close(self) -> None:
        if self.worker:
            self.worker.close()
            self.worker = None
            self.worker_key = None

    def compile(self, command: list[str], args: argparse.Namespace, compiler_hash: str,
                temporary_parent: Path) -> tuple[float, dict]:
        use_session = args.compiler_mode == "session" or (args.compiler_mode == "auto" and self.persistent)
        if not use_session:
            return invoke(command, verbose=args.verbose, timeout=args.timeout), {
                "compiler_mode": "process", "native_session_reused": False}
        identity = (command[0], compiler_hash, str(Path.cwd()), tuple(sorted(os.environ.items())))
        reused = bool(self.worker and self.worker_key == identity and self.worker.process.poll() is None)
        started = time.perf_counter_ns()
        if not reused:
            self.close()
            self.worker = NativeSession(Path(command[0]), temporary_parent, args.timeout)
            self.worker_key = identity
        try:
            _, diagnostic, result = self.worker.compile(command, args.timeout)
        except BaseException:
            if self.worker.process.poll() is not None or self.worker.diagnostics.closed:
                self.close()
            raise
        if args.verbose and diagnostic:
            print(diagnostic, file=sys.stderr)
        return (time.perf_counter_ns() - started) / 1_000_000, {
            "compiler_mode": "session", "native_session_reused": reused,
            "native_session_request": result["request"], "native_session_pid": self.worker.process.pid,
            "native_compile_ns": result["compile_ns"]}

    def tool_hash(self, path: Path) -> str:
        st = path.stat()
        identity = (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns)
        previous = self.tools.get(str(path))
        if previous and previous[0] == identity:
            return previous[1]
        digest = sha256(read_regular_file(path))
        self.tools[str(path)] = (identity, digest)
        return digest


def search_directories(paths: list[Path], roots: list[Path] = ()) -> dict[str, list[str]] | None:
    """Snapshot module candidates, following directory links without cycles.

    A new file behind a directory symlink can shadow a previously selected
    standard-library module. Record link destinations and traverse their
    contents. An unreadable or broken link makes the snapshot uncacheable.
    """
    candidates = {path.parent for path in paths} | set(roots)
    dirs = {path for path in candidates if not any(parent in candidates for parent in path.parents)}
    # .git is not an identifier-based module directory. Explicit package paths
    # may still use it: any such dependency/root disables this pruning, and the
    # changed namespace snapshot forces a validating compile before caching.
    include_git = any(".git" in path.parts for path in [*paths, *roots])
    snapshot = {}
    try:
        for directory in sorted(dirs):
            if not directory.is_dir():
                if directory.is_symlink():
                    return None
                snapshot[str(directory)] = ["\0missing-directory"]
                continue
            names = ["\0root-target:" + str(directory.resolve(strict=True))]
            pending = [directory]
            visited = set()
            while pending:
                current = pending.pop()
                status = current.stat()
                identity = (status.st_dev, status.st_ino)
                if identity in visited:
                    names.append(str(current.relative_to(directory)) + "/\0visited-directory")
                    continue
                visited.add(identity)
                with os.scandir(current) as entries:
                    children = sorted(entries, key=lambda item: item.name)
                for entry in children:
                    if entry.name == ".git" and not include_git:
                        continue
                    child = Path(entry.path)
                    relative = str(child.relative_to(directory))
                    if entry.is_symlink():
                        target = child.resolve(strict=True)
                        names.append(relative + "\0link:" + os.readlink(child) + "\0target:" + str(target))
                    if entry.is_dir(follow_symlinks=True):
                        pending.append(child)
                    elif entry.name.endswith(".goose"):
                        names.append(relative)
                    elif entry.name.endswith(".build"):
                        # Package sidecars can change import exclusion and target
                        # behavior without changing any parsed Goose source.
                        names.append(relative + "\0sha256:" + sha256(read_regular_file(child)))
            snapshot[str(directory)] = sorted(names)
    except (OSError, RuntimeError):
        # Cache validation must be conservative when a namespace cannot be
        # enumerated. The actual compiler can still build its reachable files.
        return None
    return snapshot


def read_regular_file(path: Path) -> bytes:
    # Cached source/sidecar paths may have changed type since the last build.
    # A FIFO must not block cache validation outside the compiler timeout. Open
    # first, then validate that exact descriptor, so replacing a path between a
    # separate stat and open cannot turn the check into a blocking FIFO read.
    flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_BINARY", 0)
    descriptor = os.open(path, flags)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError(errno.EINVAL, "build dependency is not a regular file", str(path))
        with os.fdopen(descriptor, "rb") as stream:
            descriptor = -1
            return stream.read()
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def source_digest(path: Path) -> str:
    # Match Goose's LoadSource: an optional UTF-8 BOM is not part of the AST.
    return sha256(read_regular_file(path).removeprefix(b"\xef\xbb\xbf"))


def dependency_snapshot(transcript: list[dict[str, str]], roots: list[Path]) -> tuple[dict, bool]:
    inputs = {}
    coherent = True
    for item in transcript:
        # Keep the lexical import path AND its resolved target. A symlink may
        # be retargeted while the previous target remains completely unchanged.
        path = Path(os.path.abspath(item["path"]))
        compiled = item["text"].encode("utf-8")
        digest = sha256(compiled)
        inputs[str(path)] = {"sha256": digest, "resolved": str(path.resolve())}
        try:
            coherent = coherent and source_digest(path) == digest
        except OSError:
            coherent = False
    directories = search_directories([Path(p) for p in inputs], roots)
    return {"files": inputs, "search_roots": [str(p) for p in roots],
            "directories": directories}, coherent


def valid_dependencies(snapshot: dict) -> bool:
    try:
        files = snapshot["files"]
        if not files:
            return False
        for path, item in files.items():
            if str(Path(path).resolve()) != item["resolved"] or source_digest(Path(path)) != item["sha256"]:
                return False
        roots = [Path(p) for p in snapshot["search_roots"]]
        directories = search_directories([Path(p) for p in files], roots)
        return directories is not None and directories == snapshot["directories"]
    except (OSError, KeyError, TypeError, RuntimeError, AttributeError):
        return False


def cache_lookup(directory: Path, key: str) -> tuple[bytes, dict] | None:
    try:
        entry = json.loads(read_regular_file(directory / "entries" / (key + ".json")))
        if not isinstance(entry, dict) or entry.get("schema") != SCHEMA or not valid_dependencies(entry["dependencies"]):
            return None
        if not isinstance(entry.get("backend_stats"), dict):
            return None
        digest = entry["module_sha256"]
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            return None
        data = read_regular_file(directory / "blobs" / (digest + ".wasm"))
        if data[:8] != b"\0asm\x01\0\0\0" or sha256(data) != digest:
            return None
        return data, entry
    except (OSError, ValueError, KeyError, TypeError, RuntimeError):
        return None


def cache_store(directory: Path, key: str, data: bytes, dependencies: dict, stats: dict) -> None:
    digest = sha256(data)
    atomic_write(directory / "blobs" / (digest + ".wasm"), data)
    entry = {"schema": SCHEMA, "module_sha256": digest,
             "dependencies": dependencies, "backend_stats": stats}
    atomic_write(directory / "entries" / (key + ".json"), canonical(entry))


def frontend_options(args: argparse.Namespace, *, oracle: bool = False) -> list[str]:
    options = [args.optimization]
    if args.stdlib:
        options += ["--stdlib", str(args.stdlib.expanduser().resolve())]
    if args.offline:
        options.append("--offline")
    if args.debug:
        options += ["--debug"] if oracle else ["-D", "GS_DEBUG=1"]
    return options


def output_paths(args: argparse.Namespace) -> list[Path]:
    output = args.output.expanduser().resolve()
    paths = [output]
    if args.backend == "c-wasm" and output.suffix == ".mjs":
        paths.append(output.with_suffix(".wasm"))
    paths += [p.expanduser().resolve() for p in (args.stats, args.emit_c) if p is not None]
    if len(set(paths)) != len(paths):
        raise BuildError("output, Wasm companion, --stats and --emit-c must use distinct paths")
    return paths


def dependency_roots(source: Path, compiler: Path, args: argparse.Namespace) -> list[Path]:
    roots = [source.parent, Path.cwd() / "stdlib"]
    roots += [compiler.parent.joinpath(*([".."] * n), "stdlib").absolute() for n in range(4)]
    if args.stdlib:
        roots.append(args.stdlib.expanduser().absolute())
    if os.environ.get("GOOSE_STDLIB"):
        roots.append(Path(os.environ["GOOSE_STDLIB"]).absolute())
    return sorted({Path(os.path.abspath(p)) for p in roots})


def dependency_hints(directory: Path, key: str) -> list[Path]:
    # Invalid old entries may still tell us which external package directories
    # to snapshot before compiling. They never supply trusted output bytes.
    try:
        entry = json.loads(read_regular_file(directory / "entries" / (key + ".json")))
        return [Path(p) for p in entry["dependencies"]["files"]]
    except (OSError, ValueError, KeyError, TypeError):
        return []


def build(args: argparse.Namespace, context: BuildContext) -> dict:
    started = time.perf_counter_ns()
    args.cache_dir = args.cache_dir.expanduser().resolve()
    if not all(math.isfinite(x) and x > 0 for x in (args.timeout, args.lock_timeout)):
        raise BuildError("--timeout and --lock-timeout must be finite and positive")
    source = args.source.expanduser().resolve()
    if not source.is_file():
        raise BuildError(f"source does not exist: {source}")
    compiler = locate(args.goose or args.build_dir / "bin" / ("goose.exe" if os.name == "nt" else "goose"),
                      "Goose compiler (run scripts/bootstrap.py)")
    output = args.output.expanduser().resolve()
    paths = output_paths(args)
    protected = {source, compiler, *(p.expanduser().resolve() for p in args.c_source),
                 *(p.expanduser().resolve() for p in args.include)}
    if set(paths) & protected:
        raise BuildError("an output would overwrite an input or the compiler")
    if args.backend == "direct" and output.suffix != ".wasm":
        raise BuildError("direct output must end in .wasm")
    if args.backend == "c-wasm" and output.suffix not in (".wasm", ".mjs"):
        raise BuildError("c-wasm output must end in .wasm (WASI) or .mjs (Emscripten)")
    if args.backend == "direct" and (args.c_source or args.include or args.c_include_dir or args.emit_c):
        raise BuildError("the direct backend does not compile C; supply scalar externs through host imports")
    if args.compiler_mode == "session" and args.backend != "direct":
        raise BuildError("--compiler-mode session only supports the direct backend")
    if args.memory64 and args.backend != "c-wasm":
        raise BuildError("--memory64 currently applies to the C-Wasm oracle; direct uses explicit wasm32 addressing")
    if not 1 <= args.initial_pages <= args.maximum_pages <= 32768:
        raise BuildError("direct memory pages require 1 <= initial <= maximum <= 32768")
    lock_started = time.perf_counter_ns()
    with OutputLocks(paths, args.lock_timeout):
        lock_ms = (time.perf_counter_ns() - lock_started) / 1_000_000
        return build_locked(args, context, source, compiler, output, protected, paths, started, lock_ms)


def build_locked(args: argparse.Namespace, context: BuildContext, source: Path, compiler: Path,
                 output: Path, protected: set[Path], paths: list[Path], started: int, lock_ms: float) -> dict:
    report = {"schema": SCHEMA, "backend": args.backend, "source": str(source),
              "output": str(output), "optimization": args.optimization,
              "cache": "disabled", "compiler": str(compiler),
              "frontend_ms": 0.0, "cc_ms": 0.0, "output_lock_ms": lock_ms,
              "full_frontend_ran": False, "full_backend_ran": False}
    publications: dict[Path, tuple[bytes, bool]] = {}
    common = frontend_options(args)
    if args.backend == "direct":
        identity = {"schema": SCHEMA, "source": str(source),
                    "compiler_sha256": context.tool_hash(compiler), "options": common,
                    "initial_pages": args.initial_pages, "maximum_pages": args.maximum_pages,
                    "cwd": str(Path.cwd()),
                    "env": {k: os.environ.get(k) for k in ("GOOSE_STDLIB", "GOOSE_HOME")}}
        key = sha256(canonical(identity))
        report["compiler_sha256"] = identity["compiler_sha256"]
        cached = None if args.no_cache else cache_lookup(args.cache_dir, key)
        if cached:
            data, entry = cached
            if set(paths) & {Path(p).resolve() for p in entry["dependencies"]["files"]}:
                raise BuildError("an output would overwrite an imported source")
            publications[output] = (data, False)
            report.update(cache="hit", module_sha256=entry["module_sha256"],
                          compiler_mode="cache", native_session_reused=False,
                          output_bytes=len(data), cached_backend_stats=entry["backend_stats"])
        else:
            roots = dependency_roots(source, compiler, args)
            hints = [source, *dependency_hints(args.cache_dir, key)]
            with tempfile.TemporaryDirectory(prefix=".goose-wasm-", dir=output.parent) as temp:
                stage = Path(temp)
                module, deps, stats = stage / "program.wasm", stage / "dependencies.json", stage / "stats.json"
                command = [str(compiler), str(source), "--target", "wasm-direct", "-o", str(module),
                           "--wasm-deps", str(deps), "--wasm-stats", str(stats),
                           "--wasm-initial-pages", str(args.initial_pages),
                           "--wasm-max-pages", str(args.maximum_pages), *common]
                for attempt in range(3):
                    namespace_before = search_directories(hints, roots)
                    elapsed, execution = context.compile(command, args, identity["compiler_sha256"], output.parent)
                    report["frontend_ms"] += elapsed
                    report.update(execution, full_frontend_ran=True, full_backend_ran=True)
                    data = module.read_bytes()
                    if data[:8] != b"\0asm\x01\0\0\0":
                        raise BuildError("compiler did not emit a WebAssembly module")
                    backend_stats = json.loads(stats.read_text())
                    transcript = json.loads(deps.read_text())
                    snapshot, coherent = dependency_snapshot(transcript, roots)
                    if set(paths) & {Path(p).resolve() for p in snapshot["files"]}:
                        raise BuildError("an output would overwrite an imported source")
                    if context.tool_hash(compiler) != identity["compiler_sha256"]:
                        context.close()
                        raise BuildError("compiler changed during compilation; previous output preserved, retry the build")
                    # A newly discovered external package requires one more pass
                    # with its namespace observed before compilation. An edit
                    # racing the compile likewise retries instead of publishing
                    # a result from an obsolete source or import selection.
                    namespace_checked = namespace_before is not None and snapshot["directories"] is not None
                    if coherent and (not namespace_checked or namespace_before == snapshot["directories"]):
                        break
                    hints = [Path(p) for p in snapshot["files"]]
                else:
                    raise BuildError("sources or module search paths changed during three compile attempts; previous output preserved")
                report["compile_attempts"] = attempt + 1
                report["namespace_verified"] = namespace_checked
                stored = False
                if not args.no_cache and namespace_checked:
                    try:
                        cache_store(args.cache_dir, key, data, snapshot, backend_stats)
                        stored = True
                    except OSError as error:
                        # A cache is optional; retain a valid compiler result and
                        # make the failed cache publication visible in statistics.
                        report["cache_error"] = str(error)
                publications[output] = (data, False)
                report.update(cache="disabled" if args.no_cache else "miss", cache_stored=stored,
                              module_sha256=sha256(data), output_bytes=len(data),
                              backend_stats=backend_stats, dependencies=len(snapshot["files"]))
    elif args.backend == "native":
        cc = locate(args.cc or os.environ.get("CC", "gcc"), "native C compiler")
        with tempfile.TemporaryDirectory(prefix=".goose-native-", dir=output.parent) as temp:
            stage = Path(temp)
            generated, binary = stage / "program.c", stage / output.name
            cmd = [str(compiler), str(source), "--target", "native", "--standalone", "-o", str(generated), *common]
            for header in args.include:
                cmd += ["--include", str(header.expanduser().resolve())]
            report["frontend_ms"] = invoke(cmd, verbose=args.verbose, timeout=args.timeout)
            command = [str(cc), str(generated), args.optimization, "-fno-strict-aliasing", "-ffp-contract=off",
                       "-I", str(compiler.parent / "include")]
            for directory in args.c_include_dir:
                command += ["-I", str(directory.expanduser().resolve())]
            command += [str(p.expanduser().resolve()) for p in args.c_source]
            command += ["-lm", "-pthread", "-ldl", "-o", str(binary)]
            report["cc_ms"] = invoke(command, verbose=args.verbose, timeout=args.timeout)
            if args.emit_c:
                saved = args.emit_c.expanduser().resolve()
                # The generated C's include paths depend on its parent. Stage in
                # that same parent, then publish with the executable and stats.
                fd, name = tempfile.mkstemp(prefix=".goose-emit-", suffix=".c", dir=saved.parent)
                os.close(fd)
                try:
                    emit_command = [str(compiler), str(source), "--target", "native", "--standalone",
                                    "-o", name, *common]
                    for header in args.include:
                        emit_command += ["--include", str(header.expanduser().resolve())]
                    invoke(emit_command, verbose=args.verbose, timeout=args.timeout)
                    publications[saved] = (Path(name).read_bytes(), False)
                finally:
                    Path(name).unlink(missing_ok=True)
            data = binary.read_bytes()
            publications[output] = (data, True)
            report.update(output_bytes=len(data), output_sha256=sha256(data), cc=str(cc),
                          full_frontend_ran=True, full_backend_ran=True, compiler_mode="process")
    else:
        # The oracle stages and publishes into our private directory. The outer
        # transaction publishes its JS/Wasm pair together with any requested
        # emitted C and stats only after every child tool succeeds.
        with tempfile.TemporaryDirectory(prefix=".goose-c-wasm-", dir=output.parent) as temp:
            stage = Path(temp)
            staged_output = stage / output.name
            command = [sys.executable, str(ROOT / "oracle" / "goose_wasm.py"), "build", str(source),
                       "--goose", str(compiler), "-o", str(staged_output), *frontend_options(args, oracle=True)]
            if output.suffix == ".wasm":
                command.append("--standalone")
            if args.emcc:
                command += ["--emcc", str(args.emcc)]
            if args.memory64:
                command.append("--memory64")
            for flag, items in (("--c-source", args.c_source), ("--c-include-dir", args.c_include_dir),
                                ("--include", args.include)):
                for item in items:
                    command += [flag, str(item.expanduser().resolve())]
            emitted_temp = None
            try:
                if args.emit_c:
                    saved = args.emit_c.expanduser().resolve()
                    fd, name = tempfile.mkstemp(prefix=".goose-emit-", suffix=".c", dir=saved.parent)
                    os.close(fd)
                    emitted_temp = Path(name)
                    command += ["--emit-c", name]
                if args.verbose:
                    command.append("--verbose")
                report["oracle_ms"] = invoke(command, verbose=args.verbose, timeout=args.timeout)
                wasm = staged_output.with_suffix(".wasm")
                data = wasm.read_bytes()
                publications[output.with_suffix(".wasm")] = (data, False)
                if output.suffix == ".mjs":
                    publications[output] = (staged_output.read_bytes(), False)
                if emitted_temp:
                    publications[args.emit_c.expanduser().resolve()] = (emitted_temp.read_bytes(), False)
            finally:
                if emitted_temp:
                    emitted_temp.unlink(missing_ok=True)
            report.update(output_bytes=len(data), module_sha256=sha256(data),
                          full_frontend_ran=True, full_backend_ran=True, compiler_mode="process",
                          host="wasi_snapshot_preview1" if output.suffix == ".wasm" else "emscripten")
            report.update(c_pointer_bits=64,
                          memory_address_bits=64 if output.suffix == ".wasm" or args.memory64 else 32,
                          target_profile="memory64-lp64-wasi64-standard-eh" if output.suffix == ".wasm"
                          else "emscripten-memory64" if args.memory64 else "emscripten-memory64-lowered-to-wasm32")
    report["total_ms"] = (time.perf_counter_ns() - started) / 1_000_000
    report["timing_scope"] = "through output preparation; excludes publication"
    if args.stats:
        publications[args.stats.expanduser().resolve()] = (json.dumps(report, indent=2).encode() + b"\n", False)
    publication_started = time.perf_counter_ns()
    publish_files(publications)
    report["publication_ms"] = (time.perf_counter_ns() - publication_started) / 1_000_000
    report["total_ms"] = (time.perf_counter_ns() - started) / 1_000_000
    report["timing_scope"] = "through output publication; excludes response serialization"
    return report


def parser() -> argparse.ArgumentParser:
    p = Parser(description=__doc__)
    commands = p.add_subparsers(dest="command", required=True, parser_class=Parser)
    commands.add_parser("version", help="show pinned toolchain versions")
    commands.add_parser("serve", help="persistent JSON-lines build server on stdin/stdout")
    b = commands.add_parser("build", help="compile with one of the three backends")
    b.add_argument("source", type=Path)
    b.add_argument("-o", "--output", type=Path, required=True)
    b.add_argument("--backend", choices=("direct", "c-wasm", "native"), default="direct")
    b.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
    b.add_argument("--goose")
    b.add_argument("--stdlib", type=Path)
    b.add_argument("--offline", action="store_true")
    b.add_argument("--debug", action="store_true")
    b.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    b.add_argument("--no-cache", action="store_true", help="force a complete compile, used by cold benchmarks")
    b.add_argument("--compiler-mode", choices=("auto", "process", "session"), default="auto",
                   help="auto uses a persistent native compiler in serve mode; every edit runs the full frontend")
    b.add_argument("--timeout", type=float, default=120, help="maximum seconds per compiler/tool invocation")
    b.add_argument("--lock-timeout", type=float, default=120, help="maximum seconds waiting for output locks")
    b.add_argument("--initial-pages", type=int, default=16)
    b.add_argument("--maximum-pages", type=int, default=256)
    levels = b.add_mutually_exclusive_group()
    for level in ("-O0", "-O1", "-O2"):
        levels.add_argument(level, dest="optimization", action="store_const", const=level)
    b.set_defaults(optimization="-O2")
    b.add_argument("--cc")
    b.add_argument("--emcc")
    b.add_argument("--memory64", action="store_true", help="memory64 for the C-Wasm oracle")
    b.add_argument("--c-source", type=Path, action="append", default=[])
    b.add_argument("--c-include-dir", type=Path, action="append", default=[])
    b.add_argument("--include", type=Path, action="append", default=[])
    b.add_argument("--emit-c", type=Path)
    b.add_argument("--stats", type=Path)
    b.add_argument("--json", action="store_true")
    b.add_argument("--verbose", "-v", action="store_true")
    return p


def serve(context: BuildContext) -> int:
    context.persistent = True
    while True:
        line = sys.stdin.buffer.readline(1_048_577)
        if not line:
            break
        request: dict = {}
        try:
            if len(line) > 1_048_576:
                while line and not line.endswith(b"\n"):
                    line = sys.stdin.buffer.readline(1_048_577)
                raise BuildError("request exceeds 1 MiB")
            request = json.loads(line)
            if not isinstance(request, dict):
                raise BuildError("request must be a JSON object")
            argv = request.get("args")
            if not isinstance(argv, list) or not all(isinstance(x, str) for x in argv):
                raise BuildError("request requires an args array of command-line strings")
            if "--help" in argv or "-h" in argv:
                raise BuildError("request help from the command line, outside the JSON-lines server")
            args = parser().parse_args(argv)
            if args.command != "build":
                raise BuildError("server requests must use the build command")
            result = build(args, context)
            response = {"id": request.get("id"), "ok": True, "result": result}
        except (BuildError, OSError, ValueError, TypeError, RuntimeError, SystemExit) as error:
            response = {"id": request.get("id") if isinstance(request, dict) else None,
                        "ok": False, "error": str(error)}
        print(json.dumps(response), flush=True)
    return 0


def main() -> int:
    context = None
    try:
        args = parser().parse_args()
        if args.command == "version":
            print((ROOT / "toolchain.json").read_text(), end="")
            return 0
        context = BuildContext()
        if args.command == "serve":
            return serve(context)
        report = build(args, context)
        if args.json:
            print(json.dumps(report))
        else:
            print(f"Wrote {report['output']} ({report['output_bytes']} bytes; "
                  f"{report['total_ms']:.3f} ms; cache {report['cache']})")
        return 0
    except KeyboardInterrupt:
        print("goose-wasm: interrupted; previous completed outputs preserved", file=sys.stderr)
        return 130
    except (BuildError, OSError, ValueError, RuntimeError) as error:
        print(f"goose-wasm: {error}", file=sys.stderr)
        return 1
    finally:
        if context:
            context.close()


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
