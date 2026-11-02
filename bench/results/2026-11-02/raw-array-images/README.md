# Raw array images · 2026-11-02

The compiler specializes array-image access for closed raw-only modules, excluding explicit public exports and nonintrinsic user imports so host memory edits remain authoritative. The ten example modules shrink from 412,112 to 275,693 bytes; eight lose their mode dispatch. [The audit](../../../../docs/WASM_AUDIT.md) lists every module and remaining opportunities.

Baseline compiler SHA-256 is `82b14bd7e795864606042853b13994e0fa8e6bddb22f02f9eef19d87849043e8`; final compiler is `78178c171d7ed846ac20aec7b54f5e2e80ffb5a73bbf3551c44b73b27b373624`. Nine paired entry probes per cell, backed by 100 builds and 400 runs, measured Sorting at 117.886 → 95.214 ms on V8 (1.240× paired, MAD 0.036) and 108.351 → 90.102 ms on Wasmtime (1.194×, MAD 0.080). Entry includes initialization, callbacks and potentially lazy JIT. Tour's unchanged module measured 0.857× on V8 (MAD 0.100), illustrating control variability. All ten final modules match the preliminary, paired and example artifacts byte for byte; eight changed from baseline.

Separately collected fresh process medians for Sorting were 107.472 ms ordinary native-host Wasm, 88.994 ms precompiled and 45.807 ms native C. Precompiled excludes its separately measured 30.805 ms preparation. Direct example cold builds took 61.302–112.922 ms versus 511.500–921.772 ms for C-to-Wasm. Earlier and current process cohorts are separate and do not establish paired speedups. See [host results](../../../wasmtime-host.md) for other examples and preparation costs.

The LangArena cohort passed 315 observations; all seven direct modules match the prior cohort, so no kernel gain is attributed to this change. Benchmark build and AOT hashes were rechecked against disk.

The compiler passed 9,573 differential observations including 7,656 native stdout comparisons, and 48 focused commands including a rerun of expanded tests. Native-host replay passed 11,484 observations across 3,828 case/backend/level units in default Wasm, serial Wasm and serial precompiled modes. Default precompiled mode separately passed twenty example artifacts and ten WAT methods across four modes; it did not receive the full replay.

[Paired probes](paired.json) · [Preliminary probes](preliminary-paired.json) · [Example builds](examples.json) · [Host results](host.json) · [LangArena cohort](cohort.json) · [Module sizes](module-sizes.json) · [Artifact comparison](artifact-comparison.json) · [Machine code](machine-code.json) · [Compiler identities](compiler-identities.json) · [Qualification](qualification.json)

The [baseline inventory](baseline-inventory.json), [baseline opcodes](baseline-opcodes.json), [candidate opcodes](candidate-opcodes.json), [differential report](differential.json.gz), and [host replay](host-qualification.json.gz) accompany retained archives, review and checksums.
