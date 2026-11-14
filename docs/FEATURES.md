# Upstream feature tracker

This page tracks which [upstream Goose](https://github.com/aardappel/goose) language, library and tool features this compiler supports. Update a row in the same change that moves it. The frozen [conformance contracts](../tests/conformance/cases.json) remain the qualification gate. This page also covers upstream work that landed after those contracts were pinned.

**Inventory (2026-11-14).**
- Contracts are pinned at upstream `2e2bede`; this inventory compares against upstream HEAD `855f103` (2026-11-12), 236 commits later.
- Compiler: the sources of `2244213` (root struct storage, `defer`, `const if` and the small-gap fixes, on the indexed checker of `eb0c15d`), built by `scripts/bootstrap.py --verify` at a fixed point with clang 23, `-O2` Goose and no profile. Executable SHA-256 `b42e927c…`.
- How it was run: every upstream HEAD test, native target at `-O0`, with the HEAD standard library, 4 jobs. Positive tests compile, run and compare against `test/expected`. `errors` must fail at parse; `errors_tc` must fail at check.
- Hand verdicts: ten results are carried from the first inventory (below), each with the same first diagnostic as then. `packages/pkg_own_c` passes when its C is linked by hand, and nine `errors_tc/recovery` files count as rejected although they stop at parse.
- Not covered: `-O2`, direct Wasm, upstream's second `GS_DEBUG` run, and the JIT, LSP and Python tool tests.
- To re-run: clone upstream, then `python3 tests/upstream_inventory.py --upstream <checkout> --output-dir build/feature-inventory`. Add `--summarize` to print the totals from an earlier run.

| Group | Pinned | Changed since pin | New since pin |
|---|---|---|---|
| Positive tests (compile, run, compare) | 543/620 | 23/34 | 101/149 |
| Must-fail tests (rejected) | 1,887/1,898 | 1/1 | 153/156 |

The first inventory (2026-11-13, installed snapshot 61, executable SHA-256 `25055855…`) had 533/620, 12/34 and 40/149 positive, and 1,887/1,898, 1/1 and 151/156 must-fail. Since then, 84 tests have started to pass and none has stopped passing.

Of the 77 pinned positive failures, 43 are [recorded gaps](../tests/conformance/known-gaps.json), 30 import native packages (audio, gfx, physics, ui), and 4 need C sources or `--include`. None fails only because of the HEAD standard library any more. Rejected programs are rejected, but upstream's `// error:` wording matches in only 131 of 2,041 cases.

Status key: **yes** = matches upstream on the tests named. **partial** = some forms or stages work. **refused** = parsed, then refused with a clear diagnostic at the named stage. **no** = not recognized. **wip** = a branch is in progress.

## Language

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Root structs (independent component storage) | `a01815f7`…`cbc64a32`, 2026-10 | parse, check, native: yes; direct Wasm: refused | Of the 50 tests that stopped at "root struct storage is not yet supported by code generation", 43 now pass natively. These include `storage/root_*` 18/18, `codegen/root_*` 8/9, `syntax/root_*`, `typing/root_*`, `threads/root_worker_local`, `optimizer/basecase_captures` and samples 02 and 13. The other 7 are `slot_pool` aborts that report the wrong line (see Arrays and runtime). `codegen/root_defer` stops at the `slice_pool` externs (see Standard library). All 58 `errors{,_tc}/root_*` programs are rejected. After checking, direct Wasm refuses root owners: "root struct storage is not supported by the direct Wasm backend; use --target native" (`tests/test_root_struct_backends.py`; gap `corpus/contracts/root-struct/owner/wasm-direct`). Contracts: `corpus/contracts/root-struct/{owner,storage,storage-scopes,components,owner-references,construction,relative-links,component-index,component-pool,component-names}/native`. |
| `defer`, including `defer f(x) { … };` | `e1d95ed0`, 2026-10-25 | yes | Pass: `syntax/defer_forms`, `codegen/defer_exits`, `defer_return_from` and `optimizer/bce_join_values`. All 18 `errors{,_tc}/defer_*` programs are rejected; upstream's wording matches in 16. `codegen/root_defer` stops at the `slice_pool` externs (see Standard library). Contracts: `corpus/contracts/defer/{forms,exits,extra,return-from,unwind,bce-join-values}` on native and direct Wasm at `-O0` and `-O2`, plus 15 type-error and 3 parse-error rows. |
| `const if` (`has_default`, `same`) | `e93d4fcd`, 2026-11-05 | yes | `typing/const_if_{arms,conditions,constructors,statements}` pass. All 19 `errors{,_tc}/const_if_*` programs are rejected; upstream's wording matches in 15. Contracts: `corpus/contracts/const-if/{arms,conditions,constructors,statements}` on native and direct Wasm, plus 15 type-error and 4 parse-error rows. |
| `src_file()`, `src_line()` and caller-location defaults | `a5579b1e`, 2026-11-11 | yes | `codegen/call_location` |
| Numeric separators `1_000` | `32a4f445`, 2026-11-11 | yes | `syntax/numeric_separators`; `errors/numeric_separator_double` rejected |
| UFCS type arguments `x.f<T>(a)` | `c1d86523` | yes | `typing/explicit_type_args` |
| `Name<T>.Variant` (payload-less generic variant) | `2fdd16df` | yes | `typing/generic_variant_constants` |
| Generic `format` overloads as rendering hooks | `f14facf1` | partial | `codegen/render_generic_non_hooks` passes; `render_generic_overloads` gives wrong output |
| Constants through `if`/`match` adapt like constants | `71e5ade1` | yes | `typing/literal_conditionals` passes. `errors_tc/literal_conditional_operation_no_fit` is rejected, with this compiler's wording. Contracts: `corpus/contracts/constant-constructs/{operations/native,operations/wasm-direct,no-fit}`. |
| Literal arguments to untyped generic parameters, char literals included (§7.7) | pin | yes | `push_n(xs, '0', n)` and `insert_at(digits, 0, '1')`, as in upstream HEAD `format_flt`, now check. Pass: samples 03, 07, 09, 10, 17, 21, 22 and 23, `stdlib_std`, `runtime/float_text_nonfinite`, `optimizer/minmax_chains` and `stdlib_exception`. `errors_tc/literal_param_{range,flow}` match upstream's messages. Unlike upstream, a literal parameter handed to a block (`F(v)`) is an ordinary typed value inside it. Contracts: `corpus/contracts/literal-parameters/{adapt/native,adapt/wasm-direct,range,flow,typed}`. |
| A function and a namespace sharing a name | pin | yes | `stdlib/stdlib_json` passes. Contracts: `corpus/contracts/namespace-function/run/{native,wasm-direct}`. |
| Untyped block parameters bind nonfixed lvalues by reference | `f1fc0acc` | no | `typing/funval_reference_params`, no longer hidden behind root structs, is refused: "non-fixed storage requires explicit copy when passed or stored by value" |
| Decided-comparison warnings | `07f09f15` | yes | `typing/decided_comparisons` |
| Packed structs: alignment and Goose-to-Goose ABI | `cec434a5`, `1213ac3b` | yes | `codegen/packed_alignment`, `packed_call_abi` |
| Packed structs through host C `extern fn` | `1213ac3b` | partial | `packages/pkg_float_abi`: sphere and mesh print `false` |
| Threads, contained workers and queues | pin | yes | `threads/*` 26/26 pinned and 5/6 new, among them `thread_shared_fills`, `host_exit`, `root_worker_local` and `slot_pool_worker`. `slice_pool_worker` is refused (see Standard library). |
| Serialization and self-relative values | pin | partial | `storage/serialize_adt_tail` passes; `serialize` and `serialize_image_checks` are recorded gaps |
| Variable images with cursor fields | pin | partial | 6 tests: "c: variable image fields require canonical array/reference cursors" |
| Coroutines, child threads, `own` | design notes | n/a | Upstream has design notes only; no tests |

## Arrays and runtime

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| `.check_length(n)` | `d6a3ceaa`, 2026-10-17 | yes | `runtime/check_length_{large,message,negative,unsigned}` pass; `errors_tc/check_length_variable` matches upstream. Contracts: `corpus/contracts/array-ranges/length-*`. |
| `.range_index(slice)` | `d6a3ceaa` | yes | `runtime/range_index_{extent,foreign,message}` and `codegen/range_index` pass; `errors_tc/range_index_{variable,message_literal}` match upstream. Provenance is always checked at run time. Contracts: `corpus/contracts/array-ranges/{ranges,range-*}`. |
| `.move_from(src)` (overlap-safe copy) | `d24161f4`, 2026-10-25 | yes | `codegen/slice_move{,_bounds,_length,_rebind_bounds}` pass; `errors_tc/slice_move_{const,relative}` match upstream. `slice_move_escape` and `slice_move_source_shrink` are rejected with this compiler's lifetime wording. Contracts: `corpus/contracts/array-ranges/move-*`. |
| Data-stack overflow message for large default appends | `0e62366f` | partial | `runtime/bulk_default_overflow` aborts, with different wording |
| Aborts inside the stdlib report the caller's line | `52282722`, `2b509397` | no | 15 abort tests differ only in stderr: we print the stdlib's line (`std.goose:N`, `slot_pool.goose:N`). They are 8 stdlib tests, `stdlib_slot_pool_{builder,caller}_line` and 5 `runtime/slot_pool_*`. |
| Debug-mode cast and overflow aborts | pin | yes | `runtime/cast_abort_*`, `overflow_abort_location` |
| Vector elementwise float ops; f32 constant rounding | `be25f6d7`, `9f53461f` | yes | `codegen/vec_elemwise`, `optimizer/constant_f32_casts` |

## Standard library (upstream HEAD)

| Module or feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| `slot_pool` | `fa1b1640` | partial | 7/17 pass, among them `stdlib_slot_pool{,_call_identity,_equivalence,_helpers,_named_free}`, `threads/slot_pool_worker` and `runtime/slot_pool_known_corrupt`. 7 abort with upstream's message at the stdlib's line. `stdlib_slot_pool_{builder,values}` are refused with "value cannot implicitly convert", and `_builder_effects` with "index_of requires an element of the receiver array". All 12 must-fail programs are rejected. |
| `slice_pool` | `71ca3687` | refused | 21 of 27 positive tests stop at HEAD `slice_pool_internal.goose`, whose runtime externs take `node[>..]&`: "extern fn place: parameter nodes: only fixed-size values cross by value". `threads/slice_pool_worker` is one of them. `codegen/root_defer` and samples 26 and 32 stop at the same place. All 14 must-fail programs are rejected. |
| Bit rotations, byte swaps, `ilog2`, `isqrt`, `gcd`, `lcm` | `75ad5bd3` | yes | `stdlib_bits`, `stdlib_dictionary_model` and `samples/15_word_freq` pass. Native C defines `gs_rotl32/64`, `gs_rotr32/64` and `gs_byte_swap16/32/64` as upstream `runtime_ext.h` does; direct Wasm lowers the rotations to `rotl`/`rotr`. `stdlib_bits_{gcd_min,isqrt_negative,lcm_overflow}` abort at the stdlib's line (see Arrays and runtime). Contracts: `corpus/contracts/runtime-externs/bits/{native,wasm-direct}`. |
| `math` additions (`hypot`, `cbrt`, `expm1`, …) | `13712d6a` | yes | `stdlib_math` passes; libm in native C, host imports in direct Wasm. Contract: `corpus/contracts/runtime-externs/native/native`. |
| `binary` (all widths, both byte orders) | `23a7533b`, `71455360` | yes | `stdlib_binary` passes. Direct Wasm lowers the float bit casts to reinterpret instructions. |
| `format_flt` rewrite | `24a2aad8` | yes | `stdlib_std` and samples 03, 09, 10, 21 and 22 pass, now that literal generic parameters work (see Language) |
| `each_utf8` block form | | no | `stdlib_each_utf8`: "no overload matches" |
| `ascii` namespace | `335fddc1` | yes | `stdlib_ascii` |
| `mat`, `quat` | `855f1037` | yes | `stdlib_mat`, `stdlib_quat` |
| `parse_uint` and base range checks | `eee6f2d0`, `d5ae5bbd` | yes | `stdlib_parse_uint_range` |
| `dictionary` | pin | partial | `stdlib_dictionary_refs` is a recorded gap |
| `csv`, `regex`, `exception` | pin | partial | csv: recorded gap; regex: a lifetime refusal at `std.goose:200`; exception: `stdlib_exception` passes, and `try<E, Body, Catch, Finally>` runs `Finally` through `defer` |
| `os`, `base64`, `heap`, `vec`, `sort`, `byteset`; checkfree std leaves | pin, `d2de07bf` | yes | stdlib tests pass |

## Checker precision

| Area | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Lifetime refinements (80+ commits since the pin) | 2026-11 | partial | New `lifetimes/*` 5/7. `emptied_static_fields` and `holder_param_stores_later` are refused. |
| Invalid programs accepted | | 9 | `errors_tc/holder_param_inexact_views`, `holder_param_inexact_copy`, `global_before_init_from_bytes_index`, `checkfree_loaded_index` and 5 more |
| `checkfree` judged by what runs, not by callee annotations | `16437205`, `4602c986`, 2026-11-13 (after `855f103`) | no | We keep the pinned rule: a `checkfree` function may call only `checkfree` functions. Upstream now accepts any callee whose code that runs inside `checkfree` keeps no bounds check, and its stdlib has dropped 132 `checkfree` annotations. As a result, `checkfree` code that calls the newest std helpers is rejected here. Adopting the new rule needs a bounds-check judgment pass, and the pinned contracts must be re-pinned (`errors_tc/checkfree_callee` changed). |
| Error recovery ordering | | partial | All 16 `errors_tc/recovery` files are rejected; the expected error sequence matches in 0 |

## Tools and packages

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Native packages `gfx`, `audio`, `physics`, `ui` | pin | no | "blessed packages are not yet supported"; also `embed_shader` |
| Package C sources (`.build` sidecars) | pin | partial | `pkg_own_c` passes when its C is linked by hand; no CLI flag |
| `--shared`, `--header`, `goose_init` | `09198beb` | no | "unknown compiler option" |
| `format`, `lsp`, `fetch`, `completion`, `--jit`, `--include` | various | no | Not part of this compiler's driver |

## Compiler defects found by the inventory

- Fixed: a call to a function whose reference parameter type is unknown aborted the compiler during overload choice (index -1) instead of reporting "unknown type name". Contract: `corpus/contracts/unknown-types/reference-member`.
- `--run` without `-o` writes `out.c` and then fails to execute `out.c.bin`.
- `typing/named_constant_literals` now compiles, but prints `false` for `HUGE > B` (`HUGE = 18446744073709551615`, `B = SZ * 2`), where upstream prints `true`. Snapshot 61 prints the same `false` when the test's `add(b, SZ)` line is removed, so the miscompile predates literal generic parameters. It is the recorded gap `upstream/typing/named_constant_literals`.
