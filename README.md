# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,689 of 10,793 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**Compiler speed.** On 2026-11-17, the current compiler took 1.000× its parent's CPU time to emit Wasm and 0.992× to emit C. These geometric means of medians across eleven programs, with 31 measurements per cell, are within noise. C emission excludes C compilation and linking. In a separate 2026-11-11 campaign, snapshot 59 took 0.58× the earlier C++ compiler's time for Wasm and 0.53× for C. [Current measurements](bench/results/2026-11-17/compiler-and-row-performance/README.md) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**Large programs.** In a separate earlier run on 2026-11-17 the compiler's self-check went from 11.5 s to 3.9 s of CPU time and from 503 to 306 MiB peak memory in an interleaved run. A later run of five pairs compiling frozen compiler sources reduced CPU time from 11.55 s to 8.64 s for Wasm and from 7.64 s to 6.69 s for C, with identical artifacts. Self-check was flat under that run's shared load. Seven later pairs of development builds reduced self-check CPU time from 3.131 s to 3.054 s. A separate change reduced Blot2's first pass from 298–308 s to 122–124 s of CPU time. That pass ends with 38 lifetime diagnostics. [Self-check](bench/results/2026-11-17/lifetime-compact-reads/README.md) · [Latest pairs](bench/results/2026-11-17/compiler-and-row-performance/README.md) · [Compiler iteration](bench/results/2026-11-17/compiler-iteration/README.md) · [Blot2](bench/results/2026-11-17/blot2-captured-reads/README.md)

**Native builds.** Sixteen parallel C units built the compiler in 16.1 s instead of 97.9 s with Clang `-O2` on eight cores. The resulting compiler executes 2.4% more instructions. Release bootstraps use one unit. [Method and results](bench/results/2026-11-14/native-units/README.md)

**Bootstrap iteration.** A warm verified bootstrap of the frozen compiler sources fell from 52.05 s to 5.80 s wall time across three paired repetitions, with native executables already cached. The generated C and compiler executable were identical. The build used Clang 23.1.5 with `-O2` and one C unit. With native executables cached, the opt-in `--reuse-toolchain` path reduced a changed-source build from 36.19 s to 8.42 s across three pairs while producing the same C and result and verifying the live fixed point. [Measurements](bench/results/2026-11-17/compiler-iteration/README.md) · [Changed-source builds](bench/results/2026-11-17/local-bootstrap/README.md)

**The compiler as Wasm.** In a separately measured run it checked itself in 13–14 s and compiled itself in 22–23 s under Wasmtime on 2026-11-17. Under V8 in Node 22 the 64-bit module took 15 s and 28 s respectively. The 32-bit module took 13–14 s and 25 s. Outputs match the native compiler byte for byte. [Measurements](bench/results/2026-11-17/lifetime-compact-reads/README.md)

**Example programs.** On a shared host, median cold builds for ten examples took 96.9–148.6 ms for direct Wasm and 0.441–3.071 s for native executables, including C compilation and linking. Full process times include launch and exit. Sorting took 273 ms with minimal Wasmtime AOT and 154 ms native. [Method and results](bench/results/2026-11-17/compiler-and-row-performance/README.md)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** A separate resident run on the official input took 2.94 s native, 3.33 s in Wasmtime and 3.02 s in V8. The GCC C and upstream Goose native controls took 2.92 s and 3.02 s. The current build produces the same artifacts. Hot runtime excludes compilation, startup and instantiation. [Method and results](bench/results/2026-11-17/compiler-and-row-performance/README.md)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

**Native rows.** Stable scans and counted literal pushes reduced append time from 238.683 ms to 0.363 ms and traversal from 600.395 ms to 0.076 ms for 8,008 rows across seven pairs. [Measurements](bench/results/2026-11-17/native-row-scans/README.md)

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
