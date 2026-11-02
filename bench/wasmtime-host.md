# Wasmtime host comparison

A native C++ host links the exact Wasmtime 50.0.1 library used by the Python host. On the ten constant-input examples it reduces fresh-process time; ordinary direct Wasm trails native C in this cohort. Precompiled Life beats generic native `-O2`, while [tuned native controls](../docs/NATIVE_PERFORMANCE.md) are faster. The host also changes callbacks and I/O, so the difference is not Python startup alone. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Direct Wasm process times](charts/wasmtime-host-runtime.svg)

![C-to-Wasm process times](charts/wasmtime-host-c-wasm.svg)

![Precompiled artifact preparation](charts/wasmtime-host-preparation.svg)

The 2026-11-02 run used a shared AMD Ryzen 7 3800X Linux machine, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, compiler SHA-256 `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689`, GCC 16.2.1, Emscripten 6.0.13, and Wasmtime 50.0.1. The direct Wasm, C-Wasm and native C artifact bytes were reused from the separately collected example build cohort; native C was freshly executed in the same runtime blocks. Each runtime cell has one fresh-process warmup and 15 measured launches, with checked output bytes. There are 1,440 observations across 90 cells. Preparation is measured separately with five fresh preparations for each example, backend and parallel/serial setting: 200 total. Forty unique artifact/configuration pairs were qualified.

Selected direct-process medians ± MAD in milliseconds:

| Example | Python host | Native host | Precompiled run | Native C |
| --- | ---: | ---: | ---: | ---: |
| Squares | 84.824 ± 2.330 | 4.795 ± 0.543 | 2.932 ± 0.735 | 0.823 ± 0.169 |
| Sorting | 170.752 ± 8.042 | 89.252 ± 4.003 | 68.899 ± 6.860 | 46.512 ± 0.815 |
| Sudoku | 95.419 ± 5.442 | 11.446 ± 1.845 | 5.318 ± 0.141 | 4.205 ± 0.211 |
| Maze | 103.332 ± 9.067 | 12.566 ± 1.181 | 3.674 ± 0.327 | 1.035 ± 0.210 |
| Life | 110.056 ± 3.085 | 34.575 ± 5.162 | 12.390 ± 0.661 | 18.819 ± 0.685 |

For Life, precompiled C-to-Wasm runs in 6.803 ms versus 18.819 ms for native C. Its separate parallel preparation median is 17.384 ms; adding the medians estimates 24.187 ms for preparation plus one run.

Precompiled run times exclude preparation. Parallel preparation medians for those examples are respectively 5.489, 24.150, 9.346, 17.611 and 12.595 ms, including launch, compilation, serialization and writing. Adding separately measured medians estimates one preparation plus one run at 93.049 ms for Sorting, versus 89.252 ms for ordinary native-host launches; this is an estimate, not a separately measured end-to-end sample. Serial compilation remains a control, not the default.

The retained replay passed 11,484 executions: 3,828 case/backend/level combinations across normal default, normal serial and precompiled serial modes. Native and Python references were collected separately. Default precompiled loading also passed ten public WAT unit methods across four modes and twenty example artifacts; it did not receive the full replay. The unit tests cover floating point, random, NUL and UTF-8 bytes, memory64 and bounds. Numeric benchmark input tokens are ASCII; this does not establish arbitrary Python stdin Unicode parity.

## Reproduce

Install the [toolchain and optional native host](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, then run:

```sh
python bench/examples.py --output-dir build/example-benchmarks
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/wasmtime_host_charts.py build/wasmtime-host/bench/report.json --output-dir bench/charts
```

Chart rendering requires Matplotlib. The host benchmark's default output path can be changed with `--output-dir`; use its generated report path for chart rendering. See the [dated evidence](results/2026-11-02/resource-free-calls/README.md) for retained raw data and qualification.

To regenerate the qualification baseline and replay from a fresh checkout:

```sh
python bench/qualify_compiler.py --jobs 6 --output-dir build/differential-sharded
python bench/qualify_wasmtime_host.py --baseline-dir build/differential-sharded --output-dir build/wasmtime-host-qualification
python tests/test_native_wasmtime.py
```
