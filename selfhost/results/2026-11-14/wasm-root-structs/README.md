# Root structs on direct Wasm · 2026-11-14

This qualifies `c07a240`, on top of `27040e5`: the direct Wasm backend lowers root struct owners instead of refusing them.

- **Layout.** A root owner's frame places its components' own storage side by side, as native C's does. Each field takes the slot its type takes as a variable, so a resizable component keeps its 24-byte control in the frame; a `varint` keeps its encoding in 10 bytes. The checked layout of one reference per field is replaced before emission.
- **Regions.** A declaration builds each component in field order, in its place. Each component that owns storage gets its own data region, so components grow, shrink and run out independently. A local owner's regions are released with its scope; a global owner takes one dedicated region per such component. Modules on the heap backend keep each component as its own heap image.
- **Named components.** `owner.field` in an index or relative reference type is that field's static address in its global owner, with no storage of its own.

Results:

- **Bootstrap.** `scripts/bootstrap.py --verify` reached a fixed point with Clang 23 and Goose `-O2`, without a profile: the next- and third-generation C are both `214ac61e…f078`, and the executable is `46021916…f322`. [Report](bootstrap.json)
- **Conformance.** 8,350 of 8,442 rows pass at levels 0 and 2 with Wasmtime. The 92 failures are exactly the recorded gaps: none unexpected, none fixed. The closed gap is `root-struct/owner/wasm-direct`. The 28 new rows are direct Wasm runs of the nine other root-struct run contracts, and three new fixtures: `component-kinds` and `component-heap` on both targets, and `component-encoded` on direct Wasm only. [Results](conformance.json.gz)
- **Native checks.** 54 of 54 steps pass.
- **Output equivalence against `7a69a0e`** (`cffd13ea…`, the same sources as `27040e5`), with `--emit-upstream` and a frozen copy of the compiler's sources: 18 of 15,056 corpus rows differ, and none of the 3 selfhost rows. All 18 are direct Wasm emissions of programs with root structs. In 15 of them the baseline refuses the root owner and the candidate emits it: the 14 root-struct fixtures and `abort-sites/slot_pool_free`. In the other 3, slice-pool fixtures, the diagnostic changes, from the root owner to `slice_pool`'s span tree externs. [Rows](summary.json)
- **Upstream HEAD `855f103`, targeted.** This covers the 81 tests and samples outside `test/errors*` that declare a root struct or name `slot_pool` or `slice_pool`. 74 pass natively at `-O0`. On direct Wasm, 37 pass at `-O0` and the same 37 at `-O2`. The other 37 stop at direct Wasm limits that are not root storage:
  - `slice_pool`'s externs: 21
  - abort messages: 9. Stdout, exit and line match, but the host prints `(line N)` and its own wording.
  - threads: 3
  - `from_bytes`: 2
  - `os::trim_memory`: 1
  - reusable slice builtins: 1

## On `big-workload-parse`

Cherry-picked as `f3a70d3` onto `9a9d627`, which brings lifetime set sharing. `df8c8a1` then fixes native C, which gave a `varint` root component no bytes in its owner's frame (`cc_frame_size` takes the type's size, 0), so the component overlapped the next one and a write could run past the frame. It now takes 10 bytes, the widest zigzag ULEB128, as on direct Wasm, and `component-encoded` gains its native rows. Its output matches plain upstream `32a4f44`, and it runs clean under ASan and UBSan. The combined tree was qualified again:

- **Bootstrap.** A fixed point (`0d8a9802…`, executable `ca853ebf…`).
- **Conformance.** 8,352 of 8,444 rows pass, both as one unit and as three native units. The 92 failures are exactly the recorded gaps. [One unit](conformance-combined.json.gz) · [Three units](conformance-combined-native-units-3.json.gz)
- **Native checks.** 54 of 54 pass.
- **Backend tests.** 5 of 5 pass.
- **Equivalence against the `9a9d627` compiler (`e7ff8bab…`).** 20 of 7,685 outputs differ. 18 are the direct Wasm emissions listed above, and 2 are `component-encoded` at native `-O0` and `-O2`. [Rows](summary.json)

## Known limits

- Each component that owns storage takes a region, so per-region capacity falls as owners multiply. `codegen/root_loaded_aliases` (without `os::trim_memory`) needs `--wasm-max-pages 4096` for its 3 MiB component.
