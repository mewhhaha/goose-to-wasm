# The compiler as a Wasm module, 2026-11-16

The question was whether the compiler can compile itself to direct Wasm, as a test of the backend on its largest program at hand (30,181 lines in `selfhost/`). It can since `6b8bd39`, and the module runs. It cannot yet check or compile itself: that needs more than wasm32's address space gives each growable array.

## What was measured

- Source and compiler: `6b8bd39`, the bootstrapped compiler of its [qualification](runs/qualification.json) (bootstrap fixed point; conformance 10,689 of 10,793 with the 104 known gaps; native checks; unit tests rerun after the two test files were fixed, 63 pass). Its outputs differ from `c72e198`'s on [three fixtures](runs/equivalence-differences.json) of 10,049: externs with slice or reference parameters that were refused and compile now.
- Workloads: `selfhost/main.goose` emitted with `--target wasm-direct -O2 --wasm-max-pages 65535`; the resulting module run on `examples/squares.goose` (11 lines) and `examples/tour.goose` for both targets, and on `selfhost/main.goose --check`.
- Engine: Node v22.23.4, V8 12.4.254.21-node.57, through `scripts/run_wasm.mjs`. `toolchain.json` pins Node 24.22.1; that one was not installed here. Wasmtime was not run: its hosts do not supply the `os` imports yet.
- Machine: 4 cores, 16 GiB, Linux, gcc 13.3.0. Three runs each, wall time, all listed in [measurements.json](runs/measurements.json).

## Results

| | |
| --- | --- |
| the compiler emitted as Wasm | 30,763,563 bytes (30.4 MB of code, 0.3 MB of data), [23 imports](runs/module-imports.txt), in 10.2 to 11.9 s |
| the module, run on the ten examples for both targets | all 20 outputs byte for byte the native compiler's; a type error is reported with the same text and exit status |
| `squares` to Wasm: module / native compiler | 5.1 to 5.6 s / under 0.01 s |
| `squares` to C | 8.7 to 12.1 s / 0.01 s |
| `tour` to Wasm | 9.2 to 9.5 s / 0.01 s |
| `tour` to C | 11.7 to 14.1 s / 0.01 to 0.03 s |
| the module checking the compiler's own source | stops after 1.0 s: `data region exhausted (line 564)`, the push in `new_node` |

## Why it cannot check itself

The direct target lays its growable arrays out in equal regions of one linear memory. The compiler has 116 of them, so with all of wasm32's 65,535 pages each region is 35.0 MiB. A native self-compile makes 650,487 syntax nodes of 168 bytes, 109 MB in one array, beside 490,404 tokens and a 43.7 MB output; its peak RSS is 573 MiB. The total would fit in 4 GiB. The even split does not, and an array cannot be moved when it outgrows its region, because references into it stay valid.

64-bit memory is the way out that was chosen. What is known about it here:

- This Node takes a 64-bit memory behind `--experimental-wasm-memory64` (V8 13.6, the pinned one, has it on) and refuses a maximum above 262,144 pages: 16 GiB. Split evenly over 117 that is 137 MiB a region, which the self-compile's largest table fits with little to spare. Wasmtime has no such cap.
- The backend holds a reference as an i32, a slice as one i64 of a 32-bit pointer and a 32-bit count, and an array's control as u32 words; `selfhost/codegen.goose` has 293 load and store sites and does its address arithmetic in i32. Addresses of 64 bits change all three representations.

## Why it is slow

About a thousand times the native compiler on these small inputs, and nearly all of it is the engine, not the program. A CPU profile of `squares --check` (3.9 s) puts the time in the large recursive functions (`life_eval`, `check_call`, `check_function`), with 2.9 s of it system time; with `--no-liftoff` the system time is 0.65 s and the run 6.1 s. V8 compiles each function when it is first called. The backend gives every temporary a local of its own, so those functions have thousands, the baseline compiler gives each a stack slot, and each deep call touches fresh stack pages: the same reason the default stack overflowed on seven of the ten examples before the host ran the module on a worker with a 256 MiB stack. Memory is not it: 382 MiB resident.

Not tried: reusing locals in the backend, and an ahead-of-time engine (Wasmtime's `.cwasm`), which pays the compilation once.

## What changed to get here

The backend refused `selfhost/main.goose` with 12 errors of three kinds, and a thirteenth behind them:

| refusal | now |
| --- | --- |
| 11 externs of `stdlib/os.goose` and `std.goose` with a slice or an output-array parameter ("public exports accept numeric and bool values only") | an import; a slice is passed as the i64 it is held as, a reference as its i32 address |
| the driver's `extern "libc.so.6" { fn driver_system ... = "system" }` | an import under `env` like any other; the host's `system` returns -1 |
| `hardware_threads()` | 1 |

A host that appends to a growable array (what `os.read_file`, `arg` and `env` ask of it) needs to move the array's region cursor with the bytes. The module exports the three words that find it; `docs/TARGET.md` has the layout. The first attempt wrote at the control's base plus length and moved only the length: the module's next append went over the host's bytes, since it writes at the cursor.

## Not done

- The module checking and compiling the compiler: 64-bit memory first.
- A Wasmtime host for these imports (`scripts/run_wasmtime.py`, `host/wasmtime.cpp`).
- The speed of the module.
- `docs/TARGET.md` still describes a `goose.regions` custom section that this compiler does not emit.

## Tools

`tools/imports.py module.wasm` lists a module's imports with their signatures and its memory limits.
