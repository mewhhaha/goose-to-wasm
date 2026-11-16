# 64-bit memory in the direct Wasm backend, 2026-11-16

Since `3fef0c5` the direct backend builds modules for a 64-bit memory with `--wasm-memory64`. Compiled that way, the compiler runs under Wasmtime, checks its own source and compiles itself, and every output is byte for byte the native compiler's. Under V8 it still stops on its own source: V8 caps a 64-bit memory at 16 GiB, and the largest table needs a bigger share of it than an even split gives.

The 32-bit output did not change: 10,049 of 10,049 outputs are those of the previous compiler.

This follows [the compiler as a Wasm module](../wasm-hosted-compiler/README.md), where wasm32's address space stopped the self-check.

## What was measured

- **Source and compiler:** `3fef0c5`, the bootstrapped compiler of its [qualification](runs/qualification.json) (executable `04777322b410…`; the qualification ran on the same `selfhost/` at `0df4b50` with the tests and scripts of `3fef0c5` uncommitted).
- **Workloads:** `selfhost/main.goose` (30,431 lines in `selfhost/`) built with `--target wasm-direct -O2 --debug --wasm-memory64`, with `--wasm-max-pages 4194304` (256 GiB) for Wasmtime and `262144` (16 GiB) for V8. The module then run on `examples/squares.goose` for both targets and on `selfhost/main.goose` for `--check`, 32-bit Wasm, 64-bit Wasm and C.
- **Engines:** Wasmtime 50.0.1 (Python package, Cranelift `speed`) through `scripts/run_wasmtime.py`; Node v22.23.4, V8 12.4.254.21-node.57, through `scripts/run_wasm.mjs`, which turns on `--experimental-wasm-memory64` for it. `toolchain.json` pins Node 24.22.1 (V8 13.6, 64-bit memory on by default); that one was not installed here.
- **Machine:** 4 cores, 16 GiB, Linux, gcc 13.3.0. Wall time, three runs each, all in [measurements.json](runs/measurements.json), produced by [tools/measure.py](tools/measure.py).

## The compiler as a 64-bit module

| | native compiler | the module under Wasmtime | the module under V8 |
| --- | --- | --- | --- |
| `squares` to 32-bit Wasm | 0.003 s | 0.24 s, same bytes | 6.4 to 6.8 s, same bytes |
| `squares` to C | 0.002 to 0.004 s | 0.22 s, same bytes | 7.2 to 7.5 s, same bytes |
| check itself | 7.9 to 9.2 s | 25.3 to 26.5 s | stops after 7.9 s: `data region exhausted (line 622)` |
| itself to 32-bit Wasm (31,622,624 bytes) | 9.8 to 10.1 s | 30.0 to 31.0 s, same bytes | |
| itself to 64-bit Wasm (30,595,975 bytes) | 9.3 to 10.6 s | 30.8 to 31.6 s, same bytes | |
| itself to C (45,708,817 bytes) | 10.2 to 10.7 s | 32.4 to 34.4 s, same bytes | |

- The module that Wasmtime ran is 30,595,975 bytes. Asked to compile the compiler with the options it was built with, it writes those same 30,595,975 bytes: the bootstrap fixed point, through Wasm.
- Wasmtime compiles the module once, in 9.8 s (34 s of CPU on four cores), and `--cache` keeps the result (70 MB); the times above are with it cached.
- The Wasmtime times include a host written in Python. How much of the factor of three is the host was not measured.

## Why V8 still stops

V8 refuses a 64-bit memory with a declared maximum above 262,144 pages. The backend cuts memory into equal regions, one a live growable array: 117 for the compiler, so 146.8 MB each at 16 GiB.

`GOOSE_REGION_STATS=1` makes either host print how far each region's cursor got. After a self-check under Wasmtime the largest five are 175.7 MB, 117.8 MB, 58.1 MB, 43.3 MB and 42.6 MB. The first is the lifetime pass's effect list, the push at `selfhost/checker_lifetimes.goose:622` that V8 reports. 117 regions of 175.7 MB are 20.6 GB, against the cap's 17.2 GB.

Ways on, none tried: regions of unequal size, or a smaller effect record. Whether the pinned Node 24 has the same cap was not checked.

## Programs with 64-bit memory

| check | result |
| --- | --- |
| 32-bit output against the previous compiler (`6b8bd39`) | 10,049 of 10,049 the same |
| conformance, every `wasm-direct` row built with `--wasm-memory64`, Wasmtime ([summary](runs/conformance-memory64.json)) | 4,767 of 4,773 pass |
| the six that fail | three recorded gaps at two levels: two `regions` contracts and `uleb_length_boundaries`. They are recorded for 32-bit too |
| a recorded gap that passes with 64-bit memory | `packed_layout_boundaries`, both levels; it stays a gap for 32-bit |
| ten examples at `-O2` and `-O0`, 366 fixtures at `-O2`, 64-bit against 32-bit module under Node | all print the same |
| every function of the 64-bit compiler module, type-checked by [tools/wasmcheck.py](tools/wasmcheck.py) | 3,031 functions, 0 errors |

`tests/test_cli_outputs.py` (`WasmMemory64`) keeps three of these: examples under both engines, the page limits, and the self-compile to the module's own bytes.

## What 64-bit memory costs at run time

Kernel time of the four benchmark fixtures, median of five, the fixture timing itself after two warm-up calls ([runtime.json](runs/runtime.json), [tools/runtime.py](tools/runtime.py)):

| fixture | Wasmtime 32-bit | Wasmtime 64-bit | V8 32-bit | V8 64-bit |
| --- | --- | --- | --- | --- |
| `array_updates` | 27.6 ms | 27.8 ms | 82.6 ms | 99.4 ms |
| `integer_mod` | 39.9 ms | 39.9 ms | 65.3 ms | 65.5 ms |
| `float_recurrence` | 40.8 ms | 42.4 ms | 52.5 ms | 52.3 ms |
| `recursive_fibonacci` | 99.0 ms | 114.6 ms | 112.7 ms | 113.0 ms |

Two differences stand out, each on one engine: array indexing under V8 (20% slower) and calls under Wasmtime (16% slower). The others are within the runs' spread. This is why 32-bit stays the default; the README's runtime numbers are all 32-bit.

## The representation

| | wasm32 | `--wasm-memory64` |
| --- | --- | --- |
| address | i32 | i64 |
| slice | one i64: 32-bit pointer, 32-bit count | one v128: 64-bit pointer, 64-bit count |
| growable array's control | six u32 words | six u64 words |
| import taking a slice | one i64 | two i64, pointer then count |

`docs/TARGET.md` has the whole table and the host interface.

Decisions, with what was not kept:

- **A slice as a v128, not as two values.** The emitter produces one Wasm value per expression everywhere. A v128 keeps that; two i64 would have changed every call, block result and local that carries a slice. The cost is that a v128 cannot cross to a host, so an import takes the two halves.
- **A switch, not a replacement.** V8 checks 64-bit bounds explicitly, and the 10,049 unchanged outputs were the safety net for the rewrite.
- **Not kept: the runtime-limited array's prefix as two u32.** One converted stretch kept the 8-byte prefix and trapped on counts above 2^32; the readers in two other stretches had made it two address-sized words. The words won, to keep one rule for every structure the backend lays out.
- **Not kept: refusing more than 262,144 pages in the compiler.** That is V8's cap. The driver takes up to 2^32 pages and the engine says what it holds.
- **Kept for now: 32-bit element counts.** `push`, `append`, `resize` and repetition literals still check a count against 2^32 - 1 and one array's buffer against 4 GiB, because the products they guard were written for 32-bit counts. A slice's count is 64 bits.
- **A function value is still one i64** with its environment's address in 32 bits. Environments are in activation frames, at the bottom of memory.

## How the rewrite was done

`selfhost/codegen.goose` emits raw opcodes: 5,800 lines, about 290 load and store sites, address arithmetic in i32 throughout.

1. Helpers that emit the i32 form without the switch and the i64 form with it (`wa_const`, `wa_op`, `wa_load`, `wc_load`, `ws_pack`, ...), and the first 800 lines converted by hand.
2. The rest in seven stretches, converted in parallel by seven agents in private copies under [one written brief](tools/conversion-brief.md). Its two fixed rules: no byte of 32-bit output changes, and every structure the backend lays out as u32 words keeps its word order with every word address-sized. The second is what let a writer in one stretch and a reader in another agree.
3. After each merge, [narrowcheck.sh](tools/narrowcheck.sh): the 32-bit output of the examples, the compiler itself and 150 fixtures against the previous compiler, byte for byte. It never differed.
4. For 64-bit output, a type checker written for the purpose ([wasmcheck.py](tools/wasmcheck.py)) that names the first wrong instruction of each function, and [widecheck.sh](tools/widecheck.sh), which runs a program's 64-bit module against its 32-bit one.

What the first 64-bit runs found: with six stretches merged the examples without growable arrays already ran; with all seven, every example and 364 of 366 fixtures. The other two used `free`, whose slice path the hand-converted part had left 32-bit.

The checker's layout needed one change: a control's size was the constant 24 in five places.

## Not done

- The self-check under V8 (above).
- Element counts above 2^32 - 1 in one growable array.
- `host/wasmtime.cpp`, the C++ host, has neither the `os` imports nor a large-memory configuration; the Python runner has both.
- The module's speed under V8: 6 to 7 s on an 11-line program, as with 32-bit memory, for the reason given [there](../wasm-hosted-compiler/README.md#why-it-is-slow).
- The share of the host in Wasmtime's factor of three.
