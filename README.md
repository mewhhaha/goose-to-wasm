# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,693 of 10,797 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**The compiler rebuilding itself.** Our bundled 32-bit Wasm compiler takes **4.14 s** in Wasmtime versus **2.61 s** native on its own sources, or **1.59× native time** across seven rounds. On the same frozen project, Wasmtime improved from **5.64 s to 5.01 s** and native from **3.32 s to 3.12 s**. All eight paired rounds started fresh processes, reused only the compiled Wasmtime module, and emitted identical portable memory64 output. [Measurements](bench/results/2026-11-18/compiler-frame-cost/README.md)

![Seconds for native and Wasmtime to rebuild the frozen and current compiler projects](bench/results/2026-11-18/compiler-frame-cost/rebuild.svg)

**Cold and hot self-compilation.** On its own sources, the default memory64 compiler took **18.13 s** with an empty Wasmtime cache on one core, **9.52 s** with eight cores for engine preparation, and **7.54 s** with the compiler cached on disk. The bundled fixed-memory32 compiler took **5.95 s** uncached on eight cores and **4.66 s** cached on one core, versus **2.97 s** native. A one-line edit took **4.32 s** and **2.67 s** respectively. These are three-run medians from fresh processes. [Times and phase breakdown](bench/results/2026-11-18/compiler-frame-cost/README.md#cold-start-and-the-remaining-gap) · [Gdev status](bench/results/2026-11-18/compiler-request-latency/README.md#compiling-gdev)

![Seconds to rebuild the compiler with uncached, cached and native launches](bench/results/2026-11-18/compiler-frame-cost/launch.svg)

**Sizing memory32 from three examples.** An experimental layout cut frozen compiler check time from **5.19 to 3.81 s** and emission from **6.98 to 5.26 s** in the general Wasmtime host. It exhausted the token region parsing the 450-module Blot2 project. One 32-bit layout sized from both projects handled both. [Trials and capacity measurements](bench/results/2026-11-18/compiler-layout-trials/README.md)

![Compiler execution using default memory64 and two ways of sizing memory32](bench/results/2026-11-18/compiler-layout-trials/memory.svg)

**Growing memory32 as the compiler runs.** An experimental compiler parsed all 450 Blot2 modules in one pass in **1.69 s**, compared with **1.68 s** for a fixed layout sized from Blot2 itself. Across two benchmark runs, live growth cost **1.8–5.2%** when checking the compiler project and **0.6–0.7%** when emitting it. Every emission matched native output byte for byte. [Measurements and capacity limits](bench/results/2026-11-18/compiler-region-recovery/README.md)

![Wasmtime execution time with live region growth and fixed layouts for Blot2 parsing, compiler checking and compiler emission](bench/results/2026-11-18/compiler-region-recovery/live.svg)

**Compiler speed.** Across eleven programs, compiler `4a9d35e` used 0.964× the CPU time of `4e9b78e` to emit Wasm and 0.967× to emit C. These are geometric means of medians over 31 measurements per cell. The chart shows wall time. In the earlier snapshot 59 comparison, Wasm emission took 0.58× the C++ compiler’s time and C emission took 0.53×. [Measurements](bench/results/2026-11-18/compiler-frame-cost/catalog-summary.json) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**Large programs.** In a separate earlier run on 2026-11-17 the compiler's self-check went from 11.5 s to 3.9 s of CPU time and from 503 to 306 MiB peak memory in an interleaved run. A later run of five pairs compiling frozen compiler sources reduced CPU time from 11.55 s to 8.64 s for Wasm and from 7.64 s to 6.69 s for C, with identical artifacts. Self-check was flat under that run's shared load. Seven later pairs of development builds reduced self-check CPU time from 3.131 s to 3.054 s. A separate change reduced Blot2's first pass from 298–308 s to 122–124 s of CPU time. That pass ends with 38 lifetime diagnostics. [Self-check](bench/results/2026-11-17/lifetime-compact-reads/README.md) · [Compiler iteration](bench/results/2026-11-17/compiler-iteration/README.md) · [Latest self-check pairs](bench/results/2026-11-17/compiler-and-row-performance/README.md) · [Blot2](bench/results/2026-11-17/blot2-captured-reads/README.md)

**Native builds.** Sixteen parallel C units built the compiler in 16.1 s instead of 97.9 s with Clang `-O2` on eight cores. The resulting compiler executes 2.4% more instructions. Release bootstraps use one unit. [Method and results](bench/results/2026-11-14/native-units/README.md)

**Bootstrap iteration.** A warm verified bootstrap of the frozen compiler sources fell from 52.05 s to 5.80 s wall time across three paired repetitions, with native executables already cached. The generated C and compiler executable were identical. The build used Clang 23.1.5 with `-O2` and one C unit. With native executables cached, the opt-in `--reuse-toolchain` path reduced a changed-source build from 36.19 s to 8.42 s across three pairs while producing the same C and result and verifying the live fixed point. [Measurements](bench/results/2026-11-17/compiler-iteration/README.md) · [Changed-source builds](bench/results/2026-11-17/local-bootstrap/README.md)

**The compiler as Wasm.** Building compiler `4a9d35e` on its own sources on the shared host took 2.93 s for direct Wasm and 40.17 s through C and Clang. Across three runs, self-check took 2.71 s native, 7.57 s in Wasmtime and 7.64 s in V8. Emitting the compiler took 2.97 s, 7.59 s and 10.11 s respectively. Builds used CPUs 0, 2, 3, 4 and 6 for C and CPU 3 for Wasm; execution used CPU 3. Both Wasm engines used prepared, default memory64 modules and timed execution after instantiation. [Measurements](bench/results/2026-11-18/compiler-frame-cost/selfhost.json)

![Compiler self-hosting build and execution times](bench/charts/compiler-selfhost-execution.svg)

**Example programs.** On the shared host pinned to CPU 1, cold builds for the ten examples took 79.8–102.2 ms for direct Wasm and 0.370–2.596 s through C, including compilation and linking. Sorting took 189 ms with minimal Wasmtime AOT and 142 ms native, including process launch and exit. [Builds](bench/results/2026-11-18/compiler-frame-cost/examples.json) · [Process times](bench/results/2026-11-18/compiler-frame-cost/host.json)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** On the shared host pinned to CPU 1, a resident run on the official input took a median 2.99 s native, 3.20 s in Wasmtime and 3.10 s in V8. GCC C and upstream Goose native controls took 3.00 s and 3.00 s. The seven-sample runtime excludes compilation, startup and instantiation. [Measurements](bench/results/2026-11-18/compiler-frame-cost/langbench-hot.json)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

**Native rows.** Stable scans and counted literal pushes reduced append time from 238.683 ms to 0.363 ms and traversal from 600.395 ms to 0.076 ms for 8,008 rows across seven pairs. [Measurements](bench/results/2026-11-17/native-row-scans/README.md)

In separate tooling measurements, caching Wasmtime preparation cut 40.6 s to 141 ms, and the Rust host ran 4,777 memory64 contracts in 40 s versus 161 s under Python. [Tooling measurements](bench/results/2026-11-18/compiler-iteration-tools/README.md)

![Wasmtime compiler preparation and memory64 conformance time](bench/results/2026-11-18/compiler-iteration-tools/iteration.svg)

**Wasm local allocation.** Replaying optimized self-compilation bodies fell from 543 ms to 491 ms with identical local tables and instruction bytes. An overlapping-span stress case fell from 241 ms to 31 ms. [Measurements](bench/results/2026-11-17/wasm-slot-prefix/README.md)

**Varint traversal.** A checksum loop over 8,008 mixed-width values fell from 161.61 ms to 0.129 ms in resident Wasmtime with 32-bit memory. The compiler advances a bounded cursor for proven top-level loops on immutable incoming slices. [Method and results](bench/results/2026-11-17/varint-foreach/README.md)

## How it was built

The frontend, optimizer and backends are written in Goose. A C++ reference guided the initial port. Frozen source and output contracts now check behavior. A checked-in C seed bootstraps the compiler, and `--verify` compares consecutive generated C outputs. [Compiler and bootstrap](selfhost/README.md) · [Contracts](tests/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md)

With Python 3, a C compiler and Node installed, build and run the first example.

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```
