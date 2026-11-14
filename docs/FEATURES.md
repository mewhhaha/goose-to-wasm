# Upstream feature tracker

This page tracks which [upstream Goose](https://github.com/aardappel/goose) language, library and tool features this compiler supports. Update a row in the same change that moves it. The frozen [conformance contracts](../tests/conformance/cases.json) remain the qualification gate. This page also covers upstream work that landed after those contracts were pinned.

**Inventory (2026-11-14).**
- Contracts are pinned at upstream `2e2bede`; this inventory compares against upstream HEAD `855f103` (2026-11-12), 236 commits later.
- Compiler: the sources of `27040e5` (root struct storage, `defer`, `const if`, the small-gap and named-constant fixes, stdlib abort sites and `slice_pool`'s externs, on the indexed checker of `eb0c15d`), built by `scripts/bootstrap.py --verify` at a fixed point with clang 23, `-O2` Goose and no profile. Executable SHA-256 `cffd13ea…`.
- How it was run: every upstream HEAD test, native target at `-O0`, with the HEAD standard library, 4 jobs. Positive tests compile, run and compare against `test/expected`. `errors` must fail at parse; `errors_tc` must fail at check.
- Hand verdicts: ten results are carried from the first inventory (below), each with the same first diagnostic as then. `packages/pkg_own_c` passes when its C is linked by hand, and nine `errors_tc/recovery` files count as rejected although they stop at parse.
- Not covered: `-O2`, direct Wasm, upstream's second `GS_DEBUG` run, and the JIT, LSP and Python tool tests.
- To re-run: clone upstream, then `python3 tests/upstream_inventory.py --upstream <checkout> --output-dir build/feature-inventory`. Add `--summarize` to print the totals from an earlier run.

| Group | Pinned | Changed since pin | New since pin |
|---|---|---|---|
| Positive tests (compile, run, compare) | 544/620 | 23/34 | 138/149 |
| Must-fail tests (rejected) | 1,887/1,898 | 1/1 | 153/156 |

The first inventory (2026-11-13, installed snapshot 61, executable SHA-256 `25055855…`) had 533/620, 12/34 and 40/149 positive, and 1,887/1,898, 1/1 and 151/156 must-fail. The second (2026-11-14, sources of `2244213`, executable `b42e927c…`) had 543/620, 23/34 and 101/149 positive and the same must-fail counts as now. Since the second, 38 tests have started to pass and none has stopped passing: `typing/named_constant_literals`, the 20 `stdlib_slice_pool*` tests, `threads/slice_pool_worker`, `codegen/root_defer` and 15 aborts that now report the caller's line.

Of the 76 pinned positive failures, 42 are [recorded gaps](../tests/conformance/known-gaps.json), 30 import native packages (audio, gfx, physics, ui), and 4 need C sources or `--include`. None fails only because of the HEAD standard library any more. Rejected programs are rejected, but upstream's `// error:` wording matches in only 131 of 2,041 cases.

Status key: **yes** = matches upstream on the tests named. **partial** = some forms or stages work. **refused** = parsed, then refused with a clear diagnostic at the named stage. **no** = not recognized. **wip** = a branch is in progress.

## Language

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Root structs (independent component storage) | `a01815f7`…`cbc64a32`, 2026-10 | parse, check, native: yes; direct Wasm: refused | Of the 50 tests that stopped at "root struct storage is not yet supported by code generation", all 50 now pass natively. These include `storage/root_*` 18/18, `codegen/root_*` 8/9, `syntax/root_*`, `typing/root_*`, `threads/root_worker_local`, `optimizer/basecase_captures`, samples 02 and 13, and the 7 `slot_pool` aborts that need the caller's line (see Arrays and runtime). `codegen/root_defer` passes too, now that the `slice_pool` externs work (see Standard library). All 58 `errors{,_tc}/root_*` programs are rejected. After checking, direct Wasm refuses root owners: "root struct storage is not supported by the direct Wasm backend; use --target native" (`tests/test_root_struct_backends.py`; gap `corpus/contracts/root-struct/owner/wasm-direct`). Contracts: `corpus/contracts/root-struct/{owner,storage,storage-scopes,components,owner-references,construction,relative-links,component-index,component-pool,component-names}/native`. |
| `defer`, including `defer f(x) { … };` | `e1d95ed0`, 2026-10-25 | yes | Pass: `syntax/defer_forms`, `codegen/defer_exits`, `defer_return_from` and `optimizer/bce_join_values`. All 18 `errors{,_tc}/defer_*` programs are rejected; upstream's wording matches in 16. `codegen/root_defer` passes natively (see Standard library). Contracts: `corpus/contracts/defer/{forms,exits,extra,return-from,unwind,bce-join-values}` on native and direct Wasm at `-O0` and `-O2`, plus 15 type-error and 3 parse-error rows. |
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
| Threads, contained workers and queues | pin | yes | `threads/*` 26/26 pinned and 6/6 new, among them `thread_shared_fills`, `host_exit`, `root_worker_local`, `slot_pool_worker` and `slice_pool_worker` (see Standard library). |
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
| Aborts inside the stdlib report the caller's line | `52282722` | yes | The 15 abort tests that differed only in stderr pass: `stdlib_bits_{gcd_min,isqrt_negative,lcm_overflow}`, `stdlib_each_chunk_zero`, `stdlib_next_pow2_overflow`, `stdlib_rand_range_empty`, `stdlib_format_{int,uint}_base_37`, `stdlib_slot_pool_{builder,caller}_line` and `runtime/slot_pool_{builder_corrupt,corrupt,empty,negative,past_end}` (targeted inventory of the 41 tests these touch, 2026-11-14, native `-O0`: no other result changed; all 13 must-fail programs among them are rejected). Every `--stdlib` function except externs, exports, main, thread functions and functions used as function values takes its caller's place as a hidden last parameter (`mark_located_functions`): native C passes a `const GLoc *`, a `static const` entry of the caller's `g_sites`; direct Wasm passes the line, since its host's abort takes a line only. A check on one of its own library lines reports there, and its calls from those lines pass the place on. A library body the optimizer inlines into the program's code, but into a checkfree function, reports at the call (`InlineSite`, upstream `Inliner::AtCallSite`). Contracts: `corpus/contracts/abort-sites/{library-assert,library-chain,library-block}/{native,wasm-direct}` and `abort-sites/slot-pool-free/native` at `-O0` and `-O2`. |
| Type errors inside the stdlib report the instantiating call | `2b509397` | no | A type error in a library body checked for the program's call still names the library's line, with no instantiation chain. |
| Debug-mode cast and overflow aborts | pin | yes | `runtime/cast_abort_*`, `overflow_abort_location` |
| Vector elementwise float ops; f32 constant rounding | `be25f6d7`, `9f53461f` | yes | `codegen/vec_elemwise`, `optimizer/constant_f32_casts` |

## Standard library (upstream HEAD)

| Module or feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| `slot_pool` | `fa1b1640` | partial | 14/17 pass, among them `stdlib_slot_pool{,_call_identity,_equivalence,_helpers,_named_free,_builder_line,_caller_line}`, `threads/slot_pool_worker` and `runtime/slot_pool_*` 6/6. `stdlib_slot_pool_{builder,values}` are refused with "value cannot implicitly convert", and `_builder_effects` with "index_of requires an element of the receiver array". All 12 must-fail programs are rejected. This stdlib carries upstream's `slot_pool.goose` at `855f1037` (`stdlib/upstream.json`). |
| `slice_pool` | `71ca3687` | native: yes; direct Wasm: refused | 27/27 positive tests pass natively, among them the 21 that stopped at HEAD `slice_pool_internal.goose`'s runtime externs: `stdlib_slice_pool*` 20/20 and `threads/slice_pool_worker`. `codegen/root_defer` passes too, and sample 32, which has no upstream expected output, compiles and runs; sample 26 now stops later, at a lifetime refusal in `slot_pool.goose` ("stored reference does not outlive the storage that receives it"). All 14 must-fail programs are rejected. Evidence: a targeted inventory of the 117 upstream tests that name the pools, the stdlib aborts or externs (2026-11-14, native `-O0`, the `bootstrap.py --verify` compiler of this change, executable SHA-256 `cffd13ea…`): 37 fail before and pass now, none stopped passing, and the 50 must-fail programs among them are rejected. An extern parameter that references a grow-only array of C-crossing values now crosses as the array's header (upstream `ExternParamOk`), as `node[>..]&` does. The four externs (`gs_slice_pool_place`, `_free`, `_regrow`, `_trim`) are `native/slice_pool.h`, upstream's checked span tree from `runtime_os.h` at `855f1037` ported onto this backend's arrays; like upstream's `takesloc` externs they are located (see Arrays and runtime), so a corrupt tree aborts at the program's call into `slice_pool`. Native C still refuses other foreign externs that take such a reference ("foreign builder reference ABI requires a runtime adapter"). Direct Wasm refuses `slice_pool`'s root struct, and these externs by name (`tests/test_slice_pool_backends.py`). This stdlib carries upstream's `slice_pool.goose` and `slice_pool_internal.goose` at `855f1037` (`stdlib/upstream.json`). Contracts: `corpus/contracts/slice-pool/{spans,corrupt-tree,trim,direct-externs}/native` at `-O0` and `-O2`, `slice-pool/extern-array-reference` (check) and `slice-pool/extern-shrinking-reference` (type error); `native/tests/slice_pool.c` checks the span tree against a model under ASan and UBSan. |
| Bit rotations, byte swaps, `ilog2`, `isqrt`, `gcd`, `lcm` | `75ad5bd3` | yes | `stdlib_bits`, `stdlib_dictionary_model` and `samples/15_word_freq` pass. Native C defines `gs_rotl32/64`, `gs_rotr32/64` and `gs_byte_swap16/32/64` as upstream `runtime_ext.h` does; direct Wasm lowers the rotations to `rotl`/`rotr`. `stdlib_bits_{gcd_min,isqrt_negative,lcm_overflow}` abort at the caller's line (see Arrays and runtime). Contracts: `corpus/contracts/runtime-externs/bits/{native,wasm-direct}`. |
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
- Fixed: a named constant above `i64.max` (`let HUGE = 18446744073709551615`) converted silently to `i64` (as -1) when it met an `i64` named constant whose storage was referenced, so `HUGE > B` printed `false`. It now converts only to `u64`. Two such constants operate as `u64`, and a negative partner is an error, as in upstream `UnifyNumeric`. `typing/named_constant_literals` passes. Contracts: `corpus/contracts/named-constants/*`.
