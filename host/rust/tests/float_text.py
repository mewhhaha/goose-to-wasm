#!/usr/bin/env python3
"""Compare the Rust host's float text with scripts/run_wasmtime.py goose_float.

Build the printer first: cargo build --release --examples (in host/rust).
Checked: zeros, infinities and NaNs; every power of two and of ten with its
neighbours; subnormals; small integers and short decimals; the values where
the layout changes; values half way between two shortest texts; and --count
random bit patterns of each width.
"""

from __future__ import annotations

import argparse
import random
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True  # nothing of this test's is left in scripts/
sys.path.insert(0, str(HERE.parents[2] / "scripts"))
from run_wasmtime import goose_float  # noqa: E402

F32_MAX, F64_MAX = 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF


def bits32(value: float) -> int:
    try:
        return struct.unpack("<I", struct.pack("<f", value))[0]
    except OverflowError:
        return 0x7F800000


def bits64(value: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def patterns(count: int, seed: int) -> tuple[set[int], set[int]]:
    rng = random.Random(seed)
    narrow: set[int] = set()
    wide: set[int] = set()

    def near(bits: int, limit: int, into: set[int], reach: int = 3) -> None:
        for step in range(-reach, reach + 1):
            if 0 <= bits + step <= limit:
                into.add(bits + step)
                into.add((bits + step) ^ (limit + 1) >> 1)  # the negative

    def value(number: float) -> None:
        near(bits64(number), F64_MAX, wide)
        near(bits32(number), F32_MAX, narrow)

    # Zeros, infinities, NaNs with several payloads, the ends of each range.
    for bits in (0, 1, 2, 0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0x7F800000, 0x7F800001, 0x7FC00000, 0x7FFFFFFF):
        near(bits, F32_MAX, narrow)
    for bits in (0, 1, 2, 0x000FFFFFFFFFFFFF, 0x0010000000000000, 0x7FEFFFFFFFFFFFFF, 0x7FF0000000000000,
                 0x7FF0000000000001, 0x7FF8000000000000, 0x7FFFFFFFFFFFFFFF):
        near(bits, F64_MAX, wide)
    # Every power of two, subnormal ones included, and its neighbours.
    for exponent in range(-1074, 1024):
        near(bits64(2.0 ** exponent), F64_MAX, wide)
    for exponent in range(-149, 128):
        near(bits32(2.0 ** exponent), F32_MAX, narrow)
    # Every power of ten, and the digits 1 to 9 times it.
    for exponent in range(-324, 309):
        for digit in range(1, 10):
            value(float(f"{digit}e{exponent}"))
    # Subnormals: the smallest, and a spread of the rest.
    for bits in range(1, 4097):
        narrow.add(bits)
        wide.add(bits)
    for _ in range(20000):
        narrow.add(rng.randrange(1, 0x00800000))
        wide.add(rng.randrange(1, 0x0010000000000000))
    # Small integers, and short decimals around where the layout changes.
    for number in range(0, 20001):
        value(float(number))
        value(number / 10)
        value(number / 1000)
        value(number * 1e-7)
    for exponent in range(-8, 24):
        for mantissa in ("1", "9", "1.5", "9.5", "9.9999", "1.0000001", "1.2345678", "9.9999999",
                         "1.234567890123456", "9.999999999999999", "1.2345678901234567", "9.9999999999999999"):
            value(float(f"{mantissa}e{exponent}"))
    for _ in range(40000):
        digits = rng.randrange(1, 18)
        value(float(f"{rng.randrange(1, 10 ** digits)}e{rng.randrange(-330, 310)}"))
        value(float(f"{rng.randrange(1, 10 ** digits)}e{rng.randrange(-25, 25)}"))
    # Values that end in a 5 one digit past what f64 or f32 text keeps, where
    # the two nearest shortest texts are equally near: odd numbers over powers
    # of two, and odd multiples of five times powers of ten.
    for _ in range(60000):
        wide.add(bits64(rng.randrange(1, 1 << 53, 2) * 2.0 ** rng.randrange(-70, 12)))
        wide.add(bits64(rng.randrange(1, 1 << rng.randrange(2, 54), 2) * 2.0 ** rng.randrange(-30, 1)))
        narrow.add(bits32(rng.randrange(1, 1 << 24, 2) * 2.0 ** rng.randrange(-40, 12)))
        narrow.add(bits32(rng.randrange(1, 1 << rng.randrange(2, 25), 2) * 2.0 ** rng.randrange(-20, 1)))
        power = rng.randrange(0, 23)
        wide.add(bits64(float(rng.randrange(5, max(6, (1 << 53) // 5 ** power), 10) * 10 ** power)))
        power = rng.randrange(0, 11)
        narrow.add(bits32(float(rng.randrange(5, max(6, (1 << 24) // 5 ** power), 10) * 10 ** power)))
    # Random bit patterns.
    for _ in range(count):
        narrow.add(rng.getrandbits(32))
        wide.add(rng.getrandbits(64))
    return narrow, wide


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=250000, help="random bit patterns of each width")
    parser.add_argument("--seed", type=int, default=20261116)
    parser.add_argument("--printer", type=Path, default=HERE.parent / "target/release/examples/float_text")
    args = parser.parse_args()
    narrow, wide = patterns(args.count, args.seed)
    cases = [("f32", bits) for bits in sorted(narrow)] + [("f64", bits) for bits in sorted(wide)]
    request = "".join(f"{kind} {bits:x}\n" for kind, bits in cases)
    answers = subprocess.run([args.printer], input=request.encode(), stdout=subprocess.PIPE, check=True).stdout.decode().split("\n")
    if len(answers) != len(cases) + 1:
        print(f"the printer gave {len(answers) - 1} lines for {len(cases)} values", file=sys.stderr)
        return 1
    differences = 0
    for (kind, bits), answer in zip(cases, answers):
        if kind == "f32":
            expected = goose_float(struct.unpack("<f", struct.pack("<I", bits))[0], 32)
        else:
            expected = goose_float(struct.unpack("<d", struct.pack("<Q", bits))[0])
        if answer != expected:
            differences += 1
            if differences <= 20:
                print(f"{kind} {bits:x}: python {expected!r}, rust {answer!r}", file=sys.stderr)
    print(f"{len(narrow)} f32 and {len(wide)} f64 bit patterns: {differences} differences")
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
