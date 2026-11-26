#!/usr/bin/env python3
"""Browser host contracts and stdlib-web programs on direct Wasm."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import wasmtime

from tests.test_script_hosts import F32_TEXT

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew"))
WEB = ROOT / "host/web"
STDLIB = ROOT / "stdlib"
WEB_STDLIB = ROOT / "stdlib-web"
CORE_MODULES = (
    "base64", "binary", "csv", "dictionary", "exception", "ffi", "json",
    "math", "os", "regex", "slice_pool", "slot_pool", "std", "vec",
)
F64_CASES = {
    0.1: "0.1",
    2000000.25: "2000000.25",
    1e15: "1e+15",
    123456789012345.6: "123456789012345.6",
    5e-324: "5e-324",
    -0.0001: "-0.0001",
    1.7976931348623157e308: "1.7976931348623157e+308",
}


class WebSources(unittest.TestCase):
    def test_no_node_dependencies(self):
        forbidden = re.compile(r"""["']node:|\brequire\(|\bBuffer\.|\bprocess\.|\bglobal\.""")
        for src in sorted(WEB.glob("*.js")):
            with self.subTest(file=src.name):
                matches = [
                    f"{src.name}:{number}: {line.strip()}"
                    for number, line in enumerate(src.read_text(encoding="utf-8").splitlines(), 1)
                    if forbidden.search(line)
                ]
                self.assertEqual(matches, [], "\n".join(matches))

    def test_core_modules_match_stdlib(self):
        for module in CORE_MODULES:
            with self.subTest(module=module):
                name = f"{module}.goose"
                self.assertTrue((WEB_STDLIB / name).read_bytes() == (STDLIB / name).read_bytes(),
                                f"{name} differs between stdlib and stdlib-web")

    @unittest.skipUnless(shutil.which("node"), "Node.js is required")
    def test_node_syntax(self):
        for src in sorted(WEB.glob("*.js")):
            with self.subTest(file=src.name):
                result = subprocess.run(["node", "--check", str(src)], cwd=ROOT,
                                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which("bun") or shutil.which("deno"), "Bun or Deno is required")
    def test_bun_and_deno_import(self):
        script = 'import {runGoose} from "./host/web/index.js"; if (typeof runGoose !== "function") throw Error();'
        for engine, flag in (("bun", "-e"), ("deno", "eval")):
            if shutil.which(engine):
                with self.subTest(engine=engine):
                    result = subprocess.run([engine, flag, script], cwd=ROOT,
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                    self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))


class WebHostCase(unittest.TestCase):
    def node(self, script, *args):
        result = subprocess.run(
            ["node", "--input-type=module", "-e", script, "--", *map(str, args)],
            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


@unittest.skipUnless(shutil.which("node"), "Node.js is required")
class WebHostUnits(WebHostCase):
    def test_float_formatting(self):
        self.node(r"""
          import assert from "node:assert/strict";
          import {gooseFloat, gooseFloatDigits} from "./host/web/index.js";

          const bits = new DataView(new ArrayBuffer(4));
          for (const [pattern, text] of JSON.parse(process.argv[1])) {
            bits.setUint32(0, pattern);
            assert.equal(gooseFloat(bits.getFloat32(0), 32), text, pattern.toString(16));
          }
          for (const [value, text] of JSON.parse(process.argv[2])) {
            assert.equal(gooseFloat(value, 64), text, String(value));
          }
          for (const [value, digits, point] of [
            [1.5, "15", 1], [0.0025, "25", -2], [100.0, "1", 3],
            [0.0, "", 0], [-0.0, "", 0], [NaN, "", 0], [Infinity, "", 0],
          ]) {
            const actual = gooseFloatDigits(value);
            assert.deepEqual(actual, {digits: new TextEncoder().encode(digits), point}, String(value));
          }
        """, json.dumps(list(F32_TEXT.items())), json.dumps(list(F64_CASES.items())))

    def test_persistent_filesystems(self):
        self.node(r"""
          import assert from "node:assert/strict";
          import {LocalStorageFS, OPFSAdapter} from "./host/web/index.js";

          const binary = Uint8Array.of(0, 255, 10, 128);
          const name = "/data/ωmega-日本-🐟.txt";
          const utf8 = "héllo 🐟";
          const values = new Map();
          const storage = {
            getItem: (key) => values.get(key) ?? null,
            setItem: (key, value) => values.set(key, String(value)),
            removeItem: (key) => values.delete(key),
          };
          const storageOptions = {storage, prefix: "test:"};
          const local = new LocalStorageFS(storageOptions);
          assert.equal(local.makeDir("/data"), true);
          assert.equal(local.writeText(name, utf8), true);
          assert.equal(local.writeFile("/data/raw", binary), true);
          const reloaded = new LocalStorageFS(storageOptions);
          assert.equal(reloaded.readText(name), utf8);
          assert.deepEqual(reloaded.readFile("/data/raw"), binary);
          reloaded.clearStorage();
          assert.equal(values.size, 0);
          assert.deepEqual(new LocalStorageFS(storageOptions).snapshot(), {});

          class FileHandle {
            kind = "file";
            data = new Uint8Array();
            open = false;

            async createSyncAccessHandle() {
              assert.equal(this.open, false);
              this.open = true;
              return {
                getSize: () => this.data.length,
                read: (out, {at}) => {
                  const chunk = this.data.subarray(at, at + Math.min(out.length, 13));
                  out.set(chunk);
                  return chunk.length;
                },
                write: (input, {at}) => {
                  const chunk = input.subarray(0, 11);
                  if (at + chunk.length > this.data.length) {
                    const next = new Uint8Array(at + chunk.length);
                    next.set(this.data);
                    this.data = next;
                  }
                  this.data.set(chunk, at);
                  return chunk.length;
                },
                truncate: (size) => {
                  const next = new Uint8Array(size);
                  next.set(this.data.subarray(0, size));
                  this.data = next;
                },
                flush: () => assert.equal(this.open, true),
                close: () => { this.open = false; },
              };
            }
          }

          class DirectoryHandle {
            kind = "directory";
            children = new Map();

            async *entries() { yield* this.children; }

            child(name, options, Type) {
              if (!this.children.has(name) && options.create) this.children.set(name, new Type());
              const child = this.children.get(name);
              assert.ok(child instanceof Type, name);
              return child;
            }

            async getDirectoryHandle(name, options) { return this.child(name, options, DirectoryHandle); }
            async getFileHandle(name, options) { return this.child(name, options, FileHandle); }
          }

          const root = new DirectoryHandle();
          const seed = await root.getFileHandle("seed", {create: true});
          seed.data = binary.slice();
          const opfs = await OPFSAdapter.open({root});
          try {
            assert.deepEqual(opfs.readFile("/seed"), binary);
            assert.equal(seed.open, false);
            assert.equal(opfs.makeDir("/data"), true);
            assert.equal(opfs.writeFile("/data/raw", binary), true);
            assert.equal(opfs.writeText(name, utf8), true);
            assert.equal(opfs.removeFile("/seed"), true);
          } finally {
            opfs.close();
          }
          const reopened = await OPFSAdapter.open({root});
          try {
            assert.equal(reopened.readText(name), utf8);
            assert.deepEqual(reopened.readFile("/data/raw"), binary);
            assert.equal(reopened.readFile("/seed"), null);
            assert.deepEqual((await reopened.syncToMemory()).snapshot(), reopened.snapshot());
          } finally {
            reopened.close();
          }
        """)

    def test_loaders_and_worker_protocol(self):
        wasm = wasmtime.wat2wasm(r'''(module
          (import "goose" "write" (func $stdout (param i32 i32)))
          (import "env" "gs_os_write_stderr" (func $stderr (param i64)))
          (memory (export "memory") 1)
          (data (i32.const 0) "\c3\a9!")
          (func (export "_start") (result i32)
            (call $stdout (i32.const 0) (i32.const 1))
            ;; The wasm32 slice packs a pointer of 2 and a length of 1.
            (call $stderr (i64.const 4294967298))
            (call $stdout (i32.const 1) (i32.const 1))
            (i32.const 42)))''')
        self.node(r"""
          import assert from "node:assert/strict";
          import {createGooseWorker, loadGoose, runGoose} from "./host/web/index.js";

          const bytes = Uint8Array.from(JSON.parse(process.argv[1]));
          const original = bytes.slice();
          const response = () => new Response(bytes, {headers: {"Content-Type": "application/wasm"}});
          const loaded = await loadGoose(response(), {memory64: false});
          try {
            assert.ok(loaded.module instanceof WebAssembly.Module);
            assert.equal(loaded.run().returnValue, 42);
          } finally {
            await loaded.dispose();
          }
          for (const source of [response(), bytes.buffer, await WebAssembly.compile(bytes)]) {
            const result = await runGoose(source);
            assert.equal(result.exitCode, 0);
            assert.equal(result.returnValue, 42);
            assert.equal(result.stdout, "é");
            assert.equal(result.stderr, "!");
          }
          await assert.rejects(loadGoose(new Response(null, {status: 404})), /HTTP 404/);

          // Wire both ends of the real worker protocol through a mock transport.
          const workerScope = new EventTarget();
          workerScope[Symbol.for("goose.web.worker")] = true;
          globalThis.self = workerScope;
          try {
            await import("./host/web/worker.js?mock-worker");
          } finally {
            delete globalThis.self;
          }

          const worker = new EventTarget();
          const sent = [];
          let terminated = false;
          worker.terminate = () => { terminated = true; };
          worker.postMessage = (message, transfer) => {
            assert.equal(message.type, "run");
            assert.deepEqual(transfer, [message.wasmBytes]);
            sent.push(message.id);
            workerScope.dispatchEvent(new MessageEvent("message", {data: structuredClone(message, {transfer})}));
          };
          workerScope.postMessage = (message, transfer = []) => {
            worker.dispatchEvent(new MessageEvent("message", {data: structuredClone(message, {transfer})}));
          };
          globalThis.self = workerScope;
          const client = createGooseWorker({worker});
          try {
            const out = [];
            const err = [];
            const run = client.run(response(), {
              files: {"/result": Uint8Array.of(0, 255)},
              onStdout: (chunk, text) => out.push([[...chunk], text]),
              onStderr: (chunk, text) => err.push([[...chunk], text]),
            });
            const result = await run;
            assert.deepEqual(out, [[[0xc3], ""], [[0xa9], "é"]]);
            assert.deepEqual(err, [[[33], "!"]]);
            assert.equal(result.exitCode, 0);
            assert.deepEqual(result.stdoutBytes, Uint8Array.of(0xc3, 0xa9));
            assert.deepEqual(result.stderrBytes, Uint8Array.of(33));
            assert.deepEqual(result.files, {"/result": Uint8Array.of(0, 255)});
            await assert.rejects(client.run(bytes, {entry: "missing"}), /export "missing"/);
            assert.equal(new Set(sent).size, 2);
            assert.deepEqual(bytes, original, "transfer must preserve the caller's bytes");
            const pending = client.run(bytes);
            worker.dispatchEvent(Object.assign(new Event("error"), {error: new Error("worker crashed")}));
            await assert.rejects(pending, /worker crashed/);
            await assert.rejects(client.run(bytes), /worker crashed/);
          } finally {
            client.terminate();
            delete globalThis.self;
          }
          assert.equal(terminated, true);
        """, json.dumps(list(wasm)))


CORE = r'''
import std;
import base64;
import binary;
import csv;
import dictionary;
import exception;
import json;
import math;
import regex;
import slot_pool;
import vec;

extern fn find_pair_raw(s: const u8[:], a: const ByteSet&, d: i64, b: const ByteSet&) -> i64 = "gs_find_pair";

fn throw_number() { exception::throw(42); }

fn core() {
    let angle = 0.5;
    assert(abs(sin(angle) - 0.479425538604203) < 0.000000000001);
    assert(abs(cos(angle) - 0.877582561890373) < 0.000000000001);
    assert(pow(2.0, 3.0) == 8.0 && round(-0.5) == -1.0 && mul_add(2.0, 3.0, 4.0) == 10.0);

    var nodes: json::Node[>..] = [];
    var scratch: u8[>..] = [];
    let root, error = json::parse("{\"n\":12.5}", nodes, scratch);
    assert(root != null && error.len == 0);
    let number, ok = json::as_f64(json::member(root, "n"));
    assert(ok && number == 12.5);
    var text: u8[>..] = [];
    json::format_number(text, number);
    assert(text == "12.5");

    var encoded: u8[>..] = [];
    base64::encode(encoded, "hello");
    assert(encoded == "aGVsbG8=");
    var decoded: u8[>..] = [];
    assert(base64::decode(decoded, encoded) && decoded == "hello");
    assert(!base64::decode(decoded, "bad!") && decoded == "hello");

    let integer, has_integer = binary::read_u32le([0, 0x78, 0x56, 0x34, 0x12], 1);
    assert(has_integer && integer == 0x12345678);
    let missing, has_missing = binary::read_u16le([0], 0);
    assert(!has_missing && missing == 0);

    var rows = 0;
    let csv_ok = csv::each_record("a,b\r\n\"x,y\",\"c\"\"d\"\r\n") { fields =>
        assert(fields.len == 2);
        if rows == 0 { assert(fields[0] == "a" && fields[1] == "b"); }
        else { assert(fields[0] == "x,y" && fields[1] == "c\"\"d"); }
        rows++;
    };
    assert(csv_ok && rows == 2);
    var field: u8[>..] = [];
    csv::format_field(field, "c\"d");
    assert(field == "\"c\"\"d\"");

    var table = dictionary<i64, i64> {};
    assert(table.insert(1, 10) && !table.insert(1, 11));
    table.update(1, 0) { it += 5; };
    block { let value = table.get(1); assert(value != null && value == 16); }
    assert(table.remove(1) && !table.contains(1));

    var caught = 0;
    exception::try<i64>(throw_number) { error => caught = error; };
    assert(caught == 42);

    let re = regex::compile("[a-z]+[0-9]+");
    let first, last = regex::find(re, "!abc12?");
    assert(first == 1 && last == 6 && regex::count(re, "a1 b2") == 2);
    assert(!regex::matches(re, "123"));

    var slots = slot_pool<i64> {};
    let slot = slots.alloc_index(10);
    let keep = slots.alloc_index(20);
    slots.free(slot);
    assert(slots.alloc_index(30) == slot && slots.items[slot] == 30 && slots.items[keep] == 20);

    let v = float3 { 1.0, 2.0, 3.0 };
    let w = float3 { 4.0, 5.0, 6.0 };
    let crossed = cross(v, w);
    assert(dot(v, w) == 32.0 && crossed.x == -3.0 && crossed.y == 6.0 && crossed.z == -3.0);
    let a = byte_set("ac");
    let b = byte_set("b");
    assert(find_any("zzca", a) == 2 && find_any("zzz", a) == -1);
    assert(find_pair("zzab", a, 1, b) == 2 && find_pair("zzab", a, 4, b) == -1);
    assert(find_pair_raw("ab", a, -1, b) == -1);
    print("core ok");
}
'''


OS = r'''
import os;

extern fn random_bytes(out: u8[:]) -> bool = "gs_os_random_bytes";

fn contents(path: const u8[:], expected: const u8[:]) {
    var data: u8[>..] = [];
    assert(read_file(path, data) && data == expected);
}

fn invalid_path(path: const u8[:]) {
    var kept: u8[>..] = [];
    kept.append("kept");
    assert(!read_file(path, kept) && !file_exists(path) && !is_dir(path));
    assert(!write_file(path, "!") && !append_file(path, "!") && !write_file_atomic(path, "!"));
    assert(!rename_file(path, "dir/c.txt") && !rename_file("dir/b.txt", path));
    assert(!delete_file(path) && !make_dir(path) && !delete_dir(path));
    assert(!list_dir(path, kept) && kept == "kept");
    contents("dir/b.txt", "banana");
    assert(!file_exists("dir/c.txt"));
}

fn filesystem() {
    let dir = "dir";
    assert(!is_dir(dir) && make_dir(dir) && make_dir(dir) && is_dir(dir) && !file_exists(dir));
    var names: u8[>..] = [];
    assert(list_dir(dir, names) && names.len == 0);
    assert(write_file("dir/a.txt", "apple") && append_file("dir/a.txt", "!"));
    var text: u8[>..] = [];
    text.append("prefix:");
    assert(read_file("dir/a.txt", text) && text == "prefix:apple!");
    assert(!read_file("dir/no-such-file", text) && text == "prefix:apple!");

    let name = "ωmega-日本-🐟.txt";
    let unicode = str(dir, "/", name);
    assert(write_file("dir/Z.txt", "zebra") && write_file(unicode, "fish") && make_dir("dir/sub"));
    let odd = "dir/odd\nname";
    assert(write_file(odd, "odd") && list_dir(dir, names));
    assert(names == "Z.txt\na.txt\nsub\nωmega-日本-🐟.txt\n");
    contents(odd, "odd");
    assert(delete_file(odd));
    let parts = split(names, '\n');
    assert(parts.len == 5 && parts[3] == name && file_exists(unicode));
    contents(str(dir, "/", parts[3]), "fish");
    assert(is_dir("dir/sub") && !is_dir("dir/a.txt") && !file_exists("dir/sub"));
    var empty: u8[>..] = [];
    assert(list_dir("dir/sub", empty) && empty.len == 0);
    let n = names.len;
    assert(list_dir(dir, names) && names.len == n * 2 && names[..n] == names[n..]);
    var kept: u8[>..] = [];
    kept.append("kept");
    assert(!list_dir("dir/missing", kept) && !list_dir("dir/a.txt", kept) && !list_dir("", kept));
    assert(kept == "kept");
    assert(!make_dir("dir/a.txt") && !make_dir("dir/missing/sub"));
    assert(!delete_dir(dir) && !delete_dir("dir/a.txt") && !delete_file("dir/sub"));
    assert(!delete_dir("dir/missing") && !is_dir("dir/missing") && !is_dir(""));
    assert(delete_file(unicode) && !file_exists(unicode) && delete_file("dir/Z.txt"));

    let a = "dir/a.txt";
    let b = "dir/b.txt";
    let c = "dir/c.txt";
    let save = "dir/save.dat";
    assert(write_file(b, "banana") && rename_file(a, c) && !file_exists(a));
    contents(c, "apple!");
    assert(rename_file(c, b) && !file_exists(c));
    assert(!rename_file(a, b) && !rename_file(b, "dir/sub") && !rename_file(b, "dir/missing/b.txt"));
    assert(is_dir("dir/sub"));
    contents(b, "apple!");
    assert(write_file_atomic(save, "first")); contents(save, "first");
    assert(write_file_atomic(save, "second, longer")); contents(save, "second, longer");
    assert(write_file_atomic(save, "3rd")); contents(save, "3rd");
    assert(write_file_atomic(save, "")); contents(save, "");
    assert(write_file_atomic(b, "banana")); contents(b, "banana");
    assert(!write_file_atomic("dir/sub", "x") && !write_file_atomic("dir/missing/x.dat", "x"));
    assert(is_dir("dir/sub"));

    var long: u8[>..] = [];
    long.append(dir);
    while long.len < 4090 { long.push('/'); }
    long.append("b.txtx");
    assert(long.len == 4096);
    contents(long[..4095], "banana");
    invalid_path(long);
    var nul: u8[>..] = [];
    nul.append(b);
    nul.push(0);
    nul.push('x');
    invalid_path(nul);

    names.resize(0);
    assert(list_dir(dir, names) && names == "b.txt\nsave.dat\nsub\n");
    assert(delete_file(b) && delete_file(save) && delete_dir("dir/sub") && delete_dir(dir));
    assert(!is_dir(dir) && !list_dir(dir, kept) && kept == "kept");
}

fn os_checks() {
    filesystem();
    let argv = args();
    assert(argv.len == 3 && argv[0] == "web-test.wasm" && argv[1] == "os" && argv[2] == "🐟");
    var buf: u8[>..] = [];
    buf.append("prefix:");
    arg(-1, buf);
    arg(3, buf);
    assert(!env("GOOSE_NO_SUCH_VAR_", buf));
    assert(buf == "prefix:");
    assert(env("GOOSE_WEB_TEST", buf) && buf == "prefix:日本");
    assert(resource_dir() == "/assets/");

    var input_line: u8[>..] = [];
    assert(read_line(input_line) && input_line == "hello");
    input_line.resize(0);
    assert(read_line(input_line) && input_line.len == 0);
    var tail: u8[>..] = [];
    let expected_tail: u8[3] = [0, 255, 10];
    read_stdin(tail);
    assert(tail == expected_tail && !read_line(tail) && tail == expected_tail);
    read_stdin(tail);
    assert(tail == expected_tail);

    let before = clock();
    sleep_ms(-1);
    sleep_ms(0);
    sleep_ms(2);
    sleep(0.0015);
    assert(clock() >= before && time() > 1600000000.0 && time_ns() > 1600000000000000000);
    assert(random_seed() != random_seed());
    var r1: u8[1000] = [0; 1000];
    var r2: u8[1000] = [0; 1000];
    assert(random_bytes(r1) && random_bytes(r2) && r1 != r2);
    each_chunk(r1, 250) { c, i =>
        var filled = false;
        for x in c { if x != 0 { filled = true; } }
        assert(filled);
    };
    assert(random_bytes(r1[..0]) && trim_memory());
    write_stdout("out\n");
    write_stderr("err\n");
    flush_stdout();
}
'''


FFI = r'''
import ffi;

extern fn address(first: const u8&) -> u64 = "test_address";

fn foreign_memory() {
    let data: u8[5] = [65, 195, 169, 0, 255];
    let ptr = address(data[0]);
    var out: u8[>..] = [];
    out.append(">");
    assert(ffi::cstr(ptr, out) && out == ">Aé");
    assert(ffi::bytes(ptr, 5, out) && out[4..] == data);
    assert(ffi::cstr(ptr) == "Aé" && ffi::bytes(ptr + 3, 2) == data[3..]);
    let n = out.len;
    let invalid: u64 = 0xffffffffffffffff;
    assert(!ffi::cstr(0, out) && !ffi::bytes(0, 0, out));
    assert(!ffi::cstr(invalid, out) && !ffi::bytes(invalid, 1, out));
    assert(!ffi::bytes(ptr, -1, out) && !ffi::bytes(ptr, 9223372036854775807, out));
    assert(out.len == n);
    print("ffi ok");
}
'''


POOL = r'''
import slice_pool;

fn pool_checks() {
    var p = slice_pool<i64> {};
    let a = p.alloc_slice(3);
    let b = p.alloc_copy([7, 8, 9]);
    let c = p.alloc_slice(3);
    p.free_slice(c);
    let grown = p.realloc_slice(b, 5);
    assert(p.items.range_index(grown) == 3 && grown == [7, 8, 9, 0, 0]);
    let shrunk = p.realloc_slice(grown, 1);
    assert(shrunk == [7]);
    p.free_slice(a);
    p.free_slice(shrunk);
    let merged = p.alloc_slice(9);
    assert(p.items.range_index(merged) == 0 && merged == [0; 9]);
    merged[0] = 77;
    p.recycle_all();
    assert(merged[0] == 77);
    let recycled = p.alloc_copy([1, 2, 3]);
    assert(p.items.range_index(recycled) == 0 && recycled == [1, 2, 3] && p.items.len == 9);

    var bytes = slice_pool<u8> {};
    let left = bytes.alloc_slice(17);
    let released = bytes.alloc_slice(16384);
    let right = bytes.alloc_slice(19);
    left[16] = 11;
    right[0] = 33;
    for i in released.len { released[i] = 22; }
    assert(bytes.trim() && released[8192] == 22);
    bytes.free_slice(released);
    assert(bytes.trim() && bytes.trim());
    assert(left[16] == 11 && right[0] == 33);
    for i in 4096..12288 { assert(released[i] == 0); }
    print("pool ok");
}

fn corrupt_pool() {
    var p = slice_pool<i64> {};
    let s = p.alloc_slice(2);
    p.free_slice(s);
    p.nodes[p.tree.root].n = 40;
    p.alloc_slice(1);
}
'''


LIVE_AUDIO = r'''
import audio;

extern fn start_audio_clock() = "test_start_audio_clock";

fn live_audio() {
    assert(audio::open());
    let sound = audio::create_sound([0.25, -0.5, 1.0, 0.0], 48000, 2);
    let voice = audio::play(sound, 0.5, 1.0, 1.0, true);
    assert(voice.id != 0 && audio::voice_position(voice) == 0.0);
    let next = 1.0 / 48000.0;
    assert(audio::seek(voice, next) && audio::voice_position(voice) == next);
    assert(!audio::seek(voice, -1.0));
    let message = audio::error();
    assert(message == "seek needs a position of 0 or more seconds");
    var prefix: u8[4] = [0; 4];
    assert(audio::error_into(prefix) == message.len && prefix == "seek");
    var full: u8[64] = [255; 64];
    assert(audio::error_into(full) == message.len && full[..message.len] == message && full[message.len] == 255);
    assert(audio::error_into(full[..0]) == message.len);
    start_audio_clock();
    assert(audio::playing(voice));
    audio::stop(voice);
    assert(audio::voice_position(voice) == -1.0 && !audio::seek(voice, 0.0));
    audio::close();
    print("live audio ok");
}
'''


# Reference cases from upstream test/audio/audio_mixer.goose and audio_errors.goose.
# Keep the bodies inline so a source checkout of upstream is optional.
AUDIO_REFERENCE = r'''
import audio;

// The real playback mixer, advanced by exact frame counts without a device.

fn expect(out: const f32[:], expected: const f32[:]) {
    assert(out == expected);
}

fn audio_mixer() {
    assert(audio::available());
    assert(audio::open_offline(48000));
    var pcm: f32[>..] = [0.0, 0.5, 1.0, -1.0];
    let sound = audio::create_sound(pcm);
    assert(sound.id != 0);
    pcm[0] = 0.75; // Mutating the original must not change the copied sound.
    pcm.resize(0);  // Native playback owns a copy, not this Goose allocation.
    let voice = audio::play(sound);
    var out: f32[8] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    assert(audio::render(out));
    expect(out, [0.0, 0.0, 0.5, 0.5, 1.0, 1.0, -1.0, -1.0]);
    assert(!audio::playing(voice));
    assert(audio::render(out));
    expect(out, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    print("mono copied, completed, silence");

    // Half-speed linear interpolation; changing parameters does not restart.
    let slow = audio::play(sound, 0.5, -1.0, 0.5);
    assert(audio::render(out));
    expect(out, [0.0, 0.0, 0.125, 0.0, 0.25, 0.0, 0.375, 0.0]);
    assert(audio::set_voice(slow, 1.0, 1.0, 1.0));
    assert(audio::render(out));
    expect(out, [0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0]);
    print("gain, pan, interpolation, live update");

    let stereo = audio::create_sound([0.5, -0.5, 1.0, -1.0], 24000, 2);
    let looping = audio::play(stereo, 1.0, 0.0, 1.0, true);
    assert(audio::render(out));
    expect(out, [0.5, -0.5, 0.75, -0.75, 1.0, -1.0, 0.75, -0.75]);
    assert(audio::playing(looping));
    audio::stop(looping);
    assert(!audio::playing(looping));
    print("stereo, sample rates, loop boundary, stop");

    let loud = audio::create_sound([0.75, -0.75]);
    let first = audio::play(loud);
    let second = audio::play(loud);
    assert(first.id != second.id);
    assert(audio::render(out));
    expect(out, [1.0, 1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0]);
    let retained = audio::play(loud, 1.0, 0.0, 1.0, true);
    assert(audio::release_sound(loud));
    assert(!audio::playing(retained));
    assert(!audio::release_sound(loud));
    assert(audio::play(loud).id == 0);
    audio::stop(retained);
    print("overlap, clipping, release stops voices, stale handles");

    let old = audio::play(sound, 1.0, 0.0, 1.0, true);
    audio::close();
    audio::close();
    assert(!audio::playing(old));
    assert(audio::open_offline());
    let fresh = audio::create_sound([1.0]);
    assert(fresh.id != sound.id);
    assert(audio::play(sound).id == 0);
    let fresh_voice = audio::play(fresh, 1.0, 0.0, 1.0, true);
    audio::stop(old);
    assert(audio::playing(fresh_voice));
    var long_output: f32[>..] = [];
    long_output.resize(1200, 0.0);
    assert(audio::render(long_output)); // Cross multiple native block boundaries.
    for sample in long_output { assert(sample == 1.0); }
    audio::stop_all();
    assert(!audio::playing(fresh_voice));
    audio::close();
    print("close/open invalidates handles, stop all");
}


fn audio_errors() {
    assert(!audio::open_offline(0));
    assert(audio::create_sound([0.0]).id == 0);
    assert(audio::open_offline());
    assert(!audio::open_offline());
    assert(audio::create_sound([0.0], 7999).id == 0);
    assert(audio::create_sound([0.0], 192001).id == 0);
    assert(audio::create_sound([0.0], 48000, 3).id == 0);
    assert(audio::create_sound([0.0], 48000, 2).id == 0);
    assert(audio::create_sound([1.1]).id == 0);
    let empty: f32[>..] = [];
    assert(audio::create_sound(empty).id == 0);
    assert(audio::release_sound(audio::Sound { 0 }));
    let sound = audio::create_sound([0.25]);
    assert(audio::play(sound, -1.0).id == 0);
    assert(audio::play(sound, 1.0, 2.0).id == 0);
    assert(audio::play(sound, 1.0, 0.0, 0.0).id == 0);
    assert(audio::error().len > 0);
    var odd: f32[3] = [0.0, 0.0, 0.0];
    assert(!audio::render(odd));
    var zero: f32[>..] = [];
    assert(audio::render(zero));
    print("invalid rates, PCM, parameters, and output rejected");

    var voices: audio::Voice[>..] = [];
    for _ in 0..audio::MAX_VOICES {
        let voice = audio::play(sound, 1.0, 0.0, 1.0, true);
        assert(voice.id != 0);
        voices.push(voice);
    }
    assert(audio::play(sound).id == 0);
    audio::stop(voices[0]);
    let replacement = audio::play(sound, 1.0, 0.0, 1.0, true);
    assert(replacement.id != 0 && replacement.id != voices[0].id);
    audio::stop(voices[0]);
    assert(audio::playing(replacement));
    audio::stop_all();
    assert(!audio::set_voice(replacement, 1.0, 0.0, 1.0));
    print("voice capacity and generation safety");

    var sounds: audio::Sound[>..] = [sound];
    for _ in 1..audio::MAX_SOUNDS {
        let s = audio::create_sound([0.0]);
        assert(s.id != 0);
        sounds.push(s);
    }
    assert(audio::create_sound([0.0]).id == 0);
    assert(audio::release_sound(sound));
    let replacement_sound = audio::create_sound([0.0]);
    assert(replacement_sound.id != 0 && replacement_sound.id != sound.id);
    audio::close();
    assert(!audio::render(odd));
    print("sound capacity and recovery");
}
'''


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
@unittest.skipUnless(shutil.which("node"), "Node.js is required")
class WebStdlibExecution(WebHostCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def _compile(self, src, out, optimization, *, memory64=False, stdlib=WEB_STDLIB):
        command = [
            str(COMPILER), str(src), "--stdlib", str(stdlib), "--target", "wasm-direct",
            optimization, "-o", str(out),
        ]
        if memory64:
            command.append("--wasm-memory64")
        return subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=30)

    def test_native_stdlib_rejects_audio_import(self):
        src = self.work / "audio_import.goose"
        src.write_text("import audio;\nfn main() {}\n", encoding="utf-8")
        out = self.work / "audio_import.wasm"
        result = self._compile(src, out, "-O0", stdlib=STDLIB)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("blessed packages are not yet supported", result.stderr)
        self.assertFalse(out.exists())

    def test_web_stdlib_on_both_memory_widths_and_optimization_levels(self):
        programs = {
            "core": CORE + "fn main() { core(); exit(23); }\n",
            "os": OS + "fn main() { os_checks(); }\n",
            "ffi": FFI + "fn main() { foreign_memory(); }\n",
            "pool": POOL + "fn main() { pool_checks(); }\n",
            "corrupt": POOL + "fn main() { corrupt_pool(); }\n",
            "mixer": AUDIO_REFERENCE + "fn main() { audio_mixer(); }\n",
            "audio-errors": AUDIO_REFERENCE + "fn main() { audio_errors(); }\n",
            "live": LIVE_AUDIO + "fn main() { live_audio(); }\n",
            "abort": 'fn main() {\n    abort("web abort probe");\n}\n',
        }
        variants = []
        for mode, source in programs.items():
            directory = self.work / mode
            directory.mkdir()
            src = directory / "probe.goose"
            src.write_text(source, encoding="utf-8")
            for memory64 in (False, True):
                for optimization in ("-O0", "-O2"):
                    label = f"wasm{'64' if memory64 else '32'}{optimization}"
                    with self.subTest(mode=mode, variant=label):
                        out = directory / f"{label}.wasm"
                        result = self._compile(src, out, optimization, memory64=memory64)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        variants.append([mode, label, str(out), memory64])
        corrupt_line = POOL[:POOL.index("p.alloc_slice(1);")].count("\n") + 1
        if variants:
            self.node(r"""
              import assert from "node:assert/strict";
              import {readFileSync} from "node:fs";
              import {detectMemory64, runGoose} from "./host/web/index.js";

              const corruptLine = Number(process.argv[2]);
              const mixerOutput = [
                "mono copied, completed, silence",
                "gain, pan, interpolation, live update",
                "stereo, sample rates, loop boundary, stop",
                "overlap, clipping, release stops voices, stale handles",
                "close/open invalidates handles, stop all",
              ];
              const errorsOutput = [
                "invalid rates, PCM, parameters, and output rejected",
                "voice capacity and generation safety",
                "sound capacity and recovery",
              ];

              function mockAudioContext() {
                const sources = [];
                const context = {
                  currentTime: 2,
                  state: "suspended",
                  destination: {},
                  resumeCalls: 0,
                  async resume() { this.resumeCalls++; },
                  createBuffer(channels, frames, rate) {
                    assert.equal(channels, 2);
                    assert.equal(rate, 48000);
                    const data = Array.from({length: channels}, () => new Float32Array(frames));
                    return {duration: frames / rate, getChannelData: (channel) => data[channel]};
                  },
                  createBufferSource() {
                    return {
                      start(time) { this.time = time; sources.push(this); },
                      connect(destination) { assert.equal(destination, context.destination); },
                      disconnect() { this.disconnected = true; },
                      stop() { this.stopped = true; },
                    };
                  },
                };
                return {context, sources};
              }

              const cases = new Map([
                ["core", [23, "core ok\n"]],
                ["os", [0, "out\n", "err\n"]],
                ["ffi", [0, "ffi ok\n"]],
                ["pool", [0, "pool ok\n"]],
                ["mixer", [0, mixerOutput.join("\n") + "\n"]],
                ["audio-errors", [0, errorsOutput.join("\n") + "\n"]],
                ["live", [0, "live audio ok\n"]],
                ["abort", [1, "", "", "web abort probe", 2]],
                ["corrupt", [1, "", "", "slice pool span tree is corrupt", corruptLine]],
              ]);
              const failures = [];
              for (const [mode, label, file, memory64] of JSON.parse(process.argv[1])) {
                const wasm = new Uint8Array(readFileSync(file));
                assert.equal(detectMemory64(wasm), memory64, label);
                const [code, stdout, stderr = "", reason = null, line = null] = cases.get(mode);
                try {
                  const {context, sources} = mockAudioContext();
                  const delays = [];
                  const stdinChunks = [
                    new TextEncoder().encode("hello\r"),
                    new TextEncoder().encode("\n\r\n"),
                    Uint8Array.of(0, 255, 10),
                  ];
                  const result = await runGoose(wasm, {
                    args: ["web-test.wasm", mode, "🐟"],
                    env: {GOOSE_WEB_TEST: "日本"},
                    resourceDir: "/assets",
                    stdin: () => stdinChunks.shift() ?? null,
                    sleepMs: (ms) => delays.push(ms),
                    audioContext: context,
                    imports: {env: {
                      test_address: (ptr) => BigInt(ptr),
                      test_start_audio_clock() { context.state = "running"; },
                    }},
                  });
                  assert.equal(result.exitCode, code, result.stderr);
                  assert.equal(result.stdout, stdout);
                  assert.equal(result.aborted, reason !== null);
                  assert.equal(result.abortReason, reason);
                  assert.equal(result.abortLine, line);
                  assert.equal(result.stderr, reason === null ? stderr : (
                    "goose runtime error: " + reason + " (line " + line + ")\n"
                  ));

                  if (mode === "os") {
                    assert.deepEqual(delays, [2, 1]);
                    assert.deepEqual(result.fs.snapshot(), {});
                    assert.deepEqual(result.stdoutBytes, Uint8Array.of(111, 117, 116, 10));
                    assert.deepEqual(result.stderrBytes, Uint8Array.of(101, 114, 114, 10));
                  }
                  if (mode === "live") {
                    assert.equal(context.resumeCalls, 1);
                    assert.ok(sources.length >= 4, "fill the Web Audio scheduling window");
                    let expectedTime = context.currentTime;
                    for (const source of sources) {
                      assert.ok(Math.abs(source.time - expectedTime) < 1e-9);
                      expectedTime += source.buffer.duration;
                      assert.deepEqual([...source.buffer.getChannelData(0).slice(0, 4)], [0, 0, 0, 0]);
                      assert.deepEqual([...source.buffer.getChannelData(1).slice(0, 4)], [0, -0.25, 0, -0.25]);
                      assert.equal(source.stopped, true);
                      assert.equal(source.disconnected, true);
                    }
                  }
                } catch (error) {
                  failures.push(label + " " + mode + "\n" + error.stack);
                }
              }
              assert.equal(failures.length, 0, failures.join("\n\n"));
            """, json.dumps(variants), corrupt_line)

    def test_demo(self):
        src = WEB / "demo/demo.goose"
        variants = []
        for memory64 in (False, True):
            for optimization in ("-O0", "-O2"):
                label = f"wasm{'64' if memory64 else '32'}{optimization}"
                with self.subTest(variant=label):
                    out = self.work / f"demo-{label}.wasm"
                    result = self._compile(src, out, optimization, memory64=memory64)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    variants.append(str(out))
        if variants:
            self.node(r"""
              import assert from "node:assert/strict";
              import {readFileSync} from "node:fs";
              import {runGoose} from "./host/web/index.js";

              for (const file of process.argv.slice(1)) {
                const result = await runGoose(readFileSync(file));
                assert.equal(result.exitCode, 0, file + "\n" + result.stderr);
                assert.equal(result.stderr, "");
                const files = result.fs.snapshot();
                assert.deepEqual(Object.keys(files).sort(), ["/demo/chime.json", "/demo/report.json"]);
                const reportText = new TextDecoder().decode(files["/demo/report.json"]);
                const report = JSON.parse(reportText);
                assert.deepEqual(report, {frequencyHz: 440, frames: 28800, peak: report.peak});
                assert.ok(typeof report.peak === "number" && report.peak > 0.3 && report.peak < 0.45, reportText);
                assert.equal(result.stdout, "chime " + reportText + "files /demo\nchime.json\nreport.json\n");
              }
            """, *variants)


if __name__ == "__main__":
    unittest.main()
