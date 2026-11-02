# Execution boundaries · 2026-11-02

These diagnostic probes reuse the example artifacts from the [native-host report](../wasmtime-host/report.json) and the [earlier example cohort](../compact-examples/report.json). They use the same compiler, but were collected separately from the headline runtime chart. The phase report contains 400 launches across 50 cells, with one warmup and seven measured launches per cell. Artifact hashes were checked before and after phase collection; [identities](identities.json) records the inputs and source reports. The table compares direct Wasm with native C.

| Measurement | Median | MAD |
| --- | ---: | ---: |
| Sorting, ordinary Wasm setup | 37.012 ms | — |
| Sorting, ordinary Wasm `_start` | 117.940 ms | 0.728 ms |
| Sorting, native `main` | 45.740 ms | 0.864 ms |
| Sorting, precompiled Wasm setup | 0.396 ms | — |
| Sorting, precompiled Wasm `_start` | 134.983 ms | 11.842 ms |
| Squares, precompiled Wasm setup | 0.274 ms | — |
| Squares, precompiled Wasm `_start` | 0.021 ms | — |

All seven ordinary Sorting Wasm entry samples exceeded all seven native `main` samples. Precompiled Sorting entry was noisy, ranging from 117 to 147 ms; this does not establish that precompilation slows execution. The separately collected headline precompiled Squares process median was 2.233 ms, showing how much startup matters for that small example.

Wasm setup excludes reading the Wasm file and configuration, but includes AOT artifact reading, engine and store creation, module loading or compilation, linking and instantiation. Wasm `_start` includes initialization and callbacks but excludes final buffered host stdout delivery. The Linux preload wrapper measures returning native `main`, including initialization and unbuffered stdout. Neither entry boundary is a pure kernel measurement.

Life's native phase median was 34.587 ms, unlike the separately collected 18.572 ms headline process median, and its phase samples were bimodal. A separate 15-pair timer control measured ordinary and instrumented Life at 17.870 and 18.270 ms, with a paired ordinary/instrumented ratio of 0.988 (MAD 0.035). Sorting's control medians were 46.146 and 45.712 ms, with ratio 0.998 (MAD 0.037). These controls do not show a stable twofold instrumentation penalty; the cause of the Life variation is unknown. Control input identities were recorded at archival time only.

There is no universal twofold Wasmtime cost in these results: startup and execution both matter, with different effects by workload. The paths use the same algorithm but differ in lowering, memory layout and GCC versus Cranelift machine code. Both retain language bounds checks unless frontend analysis proves them redundant. The probes do not identify a single cause of the execution gap.

## Retained evidence

[Phase probes](phase-probes.json) · [Timer control](timer-control.json) · [Identities](identities.json) · [Chart verification](chart-verification.json) · [Review](review.json) · [Checksums](SHA256.json)

The archives contain [diagnostic inputs](diagnostic-inputs.tar.gz), [phase samples](phase-samples.tar.gz), [timer-control samples](timer-control-samples.tar.gz), and [charts](charts.tar.gz); [runtime preview](runtime-preview.png) records the rendered chart. To revisit the original diagnostics, extract the inputs archive at the repository root. Its scripts retain their original `build/benchmark-refresh` paths and require the prior artifacts; they are not a portable standalone benchmark.
