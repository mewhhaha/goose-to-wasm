#!/usr/bin/env python3
"""Compile Goose source to WebAssembly with the pinned, patched Goose frontend."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DEFAULT_BUILD = ROOT / "build"
PIN = json.loads((ROOT / "toolchain.json").read_text(encoding="utf-8"))


class ToolError(Exception):
    """A driver or toolchain failure, distinct from a source diagnostic."""


def byte_size(value: str) -> int:
    match = re.fullmatch(r"([0-9]+)([KMG]?)", value.upper())
    if not match:
        raise argparse.ArgumentTypeError("use a byte count or a K, M, G suffix")
    return int(match[1]) * (1024 ** " KMG".index(match[2] or " "))


def executable(value: str, name: str) -> str:
    found = shutil.which(value)
    if found:
        return str(Path(found).resolve())
    path = Path(value).expanduser()
    if path.is_file():
        return str(path.resolve())
    raise ToolError(f"{name} not found: {value}")


def run(command: list[str], *, verbose: bool) -> None:
    if verbose:
        print("+ " + subprocess.list2cmdline(command), file=sys.stderr, flush=True)
    # Argument arrays, never a shell: source/output names may contain spaces.
    result = subprocess.run(command, check=False)
    if result.returncode:
        raise ToolError(f"{Path(command[0]).name} failed (exit {result.returncode})")


def compiler(args: argparse.Namespace) -> str:
    path = args.goose or os.environ.get("GOOSE_WASM_COMPILER")
    if not path:
        suffix = ""
        if os.name == "nt":
            suffix = ".exe"
        path = str(args.build_dir / "bin" / ("goose" + suffix))
    try:
        return executable(path, "patched Goose compiler")
    except ToolError as error:
        raise ToolError(f"{error}; run python3 {ROOT / 'scripts' / 'bootstrap.py'} first") from error


def frontend(args: argparse.Namespace, goose: str, output: Path | None) -> list[str]:
    source = args.source.expanduser().resolve()
    if not source.is_file():
        raise ToolError(f"source is not a file: {source}")
    command = [goose, str(source), "--target", "wasm", args.optimization,
               "--stack-reserve", str(args.stack_size)]
    if output is None:
        command.append("--check")
    else:
        command.extend(["--standalone", "-o", str(output)])
    if args.stdlib:
        command.extend(["--stdlib", str(args.stdlib.expanduser().resolve())])
    if args.offline:
        command.append("--offline")
    if args.debug:
        command.extend(["-D", "GS_DEBUG=1"])
    for header in args.include:
        command.extend(["--include", str(header.expanduser().resolve())])
    return command


def validate_sizes(args: argparse.Namespace) -> None:
    if not 65536 <= args.stack_size <= 1024 ** 3:
        raise ToolError("--stack-size must be between 64K and 1G")
    if args.stack_size % 65536:
        raise ToolError("--stack-size must be a multiple of 64K (one Wasm page)")
    if args.command != "build":
        return
    if not 65536 <= args.call_stack_size <= 64 * 1024 ** 2:
        raise ToolError("--call-stack-size must be between 64K and 64M")
    if args.call_stack_size % 65536:
        raise ToolError("--call-stack-size must be a multiple of 64K")
    if args.max_memory % 65536 or not 32 * 1024 ** 2 <= args.max_memory <= 2 * 1024 ** 3:
        raise ToolError("--max-memory must be a multiple of 64K between 32M and 2G")
    if args.stack_size + args.call_stack_size + 1024 ** 2 >= args.max_memory:
        raise ToolError("--max-memory must leave room for a data stack, call stack and runtime")
    if max(32 * 1024 ** 2, args.call_stack_size + 16 * 1024 ** 2) > args.max_memory:
        raise ToolError("--max-memory is smaller than the initial memory required by --call-stack-size")


def build(args: argparse.Namespace, goose: str) -> None:
    emcc = executable(args.emcc or os.environ.get("EMCC", "emcc"), "Emscripten emcc")
    version = subprocess.run([emcc, "--version"], capture_output=True, text=True, check=False)
    if version.returncode:
        raise ToolError(f"cannot query Emscripten: {version.stderr.strip()}")
    match = re.search(r"\bemcc .*?\b(\d+\.\d+\.\d+)\b", version.stdout)
    if not match or match[1] != PIN["emscripten"]:
        raise ToolError(f"this target requires Emscripten {PIN['emscripten']}; "
                        "activate that SDK version before building")
    destination = args.output.expanduser().resolve()
    if args.standalone:
        if destination.suffix != ".wasm":
            raise ToolError("--standalone requires -o to end in .wasm")
        if args.preload_file:
            raise ToolError("--preload-file requires the JavaScript host; it is unavailable with --standalone")
    elif destination.suffix != ".mjs":
        raise ToolError("-o must end in .mjs; the companion .wasm is emitted beside it")
    protected = [args.source, *args.c_source, *args.include]
    outputs = [destination]
    if not args.standalone:
        outputs.append(destination.with_suffix(".wasm"))
    if args.preload_file:
        outputs.append(destination.with_suffix(".data"))
        for item in args.preload_file:
            # Match the pinned file packager's escaped-at-sign syntax.
            separator = item.replace("@@", "__").find("@")
            local = item
            if separator >= 0:
                local = item[:separator]
            protected.append(Path(local.replace("@@", "@")))
    if args.emit_c:
        outputs.append(args.emit_c.expanduser().resolve())
        if args.emit_c.suffix != ".c":
            raise ToolError("--emit-c must end in .c")
    if any(path.expanduser().resolve() in outputs for path in protected):
        raise ToolError("an output path would overwrite a source, header or preloaded file")
    destination.parent.mkdir(parents=True, exist_ok=True)
    for source in args.c_source:
        if not source.expanduser().is_file():
            raise ToolError(f"C source is not a file: {source}")
    with tempfile.TemporaryDirectory(prefix=".goose-wasm-", dir=destination.parent) as directory:
        stage = Path(directory)
        generated = stage / "program.c"
        run(frontend(args, goose, generated), verbose=args.verbose)
        module = stage / destination.name
        initial = max(32 * 1024 ** 2, args.call_stack_size + 16 * 1024 ** 2)
        memory_mode = "2"
        if args.memory64 or args.standalone:
            memory_mode = "1"
        pointer_flag = "-sMEMORY64=" + memory_mode
        if args.standalone:
            pointer_flag = "-m64"
        command = [emcc, str(generated), args.optimization,
                   "-fno-strict-aliasing", "-ffp-contract=off", pointer_flag,
                   "-sALLOW_MEMORY_GROWTH=1", f"-sINITIAL_MEMORY={initial}",
                   f"-sMAXIMUM_MEMORY={args.max_memory}",
                   f"-sSTACK_SIZE={args.call_stack_size}", "-sSTACK_OVERFLOW_CHECK=2",
                   "-sASSERTIONS=1",
                   "-sERROR_ON_UNDEFINED_SYMBOLS=1"]
        if args.standalone:
            # LP64 C and the full memory64 proposal retain upstream layouts.
            # Its WASI imports also use 64-bit pointer/size parameters; the
            # repository runners explicitly implement this host ABI.
            command.extend([
                "-sSTANDALONE_WASM=1", "-fwasm-exceptions",
                "-sSUPPORT_LONGJMP=wasm", "-sWASM_LEGACY_EXCEPTIONS=0",
            ])
        else:
            command.extend([
                "-sEXPORT_NAME=createGooseModule",
                "-sEXIT_RUNTIME=1",
                "-sEXPORTED_RUNTIME_METHODS=FS,callMain", "-sFORCE_FILESYSTEM=1",
                "-sENVIRONMENT=node,web,worker",
                "--extern-pre-js", str(HERE / "host_paths.js.in"),
                "--extern-post-js", str(HERE / "node_entry.js.in"),
            ])
        command.extend(["-o", str(module)])
        headers = [Path(goose).parent / "include", Path(goose).parent.parent / "src" / "runtime"]
        for header_dir in headers:
            if (header_dir / "goose.h").is_file():
                command.extend(["-I", str(header_dir)])
                break
        for header_dir in args.c_include_dir:
            command.extend(["-I", str(header_dir.expanduser().resolve())])
        for source in args.c_source:
            command.append(str(source.expanduser().resolve()))
        for item in args.preload_file:
            command.extend(["--preload-file", item])
        run(command, verbose=args.verbose)
        wasm = module
        if not args.standalone:
            wasm = module.with_suffix(".wasm")
        if not module.is_file() or not wasm.is_file():
            raise ToolError("Emscripten succeeded without producing the requested Wasm output")
        with wasm.open("rb") as stream:
            if stream.read(8) != b"\0asm\x01\0\0\0":
                raise ToolError("Emscripten output is not a WebAssembly module")
        if args.emit_c:
            c_path = args.emit_c.expanduser().resolve()
            if c_path in (destination, destination.with_suffix(".wasm")):
                raise ToolError("--emit-c must not overwrite the generated module")
            c_path.parent.mkdir(parents=True, exist_ok=True)
            # Goose makes includes relative to the generated C destination.
            # Generate at the requested location so saved C is independently buildable.
            run(frontend(args, goose, c_path), verbose=args.verbose)
        # Publish the executable last. A failed compile leaves earlier outputs intact.
        for artifact in sorted(stage.iterdir()):
            if artifact not in (generated, module) and artifact.is_file():
                artifact.replace(destination.parent / artifact.name)
        module.replace(destination)
    print(f"Wrote {destination}")
    if not args.standalone:
        print(f"Wrote {destination.with_suffix('.wasm')}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    sub.add_parser("version", help="print the pinned compiler and SDK versions")
    for name in ("build", "check"):
        command = sub.add_parser(name, help=f"{name} a Goose program for WebAssembly")
        command.add_argument("source", type=Path)
        command.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
        command.add_argument("--goose", help="override the patched native Goose compiler")
        command.add_argument("--stdlib", type=Path)
        command.add_argument("--stack-size", type=byte_size, default=16 * 1024 ** 2,
                             help="fixed capacity per data stack, default 16M")
        levels = command.add_mutually_exclusive_group()
        levels.add_argument("-O0", dest="optimization", action="store_const", const="-O0")
        levels.add_argument("-O1", dest="optimization", action="store_const", const="-O1")
        levels.add_argument("-O2", dest="optimization", action="store_const", const="-O2")
        command.set_defaults(optimization="-O2")
        command.add_argument("--debug", action="store_true", help="enable Goose arithmetic checks")
        command.add_argument("--offline", action="store_true", help="disable source package fetching")
        command.add_argument("--include", type=Path, action="append", default=[],
                             help="C ABI header for static externs (repeatable)")
        command.add_argument("--verbose", action="store_true")
        if name == "build":
            command.add_argument("-o", "--output", type=Path, required=True)
            command.add_argument("--emcc", help="path to emcc, default EMCC or PATH")
            command.add_argument("--memory64", action="store_true",
                                 help="emit native memory64 instead of wasm32 compatibility mode")
            command.add_argument("--standalone", action="store_true",
                                 help="emit a memory64 .wasm with explicit WASI64 imports; no JavaScript host")
            command.add_argument("--max-memory", type=byte_size, default=2 * 1024 ** 3)
            command.add_argument("--call-stack-size", type=byte_size, default=4 * 1024 ** 2)
            command.add_argument("--c-source", type=Path, action="append", default=[],
                                 help="target-compatible C extern implementation (repeatable)")
            command.add_argument("--c-include-dir", type=Path, action="append", default=[],
                                 help="additional include directory for C extern sources (repeatable)")
            command.add_argument("--preload-file", action="append", default=[],
                                 help="Emscripten file@virtual-path asset (repeatable)")
            command.add_argument("--emit-c", type=Path, help="also save generated standalone C")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.command == "version":
        print(f"Goose/Wasm: {PIN['revision']}; Emscripten {PIN['emscripten']}")
        return 0
    try:
        validate_sizes(args)
        goose = compiler(args)
        if args.command == "check":
            run(frontend(args, goose, None), verbose=args.verbose)
        else:
            build(args, goose)
        return 0
    except (ToolError, OSError) as error:
        print(f"goose-wasm: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
