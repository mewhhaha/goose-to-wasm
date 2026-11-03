# More levers

The [24-family performance campaign](FULL_PERFORMANCE_CAMPAIGN.md) tracks measured experiments and their qualification.

The [runtime targets](RUNTIME_TARGETS.md) compare the delivered compiler with fixed, separately built reference selections executed in fresh paired rounds. The selected native reference remains faster on several workloads; it is not a universal ceiling.

The [Functions investigation](FUNCTIONS_PERFORMANCE.md) removed duplicate snapshots in eligible tail-only callback forwarding and reduced module size; native-host process time still depends heavily on engine startup. The earlier campaign improved warmed Life, Sorting, Sudoku and hash. Remaining work includes generic Life stencil legality, physical layout under the exported-memory contract, and workload-specific native gaps. Binaryen O3 helped Life but regressed other workloads, so it remains a reference rather than a default pipeline. The [campaign tracker](FULL_PERFORMANCE_CAMPAIGN.md) retains measured tradeoffs and rejected experiments.

Freeze compiler and workload identities, qualify semantics, and collect interleaved confirmation pairs. Investigate regressions, module growth and compiler costs in both engines and unaffected controls.

## Example Wasm audit

The historical [audit](WASM_AUDIT.md) covers all ten examples. Leaf frames, bit counts, remainder and call specialization improved measured examples; [tuned native controls](NATIVE_PERFORMANCE.md) show further work remains.

## Native-host comparison

The [native Wasmtime host comparison](../bench/wasmtime-host.md) now measures
fresh compilation and explicit precompiled loading alongside the Python host.
Preparation and startup matter for one-off runs; the relative process times vary by workload. Host, callback and I/O differences also affect the comparison, which does not bound steady-state code generation. Serial compilation
was generally slower and remains a control rather than the default.

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
