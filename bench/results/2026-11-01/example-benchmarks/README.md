# Example program benchmarks

Status: **passed**.

2026-11-01 · AMD Ryzen 7 3800X, shared desktop host.

Goose O2. Direct Wasm uses memory32; C-Wasm uses memory64. The selected programs, their constant inputs and all printing are unchanged from the [example catalog](../../../../examples/README.md). Compiler constant folding is allowed.

Sorting's insertion-sort pass uses **20,000 values**. Its header and catalog incorrectly say 2,000; the measured source is preserved in [inputs.tar.gz](inputs.tar.gz).

Builds are complete uncached Python-driver invocations, including any C compilation/linking. OS page caches and Emscripten's installed system-library cache remain warm.

Runtime is **whole-process launch-to-exit time**, including host startup, Wasm compilation/instantiation, program initialization, computation, output delivery and teardown. Each observation starts a fresh process/instance and calls the entrypoint once. This measures CLI cost, not warmed kernel throughput.

Each cell has 5 build samples or 15 runtime samples. There is one untimed fresh-process warmup per runtime cell. Orders are shuffled with the recorded seed; builds and runtime never overlap. Every used artifact must pass its golden output. Values are median milliseconds ± median absolute deviation (MAD).

Headline runtime samples use the ordinary runners without timing-file instrumentation. The Wasm supplements use a separate shuffled set of fresh processes, with the same sample count; timing files are written after their engine intervals end.

## Compilation

| Example | Direct | C-Wasm | Native C |
| --- | ---: | ---: | ---: |
| squares | 62.957 ±1.102 | 514.545 ±4.342 | 201.613 ±3.737 |
| tour | 65.242 ±0.897 | 939.369 ±11.159 | 441.050 ±9.654 |
| functions | 86.460 ±2.875 | 926.187 ±46.820 | 515.568 ±8.586 |
| errors | 70.627 ±1.296 | 686.454 ±14.464 | 343.398 ±4.622 |
| sieve | 91.942 ±3.546 | 610.632 ±11.589 | 268.049 ±12.118 |
| sorting | 90.921 ±1.982 | 857.365 ±19.087 | 560.985 ±6.289 |
| sudoku | 94.809 ±4.800 | 531.055 ±25.103 | 283.324 ±12.774 |
| maze | 75.530 ±3.744 | 681.158 ±7.384 | 362.484 ±5.222 |
| vm | 71.074 ±0.589 | 668.411 ±2.332 | 298.363 ±11.007 |
| life | 70.367 ±1.691 | 597.100 ±20.819 | 308.870 ±12.031 |

## Whole-process runtime

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native C |
| --- | ---: | ---: | ---: | ---: | ---: |
| squares | 26.476 ±1.549 | 30.976 ±3.363 | 84.616 ±2.729 | 96.163 ±1.987 | 0.906 ±0.175 |
| tour | 73.584 ±3.656 | 32.933 ±3.395 | 150.977 ±6.787 | 123.218 ±6.412 | 0.993 ±0.130 |
| functions | 78.449 ±1.453 | 32.858 ±2.292 | 161.079 ±8.035 | 114.262 ±3.508 | 0.975 ±0.187 |
| errors | 37.121 ±1.914 | 29.331 ±1.181 | 108.477 ±4.450 | 102.905 ±4.947 | 0.942 ±0.130 |
| sieve | 85.984 ±8.239 | 32.413 ±1.516 | 120.684 ±8.053 | 96.680 ±2.295 | 1.380 ±0.317 |
| sorting | 4039.846 ±43.608 | 239.430 ±3.021 | 4334.883 ±27.083 | 246.182 ±1.695 | 48.335 ±0.839 |
| sudoku | 255.385 ±2.925 | 35.276 ±2.107 | 328.091 ±1.276 | 103.901 ±2.875 | 4.316 ±0.203 |
| maze | 156.385 ±5.025 | 30.964 ±2.311 | 131.917 ±5.925 | 106.006 ±6.317 | 1.031 ±0.168 |
| vm | 71.160 ±3.615 | 33.447 ±5.369 | 143.829 ±5.813 | 103.155 ±1.797 | 1.006 ±0.158 |
| life | 145.787 ±13.207 | 41.407 ±2.797 | 203.844 ±12.454 | 108.156 ±2.135 | 18.391 ±0.249 |

## Supplement: Wasm entrypoint

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| squares | 0.181 ±0.006 | 0.993 ±0.047 | 0.135 ±0.002 | 0.627 ±0.010 |
| tour | 36.681 ±0.589 | 2.795 ±0.151 | 1.817 ±0.052 | 1.766 ±0.038 |
| functions | 43.699 ±1.183 | 2.714 ±0.093 | 1.409 ±0.028 | 1.955 ±0.037 |
| errors | 8.415 ±1.592 | 1.795 ±0.023 | 0.866 ±0.014 | 1.743 ±0.047 |
| sieve | 16.326 ±1.195 | 1.845 ±0.042 | 6.066 ±0.110 | 1.359 ±0.020 |
| sorting | 3965.602 ±28.323 | 210.282 ±4.128 | 4202.204 ±43.330 | 132.259 ±1.448 |
| sudoku | 230.062 ±3.746 | 6.730 ±0.343 | 236.285 ±2.152 | 8.433 ±0.111 |
| maze | 41.651 ±1.401 | 1.957 ±0.028 | 1.017 ±0.041 | 2.280 ±0.060 |
| vm | 35.293 ±1.224 | 2.263 ±0.095 | 1.005 ±0.022 | 3.029 ±0.058 |
| life | 70.861 ±4.703 | 9.949 ±0.089 | 54.132 ±0.927 | 9.823 ±0.082 |

## Supplement: Wasm engine compilation and instantiation

| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| squares | 0.222 ±0.010 | 0.552 ±0.074 | 2.987 ±0.227 | 10.404 ±0.244 |
| tour | 0.487 ±0.038 | 0.573 ±0.052 | 63.305 ±2.921 | 32.502 ±0.571 |
| functions | 0.613 ±0.131 | 0.561 ±0.048 | 68.762 ±1.603 | 28.356 ±0.320 |
| errors | 0.407 ±0.051 | 0.573 ±0.032 | 21.183 ±1.257 | 15.161 ±1.032 |
| sieve | 0.351 ±0.034 | 0.523 ±0.032 | 26.170 ±1.069 | 12.177 ±1.386 |
| sorting | 0.661 ±0.089 | 0.643 ±0.048 | 78.762 ±3.863 | 31.991 ±1.363 |
| sudoku | 0.300 ±0.033 | 0.584 ±0.069 | 11.665 ±0.588 | 12.675 ±1.228 |
| maze | 0.563 ±0.087 | 0.611 ±0.065 | 48.225 ±5.547 | 16.015 ±1.307 |
| vm | 0.539 ±0.094 | 0.605 ±0.063 | 56.166 ±2.027 | 16.495 ±0.745 |
| life | 0.417 ±0.023 | 0.556 ±0.046 | 47.433 ±0.961 | 16.858 ±2.691 |

The entrypoint interval includes Goose initialization, host output callbacks and any lazy JIT work. It excludes final Wasm-host output concatenation/delivery. Native Goose prints unbuffered, so no native entrypoint column or cross-boundary speedup is presented. Process time minus engine time also includes loading, bookkeeping and teardown; it is not a pure startup measurement.

These fresh-process examples have different timing rules from LangArena's warmed computational regions. Raw samples, commands, artifact/source/compiler identities and engine versions are in [report.json](report.json). [Method and reproduction](../../../examples.md).

Retained evidence: [artifacts and per-sample logs](samples.tar.gz) · [input sources](inputs.tar.gz) · [identity](identity.json) · [validation](validation.json) · [checksums](SHA256.json).
