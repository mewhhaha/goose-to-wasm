# Guarded merge loops · November 3, 2026

Compiler SHA-256 `b53aaf097e0ea47b3f3efea158db3520aa03f9ab1fb1625efd21fff31d49319d` is compared with `1b1ec504894d387ae0bbed287d2d3214e250e6dc9bbff2ffd2893a69c06a8874` on a shared AMD Ryzen 7 3800X. Goose upstream is `2e2bedef5b980bf013cac5aaa0095bfea64e5569`; Wasmtime is 50.0.1 and Node is 24.22.1 / V8 13.6.233.17-node.58. The native host is unchanged from the [prior runtime-stencil cohort](../runtime-stencil/README.md). The full native host uses the static SDK; the warmed reference host and Python bindings are separately frozen builds at the same Wasmtime version.

Eligible two-cursor merges over 32- or 64-bit integer slices with stable local views and cursors check complete logical and physical source and destination spans before a branchless loop. It retains the original comparison, loads both candidates, selects the stored value and advances the appropriate cursor. The fast path preserves overlap behavior and access order. Failed guards and debug builds retain the scalar loop, including partial effects on traps. The [runtime investigation](../../../../docs/RUNTIME_PERFORMANCE.md) describes the implementation and tradeoffs.

In nine paired warmed rounds, Merge fell from 2,114.235 to 1,544.564 ms on Wasmtime, a paired 1.369× speedup (MAD 0.059), and from 1,911.894 to 1,463.426 ms on V8, 1.308× (MAD 0.009). The selected native reference took 1,104.079 ms in the Wasmtime paired cohort. The other nine kernel guests are byte-identical; V8 Life measured 0.965× (MAD 0.044), illustrating control variation. The insertion-sort adapter is unchanged. These are warmed kernel timings, not full Sorting process results. [Wasmtime](final-warmed.json) · [V8](final-v8.json) · [Reference selections](references.json)

Only the full Sorting example module changed, from 48,269 to 48,582 bytes; its merge body grew from 995 to 1,308 bytes. The Merge port grew from 5,214 to 5,527 bytes, with the same body increase. The insertion adapter remains 11,184 bytes. [Module analysis](module-analysis.json)

A guard-only variant was rejected after V8 elapsed time rose 19%. A minimum span of 16 gained about 1.5% on Wasmtime over the selected variant but raised V8 elapsed time 3.9%; neither mechanism was isolated. A resident-host InstancePre experiment saved about 2 µs of preparation but gave only 1.005× round-trip speedup (MAD 0.029) over 201 paired Functions requests and was rejected. The selected branchless strategy resembles the selected native Clang output. [Campaign and experiments](campaign.json)

Fresh results include 5,065 runtime and build observations plus 200 host preparations. [Examples](examples.json) · [Host](host.json) · [LangArena](cohort.json) · [Lifecycle](lifecycle.json). Reference artifacts were built earlier and executed freshly in paired Wasmtime blocks. Fresh-process launches include startup; precompiled execution excludes preparation, while resident-worker timings exclude process startup. Sorting native C measured 47.726 ms in the host cohort and 70.111 ms in the lifecycle cohort using the same binary; the unpaired difference illustrates cohort variation.

Qualification passed 74 focused gates, 9,573 differential executions including 7,656 native comparisons across 978 source cases, 11,484 host replays across 1,574 unique Wasm modules, and 3,001 effective worker observations across 3,828 aliases. [Focused qualification](qualification.json) · [Differential](differential.json) · [Host qualification](host-qualification.json) · [Worker qualification](worker-qualification.json) · [Compiler identity](compiler-identity.json).

New archives reuse exact byte objects from 16 bounded prior physical archives; aliases and document namespaces are not inherited, and all measurements are fresh. [Retention details](retention.json) and the [archive index](archives.json.gz) describe the package. Verify offline from the repository root:

```sh
python bench/results/2026-11-03/merge-bounds/reproduction/verify.py
```
