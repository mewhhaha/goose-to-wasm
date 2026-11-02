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
| squares | 66.122 ±1.463 | 525.578 ±6.337 | 207.561 ±6.209 |
| tour | 69.796 ±3.757 | 969.149 ±11.364 | 458.197 ±10.342 |
| functions | 94.456 ±7.388 | 994.348 ±29.916 | 536.901 ±6.761 |
| errors | 77.221 ±3.402 | 749.329 ±7.380 | 368.936 ±3.162 |
| sieve | 72.869 ±2.629 | 588.821 ±10.344 | 275.905 ±19.037 |
| sorting | 98.475 ±3.503 | 888.994 ±17.278 | 575.869 ±7.681 |
| sudoku | 75.306 ±2.705 | 573.036 ±29.225 | 297.416 ±7.239 |
| maze | 80.156 ±5.358 | 696.005 ±3.480 | 376.741 ±6.910 |
| vm | 74.480 ±3.285 | 725.678 ±7.424 | 311.190 ±6.600 |
| life | 73.872 ±2.347 | 627.798 ±13.707 | 326.005 ±7.535 |

## Whole-process runtime

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native C |
| --- | ---: | ---: | ---: | ---: | ---: |
| squares | 31.819 ±4.515 | 29.070 ±1.598 | 93.308 ±8.045 | 98.212 ±2.609 | 0.838 ±0.131 |
| tour | 74.830 ±2.882 | 34.674 ±3.042 | 170.330 ±11.239 | 134.994 ±10.735 | 0.903 ±0.085 |
| functions | 80.377 ±3.150 | 34.226 ±2.681 | 159.394 ±5.211 | 124.268 ±9.685 | 0.956 ±0.142 |
| errors | 36.405 ±2.272 | 29.295 ±1.400 | 111.444 ±3.814 | 107.651 ±5.304 | 0.909 ±0.115 |
| sieve | 82.753 ±10.109 | 33.760 ±2.459 | 126.639 ±8.621 | 100.797 ±2.255 | 1.178 ±0.223 |
| sorting | 262.175 ±7.926 | 258.789 ±6.358 | 299.986 ±7.657 | 268.301 ±10.017 | 50.844 ±0.548 |
| sudoku | 46.051 ±3.255 | 38.763 ±4.173 | 110.555 ±7.197 | 110.979 ±2.768 | 4.549 ±0.398 |
| maze | 143.586 ±13.365 | 36.068 ±5.592 | 149.343 ±12.568 | 107.869 ±5.340 | 0.876 ±0.036 |
| vm | 72.186 ±4.066 | 41.786 ±9.824 | 160.445 ±10.922 | 111.843 ±7.316 | 1.114 ±0.227 |
| life | 152.153 ±18.930 | 42.872 ±2.183 | 167.052 ±10.237 | 117.833 ±7.432 | 19.299 ±0.850 |

## Supplement: Wasm entrypoint

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| squares | 0.211 ±0.033 | 0.995 ±0.047 | 0.137 ±0.004 | 0.642 ±0.015 |
| tour | 37.113 ±1.110 | 2.839 ±0.163 | 1.900 ±0.044 | 1.839 ±0.042 |
| functions | 42.933 ±1.587 | 2.749 ±0.086 | 1.443 ±0.029 | 2.031 ±0.023 |
| errors | 9.673 ±1.688 | 1.851 ±0.079 | 0.915 ±0.012 | 1.816 ±0.056 |
| sieve | 15.743 ±1.152 | 2.006 ±0.169 | 2.503 ±0.061 | 1.431 ±0.039 |
| sorting | 162.186 ±3.999 | 220.239 ±4.458 | 129.245 ±1.518 | 138.797 ±2.043 |
| sudoku | 12.876 ±0.221 | 6.993 ±0.337 | 8.148 ±0.210 | 8.956 ±0.153 |
| maze | 42.156 ±1.307 | 2.003 ±0.039 | 0.866 ±0.019 | 2.321 ±0.052 |
| vm | 35.473 ±1.088 | 2.331 ±0.054 | 1.002 ±0.012 | 3.079 ±0.058 |
| life | 61.210 ±2.225 | 10.740 ±0.593 | 27.469 ±0.689 | 10.252 ±0.265 |

## Supplement: Wasm engine compilation and instantiation

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| squares | 0.262 ±0.035 | 0.536 ±0.030 | 2.982 ±0.188 | 11.258 ±0.677 |
| tour | 0.718 ±0.114 | 0.557 ±0.030 | 63.262 ±3.197 | 35.380 ±1.840 |
| functions | 0.565 ±0.079 | 0.541 ±0.025 | 68.431 ±0.953 | 30.961 ±1.472 |
| errors | 0.451 ±0.055 | 0.608 ±0.056 | 21.617 ±1.202 | 15.683 ±1.533 |
| sieve | 0.465 ±0.086 | 0.621 ±0.066 | 26.896 ±1.044 | 11.896 ±0.906 |
| sorting | 0.673 ±0.097 | 0.596 ±0.060 | 79.514 ±3.121 | 33.651 ±1.500 |
| sudoku | 0.318 ±0.034 | 0.597 ±0.040 | 12.211 ±1.013 | 12.564 ±0.785 |
| maze | 0.488 ±0.080 | 0.609 ±0.065 | 47.624 ±2.768 | 15.612 ±1.076 |
| vm | 0.565 ±0.117 | 0.564 ±0.012 | 58.668 ±1.184 | 17.337 ±1.400 |
| life | 0.480 ±0.071 | 0.625 ±0.085 | 48.137 ±1.857 | 15.043 ±1.241 |

The entrypoint interval includes Goose initialization, host output callbacks and any lazy JIT work. It excludes final Wasm-host output concatenation/delivery. Native Goose prints unbuffered, so no native entrypoint column or cross-boundary speedup is presented. Process time minus engine time also includes loading, bookkeeping and teardown; it is not a pure startup measurement.

These fresh-process examples have different timing rules from LangArena's warmed computational regions. Raw samples, commands, artifact/source/compiler identities and engine versions are in [report.json](report.json). [Method and reproduction](../../../examples.md).

Retained evidence: [artifacts and per-sample logs](samples.tar.gz) · [input sources](inputs.tar.gz) · [identity](identity.json) · [compiler change and qualification](../prefix-resolution/README.md) · [checksums](SHA256.json).
