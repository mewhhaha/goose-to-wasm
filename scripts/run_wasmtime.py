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
import os
from pathlib import Path
import struct
import sys
import threading
import time

# A program given arguments (the compiler compiled to Wasm among them) may
# recurse deeply and may hold a 64-bit memory far larger than what it touches:
# it gets this much stack, and this much address space reserved up front so
# that growing the memory never moves it.
HOSTED_STACK_BYTES = 512 << 20
HOSTED_RESERVATION_BYTES = 1 << 40


def f32(value: float) -> float:
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


def f32_scientific(magnitude: float) -> str:
    """The shortest scientific text of a positive finite f32, as native gs_fmt_f32 chooses it.

    That is the fewest significant digits that read back as the same f32, of those
    the nearest to its exact value, and of two as near the even one. Exact integers
    decide each step: one rounded candidate per length misses shorter text below a
    power of two, where the gap to the next f32 down is half the gap up.
    """
    bits = struct.unpack("<I", struct.pack("<f", magnitude))[0]
    biased, fraction = bits >> 23, bits & 0x7FFFFF
    significand = fraction | 0x800000 if biased else fraction
    # The value is quarter * 2**binary; what reads back as it reaches from
    # quarter - below to quarter + 2 in the same unit, ends included when the
    # significand is even, since reading rounds a tie to the even significand.
    quarter = significand * 4
    binary = (biased or 1) - 152
    below = 1 if fraction == 0 and biased > 1 else 2
    inclusive = significand % 2 == 0

    def scaled(scale):
        # Integers proportional to one unit of the value and one unit of 10**scale.
        return (2 ** max(binary, 0) * 10 ** max(-scale, 0), 2 ** max(-binary, 0) * 10 ** max(scale, 0))

    exponent = math.floor(math.log10(magnitude))
    while True:
        value_unit, decimal_unit = scaled(exponent)
        leading = quarter * value_unit // decimal_unit
        if leading >= 10:
            exponent += 1
        elif leading < 1:
            exponent -= 1
        else:
            break
    precision = 1
    while True:
        value_unit, decimal_unit = scaled(exponent - precision + 1)
        exact = quarter * value_unit
        low, high = (quarter - below) * value_unit, (quarter + 2) * value_unit
        truncated = exact // decimal_unit
        best = best_distance = None
        for digits in (truncated, truncated + 1):
            candidate = digits * decimal_unit
            if not (low <= candidate <= high if inclusive else low < candidate < high):
                continue
            distance = abs(candidate - exact)
            if best is None or distance < best_distance or (distance == best_distance and digits % 2 == 0):
                best, best_distance = digits, distance
        if best is not None:
            # A carry to 10**precision spells one more digit at the next power.
            text = str(best)
            digits = text.rstrip("0")
            mantissa = digits[0] + ("." + digits[1:] if len(digits) > 1 else "")
            return mantissa + "e" + str(exponent + len(text) - precision)
        precision += 1


def goose_float(value: float, bits: int = 64) -> str:
    if bits == 32:
        value = f32(value)
    if math.isnan(value):
        return "nan"
    if math.isinf(value):
        return "-inf" if value < 0 else "inf"
    negative = math.copysign(1, value) < 0
    if value == 0:
        return "-0.0" if negative else "0.0"
    magnitude = abs(value)
    shortest = f32_scientific(magnitude) if bits == 32 else repr(magnitude)
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


def create_hosted_config():
    from wasmtime import _ffi

    config = create_config()
    # Wasmtime refuses a Wasm stack larger than its fiber stack size, which
    # the Python binding has no property for: set through the C interface.
    _ffi.wasmtime_config_async_stack_size_set(config.ptr(), HOSTED_STACK_BYTES + (1 << 20))
    config.max_wasm_stack = HOSTED_STACK_BYTES
    config.memory_reservation = HOSTED_RESERVATION_BYTES
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


def run_module(data: bytes, stdin: bytes | str, *, timing: bool = True,
               prepared: PreparedModule | None = None, arguments: list[str] | None = None,
               config=None, cache: Path | None = None, invoke_start=None,
               resource_dir: Path | None = None) -> dict:
    """Run a module; `stdin` is bytes as given, or a string as its UTF-8 bytes.

    fd_read sees exactly those bytes. Scalar imports read tokens from a
    byte-for-byte latin-1 view, split on ASCII whitespace as the C++ host splits them.
    `arguments` are what the program's os.arg sees, the program first. `cache`
    is a file this host keeps the compiled module in, beside the SHA-256 of the
    module it was compiled from; it is reused only for those same bytes.
    An optional `invoke_start(store, exports)` can configure a fresh instance
    before calling its entry point. Its work is included in the execution timer.
    """
    import wasmtime

    program_arguments = list(arguments) if arguments else ["program"]

    if prepared is not None and hashlib.sha256(data).hexdigest() != prepared.source_sha256:
        raise ValueError("prepared module does not match source bytes")
    input_bytes = stdin.encode() if isinstance(stdin, str) else bytes(stdin)
    tokens = (token.decode("latin-1") for token in input_bytes.split())
    chunks: list[bytes] = []
    errors: list[bytes] = []
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

    # A slice argument. A 32-bit module passes one i64 of pointer (low 32 bits)
    # and element count; a 64-bit one passes the pointer and the count as two
    # i64. `sliced` gives an import the same arguments either way: `kinds` has
    # an "s" for each slice parameter, which arrives as its bytes.
    def sliced(kinds, action):
        def call(caller, *values):
            wide = len(values) > len(kinds)
            converted, at = [], 0
            for kind in kinds:
                if kind != "s":
                    converted.append(values[at])
                    at += 1
                elif wide:
                    converted.append(memory_bytes(caller, values[at], values[at + 1]))
                    at += 2
                else:
                    packed = values[at] & ((1 << 64) - 1)
                    converted.append(memory_bytes(caller, packed & 0xffffffff, packed >> 32))
                    at += 1
            return action(caller, *converted)
        return call

    # Appends to the growable byte array whose control is at `control`: the
    # module's exported goose.reserve makes the room, as a push in the program
    # would, and says where the bytes go (docs/TARGET.md).
    def append_bytes(caller, control, data):
        reserve = caller.get("goose.reserve")
        if not isinstance(reserve, wasmtime.Func):
            raise RuntimeError("module does not export goose.reserve")
        destination = reserve(caller, control, len(data))
        write_bytes(caller, destination if destination >= 0 else destination & 0xffffffff, bytes(data))

    def tried(action):
        try:
            return 1 if action() else 0
        except OSError:
            return 0

    def read_file(caller, path, control):
        def action():
            append_bytes(caller, control, Path(os.fsdecode(path)).read_bytes())
            return True
        return tried(action)

    def write_file(mode):
        def call(_caller, path, data):
            def action():
                with open(os.fsdecode(path), mode) as stream:
                    stream.write(data)
                return True
            return tried(action)
        return call

    def write_file_atomic(_caller, path, data):
        def action():
            target = os.fsdecode(path)
            tmp = f"{target}.tmp-{os.getpid()}-{os.urandom(6).hex()}"
            try:
                with open(tmp, "wb") as stream:
                    stream.write(data)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(tmp, target)
            except BaseException:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                raise
            return True
        return tried(action)

    def make_dir(_caller, path):
        def action():
            target = os.fsdecode(path)
            try:
                os.mkdir(target)
                return True
            except FileExistsError:
                return os.path.isdir(target)
        return tried(action)

    def list_dir(caller, path, control):
        def action():
            names = sorted(name for name in os.listdir(os.fsdecode(path)) if "\n" not in name)
            payload = "".join(name + "\n" for name in names).encode("utf-8", errors="surrogateescape")
            append_bytes(caller, control, payload)
            return True
        return tried(action)

    def read_line(caller, control):
        nonlocal input_position
        if input_position >= len(input_bytes):
            return 0
        nl = input_bytes.find(b"\n", input_position)
        if nl < 0:
            line = input_bytes[input_position:]
            input_position = len(input_bytes)
        else:
            line = input_bytes[input_position:nl]
            input_position = nl + 1
        if line.endswith(b"\r"):
            line = line[:-1]
        append_bytes(caller, control, line)
        return 1

    def read_stdin(caller, control):
        nonlocal input_position
        if input_position < len(input_bytes):
            append_bytes(caller, control, input_bytes[input_position:])
            input_position = len(input_bytes)

    def program_argument(caller, index, control):
        if 0 <= index < len(program_arguments):
            append_bytes(caller, control, os.fsencode(program_arguments[index]))

    def environment_variable(caller, name, control):
        if hasattr(os, "environb"):
            value = os.environb.get(name)
        else:
            raw = os.environ.get(name.decode("utf-8", errors="surrogateescape"))
            value = None if raw is None else raw.encode("utf-8")
        if value is None:
            return 0
        append_bytes(caller, control, value)
        return 1

    def resource_dir_host(caller, control):
        if resource_dir is None:
            return 0
        text = str(resource_dir)
        if not text.endswith(os.sep):
            text += os.sep
        append_bytes(caller, control, os.fsencode(text))
        return 1

    # std's byte-set searches: a set's members are its first 256 bytes.
    def find_any(caller, data, members):
        table = memory_bytes(caller, members & ((1 << 64) - 1) if members >= 0 else members & 0xffffffff, 256)
        for index, byte in enumerate(data):
            if table[byte]:
                return index
        return -1

    def find_pair(caller, data, first, distance, second):
        if distance < 0 or distance >= len(data):
            return -1
        address = lambda value: value if value >= 0 else value & 0xffffffff
        a, b = memory_bytes(caller, address(first), 256), memory_bytes(caller, address(second), 256)
        for index in range(len(data) - distance):
            if a[data[index]] and b[data[index + distance]]:
                return index
        return -1

    def format_float(caller, pointer, value, bits):
        text = goose_float(value, bits).encode()
        if len(text) > 32:
            raise RuntimeError("formatted float exceeds host buffer")
        if pointer < 0:
            # An i32 address above 2 GiB arrives negative; an i64 one of a
            # 64-bit memory keeps all its bits.
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
        # The stdlib's `os` externs, for a program that reads and writes files
        # (the compiler itself among them), as scripts/run_wasm.mjs has them.
        ("env", "gs_os_read_file"): (sliced("sr", read_file), True),
        ("env", "gs_os_write_file"): (sliced("ss", write_file("wb")), True),
        ("env", "gs_os_write_file_atomic"): (sliced("ss", write_file_atomic), True),
        ("env", "gs_os_append_file"): (sliced("ss", write_file("ab")), True),
        ("env", "gs_os_file_exists"): (sliced("s", lambda _c, path: tried(lambda: os.path.isfile(path))), True),
        ("env", "gs_os_remove_file"): (sliced("s", lambda _c, path: tried(lambda: (os.unlink(os.fsdecode(path)), True)[1])), True),
        ("env", "gs_os_rename_file"): (sliced("ss", lambda _c, src, dst: tried(lambda: (os.replace(os.fsdecode(src), os.fsdecode(dst)), True)[1])), True),
        ("env", "gs_os_make_dir"): (sliced("s", make_dir), True),
        ("env", "gs_os_is_dir"): (sliced("s", lambda _c, path: tried(lambda: os.path.isdir(path))), True),
        ("env", "gs_os_remove_dir"): (sliced("s", lambda _c, path: tried(lambda: (os.rmdir(os.fsdecode(path)), True)[1])), True),
        ("env", "gs_os_list_dir"): (sliced("sr", list_dir), True),
        ("env", "gs_os_read_line"): (read_line, True),
        ("env", "gs_os_read_stdin"): (read_stdin, True),
        ("env", "gs_os_write_stdout"): (sliced("s", lambda _c, text: chunks.append(text)), True),
        ("env", "gs_os_write_stderr"): (sliced("s", lambda _c, text: errors.append(text)), True),
        ("env", "gs_os_flush_stdout"): (lambda: None, False),
        ("env", "gs_os_arg_count"): (lambda: len(program_arguments), False),
        ("env", "gs_os_arg"): (program_argument, True),
        ("env", "gs_os_getenv"): (sliced("sr", environment_variable), True),
        ("env", "gs_os_resource_dir"): (resource_dir_host, True),
        ("env", "gs_os_clock_ns"): (time.perf_counter_ns, False),
        ("env", "gs_os_time_ns"): (time.time_ns, False),
        ("env", "gs_os_sleep_ms"): (lambda ms: time.sleep(ms / 1000.0) if ms > 0 else None, False),
        ("env", "gs_os_random_u64"): (lambda: struct.unpack("<q", os.urandom(8))[0], False),
        ("env", "gs_find_any"): (sliced("sr", find_any), True),
        ("env", "gs_find_pair"): (sliced("srrr", find_pair), True),
        # No process can be started from here: libc's system fails.
        ("env", "system"): (lambda _command: -1, False),
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
    if prepared is None and config is None:
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
        if prepared is not None:
            module = prepared.module
        elif cache is None:
            module = wasmtime.Module(engine, data)
        else:
            digest = hashlib.sha256(data).hexdigest()
            stamp = cache.with_name(cache.name + ".sha256")
            if cache.is_file() and stamp.is_file() and stamp.read_text().strip() == digest:
                module = wasmtime.Module.deserialize(engine, cache.read_bytes())
            else:
                module = wasmtime.Module(engine, data)
                cache.write_bytes(bytes(module.serialize()))
                stamp.write_text(digest + "\n")
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
        if invoke_start is None:
            exports["_start"](store)
        else:
            invoke_start(store, exports)
    except ProgramExit as failure:
        exit_code = failure.code
    except Exception as failure:
        exit_code = 1
        error = str(failure)
    ended = time.perf_counter_ns()
    # A module built with --wasm-region-stats exports its region table and
    # keeps each region's high-water mark. GOOSE_REGION_STATS=1 prints the
    # largest; GOOSE_REGION_PROFILE=path writes them all as "index bytes"
    # lines, what --wasm-region-profile reads.
    if (os.environ.get("GOOSE_REGION_STATS") or os.environ.get("GOOSE_REGION_PROFILE")) and store is not None and linker is not None:
        try:
            exports = instance.exports(store)
            wide = exports["goose.region_table"].type(store).content == wasmtime.ValType.i64()
            size, layout = (8, "<Q") if wide else (4, "<I")
            mask = (1 << (8 * size)) - 1
            table, count = exports["goose.region_table"].value(store) & mask, exports["goose.region_count"].value(store)
            memory, used = exports["memory"], []
            length = memory.data_len(store)
            read = lambda at: 0 if at + size > length else struct.unpack(layout, bytes(memory.read(store, at, at + size)))[0]
            for region in range(count):
                # A region ends in its cursor, its start and its high-water mark.
                end = read(table + (region + 1) * size)
                base, peak = read(end - 2 * size), read(end - size)
                if peak > base:
                    used.append((peak - base, region, end - read(table + region * size)))
            if os.environ.get("GOOSE_REGION_PROFILE"):
                Path(os.environ["GOOSE_REGION_PROFILE"]).write_text("".join(f"{region} {count}\n" for count, region, _ in sorted(used, key=lambda item: item[1])))
            used.sort(reverse=True)
            if os.environ.get("GOOSE_REGION_STATS"):
                errors.append(f"regions: {count}, memory {length}; most used ".encode()
                              + " ".join(f"#{region}:{held}/{room}" for held, region, room in used[:12]).encode() + b"\n")
        except (KeyError, NameError):
            pass
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
    parser = argparse.ArgumentParser(description=__doc__, usage="%(prog)s module.wasm [--timing-json path] [--cache path] [-- program arguments]")
    parser.add_argument("module", type=Path)
    parser.add_argument("--timing-json", type=Path)
    parser.add_argument("--cache", type=Path, help="keep the compiled module in this file and reuse it for the same module bytes")
    own = sys.argv[1:]
    program_arguments = None
    if "--" in own:
        at = own.index("--")
        own, program_arguments = own[:at], own[at + 1:]
    args = parser.parse_args(own)
    try:
        mod_dir = args.module.resolve().parent
        if program_arguments is None:
            result = run_module(args.module.read_bytes(), sys.stdin.buffer.read(), timing=args.timing_json is not None,
                                cache=args.cache, resource_dir=mod_dir)
        else:
            # On a thread whose stack holds the Wasm stack the config allows.
            outcome: dict = {}

            def hosted():
                try:
                    outcome["result"] = run_module(
                        args.module.read_bytes(), sys.stdin.buffer.read(), timing=args.timing_json is not None,
                        arguments=[str(args.module)] + program_arguments, config=create_hosted_config(),
                        cache=args.cache, resource_dir=mod_dir)
                except BaseException as failure:
                    outcome["failure"] = failure

            for stack_bytes in (HOSTED_STACK_BYTES + (64 << 20), 64 << 20, 16 << 20):
                try:
                    threading.stack_size(stack_bytes)
                    break
                except (ValueError, RuntimeError):
                    continue
            thread = threading.Thread(target=hosted)
            thread.start()
            thread.join()
            if "failure" in outcome:
                raise outcome["failure"]
            result = outcome["result"]
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
