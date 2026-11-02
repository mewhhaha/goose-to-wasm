# Runtime targets · 2026-11-02

This qualified empirical reference is specific to the source, workload, compiler, Wasmtime 50 and shared Ryzen 7 3800X host; it is not a proven ceiling. Compiler SHA-256 is `11ade4a575cd77050a7ad82b40ba972be660f9095f01714235cf57bd36d50aa6`. See the [table and method](../../../../docs/RUNTIME_TARGETS.md) for workloads, selected-reference interpretation and adapter boundaries.

The run passed 875 executions: 140 qualification, 420 pilot and 315 confirmation, covering 140 artifacts and 60 AOT preparations across 14 variants and ten workloads. Three pilot rounds selected references; nine fresh confirmation rounds retained those choices without reselection. Runtime was pinned to CPU 2; unrelated shared-host load remains possible. Direct/selected-Wasm paired median ratios were 2.473× for custom hash, 2.614× Life, 1.283× Quicksort and 1.155× Sudoku. Corresponding direct/selected-native ratios were 4.236×, 6.977×, 1.458× and 2.109×. Raw direct Wasm was its own selected Wasm reference for five workloads.

| Workload | Selected native | Selected Wasm |
| --- | --- | --- |
| Fannkuch | clang-O3-generic | direct-O2 |
| Mandelbrot | gcc-O3-generic | direct-O2 |
| Sieve | gcc-O3-generic | direct-O2 |
| CRC32 | gcc-O3-native | c-wasm-O2-simd128 |
| Custom hash | clang-O3-native | c-wasm-O3-simd128 |
| Merge sort | clang-O2-generic | direct-O2 |
| Quicksort | clang-O2-generic | direct-wasm-opt-O3 |
| Life | clang-O3-native | c-wasm-O2-simd128 |
| Insertion sort | gcc-O3-native | direct-O2 |
| Sudoku | gcc-O3-native | direct-wasm-opt-O3 |

[Full report and selected flags](references.json) · [Chart data and verification](chart-verification.json) · [Adapter cases](cases.json) · [Source and inputs](inputs.tar.gz) · [Guest artifacts](guest-artifacts.tar.gz) · [Samples](samples.tar.gz) · [Review](review.json) · [Checksums](SHA256.json)
