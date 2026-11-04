# More levers

The [24-family performance campaign](FULL_PERFORMANCE_CAMPAIGN.md) tracks measured experiments and their qualification.

The [runtime targets](RUNTIME_TARGETS.md) compare the delivered compiler with fixed, separately built reference selections executed in fresh paired rounds. The selected native reference remains faster on several workloads; it is not a universal ceiling.

The [Functions investigation](FUNCTIONS_PERFORMANCE.md) removes redundant private aggregate snapshots. Guarded branchless merge improves the measured Merge kernel; an earlier stencil lowering improved the Life adapter, while native runtime caching and resident sessions target repeated launches. Remaining work includes physical layout under the exported-memory contract and workload-specific native gaps. Guarded positive-stride store grouping and SIMD byte-equality scans are qualified and improve the measured Sieve port. Branchless last-match selection and two-vector grouping improve the measured scan; width alone has a smaller, less consistent effect. Binaryen O3 helped Life but regressed other workloads, so it remains a reference rather than a default pipeline. The [campaign tracker](FULL_PERFORMANCE_CAMPAIGN.md) retains measured tradeoffs and rejected experiments.

The [leaf and loads campaign](../bench/results/2026-11-04/leaf-and-loads/README.md) expands eligible straight-line void leaf calls in recursive callers and combines width-eight byte loads. Paired Wasmtime results improved 1.23× for Quicksort and 1.25× for custom hash; V8 was essentially flat. Quicksort grew 124 bytes, hash shrank 13 bytes, and all ten full example modules were byte-identical to the baseline. Sentinel SIMD and tail-recursion work remain open.

Freeze compiler and workload identities, qualify semantics, and collect interleaved confirmation pairs. Investigate regressions, module growth and compiler costs in both engines and unaffected controls.

## Example Wasm audit

The historical [audit](WASM_AUDIT.md) covers all ten examples. Leaf frames, bit counts, remainder and call specialization improved measured examples; [tuned native controls](NATIVE_PERFORMANCE.md) show further work remains.

## Native-host comparison

The [native Wasmtime host comparison](../bench/wasmtime-host.md) measures uncached compilation, SDK caching, precompiled loading and resident sessions alongside the Python host. A minimal AOT companion reduces host size and reduced paired Functions process time by 23.6%; it requires trusted artifacts prepared with its matching profile. Preparation and startup matter for one-off runs. Host, callback and I/O differences also affect the comparison. Serial compilation was generally slower and remains a control rather than the default.
The Functions compiler projection removed 56 copies and 921 Wasm bytes without a measurable runtime gain, so it was rejected. Lazy input v3 was also rejected after the primary workload remained flat. The [minimal AOT record](../bench/results/2026-11-04/minimal-aot/README.md) retains the experiments, corrected timing method and tradeoffs.

## Language and host coverage

The [upstream sample survey](../bench/results/2026-11-01/examples/upstream-survey.json)
compiled all 31 samples at Goose O2 using the pinned upstream revision
`2e2bedef5b980bf013cac5aaa0095bfea64e5569`. Only maze and Life compiled
unchanged for the direct target. This is a compile survey, not runtime
qualification or a percentage of language support; fixing a first refusal can
reveal another.

The first refusals include formatting/string construction, aggregate comparison,
relative/pool references, complex variable layouts and host functions taking
slices or pointers. Threads, graphics and UI also require host support.
The [target contract](TARGET.md) records the supported forms.

The new [example catalog](../examples/README.md) separates unchanged programs
from adaptations. It gives the next implementation passes broader real
programs to measure without presenting adapted examples as full Goose parity.
