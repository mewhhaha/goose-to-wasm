# Wasmtime host comparison

The native C++ host uses the full static Wasmtime SDK; Python uses its own bindings. Both are version 50.0.1, with different library bytes. The host, callbacks and I/O differ, so timing differences are not Python startup alone. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Direct Wasm process times](charts/wasmtime-host-runtime.svg)

![C-to-Wasm process times](charts/wasmtime-host-c-wasm.svg)

![Precompiled artifact preparation](charts/wasmtime-host-preparation.svg)

The November 3 UTC run used the shared AMD Ryzen 7 3800X host and compiler `1b1ec504894d387ae0bbed287d2d3214e250e6dc9bbff2ffd2893a69c06a8874`. The example build artifacts were reused; native C was freshly executed in the same runtime blocks. Native-host ordinary cells use `--no-cache`; each runtime cell has one warmup and 15 fresh-process samples with checked output: 1,440 observations. Five separate preparations per artifact/configuration provide 200 observations. Precompiled timings exclude preparation.

| Example | Python host | Native host | Precompiled | Native C |
| --- | ---: | ---: | ---: | ---: |
| Functions | 102.369 ms | 18.640 ms | 1.746 ms | 1.000 ms |
| Sorting | 102.603 ms | 31.646 ms | 16.038 ms | 46.024 ms |
| Sudoku | 79.879 ms | 9.158 ms | 4.304 ms | 4.511 ms |
| Life | 91.072 ms | 15.555 ms | 2.953 ms | 18.189 ms |

The compiler and host qualification passed 9,573 differential executions and 11,484 host replay executions. The [campaign evidence](results/2026-11-03/runtime-stencil/README.md) records identities, samples, preparation and limitations. The earlier [host cohort](results/2026-11-02/resource-free-calls/README.md) used compiler `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689` and a different host build.

## Runtime lifecycle

![Runtime lifecycle by mode](charts/runtime-lifecycle.svg)

The lifecycle cohort measures uncached compilation, an empty SDK cache, a populated SDK cache and precompiled artifacts in fresh processes; a resident session is measured separately. The resident session excludes process startup but creates fresh guest state, store and instance on every request. The empty-cache launch includes cache population; precompiled execution excludes artifact preparation.

For Functions, median milliseconds were 30.370 uncached, 32.004 cache miss, 2.689 cache hit, 1.958 precompiled, 1.252 native C and 0.315 resident. For Life, they were 21.814, 24.028, 4.319, 3.677, 33.477 and 2.020 respectively. These are separate from the table above. Life native C was 18.189 ms in the host cohort; the unpinned normal-pool samples were bimodal near 18 and 35 ms, so the cohort difference matters.

## Reproduce

Install the [toolchain and optional native host](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, then run:

```sh
python bench/examples.py --output-dir build/example-benchmarks
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/wasmtime_host_charts.py build/wasmtime-host/bench/report.json --output-dir bench/charts
python bench/runtime_lifecycle.py --example-report build/example-benchmarks/report.json --output-dir build/runtime-lifecycle
python bench/runtime_lifecycle_charts.py build/runtime-lifecycle/report.json --output build/runtime-lifecycle.svg
```

Chart rendering requires Matplotlib. The lifecycle chart command requires a fresh output path and will not overwrite an existing file. The host benchmark's default output path can be changed with `--output-dir`; use its generated report path for chart rendering. See the [dated evidence](results/2026-11-03/runtime-stencil/README.md) for retained raw data and qualification.

To regenerate the qualification baseline and replay from a fresh checkout:

```sh
python bench/qualify_compiler.py --jobs 6 --output-dir build/differential-sharded
python bench/qualify_wasmtime_host.py --baseline-dir build/differential-sharded --output-dir build/wasmtime-host-qualification
python tests/test_native_wasmtime.py
```
