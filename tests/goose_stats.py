"""Shared helpers for the tests that read the compiler's --wasm-stats: the
compiler under test, Wasm section and code decoding, and compiling a source
to direct Wasm or to a native oracle. Not a test module."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GOOSE = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goose")).resolve()
NODE = "node"
CC = "cc"


def uleb(data, offset):
    value = shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7


def sections(data):
    assert data[:8] == b"\0asm\1\0\0\0"
    offset = 8
    while offset < len(data):
        kind = data[offset]
        length, start = uleb(data, offset + 1)
        yield kind, data[start:start + length]
        offset = start + length


def function_body(path, stats, name="clear"):
    payload = dict(sections(path.read_bytes()))[10]
    count, offset = uleb(payload, 0)
    functions = sorted(stats["function_info"], key=lambda item: item["index"])
    assert count == len(functions), "statistics must cover every defined function"
    for function in functions:
        size, start = uleb(payload, offset)
        body = payload[start:start + size]
        offset = start + size
        if function["name"].split("#")[0] == name:
            return body
    raise AssertionError(f"missing {name} function")


def instructions(body):
    """Decode instruction boundaries, so immediates cannot mimic rem opcodes."""
    groups, offset = uleb(body, 0)
    for _ in range(groups):
        _, offset = uleb(body, offset)
        offset += 1  # local value type
    while offset < len(body):
        op = body[offset]
        offset += 1
        yield op
        if op in (0x02,0x03,0x04,0x0c,0x0d,0x10,0x20,0x21,0x22,0x23,0x24,0x3f,0x40,0x41,0x42):
            _, offset = uleb(body, offset)  # Signed and unsigned LEB have the same byte boundary.
        elif op == 0x0e:
            count, offset = uleb(body, offset)
            for _ in range(count+1):
                _, offset = uleb(body, offset)
        elif op == 0x11 or 0x28 <= op <= 0x3e:
            _, offset = uleb(body, offset)
            _, offset = uleb(body, offset)
        elif op == 0x43:
            offset += 4
        elif op == 0x44:
            offset += 8
        elif op == 0xfc:
            sub, offset = uleb(body, offset)
            if sub in (10,14):
                _, offset = uleb(body, offset)
                _, offset = uleb(body, offset)
            elif sub in (11,15,16,17):
                _, offset = uleb(body, offset)
            else:
                raise AssertionError(f"unexpected prefixed instruction {sub}")
        elif not (op in (0x00,0x01,0x05,0x0b,0x0f,0x1a,0x1b) or 0x45 <= op <= 0xc4):
            raise AssertionError(f"unexpected instruction {op:#x}")


class Compile:
    """Methods a TestCase borrows: a scratch directory, a direct-Wasm build
    with its statistics, and a native oracle run."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, level, debug=False, *, text):
        source = self.work / "main.goose"
        source.write_text(text)
        output = self.work / "program.wasm"
        stats = self.work / "stats.json"
        command = [str(GOOSE), str(source), "--target", "wasm-direct", f"-O{level}",
                   "--wasm-stats", str(stats), "-o", str(output)]
        if debug:
            command.append("--debug")
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        return output, json.loads(stats.read_text())

    def native(self, path, level):
        c = self.work / "oracle.c"
        binary = self.work / "oracle"
        result = subprocess.run([str(GOOSE),str(path),f"-O{level}","--target","native",
                                 "--standalone","-o",str(c)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        result = subprocess.run([CC,str(c),"-lm","-o",str(binary)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        result = subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return result.stdout
