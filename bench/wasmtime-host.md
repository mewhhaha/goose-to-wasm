# Wasmtime host comparison

A native C++ host links the exact Wasmtime 50.0.1 library used by the Python host. On the ten constant-input examples it reduces fresh-process time; ordinary direct Wasm trails native C in this cohort. Precompiled Life beats generic native `-O2`, while [tuned native controls](../docs/NATIVE_PERFORMANCE.md) are faster. The host also changes callbacks and I/O, so the difference is not Python startup alone. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Direct Wasm process times](charts/wasmtime-host-runtime.svg)

![C-to-Wasm process times](charts/wasmtime-host-c-wasm.svg)

![Precompiled artifact preparation](charts/wasmtime-host-preparation.svg)

The 2026-11-02 run used a shared AMD Ryzen 7 3800X Linux machine, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, compiler SHA-256 `11ade4a575cd77050a7ad82b40ba972be660f9095f01714235cf57bd36d50aa6`, GCC 16.2.1, Emscripten 6.0.13, and Wasmtime 50.0.1. The direct Wasm, C-Wasm and native C artifact bytes were reused from the separately collected example build cohort; native C was freshly executed in the same runtime blocks. Each runtime cell has one fresh-process warmup and 15 measured launches, with checked output bytes. There are 1,440 observations across 90 cells. Preparation is measured separately with five fresh preparations for each example, backend and parallel/serial setting: 200 total. Forty unique artifact/configuration pairs were qualified.

Selected direct-process medians in milliseconds:

| Example | Python host | Native host | Precompiled run | Native C |
| --- | ---: | ---: | ---: | ---: |
| Squares | 83.275 | 3.932 | 2.272 | 0.760 |
| Sorting | 162.293 | 83.611 | 65.535 | 46.099 |
| Sudoku | 91.013 | 12.488 | 6.660 | 4.133 |
| Maze | 94.041 | 12.403 | 2.774 | 1.188 |
| Life | 106.543 | 21.215 | 12.697 | 18.720 |

For Life, precompiled C-to-Wasm runs in 7.227 ms versus 18.720 ms for native C. Its separate parallel preparation median is 18.363 ms; adding the medians estimates 25.590 ms for preparation plus one run.

Precompiled run times exclude preparation. Parallel preparation medians for those examples are respectively 4.718, 23.550, 8.515, 14.456 and 12.677 ms, including launch, compilation, serialization and writing. Adding separately measured medians estimates one preparation plus one run at 89.085 ms for Sorting, versus 83.611 ms for ordinary native-host launches; this is an estimate, not a separately measured end-to-end sample. Serial compilation remains a control, not the default.

The retained replay passed 11,484 executions: 3,828 case/backend/level combinations across normal default, normal serial and precompiled serial modes. Native and Python references were collected separately. Default precompiled loading also passed ten public WAT unit methods across four modes and twenty example artifacts; it did not receive the full replay. The unit tests cover floating point, random, NUL and UTF-8 bytes, memory64 and bounds. Numeric benchmark input tokens are ASCII; this does not establish arbitrary Python stdin Unicode parity.

## Reproduce

Install the [toolchain and optional native host](../docs/GUIDE.md#optional-native-wasmtime-host), including the oracle SDK, then run:

```sh
python bench/examples.py --output-dir build/example-benchmarks
python bench/wasmtime_host.py --example-report build/example-benchmarks/report.json
python bench/wasmtime_host_charts.py build/wasmtime-host/bench/report.json --output-dir bench/charts
```

Chart rendering requires Matplotlib. The host benchmark's default output path can be changed with `--output-dir`; use its generated report path for chart rendering. See the [dated evidence](results/2026-11-02/native-hills/README.md) for retained raw data and qualification.

To regenerate the qualification baseline and replay from a fresh checkout:

```sh
python bench/qualify_compiler.py --jobs 6 --output-dir build/differential-sharded
python bench/qualify_wasmtime_host.py --baseline-dir build/differential-sharded --output-dir build/wasmtime-host-qualification
python tests/test_native_wasmtime.py
```
