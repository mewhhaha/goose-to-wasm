# Example benchmarks

Ten [example programs](../examples/README.md) compare direct Wasm, C-to-Wasm and native C at O2. These are fresh-process timings, distinct from the warmed computational regions in the [LangArena benchmarks](langarena/README.md).

![Example cold build times](charts/examples-compilation.svg)

![Example process times with the native Wasmtime host and native C](charts/examples-runtime.svg)

The runtime chart includes uncached native-host launches and full and minimal precompiled launches; preparation is excluded from the latter. In the 15-sample cohort, Functions took 18.321 ms cold, 1.853 ms full AOT and 1.384 ms minimal AOT, versus 0.947 ms native C. [Preparation costs and host qualification](wasmtime-host.md) give the full accounting.

[Results and raw samples](results/2026-11-04/minimal-aot/README.md)

The cold-build cohort measured direct builds at 61.2–100.9 ms and C-to-Wasm at 487.0–937.3 ms. Its [V8 and Python-host chart](charts/examples-python-runtime.svg) is a separate control.

## Method

The build cohort has five complete `--no-cache` Python-driver builds per backend/example cell. The native-host cohort reuses qualified artifact bytes and has one untimed warmup and 15 fresh-process samples per runtime configuration, with checked output. Values are median milliseconds; reports include median absolute deviation (MAD).

The headline runtime measures launch to exit, including startup, Wasm instantiation, initialization, computation, output delivery and teardown. Cold launches disable the SDK cache and include Wasm compilation; precompiled launches exclude preparation. Inputs remain constant and ordinary constant folding is allowed. Direct Wasm uses memory32; C-to-Wasm uses memory64. The runs use a shared AMD Ryzen 7 3800X, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, compiler SHA-256 `8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6`, Wasmtime 50.0.1, Emscripten 6.0.13 and GCC 16.2.1. The V8 control uses Node 24.22.1 / V8 13.6.233.17-node.58.

A corrected pidfd-based wait removes an approximately 1 ms Python timed-wait polling artifact from the earlier host cohort. Historical and corrected process timings are not a matched before/after comparison. [Evidence and limitations](results/2026-11-04/minimal-aot/README.md).

## Native gap

Earlier paired instrumented Sudoku probes measured direct Wasm entry at 3.757 → 2.992 ms on Wasmtime with compiler `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689`. Entry includes initialization and callbacks, so it is not a pure kernel timing. [Earlier execution-boundary probes](results/2026-11-02/execution-boundaries/README.md) used a different compiler and cohort; their native timings cannot be paired with these results.

The paths use the same algorithm but differ in lowering, memory layout and GCC versus Cranelift machine code. Both retain language bounds checks unless frontend analysis proves them redundant. The measurements do not isolate a single cause. The [audit evidence](results/2026-11-02/resource-free-calls/README.md) includes the probes and their limitations.

## Reproduce

With the [toolchain and native host installed](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, run from the repository root:

```sh
python bench/examples.py --machine-label 'your machine' --output-dir build/example-benchmarks
python bench/example_charts.py build/example-benchmarks/report.json
cp bench/charts/examples-runtime.svg bench/charts/examples-python-runtime.svg
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json --aot-host build/bin/goose-wasmtime-aot
python bench/example_runtime_charts.py build/wasmtime-host/bench/report.json
```

Chart generation requires Matplotlib. For a correctness-only smoke run:

```sh
python bench/examples.py squares tour --smoke --compile-samples 1 --samples 2 --warmups 0
```
