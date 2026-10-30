# Checked scalar callers — 2026-10-30

Commit `dc3ec8f` extends semantic reuse to restricted straight-line `i64`
callers. Every request revalidates closed callee contracts and binds current
specializations. Editing a callee's body can preserve caller checking while
optimization/inlining sees the new body.

This comparison uses the original 32-function chain. Each edit changes
`step0`; the unchanged `std` import is reused as parsed syntax. The baseline
enables syntax and leaf caching; the comparison enables syntax and scalar
caller caching. All local validation finished before these eight runs, with
15 samples each, in leaf–caller–caller–leaf order at O0, then O2.

| Level | Mode, in execution order | Edited median (ms) | MAD (ms) | Type-check median (ms) | First uncached request (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| O0 | Leaves | 12.898 | 1.393 | 2.316 | 86.288 |
| O0 | Callers | 13.531 | 0.909 | 2.524 | 84.512 |
| O0 | Callers | 13.437 | 0.917 | 2.297 | 87.934 |
| O0 | Leaves | 13.565 | 0.513 | 2.405 | 81.802 |
| O2 | Leaves | 13.623 | 1.188 | 2.602 | 76.068 |
| O2 | Callers | 13.996 | 1.501 | 2.444 | 81.261 |
| O2 | Callers | 14.241 | 0.737 | 2.298 | 88.387 |
| O2 | Leaves | 14.052 | 1.048 | 2.450 | 76.743 |

Every scalar-cache edit reused all 31 unchanged callers plus 8 standard-library
leaves, and missed/stored the changed `step0`. Leaf-only edits reused the 8
standard-library leaves. Both modes parsed one file and reused one template.
The scalar pool retained an estimated 221,832 bytes at the first edit; full
per-edit counts and estimates, including retained previous versions, are in
the records.

These runs demonstrate contract-based body reuse, but do **not establish an
end-to-end latency improvement** on this small chain. Type-check phase timings
also overlap at O0. Source validation, key construction, fresh allocation,
signature/frame setup, dependency checking, and import still cost time. O2
phase medians are slightly lower with callers, while total medians remain
similar. Both caches remain opt-in; these results do not imply a general
incremental type checker or a function emission cache.

Each run verifies final output `12199049576607937` for runtime input `3`.
The [records](checked-callers.json) retain raw timings, dispersion, phase
medians, counters, expected/actual output, input hashes and platform metadata.
Repeated per-function fingerprint arrays are omitted. Compiler SHA-256 stayed
unchanged through qualification and all timing runs.

The compiler passed 603 differential observations across native C, C-Wasm,
direct Wasm, V8 and Wasmtime; 99 backend checks; 13 scalar-caller tests;
10 leaf-cache tests; 22 input-dependency tests; 12 artifact-cache checks;
11 session tests; 10 syntax-cache tests; and 4 static-data tests. All 194
curated C-Wasm reference cases passed. The new tests cover diamonds, argument
order, overloads/shadows, signatures, effects/recursion fallback, diagnostics,
`checkfree`, source reindexing, zero-argument calls, and graph-depth fallback.

ASan/UBSan passed 24 ownership scenarios across O0/O2, debug modes and source
reindexing, plus storage and graph-depth checks. Eight scenarios use a
capacity-one cache: checking an edited callee evicts the caller being restored,
then the remaining cache is cleared before optimization/emission. Local leak
checking was disabled because LeakSanitizer cannot run under process tracing;
CI retains leak checking.

Reproduce each pair in leaf–caller–caller–leaf order:

```sh
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --syntax-cache --checked-leaf-cache --optimization O0 --output build/chain-leaves-O0.json
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --syntax-cache --checked-scalar-cache --optimization O0 --output build/chain-callers-O0.json
```

Repeat with O2 and distinct output filenames.
