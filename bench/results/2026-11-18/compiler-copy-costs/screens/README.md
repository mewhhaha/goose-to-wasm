# Additional compiler screens

The release at `ac55de2` includes region-call and lifetime-parameter indexes and narrower reads in lifetime checking. The experiments below remained outside that batch.

## Lifetime replay

Four source changes independently removed work in replay or effect recording. Each reduced self-check instructions by less than 1%, and each took more CPU time than its control in a single shared-host screen. All four were discarded from this batch. [Source and module hashes, counters, order and samples](replay.json)

| Frozen self-check, one sample per case | Control → trial CPU, s | Control → trial instructions, billions | Change |
| --- | ---: | ---: | ---: |
| Borrow effect, value and reach arguments | 5.643 → 9.223 | 53.215 → 53.129 | −0.16% |
| Append the effect before filling in its links | 5.643 → 12.141 | 53.215 → 53.118 | −0.18% |
| Read the compact entry and its key once | 6.670 → 6.952 | 53.215 → 52.830 | −0.72% |
| Reuse the ordinary validation read offer | 7.473 → 7.744 | 53.215 → 53.149 | −0.12% |

The first two rows share the same control. The third and fourth each had a fresh control. These screens covered self-check only and overlapped other jobs. Apply any one patch to source `4e7e1b3`. [Borrowed arguments](replay-ref.patch) · [Insertion](replay-insert.patch) · [Compact entry](replay-loop.patch) · [Validation offer](replay-validate.patch)

## Wasm function lookup

An unqualified follow-up to `ac55de2` indexed the first ordinary Wasm function for each symbol. During frozen emission, 17,042 lookups previously examined 13,861,325 function records. A separate instrumented run compared all indexed answers against the original loop, including 109 misses, with zero differences. The table used one i64 for each of 68,218 symbols, or 545,744 bytes of entries. Each elements variant still uses its existing lookup. [Trial patch](cg-function.patch) · [Shadow patch](cg-function-shadow.patch) · [Counts and provenance](cg-function.json)

| Work | Round 1 control → trial CPU, s | Round 2 control → trial CPU, s | Median instructions, billions | Change |
| --- | ---: | ---: | ---: | ---: |
| Self-check | 11.576 → 11.335 | 7.832 → 7.970 | 52.414 → 52.417 | +0.005% |
| Wasm emission | 15.834 → 10.088 | 10.453 → 10.975 | 77.431 → 76.671 | −0.98% |

Wasmtime retired fewer emission instructions in both orders. CPU time reversed direction in the second pair as native compilation and release qualification ran on the host. All four timed emissions and the shadow emission reproduced the 17,322,012-byte native reference. Wider workloads, resident memory and conformance remain unmeasured for the index. [Every timed sample and output hash](cg-function-pairs.json)

Both experiments used Wasmtime 50.0.1, CPU 4 and project `90e086f`. The native emitter from `4e7e1b3` built all trial modules with `--target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144`. The function-index benchmark used two alternating rounds of the prepared-module comparison harness, with a fresh instance for each sample. [Comparison harness](../../compiler-record-access/tools/compare.py)
