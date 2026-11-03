# Wasmtime host comparison

The native C++ host uses the full static Wasmtime SDK; Python uses its own bindings. Both are version 50.0.1, with different library bytes. The host, callbacks and I/O differ, so timing differences are not Python startup alone. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Direct Wasm process times](charts/wasmtime-host-runtime.svg)

![C-to-Wasm process times](charts/wasmtime-host-c-wasm.svg)

![Precompiled artifact preparation](charts/wasmtime-host-preparation.svg)

The November 3 UTC run used the shared AMD Ryzen 7 3800X host and compiler `f76ea0f4bfa57949f5b04d42884f8316546a7eb50720b31e564afafcad9a0af8`. The example build artifacts were reused; native C was freshly executed in the same runtime blocks. Native-host ordinary cells use `--no-cache`; each runtime cell has one warmup and 15 fresh-process samples with checked output: 1,440 observations. Five separate preparations per artifact/configuration provide 200 observations. Precompiled timings exclude preparation.

| Example | Python host | Native host | Precompiled | Native C |
| --- | ---: | ---: | ---: | ---: |
| Functions | 109.391 ms | 19.368 ms | 1.379 ms | 1.062 ms |
| Sorting | 101.020 ms | 39.147 ms | 15.515 ms | 45.638 ms |
| Sudoku | 77.050 ms | 9.064 ms | 4.186 ms | 4.043 ms |
| Life | 91.160 ms | 14.255 ms | 2.419 ms | 18.284 ms |

The compiler and host qualification passed 9,573 differential executions and 11,484 host replay executions. The [campaign evidence](results/2026-11-03/strided-stores/README.md) records identities, samples, preparation and limitations. The earlier [host cohort](results/2026-11-02/resource-free-calls/README.md) used compiler `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689` and a different host build.

## Runtime lifecycle

![Runtime lifecycle by mode](charts/runtime-lifecycle.svg)

The lifecycle cohort measures uncached compilation, an empty SDK cache, a populated SDK cache and precompiled artifacts in fresh processes; a resident session is measured separately. The resident session excludes process startup but creates fresh guest state, store and instance on every request. The empty-cache launch includes cache population; precompiled execution excludes artifact preparation.

For Functions, median milliseconds were 29.435 uncached, 31.194 cache miss, 2.689 cache hit, 1.815 precompiled, 1.179 native C and 0.334 resident. For Life, they were 17.937, 21.888, 4.232, 3.558, 34.741 and 2.011 respectively. These are separate from the table above. Sorting native C was 45.638 ms in the host cohort and 60.715 ms in the lifecycle cohort; these unpaired results show cohort variation.

## Reproduce

Install the [toolchain and optional native host](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, then run:

```sh
python bench/examples.py --output-dir build/example-benchmarks
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/wasmtime_host_charts.py build/wasmtime-host/bench/report.json --output-dir bench/charts
python bench/runtime_lifecycle.py --example-report build/example-benchmarks/report.json --output-dir build/runtime-lifecycle
python bench/runtime_lifecycle_charts.py build/runtime-lifecycle/report.json --output build/runtime-lifecycle.svg
```

Chart rendering requires Matplotlib. The lifecycle chart command requires a fresh output path and will not overwrite an existing file. The host benchmark's default output path can be changed with `--output-dir`; use its generated report path for chart rendering. See the [dated evidence](results/2026-11-03/strided-stores/README.md) for retained raw data and qualification.

To regenerate the qualification baseline and replay from a fresh checkout:

```sh
python bench/qualify_compiler.py --jobs 6 --output-dir build/differential-sharded
python bench/qualify_wasmtime_host.py --baseline-dir build/differential-sharded --output-dir build/wasmtime-host-qualification
python tests/test_native_wasmtime.py
```
