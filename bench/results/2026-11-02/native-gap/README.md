# Prefix dispatch and startup — 2026-11-02

The final array-image dispatch uses a branch table, keeps fixed-prefix paths inline, and outlines ULEB handling until encountered ULEB types select an inline preference. Header dispatch, bounds and operation order remain intact. Across 12 hot-mode control cells, all 60 paired ratios exceeded 1, with median speedups of 1.26–3.61×; these samples do not establish confidence bounds. Seven paired fresh-process entry probes per cell measured sorting at 145.846 → 116.537 ms on V8 (1.254×) and 118.511 → 117.777 ms on Wasmtime (1.004×); maze improved 2.639× and Life 1.556× on V8, with Wasmtime entry times flat. Squares stayed byte-identical with flat entry time; its 0.881× process ratio illustrates launch noise. Instrumented process ratios are diagnostic, not ordinary launch-to-exit benchmarks.

Removing block watermarks was rejected: sorting on V8 slowed 3.7×. Sharing all non-raw image access through three helpers (base, length and write) added 12–18% to Wasmtime hot-prefix cost. A hybrid guard was also rejected: ULEB on V8 reached 0.838× and runtime-limited access on Wasmtime 0.909×.

A 15-pair Life build control investigated a noisy five-pair candidate build time. Complete build medians were effectively flat at 68.525 → 68.747 ms (0.988× paired, MAD 0.022); emitter medians fell from 0.523 to 0.430 ms (1.213× paired, MAD 0.035). This does not establish a general compilation speedup.

Separate startup controls measured native empty process 0.702 ms, `node -e` 19.999 ms, empty Goose on Node 26.850 ms, empty Python 9.212 ms, Python importing Wasmtime 43.862 ms and empty Goose on Wasmtime 78.134 ms. These are independent observations, not additive costs or hard bounds. They show why small whole-process examples have a host startup hill alongside generated-code work.

Astra reviewed the plan and implementation. Qualification passed 9,453 differential observations with 7,560 native stdout comparisons, plus 44 focused commands including the 60-build/100-execution example matrix. The ordinary ten-example cohort passed 1,600 observations. Sorting launch-to-exit medians were 157 ms direct on V8, 252 ms on Wasmtime and 50 ms native. The separate LangArena cohort passed 315 observations; all seven direct modules were byte-identical to the preceding cohort, so it establishes no kernel gain from this change.


## Evidence and reproduction

The [ordinary example cohort](../compact-examples/README.md) measures launch to exit without timing-file instrumentation. [LangArena results](langarena.md) use warmed computational regions. Exact configurations and samples are retained in the [paired entry probes](paired.json), [mode controls](mode-controls.json), [startup controls](startup.json), [compilation control](compilation-control.json) and [LangArena cohort](cohort.json). Rejected experiments are retained alongside them.

[Compiler identities](compiler-identities.json) · [Artifact comparison](artifact-comparison.json) · [Qualification](qualification.json) · [Differential observations](differential.json.gz) · [Archive map](archive-path-map.json.gz) · [Audit](review.json) · [Hashes](SHA256.json)

[Example inputs](example-inputs.tar.gz) · [Example samples](example-samples.tar.gz) · [Paired trials](paired-trials.tar.gz) · [Compiler source](compiler-source.tar.gz) · [Trial snapshots](trial-snapshots.tar.gz) · [Startup evidence](floor.tar.gz) · [Qualification logs](qualification.tar.gz) · [Differential shards](differential-shards.tar.gz) · [LangArena logs](langarena.tar.gz)

Differential shards retain per-case sources, commands, output, statistics and hashes of omitted rebuildable ELF/Wasm binaries. Compiler binaries are omitted; SDK source headers and pins are retained. The original ad hoc startup harness was not preserved, but exact commands, raw samples and empty artifacts are retained, with [proof that the final empty guest is byte-identical](startup-artifact-comparison.json).

The [reproduction scripts](reproduction/) retain paired, mode, build and qualification harnesses. Copy `measure_pairs.py` to `build/sorting-climb/`; mode, build and qualification scripts expect `build/native-gap/`. Restore the pinned inputs and qualified compiler installations, and use the commands and toolchain identities in the reports. Host load, engine tiering and fixed inputs limit these measurements.
