# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,697 of 10,801 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**Small program builds.** Across eleven programs, `9a6040a` used **4.15% fewer instructions to check**, **2.66% fewer to emit Wasm** and **2.32% fewer to emit C** than `092d3d3`. These averages summarize 30 paired rounds per program on CPU 5, with similar savings on CPU 6. CPU and elapsed time intervals on both CPUs included no change. [Small build measurements](bench/results/2026-11-20/small-build-frontend/README.md#small-program-builds)

![Instructions saved across eleven small programs](bench/results/2026-11-20/small-build-frontend/small-builds.svg)

**The compiler rebuilding itself.** On its own sources, `9a6040a` took **2.03 s in cached Wasmtime** and **1.55 s native**, a 1.32× median within-pair ratio over 10 pairs. Against `092d3d3` on frozen sources, Wasmtime used **0.21% fewer instructions** and native used **0.41% fewer**. Elapsed-time intervals included no change for either engine across 12 pairs. An independent Wasmtime repeat favored the candidate in 8 of 12 pairs. [Full rebuild measurements](bench/results/2026-11-20/small-build-frontend/README.md#rebuilding-the-compiler)

![Time saved in twelve paired Wasmtime rebuilds and seconds to rebuild the current compiler](bench/results/2026-11-20/small-build-frontend/paired-rebuild.svg)

**Cold and cached self-compilation.** The bundled 32-bit compiler took **2.79 s cold** with eight compilation threads and **2.45 s cached** on one core. Native took **1.54 s**. These are medians of three fresh processes on a shared host. [Measurement details](bench/results/2026-11-20/small-build-frontend/README.md#cold-and-cached-self-compilation)

![Seconds to rebuild the compiler in cold, cached and native processes](bench/results/2026-11-20/small-build-frontend/launch.svg)

**Compiler speed.** In a separate CPU 2 run across eleven programs, `9a6040a` used 1.28% less CPU time to emit Wasm (95% interval -2.42% to -0.17%) and 2.61% less to emit C (-3.65% to -0.92%) than `092d3d3`. The Wasm elapsed-time interval included no change, while C emission took less elapsed time. The chart shows 31 builds per workload and compiler. In the earlier snapshot 59 comparison, direct Wasm emission took 0.58× the C++ compiler’s time and C emission took 0.53×. [Catalog measurements](bench/results/2026-11-20/small-build-frontend/catalog-summary.json) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**The compiler as Wasm.** Building `9a6040a` with a pinned Goose emitter took 3.14 s for direct Wasm and 49.35 s through C and Clang (native range 44.38–50.27 s on the shared host). The resulting compiler checked itself in 1.47 s native, 3.50 s in Wasmtime and 4.37 s in V8. Wasm engine times exclude instantiation and use portable memory64. [Three builds and three execution rounds](bench/results/2026-11-20/small-build-frontend/selfhost.json)

![Compiler self-hosting build and execution times](bench/charts/compiler-selfhost-execution.svg)

**Example programs.** On CPU 2, cold builds for ten examples took 81.9–102.1 ms for direct Wasm and 0.381–2.837 s through C, including compilation and linking. Sorting took 161 ms in minimal precompiled Wasmtime and 124 ms native, including process launch and exit. [Builds](bench/results/2026-11-20/small-build-frontend/examples.json.gz) · [Process times](bench/results/2026-11-20/small-build-frontend/host.json.gz)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** On the official input, resident execution took 2.76 s native, 3.00 s in Wasmtime and 2.91 s in V8. GCC C took 2.74 s and upstream native Goose took 2.82 s. Seven samples per engine on CPU 2 exclude compilation, startup and instantiation. [Measurements](bench/results/2026-11-20/small-build-frontend/langbench-hot.json.gz)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

<details><summary>Earlier measurements</summary>

| Question | Measurements |
| --- | --- |
| What did optimizing node traversal save in the previous study? | [Node traversal study](bench/results/2026-11-20/optimizer-node-traversal/README.md) |
| What did recording allocator events save in the previous study? | [Event and allocator study](bench/results/2026-11-20/wasm-local-events/README.md) |
| Can the Wasm allocator avoid decoding instructions the compiler just wrote? | [Recorded events on 1,539 function bodies](bench/results/2026-11-20/holder-lookups/README.md#recording-the-instructions-the-allocator-needs) |
| How far has full compiler rebuild time come on the original project? | [Cumulative full rebuilds](bench/results/2026-11-20/small-build-frontend/campaign.svg) · [Experiments and remaining work](bench/results/2026-11-19/compiler-opportunities/README.md#remaining-work) · [Function lookup scaling](bench/results/2026-11-19/function-lookup/README.md#programs-with-many-functions) |
| Which compiler phases account for the Wasmtime gap? | [Phase counts and the same-Wasm engine comparison](bench/results/2026-11-19/lifetime-evaluator-frames/README.md#where-the-gap-remains) |
| What changed when Wasm copied small records with SIMD? | [Fixed record copies and cold launches](bench/results/2026-11-19/fixed-record-copies/README.md) |
| Why did skipping more calls add a full pass? | [Caller trace and binding changes](bench/results/2026-11-19/lifetime-callers/README.md#why-skipping-bodies-added-a-pass) |
| Which lifetime changes removed the fifth discovery pass? | [Store delivery, tuple reuse and paired rebuilds](bench/results/2026-11-19/lifetime-store-delivery/README.md) |
| What did removing array-header forwarding save? | [Bundled host rebuilds and launch times](bench/results/2026-11-19/bundled-publications/README.md) |
| What did the checker save by tracking reads on demand? | [Read tracking and paired compiler rebuilds](bench/results/2026-11-19/construct-read-demand/README.md) |
| What did skipping temporary expression records save? | [Expression checking, rebuilds and grouping experiments](bench/results/2026-11-19/expression-lifetimes/README.md) |
| What did skipping repeated array effects save? | [Rebuilds, array effects and validation controls](bench/results/2026-11-19/lifetime-array-effects/README.md) |
| Where can lifetime checking improve next? | [Five discovery passes, two missed errors and three experiments](bench/results/2026-11-19/lifetime-discovery/README.md) |
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
