"""Use Binaryen's ordinary import encoding while preserving every other section byte."""
from pathlib import Path
import sys


def sections(data):
    pos = 8
    while pos < len(data):
        start = pos
        kind = data[pos]
        pos += 1
        size = 0
        shift = 0
        while True:
            byte = data[pos]
            pos += 1
            size |= (byte & 127) << shift
            if byte < 128:
                break
            shift += 7
        pos += size
        assert pos <= len(data)
        yield kind, data[start:pos]


original, expanded, output = map(Path, sys.argv[1:])
compact = original.read_bytes()
imports, = [part for kind, part in sections(expanded.read_bytes()) if kind == 2]
parts = [compact[:8]]
for kind, part in sections(compact):
    if kind == 2:
        part = imports
    parts.append(part)
output.write_bytes(b"".join(parts))
