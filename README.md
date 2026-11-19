# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,693 of 10,797 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**The compiler rebuilding itself.** Across 12 paired rounds, the bundled 32-bit compiler rebuilt its own sources in a median **3.99 s in cached Wasmtime** and **2.96 s native**, with a median same-round ratio of **1.43× native time**. On the frozen `34ddff8` project, removing unused array-header forwarding cut cached Wasmtime time by **4.0%** and retired instructions by **5.0%**, bringing the paired Wasmtime/native ratio from **1.54× to 1.48×**. [Paired rebuilds](bench/results/2026-11-19/bundled-publications/README.md)

![Native and Wasmtime process time to rebuild the frozen and current compiler](bench/results/2026-11-19/bundled-publications/rebuild.svg)

**Cold and cached self-compilation.** The bundled memory32 compiler took **3.62 s** cold with eight cores and **2.77 s** cached on one core, versus **1.87 s** native. With an empty cache, the default memory64 compiler took **13.38 s** on one core and **6.19 s** on eight. Each figure is the median of three fresh processes. [Launch and edit times](bench/results/2026-11-19/bundled-publications/README.md#cold-and-cached-self-compilation) · [Gdev status](bench/results/2026-11-18/compiler-request-latency/README.md#compiling-gdev)

![Seconds to rebuild the compiler in cold, cached and native processes](bench/results/2026-11-19/bundled-publications/launch.svg)

**Compiler speed.** Across eleven programs, compiler `7ff11b7` used 2.1% less CPU time than `fc34386` to emit Wasm and 0.7% less to emit C. These are geometric means of medians over 31 measurements per cell. The chart shows wall time. In the earlier snapshot 59 comparison, Wasm emission took 0.58× the C++ compiler’s time and C emission took 0.53×. [Measurements](bench/results/2026-11-19/bundled-publications/catalog-summary.json) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**The compiler as Wasm.** Using a pinned Goose emitter, building compiler `7ff11b7` on the shared host took 2.32 s for direct Wasm and 29.48 s through C and Clang. Across three runs on those same sources, the resulting compiler took 2.25 s native, 7.07 s in Wasmtime and 8.91 s in V8 to check itself. Emitting its Wasm module took 3.65 s, 14.76 s and 13.58 s respectively. C builds used CPUs 0, 2, 4 and 6. Wasm builds and execution used CPU 3. Both Wasm engines used prepared, default memory64 modules and timed execution after instantiation. [Measurements](bench/results/2026-11-19/bundled-publications/selfhost.json)

![Compiler self-hosting build and execution times](bench/charts/compiler-selfhost-execution.svg)

**Example programs.** On the shared host pinned to CPU 1, cold builds for the ten examples took 88.0–114.6 ms for direct Wasm and 0.451–3.171 s through C, including compilation and linking. Sorting took 171 ms with minimal Wasmtime AOT and 126 ms native, including process launch and exit. [Builds](bench/results/2026-11-19/bundled-publications/examples.json.gz) · [Process times](bench/results/2026-11-19/bundled-publications/host.json.gz)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** On the shared host pinned to CPU 1, a resident run on the official input took a median 4.66 s native, 4.98 s in Wasmtime and 4.71 s in V8. GCC C and upstream Goose native controls took 4.30 s and 4.19 s. The seven-sample runtime excludes compilation, startup and instantiation. [Measurements](bench/results/2026-11-19/bundled-publications/langbench-hot.json.gz)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

<details><summary>Earlier measurements</summary>

| Question | Measurements |
| --- | --- |
| What did the checker save by tracking reads on demand? | [Read tracking and paired compiler rebuilds](bench/results/2026-11-19/construct-read-demand/README.md) |
| What did skipping temporary expression records save? | [Expression checking, rebuilds and grouping experiments](bench/results/2026-11-19/expression-lifetimes/README.md) |
| What did skipping repeated array effects save? | [Rebuilds, array effects and validation controls](bench/results/2026-11-19/lifetime-array-effects/README.md) |
| What did tracking changed reads save? | [Lifetime reads and memory cost](bench/results/2026-11-19/lifetime-read-replay/README.md) |
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
