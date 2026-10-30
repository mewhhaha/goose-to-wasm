# Checked scalar leaf reuse — 2026-10-30

Commit `caf527a` implements optional cross-request reuse of checked closed
scalar expression functions. Entries contain values and indices, and import
reconstructs a fresh request-owned checked body. This experiment compares
syntax caching alone with syntax caching plus checked-leaf reuse.

The generated workload has 64 independent arithmetic helpers and an imported
`std` module. Each edit changes one arithmetic function in the caller module;
the helpers remain unchanged. This deliberately exercises the supported leaf
boundary. It is separate from the original 32-function call-chain workload,
whose callers still recheck in this implementation.

All local builds and validation finished before timing. Each run takes 15
samples. The order is syntax–checked–checked–syntax at O0, then O2. Both modes
reuse parsed syntax, and both independently verify the final edited result
`13843` for runtime input `3`.

| Level | Mode, in execution order | Edited median (ms) | MAD (ms) | Type-check median (ms) | First uncached request (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| O0 | Syntax | 20.629 | 1.453 | 4.057 | 110.449 |
| O0 | Checked leaves | 17.746 | 0.716 | 2.545 | 125.579 |
| O0 | Checked leaves | 16.233 | 2.449 | 2.734 | 101.403 |
| O0 | Syntax | 17.936 | 2.191 | 3.483 | 84.287 |
| O2 | Syntax | 15.850 | 2.376 | 3.389 | 87.933 |
| O2 | Checked leaves | 14.522 | 0.819 | 2.779 | 92.750 |
| O2 | Checked leaves | 19.166 | 2.040 | 3.066 | 109.693 |
| O2 | Syntax | 16.535 | 2.278 | 3.191 | 86.879 |

The type-check phase is smaller with reuse in these runs. O0 edited medians
are also lower, while O2 wall-time results are mixed. Dispersion, parse-time
variation, and first-request variation show shared-host noise. These results
do not establish an overall speedup across both optimization levels or a
general compiler performance claim. The mode remains opt-in.

Each cached edit skipped 72 body checks: the 64 helpers and 8 eligible standard
library leaves. It missed and stored the changed arithmetic function. The
caller, other ineligible functions, optimizer, bounds analysis, and emitter
still ran. Each edit parsed one file and reused two parsed templates. The
retained records include per-edit entry counts and conservative storage
estimates, including prior edited versions within the 256-entry/16 MiB bound.

The [records](checked-leaves.json) retain every timing sample, phase medians,
reuse counters, first-request times, verified expected/actual output, compiler
and input hashes, and platform metadata. Repeated function fingerprint arrays
are omitted. Compiler SHA-256 stayed unchanged across qualification and timing.

This compiler passed 593 differential observations across native C, C-Wasm,
direct Wasm, V8 and Wasmtime, plus 99 backend checks, 10 checked-leaf tests,
22 input-dependency tests, 12 artifact-cache checks, 11 session tests, 10
syntax-cache tests, and 4 static-data tests. All 194 curated C-Wasm portability
cases passed; these qualify the reference pipeline. The added scalar fixture
also qualifies value-producing guards with a returning `else`, nested
conditionals, f32 coercions, narrow integers, and signed zero.

AddressSanitizer and UndefinedBehaviorSanitizer passed eight ownership
scenarios across O0/O2, debug modes, and source reindexing, plus bounded-cache
checks. Each destroys the producer AST before import and evicts entries before
optimizing/emitting the consumer. Local leak checking was disabled because
LeakSanitizer cannot run under the environment's process tracing; CI retains it.

With the pinned Node and Python environment active, reproduce each pair in
syntax–checked–checked–syntax order:

```sh
python bench/incremental.py --samples 15 --functions 64 --shape leaves \
  --native-worker --syntax-cache --optimization O0 --output build/leaves-syntax-O0.json
python bench/incremental.py --samples 15 --functions 64 --shape leaves \
  --native-worker --syntax-cache --checked-leaf-cache --optimization O0 \
  --output build/leaves-checked-O0.json
```

Repeat with O2 and distinct output filenames.
