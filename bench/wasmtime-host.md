# Wasmtime host comparison

The native C++ host uses the full static Wasmtime SDK; Python uses its own bindings. Both are version 50.0.1, with different library bytes. The host, callbacks and I/O differ, so timing differences are not Python startup alone. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Direct Wasm process times](charts/wasmtime-host-runtime.svg)

![C-to-Wasm process times](charts/wasmtime-host-c-wasm.svg)

![Precompiled artifact preparation](charts/wasmtime-host-preparation.svg)

The November 3 UTC run used the shared AMD Ryzen 7 3800X host and compiler `353a3f1bd547330c8ecd32e9084ae92d616340f81f83a5cc30f2e657d577652e`. The example build artifacts were reused; native C was freshly executed in the same runtime blocks. Each runtime cell has one warmup and 15 fresh-process samples with checked output: 1,440 observations. Five separate preparations per artifact/configuration provide 200 observations. Precompiled timings exclude preparation.

| Example | Python host | Native host | Precompiled | Native C |
| --- | ---: | ---: | ---: | ---: |
| Functions | 101.245 ms | 18.464 ms | 1.523 ms | 1.223 ms |
| Sorting | 103.713 ms | 33.813 ms | 16.786 ms | 46.331 ms |
| Sudoku | 77.552 ms | 8.761 ms | 5.467 ms | 4.130 ms |
| Life | 88.517 ms | 16.180 ms | 6.516 ms | 19.702 ms |

The compiler and host qualification passed 9,573 differential executions and 11,484 host replay executions. The [campaign evidence](results/2026-11-03/functions-calls/README.md) records identities, samples, preparation and limitations. The earlier [host cohort](results/2026-11-02/resource-free-calls/README.md) used compiler `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689` and a different host build.

## Reproduce

Install the [toolchain and optional native host](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, then run:

```sh
python bench/examples.py --output-dir build/example-benchmarks
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/wasmtime_host_charts.py build/wasmtime-host/bench/report.json --output-dir bench/charts
```

Chart rendering requires Matplotlib. The host benchmark's default output path can be changed with `--output-dir`; use its generated report path for chart rendering. See the [dated evidence](results/2026-11-03/functions-calls/README.md) for retained raw data and qualification.

To regenerate the qualification baseline and replay from a fresh checkout:

```sh
python bench/qualify_compiler.py --jobs 6 --output-dir build/differential-sharded
python bench/qualify_wasmtime_host.py --baseline-dir build/differential-sharded --output-dir build/wasmtime-host-qualification
python tests/test_native_wasmtime.py
```
