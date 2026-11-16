# The compiler as a module on V8 too: regions by need, shared locals, a Rust host, 2026-11-16

Since `6f3c963` the compiler, compiled to Wasm, compiles itself under V8 as well as under Wasmtime, as a 64-bit and as a 32-bit module, and every output is byte for byte the native compiler's. It starts a small compile in 0.04 s under Wasmtime and 1.0 to 1.4 s under V8, where it took 0.24 s and 6.4 to 6.8 s.

Four changes did it: data regions sized by measured need instead of equally, one local index for temporaries that are never live together, 64-bit element counts, and a Wasmtime host written in Rust. This page follows [64-bit memory](../wasm-memory64/README.md), which ended with V8 stopping on the compiler's own source.

## What was measured

- **Source and compiler:** `6f3c963`, the bootstrapped compiler of its [qualification](runs/qualification.json) (executable `eadfec43889e…`). "Before" is the previous qualified compiler, of `1fbbd31`.
- **Workloads:** `selfhost/main.goose` built three ways: a 64-bit module with region statistics and 256 GiB declared (for Wasmtime), and a 64-bit module for 16 GiB and a 32-bit one for 4 GiB, both with the region profile that the first one writes while compiling itself. Each module run on `examples/squares.goose`, on `selfhost/main.goose --check`, and compiling `selfhost/main.goose`.
- **Engines:** Wasmtime 50.0.1, through `host/rust` (the `wasmtime` crate, built with rustc 1.97.0) and through `scripts/run_wasmtime.py` (the Python package); Node v22.23.4, V8 12.4.254.21-node.57, through `scripts/run_wasm.mjs`. `toolchain.json` pins Node 24.22.1; that one was not installed here.
- **Machine:** 4 cores, 16 GiB, Linux, gcc 13.3.0. Wall time, three runs each, all in [measurements.json](runs/measurements.json), produced by [tools/measure.py](tools/measure.py).

## The compiler as a module

| | native compiler | Wasmtime, Rust host, 64-bit | V8, 64-bit, 16 GiB | V8, 32-bit, 4 GiB |
| --- | --- | --- | --- | --- |
| `squares` to 32-bit Wasm | 0.003 s | 0.04 s | 1.3 to 1.4 s | 1.0 s |
| check itself | 7.5 to 7.9 s | 24.8 to 25.2 s | 25.1 to 26.1 s | 21.7 to 22.7 s |
| compile itself | 9.0 to 10.3 s | 29.8 to 30.8 s | 33.2 to 34.6 s | 29.1 to 30.2 s |
| the module it writes | | the native bytes (32-bit, 64-bit and C targets) | itself | itself |

- "Itself" means the module, given the options it was built with, writes the same bytes it consists of: 25,649,770 for the 64-bit one, 26,631,288 for the 32-bit one.
- The 32-bit module compiling itself is new: before this, wasm32 stopped in the self-check.
- Without a profile the 64-bit module still stops under V8 after 5.5 s, `data region exhausted (line 622)`, as before.
- Wasmtime compiles the module once, in 8.2 s, and keeps the result with `--cache`.

## 1. Regions sized by need

**The problem.** Memory above the stack was cut into equal regions, one for each growable array that can be live at once: 117 for the compiler. Under V8's 16 GiB that is 146.8 MB each, and the lifetime pass's effect list needs 176 MB, while all arrays together hold 0.66 GB at their peaks.

**Why not adapt while running.** Three things rule it out:
- An array cannot move, because references into it stay valid. So a region's place and room are fixed when its first byte is written, before anyone knows how large it grows.
- All 117 region indexes are touched in a self-compile, so the static bound is not slack that could be given away.
- The neighbours of the large arrays are long-lived siblings, not temporaries that come and go.

Under those conditions no placement rule beats the equal split in the worst case. Need has to be measured.

**What was built.**
- A region table in static data says where each region starts. A region closes with three words (cursor, start, high-water mark), and an array control's limit is their address. Finding an array's cursor is now one load; it was a subtraction, a division and a multiplication.
- `--wasm-region-stats` keeps the high-water marks. A host writes them as a profile (`GOOSE_REGION_PROFILE=path`), lines of `index bytes`.
- `--wasm-region-profile FILE` gives region `i` the weight `bytes(i) + mean`, so regions the profile does not name get an average share. With no profile all weights are equal, as before.
- The profile here has 89 regions and 664 MB. Its largest are 176.0, 118.0, 109.3, 43.6 and 43.4 MB.
- A host no longer needs the layout: the module exports `goose.reserve(control, count)`, which makes room at the end of a byte array as a `push` would, and returns where the bytes go.

**Limits.** A profile is what one run needed. This one comes from compiling the compiler to Wasm; a profile from the self-check alone was too small for the 32-bit module's self-compile (`data region exhausted` in the backend's output array), which is how the script came to take it from a whole compile. A larger input can outgrow any profile. Taking one is a manual step.

## 2. One local for temporaries that are never live together

The backend makes a Wasm local for every temporary. `wb_reuse_locals` (`selfhost/wasm.goose`) runs over each finished function body and gives locals whose spans do not meet the same index. A span is first to last instruction, widened to a whole loop when a value is carried around it, and to the function's start when a read may see the zero a local begins with.

| the compiler as a 64-bit module | before | after |
| --- | --- | --- |
| locals declared | 1,369,283 | 96,422 |
| most in one function | 23,905 | 1,241 |
| module bytes | 30,843,153 | 25,649,770 |
| `squares` under V8 | 6.4 to 6.8 s ([earlier page](../wasm-memory64/README.md)) | 1.3 to 1.4 s |

The native compiler's own time to emit the module did not change measurably (9 to 10 s both).

## 3. Element counts

With 64-bit memory `push`, `append`, `resize` and repetition literals check a count against 2^62 - 1, not 2^32 - 1, and check its product with the element size before forming it. A test fills an array with 4,294,967,312 bytes, pushes and appends past it, and slices its tail; the 32-bit build of the same program stops with `array length overflow`.

## 4. A Rust host for Wasmtime

`host/rust` (`goose-wasmtime`, 17.2 MB, 1 min 55 s to build) does what `scripts/run_wasmtime.py` does without Python.

- Same output, exit status and error text on 620 modules compared (ten examples and 150 fixtures, 32-bit and 64-bit, with and without input), and on failing programs, traps and bad input.
- Its float text equals the Python runner's on 4.7 million f32 and f64 bit patterns. Rust's shortest f64 digits differ from Python's `repr` on exact ties; the first comparison found 1,319 of them, and the host now rounds those as Python does.
- It starts in 0.04 s where the Python runner takes 0.21 to 0.23 s. On the long runs the two take the same time (self-check 24.8 to 25.2 s against 23.4 to 24.8 s): the factor of three over the native compiler is the compiled module, not the host.
- The two hosts' cache files are not interchangeable.

## What it did to programs

Kernel time, median of five, before → after, ms ([runtime.json](runs/runtime.json), [tools/runtime.py](tools/runtime.py)). The first four are the benchmark fixtures; the last two are [here](tools/array_push.goose) and [here](tools/array_locals.goose) and use growable arrays.

| program | Wasmtime 32-bit | V8 32-bit | Wasmtime 64-bit | V8 64-bit |
| --- | --- | --- | --- | --- |
| `array_updates` | 25.7 → 26.2 | 75.9 → 77.0 | 26.0 → 26.5 | 93.9 → 87.8 |
| `integer_mod` | 37.9 → 38.0 | 62.0 → 61.5 | 38.1 → 37.6 | 62.1 → 62.3 |
| `float_recurrence` | 39.0 → 39.6 | 49.6 → 49.6 | 39.7 → 39.6 | 49.4 → 51.7 |
| `recursive_fibonacci` | 93.0 → 93.2 | 106.6 → 106.6 | 104.7 → 107.6 | 104.2 → 104.0 |
| `array_push` (4 million pushes) | 49.9 → 45.4 | 81.5 → 62.0 | 54.0 → 45.2 | 119.5 → 90.3 |
| `array_locals` (4 million calls with an array each) | 112.1 → 87.9 | 180.9 → 126.2 | 118.5 → 101.3 | 302.7 → 211.2 |

- The four fixtures did not move beyond their spread.
- Code that grows arrays is 9 to 30% faster: the cursor lookup lost its division.
- The README's benchmark tables predate this and were not rerun.

## Where 64-bit memory's cost comes from

On `recursive_fibonacci` under Wasmtime ([bounds.json](runs/bounds.json), [tools/bounds.py](tools/bounds.py)):

| | kernel, median of five |
| --- | --- |
| 32-bit memory | 99.1 ms |
| 64-bit memory | 122.8 ms |
| 64-bit memory, Spectre-hardened bounds checks off | 105.9 ms |

Wasmtime reaches a 32-bit memory through guard pages and checks nothing. For a 64-bit memory it compares every address with the bound and, by default, selects a null address on failure (a conditional move, three in the recursive function). Most of the cost is that hardening. It is a host setting and was left on.

## Evidence that nothing else changed

| check | result |
| --- | --- |
| bootstrap | fixed point |
| conformance | 10,689 of 10,793, the 104 recorded gaps |
| conformance, Wasm rows with `--wasm-memory64` (now a qualification stage) | 4,765 of 4,773, the 8 rows of `tests/conformance/known-gaps-memory64.json` |
| outputs against the previous compiler ([summary](runs/equivalence-differences.json)) | 8,662 of 10,049 the same: every check, every C output and 510 Wasm modules. The 1,387 that differ are all Wasm modules, and none differs in exit status or diagnostics |
| programs run from both compilers' modules under Node, 32-bit and 64-bit | 376 of 376 print the same |
| unit tests, with the new ones | pass |

The 64-bit gap record holds one gap shared with 32-bit and three contracts that expect a capacity of 2^32 to be refused; with 64-bit counts it is a valid count that fails where it is reserved. Three 32-bit gaps pass with 64-bit memory.

## Not kept

- **Placing regions while running** (bisecting the largest free gap, letting a region grow into a free neighbour, giving the top of the stack the rest): not built, for the reasons under section 1.
- **A smaller effect record** so that the equal split would do: 17% would have been enough for this input and no other.
- **Region statistics always on**: they cost a compare and a store at every cursor move, so they are an option.
- **A profile taken from the self-check** for the 32-bit module: too small for the compile, see section 1.

## Not done

- A profile is taken by hand, from one run. Nothing ships one with the compiler, merges two, or retries with a larger share.
- The module is three times the native compiler under Wasmtime and about the same under V8. Why was not looked into.
- The conformance runner and the benchmarks still use the Python runner; `scripts/qualify.py` does not build the Rust host; `host/wasmtime.cpp` has no `os` imports.
- The pinned Node 24 was not installed; all V8 numbers are Node 22.
- The README's runtime tables were not rerun with the faster array code.

## Tools

- `tools/measure.py`, `tools/runtime.py`, `tools/bounds.py`: the three measurements above.
- `tools/array_push.goose`, `tools/array_locals.goose`: the two array programs.
- In `../wasm-memory64/tools/`: `wasmcheck.py` (types every function of a module), `widecheck.sh` (a program's 64-bit module against its 32-bit one).
