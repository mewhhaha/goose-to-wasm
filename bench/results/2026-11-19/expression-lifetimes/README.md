# Expression lifetimes in a compiler rebuild

On the frozen project, Wasmtime rebuild time fell by **1.7%** across 16 paired rounds. The same-round Wasmtime/native ratio went from **1.57× to 1.54×**. Rebuilding the new compiler on its own sources took **3.757 s** in Wasmtime and **2.454 s** native across 14 rounds. [Frozen project](frozen.json) · [Current compiler](current.json)

![Seconds to rebuild the compiler in native and Wasmtime processes](rebuild.svg)

| Frozen project, median | Previous native | Current native | Previous Wasmtime | Current Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| Process wall time | 2.346 s | 2.345 s | 3.687 s | 3.611 s |
| Process CPU time | 2.328 s | 2.327 s | 3.660 s | 3.584 s |
| Instructions retired | 21.849 billion | 21.777 billion | 34.222 billion | 33.522 billion |
| Peak resident memory | 437.5 MiB | 437.6 MiB | 707.5 MiB | 706.6 MiB |

The project was frozen at `34ddff8`. The previous compiler was `06c84ac` and the new compiler is `6e503fb`. Wasmtime 50.0.1 loaded a precompiled, bundled memory32 compiler. Native used Clang 23.1.5 at `-O2`. Every fresh process parsed, checked and compiled the project and wrote the same 8,886,107-byte memory64 module. The two layouts were trained independently on squares, sorting and tour. [Compiler and tool hashes](verification.json) · [Current training profile](training.profile)

The two eight-round series started in opposite orders on CPU 7 of a shared Ryzen 7 3800X. The first measured 3.838 → 3.772 s in Wasmtime and the second 3.676 → 3.540 s. Wasmtime was faster in 14 of 16 pairs. Median native time changed by +0.1% within pairs. Chart bars show pooled wall-time medians. The current-source result uses two seven-round series with the order reversed between series. Absolute times vary with other work on the host. [Individual series and hardware counters](rebuild-series.json.gz)

## What changed

The lifetime checker first discovers how functions affect their callers, then validates individual uses. It used to save held operands and upcoming expressions in both passes. Only validation reads those records. Skipping them during discovery avoided **823,506 held operands and 720,840 upcoming expressions** in one self-check. The checker also returned early for **813,106** values whose type already matched and whose contents needed no conversion. [Activity counters](operations.json)

A shared empty expression result supplies the defaults for a 72-byte record. In the two main evaluators, this reduced executed zero-fill lengths from **338.4 MB to 20.0 MB** per check. Their executed copy lengths remained **1,627.0 MB**, including **1,480.8 MB** at 72 bytes per copy. These totals count Wasm instruction operands. CPU cache traffic and elapsed time are measured differently. Checking and emission produced the same counts for these two functions. [Per-site counts and memory32/64 controls](copies.json.gz)

| Compiler phase on frozen source | Previous native | Current native | Previous Wasmtime | Current Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| Parsing | 0.055 s | 0.055 s | 0.096 s | 0.095 s |
| Type checking, excluding lifetimes | 0.234 s | 0.239 s | 0.407 s | 0.403 s |
| Lifetime analysis | 1.521 s | 1.525 s | 2.366 s | 2.256 s |
| Optimization | 0.146 s | 0.146 s | 0.260 s | 0.258 s |
| Wasm emission | 0.522 s | 0.515 s | 0.824 s | 0.845 s |

Lifetime analysis accounts for 2.256 s in Wasmtime and 1.525 s native on the frozen source, a **0.730 s** gap. Phase clocks and peak memory come from five separate rounds on CPU 5. In a separate three-round self-check sampled every 2 ms of CPU time, the largest excess among named lifetime functions was `life_replay` (+209 samples), `life_eval` (+154 samples), `life_eval_body` (+151 samples). Some addresses have no symbol, and compiler inlining can change how samples are attributed. [Phase and memory samples](phases.json) · [CPU profiles](profiles.json.gz)

## Experiments left out

Writing the returned value directly into caller-provided storage removed **323.5 MB** of evaluator copies per check. Flattening that path removed **355.4 MB**. Across five paired rebuilds those strategies changed Wasmtime wall time by **−0.9%** and **−0.7%**, respectively. Expanding fixed-width copies into scalar loads and stores increased elapsed time by 2.8% for 72-byte copies. The SIMD trial at widths up to 96 bytes lowered retired instructions by 2.4% and increased elapsed time by 2.2%. The compiler keeps its existing calling convention. [Eleven experiment series](screens.json.gz) · [Source patches and probing scripts](experiments.tar.gz)

## Can the checker skip groups of reads?

In a frozen self-check, the compiler visited **8,235,771 read entries** while replaying the effects of earlier function calls. The caller had already received 1,852,489 at their current version and already knew another 4,486,327 individually. Of the version-covered entries, 1,618,977 fell in uninterrupted runs of at least 16. A group can be skipped together if every read is covered and the jump stays before the next interleaved effect. [Run lengths and per-candidate counts](replay-trials.json.gz)

| Fixed memory32 experiment, four pairs per order | First order | Reversed order | Retired instructions |
| --- | ---: | ---: | ---: |
| Return early on a completed, empty replay | +3.7% | -7.6% | -0.2% |
| Keep traversal fields together | +7.6% | -10.6% | -0.0% |
| Compare the exact caller stamp first | -5.8% | -16.6% | +0.1% |
| Combine all three changes | -6.8% | -13.6% | -0.0% |

The exact stamp matched **2,099,033 of 6,383,282** comparisons. Another ten rounds on CPU 7 gave +0.6% and -2.9% for the stamp shortcut across the two orders. A further twelve rounds included the identical release binary under a second label. The duplicate changed by +4.5% and -0.8% against the original. The stamp trial changed by +3.5% and -1.1% against the original and -3.8% and -0.3% against the duplicate. The four-pair exploratory results overlapped the launch benchmark on the shared machine. The larger apparent gain did not repeat in the control runs.

Grouping affected both traversal and storage. The three grouped compilers each exhausted a data region on the full frozen rebuild with the shipped layout, and again after separately sizing their regions from squares, sorting and tour. A fourth prototype reused the existing lookup array for group metadata and exhausted the region while appending a read under its own example-trained layout. The default memory64 layout had enough room to time all three against the release compiled for that same layout.

| Experimental memory64 compiler | Fewer read visits per self-check | First three pairs | Reversed three pairs | Retired instructions |
| --- | ---: | ---: | ---: | ---: |
| 16 adjacent entries | 272,393 | +0.5% | -9.1% | +0.3% |
| 16 reads from one call frame | 1,227,664 | -2.5% | +6.1% | +0.3% |
| 64 reads from one call frame | 663,925 | +0.1% | +4.3% | +0.4% |

For a separate memory32 comparison, both compilers sized their regions from peak use while compiling a separate compiler revision (`06c84ac`). The timed project was still `34ddff8`. Grouping 16 reads from one call frame changed median paired rebuild time by **-0.9%** (-0.3% and -5.9% across the two orders) and retired instructions by **+0.2%**. On one self-check this grouping maintained metadata for 1,003,113 appended reads and 6,332 changed leaves. It tested group membership 624,825 times and jumped 81,907 times. The release keeps the smaller per-read representation. The next candidate is reducing the number of per-frame entries created during discovery. Every successful timed process emitted the same 8,886,107-byte module. [Paired runs, capacity failures, compiler hashes and counters](replay-trials.json.gz) · [Patches and sizing profiles](replay-patches.tar.gz)

## Cold and cached self-compilation

![Cold and cached compiler process times](launch.svg)

Across three fresh processes per configuration, the default memory64 compiler took 18.17 s cold on one core and 8.29 s with eight cores available to Wasmtime. The bundled memory32 compiler took 5.39 s cold and 4.06 s cached, versus 2.58 s native. Cached engine preparation and instantiation took 5.3 ms. An edited source produced a distinct verified module in 4.32 s cached and 2.75 s native. [Launch, edit and preparation samples](launch.json)

## Qualification

All 10,057 compiler output comparisons matched. The test suites retained the 104 known default gaps in 10,797 rows and eight memory64 gaps in 4,777 rows. All 54 native checks and 90 unit tests passed. The compiler reproduced its generated C and its fixed and portable Wasm modules. The previous and new checkers matched on 11,596 ordered lifetime fingerprints across 4,357 sources, plus 14 on the compiler itself and two forced class-frame cases. [Qualification, compilers and fingerprints](verification.json)

An independent checker with replay caching disabled matched all ordered diagnostics and state on 29 additional fixtures. Three upstream Goose programs compiled and ran with matching output. Four failing upstream programs were rejected by upstream and both releases. Native diagnostics matched byte for byte across releases, as did Wasmtime diagnostics. Both hosts reported the same messages and locations, with an extra trailing newline from the Wasmtime runner. [Upstream and targeted checks](upstream-controls.json)

## Reproduce

Use the [stage build and paired measurement commands](../compiler-passes/README.md#reproduce) with three stages. Build the frozen input at `34ddff8`, the previous compiler at `06c84ac` with its [sizing profile](../lifetime-array-effects/training.profile), and the new compiler at `6e503fb` with [this profile](training.profile). Use the frozen input as the first argument of the paired measurement command. Run eight alternating rounds, reverse the four compiler arguments, and repeat. Run both new compilers on their own sources twice for seven rounds, reversing the order for the second series.

For the [copy probe](../../2026-11-18/compiler-copy-costs/copies/README.md#reproduction), pass `--only life_eval life_eval_body --detail life_eval life_eval_body` when instrumenting the named module and `--base-module` with its matching fixed memory32 module when measuring it. The counters, addresses and bytes in the exploratory result-storage trials identify experimental modules built on the previous source with the corresponding archived patches.

```sh
.venv/bin/python bench/selfbuild_charts.py bench/results/2026-11-19/expression-lifetimes
```
