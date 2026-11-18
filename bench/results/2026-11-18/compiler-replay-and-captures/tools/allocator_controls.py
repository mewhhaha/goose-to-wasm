"""Write local-allocation replay fixtures and hand-derived remapped bytes."""
import argparse
import json
import struct
from hashlib import sha256
from pathlib import Path
import wasmtime


def leb(value):
    encoded = bytearray()
    while value >= 128:
        encoded.append(128 | (value & 127))
        value >>= 7
    encoded.append(value)
    return bytes(encoded)


def local(op, index):
    return bytes([op]) + leb(index)


def reverse_code(writes, reads):
    return (b"".join(b"\x41\x15" + local(0x21, i) for i in writes)
            + b"".join(local(0x20, i) + b"\x1a" for i in reads) + b"\x0b")


def module(params, types, code):
    def section(kind, data):
        return bytes([kind]) + leb(len(data)) + data
    groups = []
    for kind in types:
        if groups and groups[-1][1] == kind:
            groups[-1][0] += 1
        else:
            groups.append([1, kind])
    body = leb(len(groups)) + b"".join(leb(n) + bytes([k]) for n, k in groups) + code
    return (b"\x00asm\x01\x00\x00\x00"
            + section(1, b"\x01\x60" + leb(params) + bytes([127]) * params + b"\x00")
            + section(3, b"\x01\x00") + section(10, b"\x01" + leb(len(body)) + body))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    cases = []
    ascending = range(1, 181)
    descending = range(180, 0, -1)
    cases.append(("reverse 180 simultaneous spans across indexes 127 and 128", 1, [127] * 180,
                  reverse_code(descending, ascending), [127] * 180, reverse_code(ascending, descending)))
    branches = bytes.fromhex("43 20 21 22 20 1a 02 40 03 40 20 81 00 1a 41 01 04 40 "
                             "41 01 21 82 00 05 41 01 21 02 0b 02 40 20 02 0e 01 00 01 0b 0b 0b 0b")
    normalized = branches.replace(b"\x20\x81\x00", b"\x20\x01").replace(b"\x21\x82\x00", b"\x21\x02")
    cases.append(("nested loop, if/else, br_table, padded indexes and float payload with local opcodes",
                  1, [127] * 3, branches, [127] * 2, normalized))
    cases.append(("implicit zero read in instruction zero precedes a disjoint write", 0, [127] * 2,
                  bytes.fromhex("20 00 1a 41 00 21 01 0b"), [127], bytes.fromhex("20 00 1a 41 00 21 00 0b")))
    cases.append(("single local bypass", 0, [127], bytes.fromhex("20 00 1a 0b"), [127], bytes.fromhex("20 00 1a 0b")))
    dispatch = b"\x02\x40\x41\x00\x0e" + leb(130) + bytes(131) + b"\x0b"
    def access(i):
        return b"\x41\x00" + local(0x21, i) + local(0x20, i) + b"\x1a"
    cases.append(("two- and three-byte local indexes and 130 br_table arms", 0, [127] * 16385,
                  dispatch + access(16383) + access(16384) + b"\x0b",
                  [127], dispatch + access(0) + access(0) + b"\x0b"))
    engine = wasmtime.Engine()
    input_data, output_data = bytearray(), bytearray()
    for _, params, locals_in, code_in, locals_out, code_out in cases:
        wasmtime.Module.validate(engine, module(params, locals_in, code_in))
        wasmtime.Module.validate(engine, module(params, locals_out, code_out))
        input_data.extend(struct.pack("<QQQ", params, len(locals_in), len(code_in)))
        input_data.extend(struct.pack(f"<{len(locals_in)}Q", *locals_in))
        input_data.extend(code_in)
        output_data.extend(struct.pack("<QQ", len(locals_out), len(code_out)))
        output_data.extend(locals_out)
        output_data.extend(code_out)
    args.output.mkdir(exist_ok=True, parents=True)
    (args.output / "controls.bin").write_bytes(input_data)
    (args.output / "controls-expected.out").write_bytes(output_data)
    print(json.dumps({"controls": [c[0] for c in cases], "validated_modules": 2 * len(cases),
                      "input": sha256(input_data).hexdigest(), "output": sha256(output_data).hexdigest()}, indent=2))


if __name__ == "__main__":
    main()
