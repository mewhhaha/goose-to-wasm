"""Add private i64 globals to a validated single-memory Wasm compiler.

wasm-copy-sites (using wasmparser) supplies decoded instruction boundaries. Existing
code and section bytes are kept, apart from appended globals/exports and counters.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path


def leb(value):
    data = bytearray()
    while value >= 128:
        data.append((value & 127) | 128)
        value >>= 7
    data.append(value)
    return data


def read(data, at):
    value, shift = 0, 0
    while True:
        b = data[at]
        value |= (b & 127) << shift
        at += 1
        if b < 128:
            return value, at
        shift += 7


def chunk(data):
    return leb(len(data)) + data


def names_section(data):
    n, p = read(data, 0)
    assert data[p:p+n] == b'name'
    p += n
    while p < len(data):
        section = data[p]
        n, p = read(data, p+1)
        end = p+n
        if section == 1:
            result = {}
            count, p = read(data, p)
            for _ in range(count):
                idx, p = read(data, p)
                n, p = read(data, p)
                result[idx] = data[p:p+n].decode()
                p += n
            assert p == end
            return result
        p = end
    raise ValueError('missing function names')


def instrument(module, site_file, output, detailed, only=()):
    data = module.read_bytes()
    assert data[:8] == b'\0asm\1\0\0\0'
    p = 8
    sections = []
    while p < len(data):
        key = data[p]
        n, p = read(data, p + 1)
        sections.append((key, data[p:p+n]))
        p += n
    by_id = dict(sections)
    names = names_section(by_id[0])
    missing = set(only).difference(names.values())
    if missing:
        raise ValueError(f"unknown function names: {sorted(missing)}")
    sites = defaultdict(list)
    for line in site_file.read_text().splitlines():
        ordinal, offset, kind, size = line.split()
        sites[int(ordinal)].append((int(offset), kind, int(size)))
    imports = by_id.get(2, b"\x00")
    imported, p = read(imports, 0)
    for _ in range(imported):
        for _ in range(2):
            n, p = read(imports, p)
            p += n
        assert imports[p] == 0, 'only imported functions are supported'
        _, p = read(imports, p+1)
    assert p == len(imports)
    count, flags_offset = read(by_id[5], 0)
    assert count == 1, 'requires a single defined memory'
    memory64 = bool(by_id[5][flags_offset] & 4)
    base, gstart = read(by_id[6], 0)
    scratch = base  # reserved for a dynamic length during straight-line instrumentation
    keys = {}
    metadata = []

    def counter(key):
        if key not in keys:
            keys[key] = base + 1 + len(keys)
            metadata.append(key)
        return keys[key]

    code = by_id[10]
    n, p = read(code, 0)
    changed = leb(n)
    counted_sites = 0
    for ordinal in range(n):
        size, p = read(code, p)
        body, cursor = code[p:p+size], 0
        p += size
        func = ordinal + imported
        name = names.get(func, f'wasm-function[{func}]')
        if only and name not in only:
            changed.extend(chunk(body))
            continue
        counted_sites += len(sites[ordinal])
        new = bytearray()
        for offset, kind, width in sites[ordinal]:
            assert cursor <= offset < len(body)
            if kind == 'copy':
                assert body[offset:offset+4] == b'\xfc\x0a\0\0'
            if kind == 'fill':
                assert body[offset:offset+3] == b'\xfc\x0b\0'
            new.extend(body[cursor:offset])
            cursor = offset
            site = None
            if name in detailed:
                site = offset
            calls = leb(counter((func, name, kind, width, site, 'calls')))
            new.extend(b'\x23' + calls + b'\x42\x01\x7c\x24' + calls)
            if width == -1:
                amount = leb(counter((func, name, kind, width, site, 'bytes')))
                if not memory64:
                    new.append(0xad)  # i64.extend_i32_u for the byte counter
                new.extend(b'\x24' + leb(scratch) + b'\x23' + amount + b'\x23' + leb(scratch)
                           + b'\x7c\x24' + amount + b'\x23' + leb(scratch))
                if not memory64:
                    new.append(0xa7)  # restore the memory32 operand
        new.extend(body[cursor:])
        changed.extend(chunk(new))
    assert p == len(code)
    n, p = read(by_id[7], 0)
    exports = leb(n + len(keys)) + by_id[7][p:]
    for i in range(len(keys)):
        exports.extend(chunk(f'probe.{i}'.encode()) + b'\x03' + leb(base+1+i))
    total = 1 + len(keys)
    globals_ = leb(base + total) + by_id[6][gstart:] + b'\x7e\x01\x42\x00\x0b' * total
    out = bytearray(data[:8])
    for key, payload in sections:
        out.append(key)
        out.extend(chunk({6: globals_, 7: exports, 10: changed}.get(key, payload)))
    output.write_bytes(out)
    output.with_suffix('.map.json').write_text(json.dumps({
        'input_sha256': hashlib.sha256(data).hexdigest(), 'output_sha256': hashlib.sha256(out).hexdigest(),
        'static_sites': counted_sites, 'imported_functions': imported, 'counters': metadata,
    }))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('module', 'sites', 'output'):
        p.add_argument(arg, type=Path)
    p.add_argument('--detail', nargs='*', default=['life_replay', 'life_effect', 'life_effect_far',
                   'life_readback', 'life_read_reach', 'life_construct_read', 'life_eval', 'life_eval_body',
                   'life_held_into', 'life_class_candidates', 'life_depth'])
    p.add_argument('--only', nargs='+', default=[], help='instrument just these named functions')
    a = p.parse_args()
    instrument(a.module, a.sites, a.output, set(a.detail), set(a.only))
