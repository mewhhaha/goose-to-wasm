# More levers

There is substantial headroom in code generation, compilation work and language
coverage. The current evidence covers seven adapted LangArena workloads and ten
example programs on one machine; it does not establish a Goose or WebAssembly
ceiling. V8 first-call behavior and generated code size remain hills.

At compiler commit `f3b6117`, CRC32 takes about 10–12% longer than C-Wasm.
Custom hash takes about 1.6× native C time. Merge sort takes 2.165 seconds on
V8 versus C-Wasm's 1.458, while direct Wasm is faster on Wasmtime. These are
configured iteration counts from the same [measured cohort](../bench/results/2026-11-01/lanes/README.md),
with memory32 direct modules and memory64 C-Wasm modules.

## Ranked implementation hills

Astra reviewed these source paths at xhigh effort. These are proposed
experiments; none has a claimed speedup yet.

| Order | Lever | Existing work to remove | First measurement and safety gate |
| --- | --- | --- | --- |
| 1 | Zero-filled array construction | `AggregateLiteral` zeroes a fresh frame image, writes each zero again, then declaration initialization copies the image. | First remove only the redundant element stores for exact integer-zero literals. Preserve frame reservation, fill-value evaluation and copy order. Measure startup separately from timed kernels, module size and emission. Direct construction into the destination needs a later alias/lifetime proof. |
| 2 | Wider bulk fills and copies | `FillLoop` handles bytes; merge sort clears an integer buffer and copies slices repeatedly. | Start with integer-zero fills using widened byte counts and the existing scalar fallback for invalid physical ranges. Later try disjoint copy loops. Test overlap, empty slices, partial traps and overflow; preserve forward-copy behavior when buffers overlap. |
| 3 | Sparse compiler storage | `Compiler::Data` allocates and zeroes dense storage for large globals; `SparseDataSegments` scans it again. | Separate logical extent from initialized bytes. Require identical addresses, memory checks and module bytes. Measure emitter time and allocation against increasing static sizes. This is not an established explanation for the latest 0.23 ms CRC emitter regression. |
| 4 | Hash lane write-back | The current cache still performs every memory store. | A fast path needs valid input ranges, disjointness from cached arrays, no other aliasing effects and a nontrapping body, including debug arithmetic and conversions. Keep today's write-through path otherwise. Measure register pressure and duplicated code as costs. |
| 5 | Packed CRC basis terms | Eight independent selections remain. | Try two adjacent bits packed into instruction immediates for u32, retaining today's u64 path and exact recurrence matcher. Check arbitrary polynomials. Larger constants and register pressure may erase the gain. |
| 6 | Build invocation overhead | Complete driver builds take 73–82 ms; actual compiler phases are much shorter. | Compare the native CLI, Python driver and persistent worker on identical sources and artifacts. Separate launch, dependency publication and compilation. Improve the integration before adding another optimization pass. |

The relevant implementation is in [expression lowering](../compiler/direct_wasm_expr.h),
[static allocation](../compiler/direct_wasm.h) and
[data-segment emission](../compiler/wasm_binary.h). Scratch-local pooling is
deferred: persistent bindings, cleanup values and results need a stronger
lifetime analysis before slots can be reused safely.

Freeze each compiler and workload, inspect the changed artifacts, then collect
at least five interleaved pairs. Look for repeatable gains of at least 5%;
investigate regressions above 3%, module growth and compiler-phase costs.
Run both engines and unaffected controls. A kept compiler change must pass the
full differential and boundary gates, refresh the README cohort and retain its
experiments, including rejected ones.

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
