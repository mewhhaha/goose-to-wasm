# Static-capacity limited-array qualification

Pinned upstream: `2e2bedef5b980bf013cac5aaa0095bfea64e5569`.
Release compiler SHA-256: `d48eabf95f3ad662aee4d49def0131d62f86e4ea79c418f34faac8735fa31cea`.
Debug compiler SHA-256: `bbe5ffd096d16fe6bc6f8c5719018a74da84b174dd302ba2cba243a00613ff53`.
The staged compiler headers were checked byte-for-byte against the prepared
Release source before committing this milestone.

- Full differential suite: **873/873 observations** across native C, C-Wasm,
  direct V8 and direct Wasmtime at O0/O2. This includes three explicit compile
  refusals, not three successful semantic executions.
- Focused Debug compiler suite: **156/156 observations**, including runtime
  debug mode, native reference output and both direct engines.
- Backend extensions: **100/100 checks**, including the explicit refusal of
  construction-time limited capacity.

Fixtures cover nested limited arrays and slices, exactly-once path evaluation,
slot replacement during iteration, aggregate pop snapshots, existing-reference
addressing, reference elements, receiver rebinding during arguments, overlapping
append, fill/default construction, copy independence, recursive/multiple returns,
zero/exact/overflow capacity and runtime count/bounds failures.

Reproduce with `tests/run_differential.py`, `tests/test_backend_extensions.py`,
and `tests/run_differential.py --goose build/dev/bin/goose --filter limited
--backends direct native`. Raw local reports are under
`build/limited-release-qualified`, `build/limited-debug-qualified`, and
`build/limited-backend-extensions`. Engine/toolchain pins are in `toolchain.json`.

This qualifies the stated fixed-value extension. Growable arrays and dynamic
ownership remain subsequent phases in the completion plan.
