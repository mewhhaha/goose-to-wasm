# Reference compiler corrections

The C backend is an independent code-generation reference, not an assumption
that every upstream C expression is free from defects. Tests retain hand-derived
answers and compare both backends on both engines. Compiler, patches and source
identities are recorded with each result.

## Overlapping append into limited storage

Goose allows a reference or slice into a limited array to remain valid after
its logical length shrinks. Appending that retained slice can make the source
and destination ranges overlap. At the pinned upstream revision
`2e2bedef5b980bf013cac5aaa0095bfea64e5569`, `CodeGen::EmitAppend` used
`CopyFn()`/`gs_memcpy` for a limited destination. That invokes C `memcpy` on
overlapping ranges, where its behavior is undefined.

The ownership regression exposed this in a native GCC build: an overlapping
append produced `[8, 8, 9, 9, 0]` instead of the snapshot result
`[8, 8, 9, 7, 0]`. This is not a reason to copy the incorrect result into the
direct emitter. The separate patch
`oracle/patches/0002-limited-append-overlap.patch` changes only that limited-array
copy to the runtime's existing `gs_memmove` helper, including its zero-length
handling. Native C and C-Wasm receive the same correction. Direct emission
snapshots an overlapping source before writing its destination.

`tests/fixtures/dynamic_limited_reuse.goose` retains the regression, including
static/runtime capacity, references and slices after shrink/clear, assignment,
and nested fixed storage. The expected output is independently specified in
`tests/test_dynamic.py`; native/C-Wasm results do not define the expected answer
by themselves. The complete C portability corpus remains a release gate after
this change.

Use `scripts/bootstrap.py` for the current combined compiler, or its
`--without-direct` option for the corrected C-reference-only build. The latter
applies all `oracle/patches/` entries from `toolchain.json` and omits the direct
backend patches and headers.
