# Bytes copied by the self-hosted Wasm compiler

Checking the frozen compiler moved **10.09 → 8.51 GB** through Wasm `memory.copy`, a **15.6%** reduction. Emission moved **16.26 → 13.55 GB**, down **16.7%**, and both compilers emitted the same 17,322,012-byte module. [Paired counts](comparison.json)

| Executed copy volume | Before | After |
| --- | ---: | ---: |
| All functions, checking | 10,088,698,284 B | 8,510,233,634 B |
| Lifetime functions, checking | 8,292,658,707 B | 6,714,003,377 B |
| Held-reference walk, checking | 876,611,349 B | 108,007,989 B |
| Class candidate lookup, checking | 536,789,622 B | 5,812,632 B |
| Scope-depth lookup, checking | 206,438,005 B | 0 B |
| Lifetime replay, checking | 305,426,693 B | 305,426,693 B |
| Region component walk, emission | 1,131,161,856 B | 0 B |

The held-reference walk previously took 3,502,973 snapshots of its inner 210-byte storage root and 157,043 of its outer root. Native Clang read the relevant fields directly. In the scope-depth lookup, Wasmtime called its copy helper for a 565-byte frame 365,377 times. Clang loaded the two fields used in the calculation. [Original machine code](lowering.json) · [Original sites and widths](before/summary.json)

Lifetime replay’s largest single copy site moved 131.1 MB through 814,368 snapshots of a 161-byte effect. Two consecutive 72-byte snapshots in the compact-read path each executed 477,654 times. Native and Wasmtime both staged the value twice there. Wasmtime also checked three ranges for address wraparound and end-of-memory. [Replay counts](after/summary.json) · [Machine code](lowering.json)

## Remaining work

| Candidate function | Copy volume | What the two machine-code paths do |
| --- | ---: | --- |
| `cg_function`, emitting | 914.8 MB | Wasmtime copies a 66-byte function record 13.86 million times during a linear lookup. Native compares one symbol field directly. |
| `life_alt_overlaps`, checking | 431.9 MB | Each of 5.33 million comparisons takes three 27-byte snapshots. Native reads fields directly on the ordinary path. The Wasm class-alias argument sites recorded zero executions. |
| `life_contains`, checking | 277.0 MB | The pair-cache probe copies 25 bytes 11.08 million times. Native reads owner and pointee directly, then selects the answer or next entry. |

The largest checking functions overall are `life_eval_body` at 932.9 MB and `life_eval` at 680.0 MB. Their totals mix initialization, by-value arguments, and returned `LifeValue` records. One regression accounts for 11.5 MB in `life_eval_body` as an existing cell snapshot grows from 93 to 101 bytes. The three sites above have direct machine-code comparisons and are candidates for timing experiments. [Candidate machine code](remaining.json) · [Site counters](post-sites.json.gz)

## Reproduction

Compiler revisions are `4e7e1b3` and `ac55de2`. Both ran the frozen `90e086f` project using memory64, Wasmtime 50.0.1, and the same guest command-line arguments. All byte counts are executed Wasm operand lengths. CPU time and physical memory traffic require separate measurements. Each execution checked source archive hashes, the compiler binary, and its named module. Fresh instances ran checking and emission. [Before check](before/check.json.gz) · [Before emission](before/emit.json.gz) · [After check](after/check.json.gz) · [After emission](after/emit.json.gz)

The wasmparser decoder identifies instruction boundaries. The instrumenter appends i64 counters for each function, operation and fixed width, plus separate site counters in selected functions. A dynamic copy records its actual length operand. The decoder covered 19,247 static copy, fill and adjacent equal-width load/store sites before and 19,239 after. Each run saw one adjacent eight-byte transfer. That diagnostic counts only directly adjacent instructions. Fill bytes have their own totals. The synthetic control covers fixed and dynamic widths, overlapping ranges, zero lengths, an untaken copy, and a scalar load/store pair. It compares the final memories. [Counter control](control.json)

Build both compiler stages with the flags in the stage build records. Prepare the baseline naming compiler with the earlier compiler-record-access profiling script. From the repository root, run the following with the actual stage and scratch locations. The machine-code excerpts require the pinned Wasmtime build and x86 CPU features.

```sh
bash bench/results/2026-11-18/compiler-copy-costs/copies/reproduce.sh \
  build/replay-next/stage build/copy-trial/reader/own build/six-hills-1118/selfhost-chart \
  build/replay-next/profile/namer.wasm build/replay-next/views/expected.wasm build/copy-repro
```
