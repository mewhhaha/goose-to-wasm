#!/usr/bin/env python3
"""Build Goose with the direct backend or either differential reference path.

The direct path invokes one native compiler and writes WebAssembly bytes. It
never emits C or launches a C compiler. Its cache is a dependency-checked module
cache; edited programs still run the complete semantic frontend.
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
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "goose-direct-build-v1"


class BuildError(Exception):
    pass


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


def invoke(command: list[str], *, verbose: bool = False) -> float:
    if verbose:
        print("+ " + subprocess.list2cmdline(command), file=sys.stderr, flush=True)
    start = time.perf_counter_ns()
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            check=False)
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    if result.returncode:
        diagnostic = (result.stderr + result.stdout).decode("utf-8", errors="replace").strip()
        raise BuildError(f"{Path(command[0]).name} failed ({result.returncode}):\n{diagnostic}")
    if verbose:
        sys.stderr.write((result.stdout + result.stderr).decode("utf-8", errors="replace"))
    return elapsed


class NativeWorker:
    """One sequential compiler process; every request owns a fresh frontend."""
    def __init__(self, compiler: Path) -> None:
        self.log = tempfile.TemporaryFile(mode="w+t")
        try:
            self.process = subprocess.Popen([str(compiler), "--wasm-session"], stdin=subprocess.PIPE,
                                            stdout=subprocess.PIPE, stderr=self.log, text=True)
        except OSError:
            self.log.close()
            raise
        self.sequence = 0

    def request(self, payload: dict) -> dict:
        self.sequence += 1
        payload = {**payload, "id": self.sequence}
        try:
            self.process.stdin.write(canonical(payload).decode() + "\n")
            self.process.stdin.flush()
            line = self.process.stdout.readline()
            if not line:
                raise BuildError("native compiler worker exited before replying")
            reply = json.loads(line)
            if not isinstance(reply, dict) or reply.get("id") != self.sequence:
                raise BuildError("native compiler worker returned an invalid response")
        except (BrokenPipeError, OSError, ValueError) as error:
            raise BuildError(f"native compiler worker communication failed: {error}") from error
        return reply

    def close(self) -> None:
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdout.close()
        self.log.close()


class BuildContext:
    """Process-lifetime tool identity memoization; source contents are always read."""
    def __init__(self, *, native_worker: bool = False, lexical_cache: bool = False,
                 syntax_cache: bool = False) -> None:
        self.tools: dict[str, tuple[tuple[int, ...], str]] = {}
        self.native_worker = native_worker
        self.lexical_cache = lexical_cache
        self.syntax_cache = syntax_cache
        self.sources: dict[str, str] = {}
        self.worker: NativeWorker | None = None
        self.worker_key: tuple | None = None

    def close(self) -> None:
        if self.worker is not None:
            self.worker.close()
            self.worker = None
            self.worker_key = None

    def compile_direct(self, compiler: Path, args: argparse.Namespace, module: Path,
                       deps: Path, stats: Path) -> tuple[float, dict]:
        key = (str(compiler), self.tool_hash(compiler), str(Path.cwd()),
               os.environ.get("GOOSE_STDLIB"), os.environ.get("GOOSE_HOME"))
        if self.worker is not None and (self.worker_key != key or self.worker.process.poll() is not None):
            self.close()
        if self.worker is None:
            self.worker = NativeWorker(compiler)
            self.worker_key = key
        payload = {"source": str(args.source.expanduser().resolve()), "output": str(module),
                   "stdlib": str(args.stdlib.expanduser().resolve()) if args.stdlib else "",
                   "optimization": int(args.optimization[-1]), "debug": args.debug, "offline": args.offline,
                   "initial_pages": args.initial_pages, "maximum_pages": args.maximum_pages,
                   "sources": self.sources, "lexical_cache": self.lexical_cache,
                   "syntax_cache": self.syntax_cache}
        start = time.perf_counter_ns()
        try:
            reply = self.worker.request(payload)
        except BuildError:
            self.close()
            raise
        elapsed = (time.perf_counter_ns() - start) / 1_000_000
        if not reply.get("ok"):
            raise BuildError("native compiler worker failed:\n" + str(reply.get("error", "unknown error")))
        if not isinstance(reply.get("dependencies"), list) or not isinstance(reply.get("stats"), dict):
            self.close()
            raise BuildError("native compiler worker returned invalid build metadata")
        if args.verbose:
            sys.stderr.write(reply.get("diagnostics", ""))
        atomic_write(deps, canonical(reply["dependencies"]))
        atomic_write(stats, canonical(reply["stats"]))
        return elapsed, {"compiler_worker_pid": self.worker.process.pid,
                         "compiler_worker_request": self.worker.sequence,
                         "compiler_process_reused": self.worker.sequence > 1}

    def tool_hash(self, path: Path) -> str:
        st = path.stat()
        identity = (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns)
        previous = self.tools.get(str(path))
        if previous and previous[0] == identity:
            return previous[1]
        digest = sha256(path.read_bytes())
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
                    if entry.name == ".git":
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
            snapshot[str(directory)] = sorted(names)
    except (OSError, RuntimeError):
        # Cache validation must be conservative when a namespace cannot be
        # enumerated. The actual compiler can still build its reachable files.
        return None
    return snapshot


def source_digest(path: Path) -> str:
    # Match Goose's LoadSource: an optional UTF-8 BOM is not part of the AST.
    return sha256(path.read_bytes().removeprefix(b"\xef\xbb\xbf"))


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
            "directories": directories}, coherent and directories is not None


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
    except (OSError, KeyError, TypeError):
        return False


def cache_lookup(directory: Path, key: str) -> tuple[bytes, dict] | None:
    try:
        entry = json.loads((directory / "entries" / (key + ".json")).read_text())
        if entry.get("schema") != SCHEMA or not valid_dependencies(entry["dependencies"]):
            return None
        data = (directory / "blobs" / (entry["module_sha256"] + ".wasm")).read_bytes()
        if sha256(data) != entry["module_sha256"]:
            return None
        return data, entry
    except (OSError, ValueError, KeyError, TypeError):
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


def build(args: argparse.Namespace, context: BuildContext) -> dict:
    started = time.perf_counter_ns()
    if context.sources and (not context.native_worker or args.backend != "direct"):
        raise BuildError("source overlays require the direct backend in serve --native-worker")
    source = args.source.expanduser().resolve()
    if not source.is_file():
        raise BuildError(f"source does not exist: {source}")
    compiler = locate(args.goose or args.build_dir / "bin" / ("goose.exe" if os.name == "nt" else "goose"),
                      "Goose compiler (run scripts/bootstrap.py)")
    output = args.output.expanduser().resolve()
    protected = {source, compiler, *(Path(p) for p in context.sources), *(p.expanduser().resolve() for p in args.c_source),
                 *(p.expanduser().resolve() for p in args.include)}
    def protect_dependencies(files):
        protected.update(Path(path).resolve() for path in files)
        if output in protected or output.with_suffix(".wasm") in protected:
            raise BuildError("an output would overwrite a source dependency")
        if args.stats and args.stats.expanduser().resolve() in protected:
            raise BuildError("--stats must not overwrite a source dependency")
    if output in protected or output.with_suffix(".wasm") in protected:
        raise BuildError("an output would overwrite an input")
    if args.backend == "direct" and output.suffix != ".wasm":
        raise BuildError("direct output must end in .wasm")
    if args.backend == "c-wasm" and output.suffix not in (".wasm", ".mjs"):
        raise BuildError("c-wasm output must end in .wasm (WASI) or .mjs (Emscripten)")
    if args.backend == "direct" and (args.c_source or args.include or args.c_include_dir or args.emit_c):
        raise BuildError("the direct backend does not compile C; supply scalar externs through host imports")
    if args.memory64 and args.backend != "c-wasm":
        raise BuildError("--memory64 currently applies to the C-Wasm oracle; direct uses explicit wasm32 addressing")
    if not 1 <= args.initial_pages <= args.maximum_pages <= 32768:
        raise BuildError("direct memory pages require 1 <= initial <= maximum <= 32768")
    if args.stats:
        target = args.stats.expanduser().resolve()
        if target in (output, output.with_suffix(".wasm")) or target in protected:
            raise BuildError("--stats must not overwrite source or output")
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {"schema": SCHEMA, "backend": args.backend, "source": str(source),
              "output": str(output), "optimization": args.optimization,
              "cache": "disabled", "compiler": str(compiler),
              "frontend_ms": 0.0, "cc_ms": 0.0}
    common = frontend_options(args)
    if args.backend == "direct":
        identity = {"schema": SCHEMA, "source": str(source),
                    "compiler_sha256": context.tool_hash(compiler), "options": common,
                    "initial_pages": args.initial_pages, "maximum_pages": args.maximum_pages,
                    "cwd": str(Path.cwd()),
                    "env": {k: os.environ.get(k) for k in ("GOOSE_STDLIB", "GOOSE_HOME")}}
        key = sha256(canonical(identity))
        report["compiler_sha256"] = identity["compiler_sha256"]
        cached = None if args.no_cache or context.sources else cache_lookup(args.cache_dir, key)
        if cached:
            data, entry = cached
            protect_dependencies(entry["dependencies"]["files"])
            # Avoid touching an already correct output on an unchanged rebuild.
            if not output.is_file() or sha256(output.read_bytes()) != entry["module_sha256"]:
                atomic_write(output, data)
            report.update(cache="hit", module_sha256=entry["module_sha256"],
                          output_bytes=len(data), cached_backend_stats=entry["backend_stats"])
        else:
            with tempfile.TemporaryDirectory(prefix=".goose-wasm-", dir=output.parent) as temp:
                stage = Path(temp)
                module, deps, stats = stage / "program.wasm", stage / "dependencies.json", stage / "stats.json"
                command = [str(compiler), str(source), "--target", "wasm-direct", "-o", str(module),
                           "--wasm-deps", str(deps), "--wasm-stats", str(stats),
                           "--wasm-initial-pages", str(args.initial_pages),
                           "--wasm-max-pages", str(args.maximum_pages), *common]
                if context.native_worker:
                    report["frontend_ms"], worker_info = context.compile_direct(compiler, args, module, deps, stats)
                    report.update(worker_info)
                else:
                    report["frontend_ms"] = invoke(command, verbose=args.verbose)
                data = module.read_bytes()
                if data[:8] != b"\0asm\x01\0\0\0":
                    raise BuildError("compiler did not emit a WebAssembly module")
                backend_stats = json.loads(stats.read_text())
                roots = [source.parent, Path.cwd() / "stdlib"]
                roots += [compiler.parent.joinpath(*([".."] * n), "stdlib").absolute() for n in range(4)]
                if args.stdlib:
                    roots.append(args.stdlib.expanduser().absolute())
                if os.environ.get("GOOSE_STDLIB"):
                    roots.append(Path(os.environ["GOOSE_STDLIB"]).absolute())
                # Normalize '..' without resolving symlinks away.
                roots = sorted({Path(os.path.abspath(p)) for p in roots})
                snapshot, coherent = dependency_snapshot(json.loads(deps.read_text()), roots)
                protect_dependencies(snapshot["files"])
                if not args.no_cache and not context.sources and coherent:
                    cache_store(args.cache_dir, key, data, snapshot, backend_stats)
                atomic_write(output, data)
                report.update(cache="disabled" if args.no_cache or context.sources else "miss",
                              cache_stored=not args.no_cache and not context.sources and coherent,
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
            report["frontend_ms"] = invoke(cmd, verbose=args.verbose)
            command = [str(cc), str(generated), args.optimization, "-fno-strict-aliasing", "-ffp-contract=off",
                       "-I", str(compiler.parent / "include")]
            for directory in args.c_include_dir:
                command += ["-I", str(directory.expanduser().resolve())]
            command += [str(p.expanduser().resolve()) for p in args.c_source]
            command += ["-lm", "-pthread", "-ldl", "-o", str(binary)]
            report["cc_ms"] = invoke(command, verbose=args.verbose)
            if args.emit_c:
                saved = args.emit_c.expanduser().resolve()
                if saved in protected or saved == output:
                    raise BuildError("--emit-c would overwrite another input/output")
                saved.parent.mkdir(parents=True, exist_ok=True)
                emit_command = [str(compiler), str(source), "--target", "native", "--standalone",
                                "-o", str(saved), *common]
                for header in args.include:
                    emit_command += ["--include", str(header.expanduser().resolve())]
                invoke(emit_command, verbose=args.verbose)
            data = binary.read_bytes()
            atomic_write(output, data, executable=True)
            report.update(output_bytes=len(data), output_sha256=sha256(data), cc=str(cc))
    else:
        command = [sys.executable, str(ROOT / "oracle" / "goose_wasm.py"), "build", str(source),
                   "--goose", str(compiler), "-o", str(output), *frontend_options(args, oracle=True)]
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
        if args.emit_c:
            command += ["--emit-c", str(args.emit_c.expanduser().resolve())]
        if args.verbose:
            command.append("--verbose")
        report["oracle_ms"] = invoke(command, verbose=args.verbose)
        wasm = output.with_suffix(".wasm")
        data = wasm.read_bytes()
        report.update(output_bytes=len(data), module_sha256=sha256(data),
                      host="wasi_snapshot_preview1" if output.suffix == ".wasm" else "emscripten")
        report.update(c_pointer_bits=64,
                      memory_address_bits=64 if output.suffix == ".wasm" or args.memory64 else 32,
                      target_profile="memory64-lp64-wasi64-standard-eh" if output.suffix == ".wasm"
                      else "emscripten-memory64" if args.memory64 else "emscripten-memory64-lowered-to-wasm32")
    report["total_ms"] = (time.perf_counter_ns() - started) / 1_000_000
    if args.stats:
        target = args.stats.expanduser().resolve()
        if target == output or target in protected:
            raise BuildError("--stats must not overwrite source or output")
        atomic_write(target, json.dumps(report, indent=2).encode() + b"\n")
    return report


def parser() -> argparse.ArgumentParser:
    p = Parser(description=__doc__)
    commands = p.add_subparsers(dest="command", required=True, parser_class=Parser)
    commands.add_parser("version", help="show pinned toolchain versions")
    server = commands.add_parser("serve", help="persistent JSON-lines build server on stdin/stdout")
    server.add_argument("--native-worker", action="store_true",
                        help="retain a native compiler process; each edited build still runs the full frontend")
    server.add_argument("--lexical-cache", action="store_true",
                        help="reuse unchanged source tokens in the native worker (requires --native-worker)")
    server.add_argument("--syntax-cache", action="store_true",
                        help="reuse parsed modules in a fresh AST (requires --native-worker)")
    b = commands.add_parser("build", help="compile with one of the three backends")
    b.add_argument("source", type=Path)
    b.add_argument("-o", "--output", type=Path, required=True)
    b.add_argument("--backend", choices=("direct", "c-wasm", "native"), default="direct")
    b.add_argument("--build-dir", type=Path, default=ROOT / "build")
    b.add_argument("--goose")
    b.add_argument("--stdlib", type=Path)
    b.add_argument("--offline", action="store_true")
    b.add_argument("--debug", action="store_true")
    b.add_argument("--cache-dir", type=Path, default=ROOT / "build" / "cache")
    b.add_argument("--no-cache", action="store_true", help="force a complete compile, used by cold benchmarks")
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
    for line in sys.stdin:
        context.sources = {}
        request: dict = {}
        try:
            if len(line) > 1_048_576:
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
            overlays = request.get("sources", {})
            if not isinstance(overlays, dict) or not all(isinstance(k, str) and isinstance(v, str)
                                                       for k, v in overlays.items()):
                raise BuildError("sources must be an object mapping existing paths to source text")
            for path, text in overlays.items():
                resolved = str(Path(path).expanduser().resolve())
                if not Path(resolved).is_file():
                    raise BuildError("source overlays require existing files")
                if resolved in context.sources:
                    raise BuildError("duplicate source overlay path")
                context.sources[resolved] = text
            result = build(args, context)
            response = {"id": request.get("id"), "ok": True, "result": result}
        except (BuildError, OSError, ValueError, TypeError, SystemExit) as error:
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
        if (getattr(args, "lexical_cache", False) or getattr(args, "syntax_cache", False)) and not args.native_worker:
            raise BuildError("--lexical-cache and --syntax-cache require --native-worker")
        context = BuildContext(native_worker=getattr(args, "native_worker", False),
                               lexical_cache=getattr(args, "lexical_cache", False),
                               syntax_cache=getattr(args, "syntax_cache", False))
        if args.command == "serve":
            return serve(context)
        report = build(args, context)
        if args.json:
            print(json.dumps(report))
        else:
            print(f"Wrote {report['output']} ({report['output_bytes']} bytes; "
                  f"{report['total_ms']:.3f} ms; cache {report['cache']})")
        return 0
    except (BuildError, OSError, ValueError) as error:
        print(f"goose-wasm: {error}", file=sys.stderr)
        return 1
    finally:
        if context is not None:
            context.close()


if __name__ == "__main__":
    sys.exit(main())
