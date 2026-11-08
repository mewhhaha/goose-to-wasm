# Scalar Wasm locals · 2026-11-08

Snapshot 57 (`fbc56870acf7551a43797cb4605c9fe49b5d976f65ffed0a7b3c8a215531dbae` codegen source; parent snapshot 56) specializes emitted Wasm for proven scalar and fixed scalar-array modules and uses typed locals for eligible scalar parameters and simple declarations. Captures, compound values and references stay excluded. Frame offsets, reservations and debug checks are preserved.

The official Langbench Mandelbrot input is 2,048 × 2,048 pixels with 1,000 iterations and checksum 1,038,538,536. Seven timed samples follow one warmup per profile. Resident Wasmtime and V8 setup, compilation, deserialization and instantiation are outside the guest timer. The snapshot 57 Wasm module is 2,796 bytes; snapshot 56's separately recorded module is 4,341 bytes.

The compiler comparison covers 11 programs (ten examples and Mandelbrot), three compilers (the prior optimized C++ compiler and Goose snapshots 56 and 57), and source-to-Wasm and source-to-C with the same `-O2` input: 66 cells, five measurements and one warmup per cell. Downstream C compilation and runtime validation occur after timing. These are compiler execution measurements, not compiler construction times.


## Runtime

| Runtime | Official computation, ms ±MAD |
| --- | ---: |
| C / GCC | 2452.40 ±13.23 |
| C / Clang | 2626.21 ±25.42 |
| Upstream Goose native | 2447.83 ±14.69 |
| Goose 57 native | 2453.63 ±32.22 |
| Goose 57 / Wasmtime | 2639.67 ±20.55 |
| Goose 57 / V8 | 2574.22 ±24.98 |

Wasmtime is 1.076× native time and V8 is 1.049× by the ratios of medians. All 144 runtime checks passed, including warmups. Wasmtime compiled and deserialized once; V8 constructed one module in one resident process. Fresh store/instance setup is outside the guest clock. V8 used default tiering; the tier was not explicitly verified. Wasmtime preparation took 5.97 ms, including 5.39 ms module compilation and 0.071 ms deserialization, and is excluded from the computation bars.

The [previous snapshot 56 run](../../2026-11-07/langbench-hot/README.md) recorded 35.21 s Wasmtime and 42.54 s V8; it was collected separately. The new [paired smaller-input run](paired-runtime.json) alternates the exact old and new modules on CPU 7, with one warmup and seven measured pairs per engine (512², 500 iterations, checksum 33,209,574). Median new/old ratios are 0.07176 for Wasmtime and 0.05796 for V8: 13.93× and 17.25× faster. These ratios do not assert a paired speedup on the official input.

The [preserved WAT](mandelbrot.candidate.wat.gz) module's five loop subtrees contain no memory loads, stores or calls; prologue/epilogue traffic remains. [Inspection](inspection.json) counts lexical loop subtrees, including overlaps, rather than dynamic instructions. The conservative proof leaves compound programs on the existing path; this result is not a language-wide native-speed claim.

## Compiler execution

The table gives median milliseconds. The chart has ±MAD whiskers; all raw observations and validation commands are in [compiler-comparison.json](compiler-comparison.json). Shuffled balanced rounds retain OS caches. All 66 cells passed, including validation on both engines for each unique Wasm output and independent golden outputs for native C. No C++ oracle is used.

| Program | C++ → Wasm | Goose 56 → Wasm | Goose 57 → Wasm | C++ → C | Goose 56 → C | Goose 57 → C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| squares | 2.49 | 3.04 | 2.86 | 3.14 | 2.98 | 3.04 |
| tour | 4.56 | 15.00 | 14.92 | 5.02 | 7.30 | 7.01 |
| functions | 20.77 | 82.09 | 81.98 | 21.83 | 52.49 | 52.17 |
| errors | 9.23 | 31.06 | 30.65 | 9.44 | 26.54 | 26.06 |
| sieve | 7.09 | 23.68 | 23.80 | 7.56 | 20.45 | 20.58 |
| sorting | 26.24 | 83.81 | 84.00 | 27.20 | 55.92 | 55.54 |
| sudoku | 8.38 | 25.42 | 24.95 | 8.75 | 22.72 | 22.59 |
| maze | 11.46 | 38.29 | 38.27 | 11.74 | 28.20 | 27.79 |
| vm | 8.38 | 32.42 | 32.20 | 8.72 | 24.91 | 24.45 |
| life | 8.81 | 26.24 | 26.12 | 8.77 | 22.66 | 22.36 |
| mandelbrot | 7.00 | 21.38 | 20.92 | 7.36 | 20.49 | 20.74 |

Across eleven programs, geometric-mean Goose 57 / C++ ratios are 3.003 for direct Wasm and 2.209 for C emission. Versus Goose 56 they are 0.988 and 0.992; small changes on this shared machine do not establish a compilation improvement. Compiler construction is excluded.

The first comparison was rejected: the native validation link lacked `-rdynamic`, so `bench_input` could not be resolved for Goose Mandelbrot. Its failed cells have no score. The entire 396-invocation campaign was rerun with the corrected validation flags. The rejected report, exact old harness and emitted artifacts remain in the capsule. A brief accidental broad test run occurred after those first compiler timers and before the qualified campaign; it overlapped neither qualified runtime nor compilation timers.

## Full examples

Five builds, five process samples after one warmup, and five AOT preparations per cell. These launch-to-exit timings include host startup, loading, execution, output and teardown. They are separate from the resident Mandelbrot kernel. AOT serialization/compilation is outside runtime and shown in its own chart. All outputs match the catalog goldens.

| Program | Complete Wasm build, ms | Complete native build, ms | Minimal AOT process, ms | Native process, ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.78 | 257.03 | 0.926 | 0.782 |
| tour | 62.15 | 910.78 | 1.008 | 1.423 |
| functions | 158.48 | 1618.71 | 1.096 | 0.881 |
| errors | 81.21 | 725.96 | 1.298 | 0.912 |
| sieve | 72.99 | 399.90 | 3.774 | 2.003 |
| sorting | 134.52 | 1852.73 | 179.970 | 115.537 |
| sudoku | 73.70 | 473.70 | 13.164 | 10.446 |
| maze | 87.23 | 717.23 | 1.586 | 1.115 |
| vm | 81.41 | 598.69 | 1.516 | 1.020 |
| life | 75.27 | 528.00 | 27.556 | 22.481 |

Sorting remains 1.56× native process time. These are fresh snapshot 57 observations; earlier example rows were collected separately and do not establish a paired improvement or regression.

## Identity and reproduction

- Shared AMD Ryzen 7 3800X, CPU 7. Raw reports retain versions, flags, commands, process IDs, machine state and all individual measurements.
- Codegen source: `fbc56870acf7551a43797cb4605c9fe49b5d976f65ffed0a7b3c8a215531dbae`.
- Wasm: `cd7e4ff2aed97d25f32b12989ff015a375eedb9b2ec9dadc46d582d4f320986c` (2,796 bytes).
- cpp: `8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6`
- goose56: `febb9bcacc2346ad0eb96daec2126cce74d23efc07a4bfe249f97aae068ef088`
- goose57: `8b33754483aed2a04c8be11ac9c42a062f6c6720cbd58316d3c4b4f236803eb9`
- The C++ chart competitor is the prior optimized C++ implementation, not Zig and not the separately built upstream native runtime control. Its [source identity](../../2026-11-04/leaf-and-loads/compiler-identity.json) and exact executable are retained. Upstream native-control build identity is in the compilation reference.

[Resident runtime](report.json) · [Five-build workload reference](compilation-reference.json) · [Compiler execution](compiler-comparison.json) · [Example builds/processes](examples.json) · [Host/AOT preparation](host.json) · [Metrics](metrics.json) · [Chart verification](chart-verification.json) · [Qualification](../../../../selfhost/results/2026-11-08/scalar-wasm-locals/summary.json)

The compilation reference's one-sample cold runtime observations qualify the newly built artifacts; the seven-sample resident report supplies runtime comparisons. C uses GCC/Clang `-O3 -march=x86-64-v3` with strict floating point and a one-thread queue; Goose uses a scalar port. Goose semantic passes use `-O2`. The complete workload build chart includes native C compilation/linking. Frontend-only compiler bars use the same input and standard library for all three compiler executables, ending after Wasm or standalone C emission.

The [capsule](reproduction.tar.gz) stores raw reports, exact binaries and emitted outputs, code and manifests as deduplicated SHA-256 objects. Extract `RESTORE.py` and run `python3 RESTORE.py reproduction.tar.gz /new/destination` to verify objects and restore every relative path and file mode. The separate [compiler qualification capsule](../../../../selfhost/results/2026-11-08/scalar-wasm-locals/README.md) supplies the frozen compiler sources and C-only bootstrap. Installed engine/compiler system libraries are fingerprinted rather than redistributed; restore the recorded tool versions before rerunning. Absolute recorded paths refer to the original workspace; supply restored paths to harness options.

```sh
python3 bench/langbench.py --goose build/bin/goose \
  --upstream-goose /path/to/upstream/goose --upstream-stdlib /path/to/upstream/stdlib \
  --samples 1 --compile-samples 5 --output-dir build/langbench-build-reference
python3 bench/langbench_hot.py --reference-report build/langbench-build-reference/report.json \
  --artifacts-dir build/langbench-build-reference/builds --samples 7 \
  --output-dir build/langbench-hot
python3 bench/compare_compilers.py --cpp /path/to/previous-cpp/goose \
  --parent /path/to/goose56 --parent-source /path/to/snapshot56/selfhost \
  --candidate build/bin/goose --candidate-source selfhost \
  --output-dir build/compiler-comparison
```

The restored public compiler re-emitted the exact measured Wasm hash; see the [capsule check](capsule-verification.json). See [validation.json](validation.json) for report and capsule hashes. The five focused benchmark test files passed 28 tests. All benchmark inputs were frozen before measurement; compiler qualification completed before this quiet window. Measurements share a host, retain filesystem caches, and cover these workloads only.
