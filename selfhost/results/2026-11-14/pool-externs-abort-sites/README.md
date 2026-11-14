# Pool externs and abort sites · 2026-11-14

This qualifies `7a69a0e`, two upstream features on top of `3f54a4d`:

- **Aborts inside the stdlib report the program's line** (`bdff21f`, upstream `52282722`). Every `--stdlib` function except externs, exports, main, thread functions and functions used as function values takes its caller's place as a hidden last parameter. Native C passes a `static const GLoc` from the caller's `g_sites` table; direct Wasm passes the line, because its host abort import takes only a line, so it prints `(line N)` rather than `file:line`. Library code the optimizer inlines into the program's code reports at the call, except inside checkfree functions.
- **`slice_pool`'s span tree for native C** (`7a69a0e`, upstream `71ca3687`). Extern parameters may reference a grow-only array of C-crossing values, which crosses as the array's header. `native/slice_pool.h` ports upstream's checked span tree from `runtime_os.h` at `855f1037`. Direct Wasm refuses these externs by name. `stdlib/` carries upstream's `slot_pool.goose`, `slice_pool.goose` and `slice_pool_internal.goose` at `855f1037`.

Results:

- **Bootstrap.** `scripts/bootstrap.py --verify` reached a fixed point with Clang 23 and Goose `-O2`, without a profile: the next- and third-generation C are both `81387578…322b`, and the executable is `cffd13ea…329d`. [Report](bootstrap.json)
- **Conformance.** 8,320 of 8,414 rows pass at levels 0 and 2, both as one unit and with `--native-units 3`. The 94 failures are exactly the recorded gaps: none unexpected, none fixed. [Single unit](conformance.json.gz) · [Three units](conformance-native-units-3.json.gz)
- **Native checks.** 54 of 54 steps pass. Four of them are new: `native/tests/slice_pool.c`, which checks 200,000 random place, free and regrow operations against a free-span model, in release and under ASan/UBSan.
- **Upstream HEAD `855f103`, targeted.** The 117 tests that name the pools, stdlib aborts or externs, run natively at `-O0`. 37 went from failing to passing and none regressed. All 50 must-fail programs among them are rejected. The full inventory, rerun afterwards with the same compiler, moved 38 tests from failing to passing against the run of `2244213` and none the other way; [FEATURES.md](../../../../docs/FEATURES.md) carries its totals. [Results](upstream-inventory.jsonl.gz)
- **Output equivalence against `3f54a4d`** (`599ac861…`): 60 of 7,673 corpus rows differ, and both selfhost rows differ. A candidate rebuilt with the location pass disabled reproduces the baseline's bytes for every differing native and Wasm row, so the located parameter is the only cause. The 5 differing check rows are the new slice-pool fixtures, which the baseline refuses. The compiler's own C shrinks from 44,323,775 to 44,265,519 bytes at `-O2`, and from 24,027,094 to 24,002,361 at `-O0`, because `g_at->file` replaces repeated stdlib path strings. The corpus took 38.1 s against the baseline's 39.2 s. [Rows](summary.json)

## Known limits

- Direct Wasm aborts print `(line N)`, not `file:line`. Fixing that changes the host abort ABI of every module.
- Library functions used as runtime function values, and thread entry functions, report their own lines; upstream specializes them.
- Native C still refuses foreign C externs that take `T[>..]&` ("foreign builder reference ABI requires a runtime adapter").
- `stdlib_slot_pool_{builder,values,builder_effects}` and sample 26 stop at checker refusals.
