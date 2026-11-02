# Native execution hills · 2026-11-02

The direct compiler removes dead frames and pending checks for proven leaf calls, recognizes the exact unsigned Kernighan bit-count loop, handles runtime positive power-of-two signed remainder with masks and a fallback, specializes at most two literal-divisor call variants, and emits direct guards in eligible four-way unrolled loops. Naive eight- and sixteen-way unrolling were rejected. Baseline commit `93dfbf1` used compiler SHA-256 `78178c171d7ed846ac20aec7b54f5e2e80ffb5a73bbf3551c44b73b27b373624`; final compiler SHA-256 is `11ade4a575cd77050a7ad82b40ba972be660f9095f01714235cf57bd36d50aa6`.

| Paired entry | V8 baseline → final | V8 ratio (MAD) | Wasmtime baseline → final | Wasmtime ratio (MAD) |
| --- | ---: | ---: | ---: | ---: |
| Sorting | 93.919 → 80.228 ms | 1.182× (0.092) | 86.565 → 66.117 ms | 1.386× (0.217) |
| Sudoku | 18.860 → 8.156 ms | 1.753× (0.422) | 6.541 → 3.836 ms | 1.724× (0.160) |
| Life | 30.570 → 9.103 ms | 3.322× (0.425) | 24.256 → 12.953 ms | 2.277× (0.620) |

Fifteen paired samples per cell use 100 builds and 640 runs; entry includes initialization, callbacks and possible lazy JIT. Stage experiments each use nine pairs for five examples; their factors cannot be multiplied. The separately collected fresh-process host cohort measured Life at 21.215 ms ordinary, 12.697 ms precompiled and 18.720 ms native C; Sudoku at 12.488, 6.660 and 4.133 ms; Sorting at 83.611, 65.535 and 46.099 ms. Precompiled times exclude preparation. The [host comparison](../../../wasmtime-host.md) includes preparation costs.

Native C in that cohort uses generic GCC `-O2`. Separate same-generated-C GCC `-O3 -march=native` controls measured approximately 2.0 ms Life, 2.3 ms Sudoku and 11.4 ms Sorting; they are not paired with the current process cohort. The [native comparison](../../../../docs/NATIVE_PERFORMANCE.md) includes Clang controls and limitations.

Qualification passed 9,573 differential observations including 7,656 native stdout comparisons, and 51 focused commands. Native-host replay passed 11,484 observations over 3,828 case/backend/level units in default Wasm, serial Wasm and serial precompiled modes. Default precompiled mode separately passed twenty example artifacts and ten WAT methods across four modes, not the full replay.

[Paired probes](paired.json) · [Leaf](leaf-paired.json) · [Remainder](remainder-paired.json) · [Branch](branch-paired.json) · [Constants](constant-paired.json) · [Unrolling controls](unroll-controls.json) · [Machine code](machine-code.json) · [Module sizes](module-sizes.json) · [Example builds](examples.json) · [Host results](host.json) · [LangArena](cohort.json) · [Tuned native](native-tuned.json) · [Qualification](qualification.json)

[Samples](samples.tar.gz) · [Source and inputs](inputs.tar.gz) · [Guest artifacts](guest-artifacts.tar.gz) · [Archive verification](archive-verification.json) · [Review](review.json) · [Checksums](SHA256.json)
