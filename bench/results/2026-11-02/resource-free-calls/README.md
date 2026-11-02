# Resource-free calls · 2026-11-02

Proven resource-free recursive and fixed-reference calls omit frames, including numeric inline occurrences. The initial SCC-only experiment `f0d` changed none of the ten example modules; numeric inline support was needed. The final compiler changed only Sudoku, shrinking its module from 11,953 to 10,966 bytes.

Fifteen paired full-example entry probes gave separate Sudoku medians of 12.137 → 6.009 ms on V8 and 3.757 → 2.992 ms on Wasmtime. Median paired speedups were 1.642× (MAD 0.326) and 1.259× (MAD 0.032), respectively; these are not quotients of the separate medians. Entry includes initialization, callbacks and possible lazy JIT. The other nine example modules were byte-identical; their timing changes are noise.

Nine fresh paired warmed rounds across ten workloads used the original reference selections without reselection. They measured the Sudoku adapter at 1.066× baseline/current (MAD 0.002), with current direct/selected-native ratio 1.801×. The warmed run contains 415 executions. [Runtime targets](../../../../docs/RUNTIME_TARGETS.md) describes the workload and adapter boundaries; the [original reference cohort](../runtime-targets/README.md) retains the frozen selections.

The fresh headline cohorts passed 1,600 example observations, 1,440 host observations and 315 LangArena observations, alongside 200 host preparations. All seven direct LangArena modules were unchanged, so no kernel gain is attributed to this change.

All 53 focused gates passed. Differential qualification passed 9,573 observations across 978 cases, with no failures and 7,656 native stdout comparisons. Native-host qualification passed 11,484 replays over 1,574 unique modules in three modes. Default AOT did not receive the full replay; ten WAT unit methods and twenty example artifacts cover it separately in the fresh host report.

[Full-example pairs](paired.json) · [Warmed pairs](warmed-paired.json) · [Rejected SCC experiment](rejected-paired.json) · [Compiler identities](compiler-identities.json) · [Artifact comparison](artifact-comparison.json) · [Qualification](qualification.json) · [Differential report](differential.json.gz) · [Host replay](host-qualification.json.gz)

[Examples](examples.json) · [Host](host.json) · [LangArena](cohort.json) · [README data](readme.json) · [Target chart verification](target-chart-verification.json) · [Chart verification](chart-verification.json) · [Archive index](archives.json.gz) · [Source map](source-map.json) · [Artifact map](artifact-map.json) · [Retention](retention.json) · [Review](review.json) · [Checksums](SHA256.json)

The archives retain inputs, guest artifacts, samples, qualification logs, disassembly and charts. Full-replay and differential guest bytes and compiler/tool binaries are omitted; identities remain in the reports. Frozen first-cohort guests are referenced by hash.
