#!/usr/bin/env python3
"""Stage warmed kernel adapters without copying the examples' algorithms."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1
PUZZLES = (
    "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79",
    "8..........36......7..9.2...5...7.......457.....1...3...1....68..85...1..9....4..",
)

DECLARATIONS = """
extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value:i64) -> i64;
extern fn bench_sink(value:i64);

fn reference_finish(checksum:u32, elapsed:i64) {
    bench_sink(checksum); print(checksum); print(elapsed);
}
"""

LIFE = """
fn measured_run(initial:u8[:], cur:u8[:], next:u8[:], generations:i64, iteration:i64) -> u32 {
    copy_into(cur, initial);
    cur[bench_barrier(iteration) % cur.len] ^= 1;
    for gen in generations / 2 {
        step(cur, next, 64, 32);
        step(next, cur, 64, 32);
    }
    var hash:u32 = 5381;
    for value in cur { hash = (hash << 5) + hash + value; }
    return hash;
}

fn main() {
    let seed = bench_input(); let generations = bench_input();
    let iterations = bench_input(); let warmups = bench_input();
    assert(seed >= 0 && generations >= 2 && generations <= 2000 && generations % 2 == 0);
    assert(iterations > 0 && iterations <= 1000 && warmups >= 0 && warmups <= 20);
    var r = rng { seed as! u64 };
    var initial:u8[>..] = []; var cur:u8[>..] = []; var next:u8[>..] = [];
    for i in 64 * 32 { initial.push(if r.rand_int(4) == 0 { 1 } else { 0 }); }
    cur.resize(64 * 32, 0); next.resize(64 * 32, 0);
    var warmed:u32 = 0;
    for i in warmups { warmed += measured_run(initial, cur, next, generations, i); }
    bench_sink(warmed);
    let count = bench_barrier(iterations); var checksum:u32 = 0;
    let started = bench_clock();
    for i in count { checksum += measured_run(initial, cur, next, generations, i); }
    let elapsed = bench_clock() - started;
    reference_finish(checksum, elapsed);
}
"""

SORTING = """
fn measured_run(initial:i32[:], working:i32[:], iteration:i64) -> u32 {
    copy_into(working, initial);
    working[0] = bench_barrier(iteration) as! i32;
    insertion_sort(working);
    assert(is_sorted(working));
    var hash:u32 = 5381;
    for value in working { hash = (hash << 5) + hash + (value as! u32); }
    return hash;
}

fn main() {
    let size = bench_input(); let seed = bench_input();
    let iterations = bench_input(); let warmups = bench_input();
    assert(size >= 1 && size <= 20000 && seed >= 0);
    assert(iterations > 0 && iterations <= 1000 && warmups >= 0 && warmups <= 20);
    let initial = random_ints(size, seed as! u64);
    var working:i32[>..] = []; working.resize(size, 0);
    var warmed:u32 = 0;
    for i in warmups { warmed += measured_run(initial, working, i); }
    bench_sink(warmed);
    let count = bench_barrier(iterations); var checksum:u32 = 0;
    let started = bench_clock();
    for i in count { checksum += measured_run(initial, working, i); }
    let elapsed = bench_clock() - started;
    reference_finish(checksum, elapsed);
}
"""

SUDOKU = """
fn measured_run(iteration:i64) -> u32 {
    let kind = bench_barrier(iteration) % 2;
    let puzzle = if kind == 0 { "@EASY@" } else { "@HARD@" };
    var board = parse(puzzle); guesses = 0;
    assert(solve(board));
    var hash:u32 = guesses as! u32;
    for value in board.cells { hash = (hash << 5) + hash + value; }
    return hash;
}

fn main() {
    let offset = bench_input(); let iterations = bench_input(); let warmups = bench_input();
    assert(offset >= 0 && offset <= 1 && iterations > 0 && iterations <= 1000);
    assert(warmups >= 0 && warmups <= 20);
    var warmed:u32 = 0;
    for i in warmups { warmed += measured_run(i + offset); }
    bench_sink(warmed);
    let count = bench_barrier(iterations); var checksum:u32 = 0;
    let started = bench_clock();
    for i in count { checksum += measured_run(i + offset); }
    let elapsed = bench_clock() - started;
    reference_finish(checksum, elapsed);
}
""".replace("@EASY@", PUZZLES[0]).replace("@HARD@", PUZZLES[1])


def random_words(seed, count):
    """Independent SplitMix64 implementation of std.goose's input generator."""
    state = seed
    for _ in range(count):
        state = (state + 11400714819323198485) & MASK64
        value = state
        value = ((value ^ (value >> 30)) * 13787848793156543929) & MASK64
        value = ((value ^ (value >> 27)) * 10723151780598845931) & MASK64
        yield value ^ (value >> 31)


def checksum(values, initial=5381):
    result = initial
    for value in values:
        result = (result * 33 + value) & MASK32
    return result


def life_step(rows, width):
    """Bit-plane neighbour addition, independent of the scalar Goose kernel."""
    mask = (1 << width) - 1
    out = []
    for y, current in enumerate(rows):
        above = rows[y - 1]
        below = rows[(y + 1) % len(rows)]
        neighbours = []
        for row in (above, current, below):
            neighbours.extend((((row << 1) & mask) | (row >> (width - 1)),
                               (row >> 1) | ((row & 1) << (width - 1))))
        neighbours.extend((above, below))
        ones = twos = fours = eights = 0
        for row in neighbours:
            carry = ones & row
            ones ^= row
            next_carry = twos & carry
            twos ^= carry
            carry = fours & next_carry
            fours ^= next_carry
            eights ^= carry
        two_or_three = twos & ~(fours | eights) & mask
        out.append(two_or_three & (ones | current))
    return out


def life_checksum(seed, generations, iterations):
    initial = [int(word % 4 == 0) for word in random_words(seed, 64 * 32)]
    total = 0
    for iteration in range(iterations):
        cells = initial.copy()
        cells[iteration % len(cells)] ^= 1
        rows = [sum(cells[y * 64 + x] << x for x in range(64)) for y in range(32)]
        for _ in range(generations):
            rows = life_step(rows, 64)
        total += checksum((row >> x) & 1 for row in rows for x in range(64))
    return total & MASK32


def sorting_checksum(size, seed, iterations):
    initial = [word % 1000000 for word in random_words(seed, size)]
    total = 0
    for iteration in range(iterations):
        working = initial.copy()
        working[0] = iteration
        total += checksum(sorted(working))
    return total & MASK32


def solve_sudoku(puzzle):
    """Independent Python search, preserving MRV and digit order for guesses."""
    cells = []
    for char in puzzle:
        value = 0
        if char != ".":
            value = int(char)
        cells.append(value)
    rows = [0] * 9
    cols = [0] * 9
    boxes = [0] * 9
    for index, digit in enumerate(cells):
        if digit:
            box = (index // 27) * 3 + (index % 9) // 3
            rows[index // 9] |= 1 << digit
            cols[index % 9] |= 1 << digit
            boxes[box] |= 1 << digit
    guesses = 0

    def search():
        nonlocal guesses
        best = -1
        best_count = 10
        selected = 0
        for index, value in enumerate(cells):
            if value:
                continue
            box = (index // 27) * 3 + (index % 9) // 3
            candidates = ~(rows[index // 9] | cols[index % 9] | boxes[box]) & 0x3FE
            count = candidates.bit_count()
            if count < best_count:
                best, best_count, selected = index, count, candidates
                if count == 0:
                    return False
        if best < 0:
            return True
        row, col = divmod(best, 9)
        box = (best // 27) * 3 + (best % 9) // 3
        for digit in range(1, 10):
            bit = 1 << digit
            if not selected & bit:
                continue
            guesses += 1
            cells[best] = digit
            rows[row] |= bit
            cols[col] |= bit
            boxes[box] |= bit
            if search():
                return True
            cells[best] = 0
            rows[row] &= ~bit
            cols[col] &= ~bit
            boxes[box] &= ~bit
        return False

    assert search()
    for offset in range(9):
        assert set(cells[offset * 9:offset * 9 + 9]) == set(range(1, 10))
        assert set(cells[offset::9]) == set(range(1, 10))
    return cells, guesses


def sudoku_checksums():
    values = []
    for puzzle in PUZZLES:
        cells, guesses = solve_sudoku(puzzle)
        values.append(checksum(cells, guesses))
    return values


def stage(output):
    output.mkdir(parents=True, exist_ok=True)
    configs = {
        "life": {"test": (2024, 4, 2, 1), "run": (2024, 200, 64, 2)},
        "sorting": {"test": (64, 1, 3, 1), "run": (20000, 1, 32, 2)},
        "sudoku": {"test": (0, 2, 1), "run": (0, 128, 4)},
    }
    templates = {"life": LIFE, "sorting": SORTING, "sudoku": SUDOKU}
    sudoku = sudoku_checksums()
    cases = []
    for name, profiles in configs.items():
        source = ROOT / "examples" / (name + ".goose")
        original = source.read_text()
        assert original.count("\nfn main() {") == 1
        prefix = original.partition("\nfn main() {")[0]
        target = output / (name + ".goose")
        target.write_text(prefix + DECLARATIONS + templates[name])
        item = {"name": "Example::" + name.title(), "source": target.name,
                "notes": "Kernel adapter; original function bodies retained, display and other example jobs excluded. One-time preparation is outside the timer; per-run reset, perturbation, validation and checksum are timed. Each job uses one opaque barrier. Warmup checksums are consumed separately. Runtime imports disable the direct compiler's closed-module raw-array proof; this is separate from the original full-program binary.",
                "original": str(source), "original_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "retained_prefix_sha256": hashlib.sha256(prefix.encode()).hexdigest(),
                "source_files": [str(source), str(Path(__file__).resolve()), str(ROOT / "build/bin/stdlib/std.goose")]}
        if name == "life":
            item["kernel"] = "Fixed 64x32 toroidal step, original SplitMix64 soup, 200 generations/run. Copy, one-cell input perturbation and final grid hash included. Literal dimensions retain specialization eligibility."
        elif name == "sorting":
            item["kernel"] = "Original insertion_sort on 20000 SplitMix64 values; copy, first-value perturbation, sortedness check and final array hash included."
        else:
            item["kernel"] = "Original MRV solver alternating the same easy/hard puzzles; parse, solve, guess count and final solution hash included."
        for profile, values in profiles.items():
            if name == "life":
                expected = life_checksum(*values[:3])
            elif name == "sorting":
                expected = sorting_checksum(*values[:3])
            else:
                offset, iterations, _ = values
                expected = sum(sudoku[(i + offset) % 2] for i in range(iterations)) & MASK32
            item[profile] = {"stdin": " ".join(map(str, values)) + "\n", "checksum": expected}
        cases.append(item)
    report = {"schema": "goose-runtime-reference-cases-v1", "cases": cases}
    manifest = output / "cases.json"
    manifest.write_text(json.dumps(report, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/runtime-reference/inputs")
    args = parser.parse_args()
    print(stage(args.output.resolve()))
