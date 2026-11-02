# Example benchmarks

Ten [example programs](../examples/README.md) compare direct Wasm, C-to-Wasm and native C at O2. These are fresh-process timings, distinct from the warmed computational regions in the [LangArena benchmarks](langarena/README.md).

![Example cold build times](charts/examples-compilation.svg)

![Example process times with the native Wasmtime host and native C](charts/examples-runtime.svg)

The runtime chart shows ordinary native-host launches, which compile Wasm on launch, and precompiled launches, which exclude preparation. Native C was freshly measured in the same runtime blocks and appears in both panels. For Sorting, ordinary direct Wasm took 89.252 ms, C-to-Wasm 161.367 ms and native C 46.512 ms. Precompiled direct Wasm took 68.899 ms. For Life, precompiled direct Wasm took 12.390 ms versus 18.819 ms native; precompiled C-to-Wasm took 6.803 ms, excluding its 17.384 ms preparation median. [Preparation costs and host qualification](wasmtime-host.md) give the full accounting.

[Current results and raw samples](results/2026-11-02/resource-free-calls/README.md) · [Earlier example cohort](results/2026-11-02/compact-examples/README.md)

The cold-build chart comes from a separately collected cohort using the same compiler: direct builds took 60.842–85.435 ms versus 521.026–926.835 ms for C-to-Wasm. Its [V8 and Python-host runtime chart](charts/examples-python-runtime.svg) is a separate control from the native-host runtime cohort.

## Method

The build cohort has five complete `--no-cache` Python-driver builds per backend/example cell. The native-host cohort reuses its qualified artifact bytes and has one untimed fresh-process warmup and 15 fresh-process samples per runtime configuration, with checked output. Values are median milliseconds; the reports also include median absolute deviation (MAD).

The headline runtime measures launch to exit, including startup, Wasm instantiation, initialization, computation, output delivery and teardown. Ordinary launches also include Wasm compilation; precompiled launches exclude preparation. The current build cohort's separate entry probes use the Python host and a different timing boundary.

Inputs remain constant and ordinary constant folding is allowed. Direct Wasm uses memory32; C-to-Wasm uses memory64. OS page and installed Emscripten library caches remain warm. The runs use a shared AMD Ryzen 7 3800X desktop, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, compiler SHA-256 `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689`, Wasmtime 50.0.1, Emscripten 6.0.13 and GCC 16.2.1. The V8 control uses Node 24.22.1 / V8 13.6.233.17-node.58.

## Native gap

Separate paired instrumented Sudoku probes measured direct Wasm entry at 3.757 → 2.992 ms on Wasmtime. Entry includes initialization and callbacks, so it is not a pure kernel timing. [Earlier execution-boundary probes](results/2026-11-02/execution-boundaries/README.md) used a different compiler and cohort; their native timings cannot be paired with these results.

The paths use the same algorithm but differ in lowering, memory layout and GCC versus Cranelift machine code. Both retain language bounds checks unless frontend analysis proves them redundant. The measurements do not isolate a single cause. The [audit evidence](results/2026-11-02/resource-free-calls/README.md) includes the probes and their limitations.

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
