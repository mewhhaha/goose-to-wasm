# Example program benchmarks

Status: **passed**.

2026-11-02 · AMD Ryzen 7 3800X, shared desktop host.

Goose O2. Direct Wasm uses memory32; C-Wasm uses memory64. The selected programs, their constant inputs and all printing are unchanged from the [example catalog](../../../../examples/README.md). Compiler constant folding is allowed.

Builds are complete uncached Python-driver invocations, including any C compilation/linking. OS page caches and Emscripten's installed system-library cache remain warm.

Runtime is **whole-process launch-to-exit time**, including host startup, Wasm compilation/instantiation, program initialization, computation, output delivery and teardown. Each observation starts a fresh process/instance and calls the entrypoint once. This measures CLI cost, not warmed kernel throughput.

Each cell has 5 build samples or 15 runtime samples. Untimed fresh-process warmups per runtime cell: 1. Orders are shuffled with the recorded seed; builds and runtime never overlap. Every used artifact must pass its golden output. Values are median milliseconds ± median absolute deviation (MAD).

Headline runtime samples use the ordinary runners without timing-file instrumentation. The Wasm supplements use a separate shuffled set of fresh processes, with the same sample count; timing files are written after their engine intervals end.

## Compilation

| Example | Direct | C-Wasm | Native C |
| --- | ---: | ---: | ---: |
| squares | 60.615 ±0.927 | 506.135 ±15.634 | 213.571 ±5.107 |
| tour | 63.299 ±1.657 | 960.487 ±12.218 | 407.313 ±3.173 |
| functions | 109.028 ±17.387 | 907.963 ±7.905 | 492.396 ±9.643 |
| errors | 96.592 ±0.626 | 698.747 ±3.500 | 326.228 ±0.920 |
| sieve | 66.555 ±0.308 | 572.100 ±4.154 | 239.569 ±7.582 |
| sorting | 86.802 ±0.867 | 880.977 ±37.815 | 537.300 ±11.576 |
| sudoku | 67.162 ±0.026 | 503.322 ±16.356 | 262.153 ±4.310 |
| maze | 70.881 ±0.299 | 658.550 ±23.669 | 386.326 ±29.370 |
| vm | 68.741 ±2.336 | 718.745 ±30.233 | 283.301 ±4.676 |
| life | 72.219 ±3.977 | 602.082 ±19.660 | 300.348 ±1.855 |

## Whole-process runtime

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native C |
| --- | ---: | ---: | ---: | ---: | ---: |
| squares | 28.877 ±4.996 | 29.158 ±2.045 | 91.329 ±10.398 | 102.710 ±9.868 | 0.827 ±0.132 |
| tour | 51.160 ±6.178 | 35.503 ±5.454 | 126.827 ±8.860 | 122.951 ±8.937 | 0.943 ±0.129 |
| functions | 51.699 ±2.528 | 31.891 ±2.073 | 133.638 ±8.322 | 132.437 ±14.461 | 0.966 ±0.157 |
| errors | 32.879 ±4.054 | 29.399 ±1.769 | 98.992 ±4.320 | 102.797 ±5.354 | 0.996 ±0.176 |
| sieve | 52.508 ±13.503 | 34.108 ±2.997 | 98.602 ±5.684 | 99.394 ±3.939 | 1.140 ±0.087 |
| sorting | 157.245 ±6.928 | 244.397 ±8.885 | 252.317 ±7.795 | 257.452 ±9.531 | 49.839 ±2.991 |
| sudoku | 42.949 ±4.897 | 36.763 ±2.582 | 98.036 ±2.941 | 106.578 ±3.357 | 4.970 ±0.792 |
| maze | 51.259 ±9.285 | 31.342 ±1.305 | 118.575 ±3.982 | 107.736 ±10.789 | 0.982 ±0.210 |
| vm | 46.310 ±7.710 | 31.700 ±2.554 | 113.747 ±5.919 | 124.420 ±12.409 | 0.971 ±0.181 |
| life | 80.829 ±8.124 | 43.519 ±3.099 | 138.074 ±7.071 | 109.374 ±6.206 | 19.025 ±0.553 |

## Supplement: Wasm entrypoint

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| squares | 0.196 ±0.018 | 0.971 ±0.020 | 0.130 ±0.003 | 0.645 ±0.011 |
| tour | 22.384 ±5.624 | 3.695 ±0.972 | 1.780 ±0.042 | 1.775 ±0.023 |
| functions | 20.205 ±2.681 | 2.735 ±0.101 | 1.368 ±0.010 | 1.964 ±0.030 |
| errors | 3.734 ±0.749 | 1.803 ±0.025 | 0.874 ±0.011 | 1.756 ±0.025 |
| sieve | 8.425 ±0.903 | 2.548 ±0.724 | 1.673 ±0.035 | 1.373 ±0.029 |
| sorting | 123.201 ±3.448 | 212.322 ±5.394 | 122.960 ±1.005 | 133.174 ±2.087 |
| sudoku | 12.817 ±1.217 | 6.885 ±0.439 | 7.932 ±0.142 | 8.611 ±0.112 |
| maze | 15.920 ±0.508 | 2.007 ±0.080 | 0.811 ±0.016 | 2.295 ±0.026 |
| vm | 11.925 ±1.501 | 2.302 ±0.115 | 0.949 ±0.010 | 3.079 ±0.046 |
| life | 41.436 ±2.624 | 10.859 ±0.888 | 26.065 ±0.351 | 9.846 ±0.198 |

## Supplement: Wasm engine compilation and instantiation

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| squares | 0.273 ±0.029 | 0.536 ±0.032 | 2.992 ±0.172 | 11.869 ±1.569 |
| tour | 0.567 ±0.077 | 0.714 ±0.088 | 39.986 ±6.449 | 32.623 ±1.462 |
| functions | 0.575 ±0.088 | 0.551 ±0.043 | 35.733 ±2.462 | 28.719 ±1.211 |
| errors | 0.357 ±0.055 | 0.598 ±0.059 | 14.912 ±2.308 | 15.314 ±1.730 |
| sieve | 0.375 ±0.027 | 0.643 ±0.072 | 13.661 ±0.366 | 13.038 ±1.841 |
| sorting | 0.505 ±0.103 | 0.656 ±0.051 | 50.188 ±10.874 | 31.183 ±0.821 |
| sudoku | 0.337 ±0.035 | 0.606 ±0.062 | 7.460 ±0.639 | 12.456 ±1.198 |
| maze | 0.443 ±0.022 | 0.635 ±0.073 | 24.801 ±3.560 | 16.894 ±2.455 |
| vm | 0.482 ±0.058 | 0.606 ±0.057 | 27.367 ±0.732 | 15.982 ±0.541 |
| life | 0.430 ±0.060 | 0.615 ±0.060 | 23.113 ±0.434 | 14.782 ±1.411 |

The entrypoint interval includes Goose initialization, host output callbacks and any lazy JIT work. It excludes final Wasm-host output concatenation/delivery. Native Goose prints unbuffered, so no native entrypoint column or cross-boundary speedup is presented. Process time minus engine time also includes loading, bookkeeping and teardown; it is not a pure startup measurement.

These fresh-process examples have different timing rules from LangArena's warmed computational regions. Raw samples, commands, artifact/source/compiler identities and engine versions are in [report.json](report.json). [Method and reproduction](../../../examples.md).


Retained evidence: [raw example samples and logs](../native-gap/example-samples.tar.gz) · [example inputs and source snapshots](../native-gap/example-inputs.tar.gz) · [checksums](../native-gap/SHA256.json).
