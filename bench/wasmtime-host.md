# Wasmtime host comparison

A native C++ host links the exact Wasmtime 50.0.1 library used by the Python host. On the ten constant-input examples it reduces fresh-process time; direct Wasm still trails native C. The host also changes callbacks and I/O, so the difference is not Python startup alone. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Direct Wasm process times](charts/wasmtime-host-runtime.svg)

![C-to-Wasm process times](charts/wasmtime-host-c-wasm.svg)

![Precompiled artifact preparation](charts/wasmtime-host-preparation.svg)

The 2026-11-02 run used a shared AMD Ryzen 7 3800X Linux machine, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, compiler SHA-256 `82b14bd7e795864606042853b13994e0fa8e6bddb22f02f9eef19d87849043e8`, GCC 16.2.1, Emscripten 6.0.13, and Wasmtime 50.0.1. The direct Wasm, C-Wasm and native C artifact bytes were reused from the separately collected example build cohort; native C was freshly executed in the same runtime blocks. Each runtime cell has one fresh-process warmup and 15 measured launches, with checked output bytes. There are 1,440 observations across 90 cells. Preparation is measured separately with five fresh preparations for each example, backend and parallel/serial setting: 200 total. Forty unique artifact/configuration pairs were qualified.

Selected direct-process medians in milliseconds:

| Example | Python host | Native host | Precompiled run | Native C |
| --- | ---: | ---: | ---: | ---: |
| Squares | 86.362 | 4.104 | 2.229 | 0.862 |
| Sorting | 221.510 | 138.141 | 93.519 | 47.638 |
| Sudoku | 97.981 | 18.274 | 9.591 | 4.631 |
| Maze | 113.004 | 31.235 | 2.810 | 0.859 |
| Life | 137.066 | 53.580 | 31.781 | 20.214 |

For Life, precompiled C-to-Wasm runs in 7.685 ms versus 20.214 ms for native C. Its separate parallel preparation median is 22.948 ms; adding the medians estimates 30.633 ms for preparation plus one run.

Precompiled run times exclude preparation. Default parallel preparation medians for those examples are respectively 4.792, 47.531, 8.714, 24.511 and 29.025 ms, including launch, compilation, serialization and writing. Adding separately measured medians estimates one preparation plus one run at 7.021 ms for Squares and 141.050 ms for Sorting, versus 4.104 and 138.141 ms for ordinary native-host launches. Dividing preparation by per-run savings estimates break-even at 2.56 and 1.07 runs respectively; these sums and ratios are estimates, not separately measured end-to-end samples. Serial compilation remains a control, not the default.

The retained replay passed 11,484 executions: 3,828 case/backend/level combinations across normal default, normal serial and precompiled serial modes. Native and Python references were collected separately. Default precompiled loading also passed ten public WAT unit methods across four modes and twenty example artifacts; it did not receive the full replay. The unit tests cover floating point, random, NUL and UTF-8 bytes, memory64 and bounds. Numeric benchmark input tokens are ASCII; this does not establish arbitrary Python stdin Unicode parity.

## Reproduce

Install the [toolchain and optional native host](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, then run:

```sh
python bench/examples.py --output-dir build/example-benchmarks
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/wasmtime_host_charts.py build/wasmtime-host/bench/report.json --output-dir bench/charts
```

Chart rendering requires Matplotlib. The host benchmark's default output path can be changed with `--output-dir`; use its generated report path for chart rendering. See the [dated evidence](results/2026-11-02/sorting-execution/README.md) for retained raw data and qualification.

To regenerate the qualification baseline and replay from a fresh checkout:

```sh
python bench/qualify_compiler.py --jobs 6 --output-dir build/differential-sharded
python bench/qualify_wasmtime_host.py --baseline-dir build/differential-sharded --output-dir build/wasmtime-host-qualification
python tests/test_native_wasmtime.py
```
