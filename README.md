# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,693 of 10,797 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**The compiler rebuilding itself.** The bundled 32-bit compiler rebuilt its own sources in **3.48 s** in Wasmtime and **2.21 s** native, or **1.58× native time** across seven fresh-process pairs. On the same frozen compiler project, Wasmtime took **3.65 s before and 3.65 s after**, and native took **2.33 s before and 2.28 s after**. Across 22 alternating pairs the median within-pair change in Wasmtime time was +0.1%. Tracking changed lifetime reads saved 0.73 billion Wasmtime instructions per rebuild. [Paired measurements and memory cost](bench/results/2026-11-19/lifetime-read-replay/README.md)

![Native and Wasmtime process time to rebuild the frozen and current compiler](bench/results/2026-11-19/lifetime-read-replay/rebuild.svg)

**Cold and cached self-compilation.** With an empty Wasmtime cache, the default memory64 compiler took **19.75 s** on one core and **12.72 s** with eight cores for preparation. The bundled fixed memory32 compiler took **12.06 s** uncached and **8.54 s** cached, versus **5.94 s** native. These three-run medians overlapped other benchmarks on the shared host. [Edited builds and phase times](bench/results/2026-11-19/lifetime-read-replay/README.md#cold-and-cached-self-compilation) · [Gdev status](bench/results/2026-11-18/compiler-request-latency/README.md#compiling-gdev)

![Seconds to rebuild the compiler in cold, cached and native processes](bench/results/2026-11-19/lifetime-read-replay/launch.svg)

**Compiler speed.** Across eleven programs, compiler `06c84ac` used 2.3% less CPU time than `34ddff8` to emit Wasm and 2.1% less to emit C. These are geometric means of medians over 31 measurements per cell. The chart shows wall time. In the earlier snapshot 59 comparison, Wasm emission took 0.58× the C++ compiler’s time and C emission took 0.53×. [Measurements](bench/results/2026-11-19/lifetime-array-effects/catalog-summary.json) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**The compiler as Wasm.** Building compiler `06c84ac` on its own sources on the shared host took 2.58 s for direct Wasm and 57.58 s through C and Clang. Across three runs, self-check took 1.83 s native, 4.94 s in Wasmtime and 5.35 s in V8. Emitting the compiler took 2.55 s, 6.74 s and 7.23 s respectively. C builds used CPUs 0, 2, 4 and 6. Wasm builds and execution used CPU 3. Both Wasm engines used prepared, default memory64 modules and timed execution after instantiation. [Measurements](bench/results/2026-11-19/lifetime-array-effects/selfhost.json)

![Compiler self-hosting build and execution times](bench/charts/compiler-selfhost-execution.svg)

**Example programs.** On the shared host pinned to CPU 1, cold builds for the ten examples took 76.2–94.3 ms for direct Wasm and 0.347–2.508 s through C, including compilation and linking. Sorting took 352 ms with minimal Wasmtime AOT and 260 ms native, including process launch and exit. [Builds](bench/results/2026-11-19/lifetime-array-effects/examples.json.gz) · [Process times](bench/results/2026-11-19/lifetime-array-effects/host.json.gz)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** On the shared host pinned to CPU 1, a resident run on the official input took a median 2.58 s native, 2.82 s in Wasmtime and 2.74 s in V8. GCC C and upstream Goose native controls took 2.57 s and 2.72 s. The seven-sample runtime excludes compilation, startup and instantiation. [Measurements](bench/results/2026-11-19/lifetime-array-effects/langbench-hot.json.gz)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

<details><summary>Earlier measurements</summary>

| Question | Measurements |
| --- | --- |
| What improved string-heavy builds? | [8,192 literals and full compiler rebuilds](bench/results/2026-11-19/compiler-passes/README.md) |
| How much memory does a 32-bit compiler need? | [Fixed layouts and Blot2 capacity](bench/results/2026-11-18/compiler-layout-trials/README.md) · [Growing regions during compilation](bench/results/2026-11-18/compiler-region-recovery/README.md) |
| What sped up large project checks? | [Lifetime analysis](bench/results/2026-11-17/lifetime-compact-reads/README.md) · [Compiler iteration](bench/results/2026-11-17/compiler-iteration/README.md) · [Self-check pairs](bench/results/2026-11-17/compiler-and-row-performance/README.md) · [Blot2](bench/results/2026-11-17/blot2-captured-reads/README.md) |
| How much time do native builds and bootstrap take? | [Parallel C units](bench/results/2026-11-14/native-units/README.md) · [Changed-source bootstrap](bench/results/2026-11-17/local-bootstrap/README.md) |
| Which runtime and tooling costs improved? | [Native row scans](bench/results/2026-11-17/native-row-scans/README.md) · [Wasmtime preparation](bench/results/2026-11-18/compiler-iteration-tools/README.md) · [Wasm local allocation](bench/results/2026-11-17/wasm-slot-prefix/README.md) · [Varint traversal](bench/results/2026-11-17/varint-foreach/README.md) |

</details>

## How it was built

The frontend, optimizer and backends are written in Goose. A C++ reference guided the initial port. Frozen source and output contracts now check behavior. A checked-in C seed bootstraps the compiler, and `--verify` compares consecutive generated C outputs. [Compiler and bootstrap](selfhost/README.md) · [Contracts](tests/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md)

With Python 3, a C compiler and Node installed, build and run the first example.

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```
