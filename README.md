# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose, producing WebAssembly directly or native executables through C. Conformance is partial: 92 of 8,545 contract rows remain open. The features of upstream Goose since those contracts were pinned are [tracked separately](docs/FEATURES.md).

## Benchmarks

**Compiler speed.** With the supplied Clang 23 profile, snapshot 59 took 0.58 of the previous C++ compiler's time to emit Wasm and 0.53 to emit C: 1.73× and 1.88× faster, and 1.80× across all 22 cells. It is 1.74× faster than snapshot 58 for Wasm and 1.76× for C. These are geometric means across eleven programs; Tour emitted as Wasm is the one cell still slower than C++. C emission excludes C compilation and linking. Library functions the program does not reach are no longer parsed or checked. [Method and results](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**Large programs.** On 2026-11-13, checking a 450-module, 120,000-line compiler took 0.37–0.43 of the previous build's CPU time (11 s instead of 30 s on a quiet machine), and the compiler took 0.56–0.66 to check itself. Both produced identical output. Type checking now uses indexed scope, effect and return-root lookups, and the lifetime analysis skips effects it has already recorded. [Method and results](bench/results/2026-11-13/large-program-checking/README.md) On 2026-11-14 the lifetime analysis stopped copying a set at every join and began sharing equal lists. Its state and all output are unchanged. The compiler checks itself in about the same time (0.98, inside the noise of a loaded machine) with 5% less memory. Given a `main`, the 450-module compiler's analysis now runs 31,000 call contexts, up from about 1,650, before it runs out of space. It still does not finish. [Method and results](bench/results/2026-11-14/lifetime-set-sharing/README.md)

**Native builds.** On 2026-11-14, the compiler's own 40.7 MB of generated C built in 16.1 s as 16 parallel C units instead of 97.9 s as one, with Clang `-O2` on 8 cores; the split-built compiler executes 2.4% more instructions, so release bootstraps stay one unit. Once the runtime object is cached, the ten examples' C compiles 4–37% faster with GCC. The published example campaign below uses `--no-cache`, whose builds are unchanged. [Method and results](bench/results/2026-11-14/native-units/README.md)

**Example programs.** These and the Mandelbrot measurements are from the snapshot 58 campaign ([results](bench/results/2026-11-08/compiler-throughput-58/README.md)). Across ten examples, median cold builds took 50–69 ms for direct Wasm and 253–1,924 ms for native executables. Native builds include C compilation and linking; process times include launch and exit. Wasmtime preparation is measured separately. Sorting took 177 ms with minimal AOT and 113 ms native.

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** On the official input, median computation took 2.40 s native, 2.57 s in Wasmtime and 2.50 s in V8. The native C and upstream Goose controls took 2.40 s and 2.39 s. Hot runtime measures guest computation with a resident Wasm module; compilation, startup and instantiation are outside the timer. Build times include C compilation and linking for native executables.

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

## Construction and contracts

The compiler implements its frontend, optimizer and backends in Goose. A checked-in C seed bootstraps it; `--verify` checks consecutive generated C outputs match. A C++ reference guided the initial port. Frozen source and output contracts now check behavior: snapshot 59 passes 7,955 of 8,055 rows, each matching snapshot 58. The 100 existing gaps remain. [Qualification](selfhost/results/2026-11-11/compiler-throughput-59/README.md) The current sources add root structs, `defer` and `const if`, and pass 8,296 of 8,390 rows, also when native C builds as parallel units. [Qualification](selfhost/results/2026-11-14/upstream-features/README.md) · [Since](selfhost/results/2026-11-14/named-constants/summary.json) With `slice_pool`'s span tree for native C and stdlib aborts that report the program's line, they pass 8,320 of 8,414. [Qualification](selfhost/results/2026-11-14/pool-externs-abort-sites/README.md) With root structs on direct Wasm, they pass 8,352 of 8,444. [Qualification](selfhost/results/2026-11-14/wasm-root-structs/README.md) Snapshot 62 freezes these sources with a retrained profile, and fixes native range loops, whose index counted from the range's first value instead of 0; 8,356 of 8,448 rows pass. [Snapshot 62](selfhost/results/2026-11-14/snapshot-62/README.md) Running about 700 programs from the earlier C++ compiler's tests through plain upstream found further disagreements. Eleven are fixed, among them an assignable variable-size enum, effectful defaults evaluated once on direct Wasm, native C that did not compile for `varint` grow arrays, and false lifetime and region rejections; 8,453 of 8,545 rows pass. [Differences](docs/FEATURES.md#differences-found-by-the-upstream-differential-run)

With Python 3, a native C compiler and Node:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
