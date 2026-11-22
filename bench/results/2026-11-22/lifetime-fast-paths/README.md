# Lifetime fast paths and frame dependency skipping

Precomputing per-type, per-symbol and per-node lifetime flags, eliding inert scalar operations and cells, tracking clean concrete frames across discovery passes, indexing live reference holders with a bitmap and caching shrink/walk/global-capture checks cut lifetime checking time roughly in half on frozen source `9a6040a`: **−50.1%** in cached Wasmtime (0.901 s → **0.449 s**) and **−52.9%** native (0.795 s → **0.379 s**). Full rebuilds fell **26.1%** in cached Wasmtime (1.775 s → **1.314 s**, −28.8% instructions) and **27.3%** native (1.511 s → **1.107 s**, −30.6% instructions). The new balanced Wasmtime compiler rebuilt the frozen project **13.5% faster** (0.865× paired elapsed time, 0.759× instructions, 7/7 pairs) than the previous `766898a` native compiler. [Profiles](profiles.json) · [Paired rebuilds](rebuilds.json) · [All samples](samples.json.gz) · [Training profile](training.profile)

![Module sizes and cold and cached rebuild times before and after lifetime fast paths](release.svg)

## Changes in `selfhost/checker_lifetimes.goose`

- **Precomputed lifetime flags (`life_prepare_nodes`, `life_analyze_node`):** classifies types (`TF_L_*`), non-address-taken scalar locals/parameters (`SF_SCALAR_LOCAL`), scopes containing live cells (`scope_has_cell`), pure-place/shrink-free/inert expressions (`NF_PURE_PLACE`, `NF_MAY_SHRINK`, `NF_INERT`) and acyclic inert helper functions (`NF_FN_INERT`).
- **Void-returning evaluator (`life_eval_void`):** evaluates statements, conditions and discarded operands without constructing or copying 72-byte `LifeValue` records, and forwards a block's `receiving` destination only to true `F_TAIL` expressions.
- **Discovery frame dependency skipping (`life_frame_is_clean`, `dep_roots`, `dep_callees`):** records roots read and callees invoked by clean non-recursive concrete frames and skips re-evaluating unchanged frames in later discovery passes while replaying their summaries.
- **Live holder bitmap & shrink/walk/capture epochs (`live_holder_bits`, `live_holder_words`, `shrink_clean`, `walk_memo_roots`, `global_live_epoch`):** scans only live holder cells on array shrinks and loop entries, memoizes negative shrink checks by `holder_grow_epoch`, expands `held_walks` memoization up to 32 roots with epoch validation, avoids allocating global-capture snapshots when unchanged (`life_global_captures_match`), and skips redundant `life_grow` hold scans when `build_holds == 0`.

## Full builds on a frozen project

Measured on frozen source `9a6040a` on CPU 7 (Ryzen 7 3800X) with primed Wasmtime 50.0.1 caches (`host/rust/target/release/goose-wasmtime`, SHA-256 `b247393d...`). Every run verified deterministic 6,594,988-byte portable memory64 output (SHA-256 `3e3d7d8a...`). Both native compilers were built with `scripts/bootstrap.py --verify`; both bundled memory32 Wasm releases were built with `--wasm-bundled-host --wasm-initial-pages 65535 --wasm-max-pages 65535` and a release-specific region layout profile trained on `squares`, `sorting` and `tour`.

| Release | Raw Wasm | Gzip | Cold rebuild | Cached rebuild |
| --- | ---: | ---: | ---: | ---: |
| Previous balanced (`766898a`, `ced8e84e`) | 2.78 MB | 0.82 MB | 3.95 s | 1.74 s |
| Lifetime fast paths, balanced (`ec34ff9b`) | 2.85 MB | 0.84 MB | **3.57 s** (−9.1% paired) | **1.30 s** (−25.4% paired) |
| Lifetime fast paths, size (`046c08aa`) | 2.45 MB | 0.69 MB | 4.02 s (+2.9% paired) | **1.30 s** (−26.7% paired) |

| Cached, 7 alternating pairs (frozen `9a6040a`) | Before median (`766898a`) | After median | Paired elapsed ratio | Paired lifetime ratio | Paired instruction ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wasmtime balanced | 1.775 s (13.765 B instr) | **1.314 s** (9.799 B instr) | **0.739×** (7/7 faster) | **0.499×** (−50.1%) | **0.712×** (−28.8%) |
| Native | 1.511 s (12.913 B instr) | **1.107 s** (8.959 B instr) | **0.727×** (7/7 faster) | **0.471×** (−52.9%) | **0.694×** (−30.6%) |
| Wasmtime after / Native before | 1.511 s (12.913 B instr) | **1.314 s** (9.799 B instr) | **0.865×** (7/7 faster) | **0.560×** (−44.0%) | **0.759×** (−24.1%) |
| Wasmtime after / Native after | 1.107 s (8.959 B instr) | 1.314 s (9.799 B instr) | 1.174× | 1.172× | 1.094× |

On the current compiler's own source (`selfhost/main.goose`, 7 alternating pairs on CPU 7), the balanced Wasmtime compiler took **1.243 s** (`life = 0.464 s`, 9.002 B instr) vs **1.013 s** native (`life = 0.385 s`, 8.022 B instr) — a **1.23×** paired elapsed ratio (**1.12×** instructions), with both compilers emitting identical 4,518,926-byte portable memory64 Wasm (`4f93609e...`).

## Qualification

- C bootstrap (`scripts/bootstrap.py --verify`) reached a fixed point (`579671fb...`).
- Native and balanced 32-bit Wasm compilers rebuilt the bundled 32-bit direct compiler byte-for-byte (`1b22b4b4...`, 3,743,151 bytes).
- Default conformance: **10,697/10,801** (104 recorded gaps, 0 unexpected failures).
- Memory64 conformance: **4,771/4,779** (8 recorded gaps, 0 unexpected failures).
- Native runtime checks: **54/54** passed.
- Unit tests: **101/101** passed (2 skipped).
- Output equivalence (`tests/output_equivalence.py`): **10,060/10,061** matched identically. The single difference is `upstream:test/errors_tc/byteview_cycle_holder.goose`, where both compilers reject the invalid program (exit 1) and the candidate reports the actual escaping store at line 5:47 (`out.bytes = h.bytes`, matching upstream's test annotation) instead of baseline's line 8:23 (which stemmed from `life_eval_block` forwarding a `void` caller's destination into a non-tail `;` statement).
- Proof & diagnostic sweep across **4,519** corpus, fixture and selfhost sources (`LIFE_CONCRETE_FRAMES = 4096`): **4,518/4,519** matched exported provenance hashes and diagnostics identically, with only the same `byteview_cycle_holder.goose` diagnostic improvement. At forced `LIFE_CONCRETE_FRAMES = 16`, all 4,519 exit codes and diagnostics matched (modulo `byteview_cycle_holder.goose`), with 4 small fixtures remaining concrete slightly longer because inert helper functions no longer allocate frames.
- Measured with [measure_batch2.py](measure_batch2.py) and plotted with [plot.py](plot.py).

## Reader benchmarks

All five reader suites were refreshed against the qualified `f7ae491` compiler (`ea53dd6d...`) using Node `24.22.1` (V8 `13.6.233.17-node.58`), Wasmtime `50.0.1`, GCC `16.2.1` and Clang `23.1.5`:

- **Cold and cached launches:** Three fresh-process rounds on CPU 3 (8-core cold preparation on CPUs 0–7) using frozen `f7ae491` sources and the release layout profile. The fixed 32-bit bundled compiler took **1.71 s cold** (8 cores) and **1.23 s cached** (1 core) vs **1.05 s native**; 64-bit cold took 6.90 s (1 core) / 2.97 s (8 cores), 64-bit cached 2.32 s and bundled 64-bit cached 1.91 s. [All launches](launch.json) · [Chart](launch.svg)
- **Eleven-program compiler catalog:** All 44 cells (31 samples per cell on CPU 2) qualified and emitted byte-identical Wasm and C outputs between `766898a` and `f7ae491`. Geometric-mean compiler CPU time changed by **+3.4%** (95% CI +2.1% to +4.4%) for direct Wasm and **+2.1%** (95% CI +1.0% to +3.5%) for C emission — capturing the fixed `life_prepare_nodes` setup cost on short ~5–15 ms inputs (while `sorting` improved −1.1% Wasm / −2.5% C). [Compiler catalog](compiler-comparison.json.gz) · [Intervals](catalog-summary.json) · [Chart receipt](compiler-chart.json)
- **Portable self-hosting:** Three builds and three execution rounds on frozen `f7ae491` sources (CPU 4; Clang 23 builds on CPUs 1, 3, 5, 7) using the bootstrapped `f7ae491` emitter. Building took **1.01 s** for portable Wasm and **18.98 s** through C and Clang with byte-identical outputs across all three rounds. Checking took **0.68 s** native, **1.65 s** Wasmtime and **2.15 s** V8; emitting `compiler.wasm` took **1.09 s** native, **2.31 s** Wasmtime and **2.74 s** V8 (byte-identical across all three engines). [Portable build and execution](selfhost.json) · [Chart receipt](selfhost-chart.json)
- **Ten example programs:** All 100 cold builds (5 samples per cell on CPU 3; **62.7–80.9 ms** direct Wasm, **0.300–2.236 s** through C) and 360 native-host process runs passed output checks. The initial CPU 3 native-host run saw transient background contention on the unchanged native-C control (`sorting` 240 ms vs 124.8 ms in `examples.py`), so the native-host suite was repeated cleanly on CPU 7: `sorting` took **113 ms** in minimal precompiled Wasmtime (**115 ms** full precompiled) vs **131 ms** native C, and `sudoku` took **7.6 ms** minimal precompiled vs **6.6 ms** native C. [Example builds](examples.json.gz) · [Process timings](host.json.gz)
- **Langbench Mandelbrot:** All 30 builds (5 rounds on CPU 1; direct Wasm **4.4 ms**, Goose native **365.3 ms**, GCC C **64.0 ms**, Clang C **75.2 ms**, upstream Goose `2e2bedef` **222.0 ms**) and 7 resident samples per engine passed official checksum verification. Official resident medians: **2.70 s** native, **2.86 s** Wasmtime, **2.88 s** V8, **2.59 s** GCC C, **2.74 s** Clang C and **2.70 s** upstream native Goose. [Mandelbrot builds](langbench-build.json) · [Build chart receipt](langbench-chart.json) · [Resident runs](langbench-hot.json.gz) · [Resident chart receipt](langbench-hot-chart.json) · [CPU pressure](reader-pressure.json)

All timed example and Mandelbrot builds executed the pinned `f7ae491` compiler binary (`ea53dd6d...`); ambient working-tree fingerprints in `examples.json.gz`, `host.json.gz` and `langbench-build.json` reflect concurrent unstaged edits present in `selfhost/{codegen,optimizer,wasm}.goose` during those runs.
