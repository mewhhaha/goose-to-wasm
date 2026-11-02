# Sorting execution · 2026-11-02

Four-way unrolling improves direct Wasm Sorting entry time on Wasmtime without an established V8 change. The source algorithm and workload are unchanged. Baseline commit `7957d3c` used compiler SHA-256 `3316710bb9d2b3100e94c2023000f0cb1b7517010ef04076314b4703fdcfcbba`; the new compiler is `82b14bd7e795864606042853b13994e0fa8e6bddb22f02f9eef19d87849043e8`. Both use Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, Wasmtime 50.0.1 and Node 24.22.1. The Wasmtime probes use the native C++ host.

The emitter generates one balanced loop iteration and copies it three times for eligible local-index loops, preserving conditions, stores, traps and cleanup order. Sorting's `insertion_sort` function body grows from 444 to 825 bytes; the whole Wasm module grows from 96,308 to 96,689 bytes, about 0.4%. The final module matches the retained four-way experiment SHA-256 `cd182e10e03dd0c0e4be69826119d5d6e96b1cad048b9ec8d4c70586778c0b26`. Squares, Sudoku, Maze and Life modules are byte-identical to baseline.

| Sorting entry, nine paired probes | Baseline median | New median | Paired speedup | MAD of ratio |
| --- | ---: | ---: | ---: | ---: |
| Wasmtime | 141.475 ms | 90.029 ms | 1.398× | 0.221 |
| V8 | 116.330 ms | 113.109 ms | 0.961× | 0.090 |

Entry includes initialization and host callbacks; it is not a pure kernel measurement. Samples checked output against the golden files. Four unchanged-module controls showed timing noise with no attributed gain. Six nearby source variants measured 1.146–1.473× on Wasmtime over five pairs. A weak V8 case repeated over 15 pairs measured 0.991× on V8 and 1.333× on Wasmtime.

The separately collected current-compiler build cohort measured direct cold builds at 63.093–89.827 ms versus 505.994–977.136 ms for C-to-Wasm. In the fresh native-host cohort, Sorting process medians were 138.141 ms ordinary direct Wasm, 93.519 ms precompiled direct Wasm and 47.638 ms native C. Precompiled excludes its separately measured 47.531 ms parallel preparation. See the [host comparison](../../../wasmtime-host.md) for the other examples and preparation accounting. The fresh LangArena cohort passed 315 observations; all seven direct modules were byte-identical to baseline, so no kernel gain is attributed to this change.

Profiles put both native and Wasm in insertion sort. Direct `&&` branches and nested guards improved Wasmtime by roughly 1.5×, and load CSE by roughly 1.15×, but each caused roughly 4× slower default V8 execution. Two-way unrolling also slowed V8; adding caching to four-way unrolling produced no additional Wasmtime gain. V8 traces and separate engine-flag controls support a tiering threshold explanation: the inner backedge charged 307 budget units at baseline versus 255 with CSE, approximately corresponding to bytes executed, while the global budget remained 13,000,000; the code optimized later. These controls are separate from the paired measurements above.

The current compiler passed 9,573 differential observations, including 7,656 native stdout comparisons, and 46 focused commands including 88 while-tail and partial-store checks. The native-host replay passed 11,484 observations over 3,828 case/backend/level units, covering default Wasm, serial Wasm and serial precompiled modes. Default precompiled mode was not part of that full replay; twenty example artifacts and public WAT unit tests across four modes passed separately.

## Evidence

[Paired measurements](paired.json) · [Nearby variants](nearby.json) · [Repeated weak case](nearby-repeat.json) · [Profile summary](profile-summary.json) · [Tiering controls](tiering-controls.json) · [Artifact comparison](artifact-comparison.json) · [Compiler identities](compiler-identities.json) · [Example builds](examples.json) · [Host measurements](host.json) · [LangArena cohort](cohort.json) · [README chart data](readme.json)

The rejected [branch](branch-paired.json), [guard](guard-paired.json), [load](load-paired.json) and [unrolling](unroll-controls.json) experiments retain their samples and controls. [Qualification](qualification.json), the [differential report](differential.json.gz) and [host replay](host-qualification.json.gz) record correctness coverage. Inputs, guest artifacts, samples, profiles and qualification logs are retained in the accompanying archives; [checksums](SHA256.json) and [review](review.json) cover the evidence package.
