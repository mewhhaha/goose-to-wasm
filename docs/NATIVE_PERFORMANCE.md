# Getting closer to native

The newer [matched runtime targets](RUNTIME_TARGETS.md) compare selected native and Wasm profiles under the same warmed workloads; the full-process controls below are separate.

The existing example charts use GCC 16 `-O2` for generic CPU native C. Separate controls compiled the same generated C, from the same frozen Goose `-O2` compiler and unchanged sources, with host-tuned flags. Medians below are milliseconds from fresh process launch to exit, with one warmup and 15 measured launches per cell; outputs were checked.

| Example | GCC `-O2` generic | GCC `-O3 -march=native` | Clang 23 `-O3 -march=native` |
| --- | ---: | ---: | ---: |
| Life | 17.717 | 1.982 | 7.792 |
| Sudoku | 3.862 | 2.302 | 4.504 |
| Sorting | 44.794 | 11.403 | 34.273 |

These are separately collected controls, not the main benchmark cohort or a universal native performance ceiling. The [raw measurements](../bench/results/2026-11-02/native-hills/native-tuned.json) record the compiler and machine identities. GCC's tuned Life assembly contains constant-propagated step clones without `idiv`; Sorting uses an eight-way scalar shift chain and AVX2 for `is_sorted`. This shows why the generic GCC comparison alone does not describe the available native code.

The current compiler omits dead frames for proven scalar/slice leafs, recognizes the exact unsigned Kernighan loop as `popcnt`, handles runtime positive power-of-two signed remainder with masks, specializes up to two literal-divisor call variants, and emits direct guards in eligible unrolled loops. The [Wasm audit](WASM_AUDIT.md) and [dated evidence](../bench/results/2026-11-02/native-hills/README.md) report measurements and qualification. Current fresh-process Wasmtime native-host medians for Life, Sudoku and Sorting are 21.215, 12.488 and 83.611 ms ordinary, or 12.697, 6.660 and 65.535 ms precompiled; preparation is excluded. These are separate from the tuned controls above and cannot be paired with them.
