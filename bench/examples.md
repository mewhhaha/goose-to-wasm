# Example benchmarks

Ten [example programs](../examples/README.md) compare direct Wasm, C-to-Wasm and native C at O2. These are fresh-process timings, distinct from the warmed computational regions in the [LangArena benchmarks](langarena/README.md).

![Example cold build times](charts/examples-compilation.svg)

![Example process times with the native Wasmtime host and native C](charts/examples-runtime.svg)

The runtime chart shows ordinary native-host launches, which compile Wasm on launch, and precompiled launches, which exclude preparation. Native C was freshly measured in the same runtime blocks and appears in both panels. For Sorting, ordinary direct Wasm took 159.334 ms, C-to-Wasm 154.693 ms and native C 46.074 ms. Precompiled direct Wasm took 118.099 ms. For Life, precompiled direct Wasm took 26.931 ms versus 18.572 ms native; precompiled C-to-Wasm took 6.754 ms, excluding its 17.666 ms preparation median. [Preparation costs and host qualification](wasmtime-host.md) give the full accounting.

[Native-host results and raw samples](results/2026-11-02/wasmtime-host/README.md) · [Earlier example cohort](results/2026-11-02/compact-examples/README.md)

The cold-build chart comes from the separately collected earlier cohort with the same compiler: direct builds took 61–109 ms versus 503–960 ms for C-to-Wasm. The earlier [V8 and Python-host runtime chart](charts/examples-python-runtime.svg) and [entry measurements](../docs/RUNTIME_PERFORMANCE.md#prefix-dispatch-and-startup) remain available as controls; their measurements are separate from the native-host cohort.

## Method

The earlier cohort has five complete `--no-cache` Python-driver builds per backend/example cell. The native-host cohort reuses its qualified artifact bytes and has one untimed fresh-process warmup and 15 fresh-process samples per runtime configuration, with checked output. Values are median milliseconds; the reports also include median absolute deviation (MAD).

The headline runtime measures launch to exit, including startup, Wasm instantiation, initialization, computation, output delivery and teardown. Ordinary launches also include Wasm compilation; precompiled launches exclude preparation. The earlier cohort's separate entry probes use a different timing boundary and host.

Inputs remain constant and ordinary constant folding is allowed. Direct Wasm uses memory32; C-to-Wasm uses memory64. OS page and installed Emscripten library caches remain warm. The runs use a shared AMD Ryzen 7 3800X desktop, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, compiler SHA-256 `3316710bb9d2b3100e94c2023000f0cb1b7517010ef04076314b4703fdcfcbba`, Wasmtime 50.0.1, Emscripten 6.0.13 and GCC 16.2.1. The earlier V8 control uses Node 24.22.1 / V8 13.6.233.17-node.58.

## Native gap

Separate instrumented probes help locate the gap, though their boundaries differ. For Sorting, ordinary direct Wasm spent 117.940 ms in `_start` (MAD 0.728 ms), versus 45.740 ms in native `main` (MAD 0.864 ms); Wasm setup took 37.012 ms. Precompiled setup took 0.396 ms. These seven-sample probes include initialization in both entry timings; Wasm entry excludes final stdout delivery, while native `main` includes unbuffered stdout. They are not pure kernel timings. For Squares, precompiled entry took 0.021 ms against 2.233 ms for the full process, so startup dominates that small example.

The paths use the same algorithm but differ in lowering, memory layout and GCC versus Cranelift machine code. Both retain language bounds checks unless frontend analysis proves them redundant. The measurements do not isolate a single cause. [Execution-boundary evidence](results/2026-11-02/execution-boundaries/README.md) includes the probes and their limitations.

## Reproduce

With the [toolchain and native host installed](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, run from the repository root:

```sh
python bench/examples.py --machine-label 'your machine' --output-dir build/example-benchmarks
python bench/example_charts.py build/example-benchmarks/report.json
cp bench/charts/examples-runtime.svg bench/charts/examples-python-runtime.svg
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/example_runtime_charts.py build/wasmtime-host/bench/report.json
```

Chart generation requires Matplotlib. For a correctness-only smoke run:

```sh
python bench/examples.py squares tour --smoke --compile-samples 1 --samples 2 --warmups 0
```
