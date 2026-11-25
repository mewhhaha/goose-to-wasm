"""Exercise fixed-size memory operations and field-load displacements at byte boundaries."""
import subprocess
import sys
import unittest

import wasmtime

from tests import goose_stats


SOURCE = """struct CopyArguments { destination: u8[33]&, source: const u8[33]& }
struct Padded { pad 34, tag: u8 }
extern fn place_copy(arguments: u8[16]&);
extern fn observe_image(image: const Padded&);
var destination: u8[33] = [0; 33];
var source: u8[33] = [0; 33];

export fn move_image() {
    var arguments = CopyArguments { destination, source };
    let reference: CopyArguments&? = &arguments;
    place_copy(reference as! u8[16]&);
    arguments.destination = arguments.source;
}

export fn clear_image() {
    let image = Padded { 9 };
    observe_image(image);
}

fn main() {}
"""


def exported_body(wasm, name):
    sections = dict(goose_stats.sections(wasm))
    # This fixture imports only functions.
    imports, _ = goose_stats.uleb(sections[2], 0)
    exports = sections[7]
    count, offset = goose_stats.uleb(exports, 0)
    for _ in range(count):
        length, offset = goose_stats.uleb(exports, offset)
        export = exports[offset:offset + length].decode()
        offset += length
        kind = exports[offset]
        index, offset = goose_stats.uleb(exports, offset + 1)
        if export == name and kind == 0:
            code = sections[10]
            _, offset = goose_stats.uleb(code, 0)
            for _ in range(index - imports + 1):
                length, offset = goose_stats.uleb(code, offset)
                body = code[offset:offset + length]
                offset += length
            return body
    raise AssertionError(f"missing {name} export")


class FixedMemoryOps(goose_stats.Compile, unittest.TestCase):
    def test_field_load_displacement_fits_memory32(self):
        source = """struct Large { pad 65536, field: i64 = 42 }
fn read(record: const Large&) -> i64 { record.field }
fn main() {
    let record = Large {};
    var enabled: u8[>..] = [];
    enabled.push(1);
    if enabled[0] == 1 { print(read(record)); }
}
"""
        for pages, folded in ((256, True), (65535, False)):
            with self.subTest(pages=pages):
                module, _ = self.compile(2, text=source, flags=("--wasm-bundled-host", "--wasm-max-pages", str(pages)))
                code = dict(goose_stats.sections(module.read_bytes()))[10]
                count, offset = goose_stats.uleb(code, 0)
                loads = []
                for _ in range(count):
                    size, start = goose_stats.uleb(code, offset)
                    offset = start + size
                    loads.extend(arg for op, arg in goose_stats.instruction_operands(code[start:offset]) if op == 0x29)
                self.assertEqual(65536 in loads, folded)
                output = subprocess.check_output([goose_stats.NODE, goose_stats.ROOT / "scripts/run_wasm.mjs", module], timeout=30)
                self.assertEqual(output, b"42\n")

    def test_field_load_displacement_memory64(self):
        source = """struct Large { pad 65536, field: i64 = 42 }
fn read(record: const Large&) -> i64 { record.field }
fn main() {
    let record = Large {};
    var enabled: u8[>..] = [];
    enabled.push(1);
    if enabled[0] == 1 { print(read(record)); }
}
"""
        module, _ = self.compile(2, text=source, flags=("--wasm-memory64", "--wasm-max-pages", "4194304"))
        code = dict(goose_stats.sections(module.read_bytes()))[10]
        count, offset = goose_stats.uleb(code, 0)
        loads = []
        for _ in range(count):
            size, start = goose_stats.uleb(code, offset)
            offset = start + size
            loads.extend(arg for op, arg in goose_stats.instruction_operands(code[start:offset]) if op == 0x29)
        self.assertIn(65536, loads)
        output = subprocess.check_output([sys.executable, goose_stats.ROOT / "scripts/run_wasmtime.py", module], timeout=30)
        self.assertEqual(output, b"42\n")

    def test_vector_copy_and_zero_fill(self):
        source = self.work / "images.goose"
        source.write_text(SOURCE)
        output = self.work / "images.wasm"
        for width, level, bundled in ((32, 2, True), (32, 2, False), (32, 0, True), (64, 2, True)):
            with self.subTest(width=width, level=level, bundled=bundled):
                command = [goose_stats.GOOSE, source, "--target", "wasm-direct", f"-O{level}", "-o", output]
                if width == 64:
                    command.append("--wasm-memory64")
                if bundled:
                    command.append("--wasm-bundled-host")
                result = subprocess.run(command, capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr)
                wasm = output.read_bytes()
                vector = width == 32 and level == 2 and bundled
                # v128.load at zero and v128.store at the exact 33-byte tail.
                move = exported_body(wasm, "move_image")
                self.assertEqual(b"\xfd\x00\x00\x00" in move, vector)
                self.assertEqual(b"\xfd\x0b\x00\x11" in move, vector)
                # The fill checks its exact 35-byte extent before its lower stores.
                clear = exported_body(wasm, "clear_image")
                stores = [clear.find(b"\xfd\x0f\xfd\x0b\x00" + bytes([offset])) for offset in (19, 16, 0)]
                if vector:
                    self.assertLess(-1, stores[0])
                    self.assertLess(stores[0], stores[1])
                    self.assertLess(stores[1], stores[2])
                else:
                    self.assertEqual(stores, [-1, -1, -1])
                self.run_images(wasm, width)

    def run_images(self, wasm, width):
        engine = wasmtime.Engine()
        module = wasmtime.Module(engine, wasm)
        store = wasmtime.Store(engine)
        linker = wasmtime.Linker(engine)
        destination = origin = 0
        images = []

        def place_copy(caller, address):
            # The host supplies two raw Wasm addresses in the record's slots.
            arguments = destination.to_bytes(width // 8, "little") + origin.to_bytes(width // 8, "little")
            caller.get("memory").write(caller, arguments, address)

        def observe_image(caller, address):
            memory = caller.get("memory")
            images.append(bytes(memory.read(caller, address, address + 35)))
            # Leave residue in this activation's local and temporary storage.
            memory.write(caller, b"\xaa" * 80, address)

        callbacks = {"place_copy": place_copy, "observe_image": observe_image}
        for item in module.imports:
            if item.name in callbacks:
                linker.define_func(item.module, item.name, item.type, callbacks[item.name], access_caller=True)
            else:
                self.assertEqual(item.module, "goose")
                linker.define_func(item.module, item.name, item.type, lambda *args: None)
        exports = linker.instantiate(store, module).exports(store)
        exports["_start"](store)
        memory = exports["memory"]
        boundary = memory.data_len(store)
        base = boundary - 96
        payload = bytes(range(96))

        for into, start in ((1, 0), (0, 1), (17, 0), (0, 17)):
            destination, origin = base + into, base + start
            memory.write(store, payload, base)
            exports["move_image"](store)
            expected = bytearray(payload)
            expected[into:into + 33] = payload[start:start + 33]
            self.assertEqual(memory.read(store, base, boundary), expected)

        for destination, origin in ((boundary - 16, base), (base, boundary - 16)):
            memory.write(store, payload, base)
            with self.assertRaises(wasmtime.Trap):
                exports["move_image"](store)
            self.assertEqual(memory.read(store, base, boundary), payload)

        exports["clear_image"](store)
        exports["clear_image"](store)
        self.assertEqual(images, [bytes(34) + b"\x09"] * 2)
