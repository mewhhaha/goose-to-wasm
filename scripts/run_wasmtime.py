#!/usr/bin/env python3
"""Run direct Goose WebAssembly with the pinned Wasmtime Python bindings.

Only scalar input/output and benchmark boundary calls cross into Python.
The computational kernels execute entirely in compiled WebAssembly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import time


def f32(value: float) -> float:
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


def goose_float(value: float, bits: int = 64) -> str:
    if math.isnan(value):
        return "nan"
    if math.isinf(value):
        return "-inf" if value < 0 else "inf"
    negative = math.copysign(1, value) < 0
    if value == 0:
        return "-0.0" if negative else "0.0"
    magnitude = abs(value)
    shortest = repr(magnitude)
    if bits == 32:
        for precision in range(1, 10):
            candidate = format(magnitude, f".{precision}g")
            if f32(float(candidate)) == magnitude:
                shortest = candidate
                break
    pieces = shortest.lower().split("e")
    mantissa = pieces[0]
    exponent = int(pieces[1]) if len(pieces) > 1 else 0
    point = mantissa.find(".")
    if point < 0:
        point = len(mantissa)
    digits = mantissa.replace(".", "")
    leading = len(digits) - len(digits.lstrip("0"))
    exponent += point - leading - 1
    digits = digits[leading:].rstrip("0")
    if exponent < -4 or exponent >= max(15, len(digits)):
        text = digits[0]
        if len(digits) > 1:
            text += "." + digits[1:]
        text += "e" + ("-" if exponent < 0 else "+") + str(abs(exponent)).zfill(2)
    elif exponent < 0:
        text = "0." + "0" * (-exponent - 1) + digits
    elif len(digits) <= exponent + 1:
        text = digits + "0" * (exponent + 1 - len(digits)) + ".0"
    else:
        text = digits[:exponent + 1] + "." + digits[exponent + 1:]
    return ("-" if negative else "") + text


class ProgramExit(Exception):
    def __init__(self, code: int):
        self.code = code


def create_config():
    import wasmtime

    config = wasmtime.Config()
    config.cranelift_opt_level = "speed"
    config.wasm_memory64 = True
    config.wasm_tail_call = True
    config.wasm_exceptions = True
    config.wasm_simd = True
    config.wasm_bulk_memory = True
    config.wasm_multi_value = True
    config.wasm_threads = False
    config.wasm_relaxed_simd = False
    return config


def create_engine(config=None):
    import wasmtime

    if config is None:
        config = create_config()
    return wasmtime.Engine(config)


class PreparedModule:
    def __init__(self, engine, module, source_sha256, serialized_sha256, preparation):
        self.engine = engine
        self.module = module
        self.source_sha256 = source_sha256
        self.serialized_sha256 = serialized_sha256
        self.preparation = preparation


def prepare_module(data: bytes, artifact: Path) -> PreparedModule:
    """Compile and deserialize only our own just-written trusted local artifact."""
    import wasmtime

    started = time.perf_counter_ns()
    engine = create_engine()
    engine_ready = time.perf_counter_ns()
    compiled = wasmtime.Module(engine, data)
    compiled_at = time.perf_counter_ns()
    serialized = bytes(compiled.serialize())
    serialized_at = time.perf_counter_ns()
    with artifact.open("xb") as stream:
        stream.write(serialized)
    digest = hashlib.sha256(serialized).hexdigest()
    local = artifact.read_bytes()
    if hashlib.sha256(local).hexdigest() != digest:
        raise ValueError("just-written trusted Wasmtime artifact changed")
    read_at = time.perf_counter_ns()
    module = wasmtime.Module.deserialize(engine, local)
    finished = time.perf_counter_ns()
    return PreparedModule(engine, module, hashlib.sha256(data).hexdigest(), digest,
                          {"engine_creation_ns": engine_ready - started,
                           "module_compile_ns": compiled_at - engine_ready,
                           "serialize_ns": serialized_at - compiled_at,
                           "write_read_verify_ns": read_at - serialized_at,
                           "deserialize_ns": finished - read_at,
                           "total_ns": finished - started, "module_compile_count": 1,
                           "module_deserialize_count": 1, "serialized_path": str(artifact)})


def run_module(data: bytes, stdin: str, *, timing: bool = True, prepared: PreparedModule | None = None) -> dict:
    import wasmtime

    if prepared is not None and hashlib.sha256(data).hexdigest() != prepared.source_sha256:
        raise ValueError("prepared module does not match source bytes")
    tokens = iter(stdin.split())
    chunks: list[bytes] = []
    errors: list[bytes] = []
    input_bytes = stdin.encode()
    input_position = 0
    sink = 0

    def read_integer():
        value = int(next(tokens), 10)
        if not -(1 << 63) <= value < (1 << 63):
            raise ValueError("host input exceeds i64")
        return value

    def memory_bytes(caller, pointer, length):
        memory = caller.get("memory")
        if not isinstance(memory, wasmtime.Memory):
            raise RuntimeError("module does not export memory")
        start, size = pointer, length
        if start < 0 or size < 0:
            raise RuntimeError("negative host address")
        if start + size > memory.data_len(caller):
            raise RuntimeError("host write is outside exported memory")
        return bytes(memory.read(caller, start, start + size))

    def write_bytes(caller, pointer, value):
        memory_bytes(caller, pointer, len(value))
        caller.get("memory").write(caller, value, pointer)

    def write64(caller, pointer, value):
        write_bytes(caller, pointer, struct.pack("<Q", value))

    def format_float(caller, pointer, value, bits):
        text = goose_float(value, bits).encode()
        if len(text) > 32:
            raise RuntimeError("formatted float exceeds host buffer")
        pointer &= 0xffffffff
        memory_bytes(caller, pointer, 32)
        write_bytes(caller, pointer, text)
        return len(text)

    def iovecs(caller, pointer, count):
        data = memory_bytes(caller, pointer, count * 16)
        return struct.iter_unpack("<QQ", data)

    def args_sizes(caller, argc, size):
        write64(caller, argc, 1)
        write64(caller, size, 8)
        return 0

    def args_get(caller, argv, buffer):
        write64(caller, argv, buffer)
        write_bytes(caller, buffer, b"program\0")
        return 0

    def environment_sizes(caller, count, size):
        write64(caller, count, 0)
        write64(caller, size, 0)
        return 0

    def clock_get(caller, clock, _precision, pointer):
        if clock == 0:
            value = time.time_ns()
        elif clock == 1:
            value = time.perf_counter_ns()
        else:
            return 28
        write64(caller, pointer, value)
        return 0

    def fd_write(caller, fd, pointer, count, written):
        if fd not in (1, 2):
            return 8
        target = chunks if fd == 1 else errors
        total = 0
        for start, size in iovecs(caller, pointer, count):
            target.append(memory_bytes(caller, start, size))
            total += size
        write64(caller, written, total)
        return 0

    def fd_read(caller, fd, pointer, count, read):
        nonlocal input_position
        if fd != 0:
            return 8
        total = 0
        for start, size in iovecs(caller, pointer, count):
            selected = input_bytes[input_position:input_position + size]
            write_bytes(caller, start, selected)
            input_position += len(selected)
            total += len(selected)
            if len(selected) < size:
                break
        write64(caller, read, total)
        return 0

    def abort(caller, pointer, length, line):
        message = memory_bytes(caller, pointer, length).decode("utf-8", errors="replace")
        raise RuntimeError(f"goose runtime error: {message} (line {line})")

    def exit_program(code):
        raise ProgramExit(code)

    def barrier(value):
        nonlocal sink
        sink = value
        return sink

    def consume(value):
        nonlocal sink
        sink = value

    functions = {
        ("goose", "write"): (lambda c, p, n: chunks.append(memory_bytes(c, p, n)), True),
        ("goose", "print_i64"): (lambda value: chunks.append(str(value).encode()), False),
        ("goose", "print_u64"): (lambda value: chunks.append(str(value & ((1 << 64) - 1)).encode()), False),
        ("goose", "print_f64"): (lambda value: chunks.append(goose_float(value).encode()), False),
        ("goose", "print_f32"): (lambda value: chunks.append(goose_float(value, 32).encode()), False),
        ("goose", "format_f64"): (lambda c, p, v: format_float(c, p, v, 64), True),
        ("goose", "format_f32"): (lambda c, p, v: format_float(c, p, v, 32), True),
        ("goose", "print_bool"): (lambda value: chunks.append(b"true" if value else b"false"), False),
        ("goose", "newline"): (lambda: chunks.append(b"\n"), False),
        ("goose", "abort"): (abort, True),
        ("goose", "exit"): (exit_program, False),
        ("env", "bench_input"): (read_integer, False),
        ("env", "bench_input_f64"): (lambda: float(next(tokens)), False),
        ("env", "bench_clock"): (time.perf_counter_ns, False),
        ("env", "bench_barrier"): (barrier, False),
        ("env", "bench_sink"): (consume, False),
        ("env", "emscripten_notify_memory_growth"): (lambda _index: None, False),
        ("wasi_snapshot_preview1", "args_sizes_get"): (args_sizes, True),
        ("wasi_snapshot_preview1", "args_get"): (args_get, True),
        ("wasi_snapshot_preview1", "environ_sizes_get"): (environment_sizes, True),
        ("wasi_snapshot_preview1", "environ_get"): (lambda _a, _b: 0, False),
        ("wasi_snapshot_preview1", "clock_time_get"): (clock_get, True),
        ("wasi_snapshot_preview1", "proc_exit"): (exit_program, False),
        ("wasi_snapshot_preview1", "fd_write"): (fd_write, True),
        ("wasi_snapshot_preview1", "fd_read"): (fd_read, True),
        ("wasi_snapshot_preview1", "fd_close"): (lambda fd: 0 if fd in (0, 1, 2) else 8, False),
        ("wasi_snapshot_preview1", "fd_seek"): (lambda fd, _offset, _whence, _out: 70 if fd in (0, 1, 2) else 8, False),
    }
    config = None
    if prepared is None:
        config = create_config()
    started = time.perf_counter_ns()
    instantiated = started
    exit_code = 0
    error = ""
    store = None
    linker = None
    try:
        if prepared is None:
            engine = create_engine(config)
        else:
            engine = prepared.engine
        store = wasmtime.Store(engine)
        if prepared is None:
            module = wasmtime.Module(engine, data)
        else:
            module = prepared.module
        linker = wasmtime.Linker(engine)
        defined = set()
        for imported in module.imports:
            key = (imported.module, imported.name)
            if key in defined:
                continue
            if key not in functions or not isinstance(imported.type, wasmtime.FuncType):
                raise RuntimeError(f"unsupported direct host import: {imported.module}.{imported.name}")
            callback, with_caller = functions[key]
            linker.define_func(imported.module, imported.name, imported.type, callback, access_caller=with_caller)
            defined.add(key)
        instance = linker.instantiate(store, module)
        exports = instance.exports(store)
        if "__set_stack_limits" in exports:
            exports["emscripten_stack_init"](store)
            exports["__set_stack_limits"](
                store, exports["emscripten_stack_get_base"](store), exports["emscripten_stack_get_end"](store)
            )
        instantiated = time.perf_counter_ns()
        exports["_start"](store)
    except ProgramExit as failure:
        exit_code = failure.code
    except Exception as failure:
        exit_code = 1
        error = str(failure)
    ended = time.perf_counter_ns()
    if prepared is not None:
        if linker is not None:
            linker.close()
        if store is not None:
            store.close()
    result = {
        "stdout": b"".join(chunks), "stderr": b"".join(errors).decode(errors="replace") + error, "exit_code": exit_code,
    }
    if timing:
        from importlib.metadata import version

        result["timing"] = {
            "engine": "Wasmtime", "wasmtime": version("wasmtime"),
            "optimization": "cranelift speed", "compile_instantiate_ns": instantiated - started,
            "start_function_ns": ended - instantiated, "engine_total_ns": ended - started,
        }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module", type=Path)
    parser.add_argument("--timing-json", type=Path)
    args = parser.parse_args()
    try:
        result = run_module(args.module.read_bytes(), sys.stdin.read(), timing=args.timing_json is not None)
        sys.stdout.buffer.write(result["stdout"])
        if result["stderr"]:
            print(result["stderr"], file=sys.stderr)
        if args.timing_json:
            args.timing_json.write_text(json.dumps(result["timing"], indent=2) + "\n", encoding="utf-8")
        return result["exit_code"]
    except ImportError:
        print("Wasmtime bindings missing; install wasmtime==50.0.1", file=sys.stderr)
        return 1
    except (OSError, RuntimeError, ValueError) as error:
        print(f"direct Wasmtime host: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
