# Upstream feature tracker

This page tracks which [upstream Goose](https://github.com/aardappel/goose) language, library and tool features this compiler supports. Update a row in the same change that moves it. The frozen [conformance contracts](../tests/conformance/cases.json) remain the qualification gate. This page also covers upstream work that landed after those contracts were pinned.

**Baseline (2026-11-13).**
- Contracts are pinned at upstream `2e2bede`; this inventory compares against upstream HEAD `855f103` (2026-11-12), 236 commits later.
- Compiler: installed snapshot 61, executable SHA-256 `25055855…`.
- How it was run: every upstream HEAD test, native target at `-O0`, with the HEAD standard library. Positive tests compile, run and compare against `test/expected`. `errors` must fail at parse; `errors_tc` must fail at check.
- Not covered: `-O2`, direct Wasm, upstream's second `GS_DEBUG` run, and the JIT, LSP and Python tool tests.
- To re-run: clone upstream, then `python3 tests/upstream_inventory.py --upstream <checkout> --output-dir build/feature-inventory`. Add `--summarize` to print the totals from an earlier run.

| Group | Pinned | Changed since pin | New since pin |
|---|---|---|---|
| Positive tests (compile, run, compare) | 533/620 | 12/34 | 40/149 |
| Must-fail tests (rejected) | 1,887/1,898 | 1/1 | 151/156 |

Of the 87 pinned positive failures, 45 are [recorded gaps](../tests/conformance/known-gaps.json), 30 import native packages (audio, gfx, physics, ui), 8 fail only with the HEAD standard library, and 4 need C sources or `--include`. Rejected programs are rejected, but upstream's `// error:` wording matches in only 91 of 2,039 cases.

Status key: **yes** = matches upstream on the tests named. **partial** = some forms or stages work. **refused** = parsed, then refused with a clear diagnostic at the named stage. **no** = not recognized. **wip** = a branch is in progress.

## Language

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Root structs (independent component storage) | `a01815f7`…`cbc64a32`, 2026-10 | parse, check: yes; codegen: refused (wip) | 47 new tests stop at "root struct storage is not yet supported by code generation", e.g. `storage/root_*`, `codegen/root_*`, `typing/root_struct_types`. Rejection tests `errors/root_*` pass. Also blocks the blot2 fixture's emit. |
| `defer`, including `defer f(x) { … };` | `e1d95ed0`, 2026-10-25 | parse: partial; check: refused (wip) | `syntax/defer_forms`, `codegen/defer_exits`, `defer_return_from`. The trailing-block form fails to parse at `;`, where upstream reports a check error. HEAD `exception.goose` uses `defer`. |
| `const if` (`has_default`, `same`) | `e93d4fcd`, 2026-11-05 | parse: yes; check: refused (wip) | `typing/const_if_{arms,conditions,constructors,statements}`. `errors/const_if_*` pass. |
| `src_file()`, `src_line()` and caller-location defaults | `a5579b1e`, 2026-11-11 | yes | `codegen/call_location` |
| Numeric separators `1_000` | `32a4f445`, 2026-11-11 | yes | `syntax/numeric_separators`; `errors/numeric_separator_double` rejected |
| UFCS type arguments `x.f<T>(a)` | `c1d86523` | yes | `typing/explicit_type_args` |
| `Name<T>.Variant` (payload-less generic variant) | `2fdd16df` | yes | `typing/generic_variant_constants` |
| Generic `format` overloads as rendering hooks | `f14facf1` | partial | `codegen/render_generic_non_hooks` passes; `render_generic_overloads` gives wrong output |
| Constants through `if`/`match` adapt like constants | `71e5ade1` | no (wip) | `typing/literal_conditionals`: "value cannot implicitly convert" |
| Untyped char literal binding a generic `T` | pin | no (wip) | `push_n(xs, '0', n)` is refused. Upstream HEAD `format_flt` calls it this way, so 8 pinned tests fail with the HEAD stdlib only. |
| A function and a namespace sharing a name | pin | no (wip) | `stdlib/stdlib_json`: "duplicate declaration in this scope" |
| Untyped block parameters bind nonfixed lvalues by reference | `f1fc0acc` | unknown | `typing/funval_reference_params` is hidden behind root structs |
| Decided-comparison warnings | `07f09f15` | yes | `typing/decided_comparisons` |
| Packed structs: alignment and Goose-to-Goose ABI | `cec434a5`, `1213ac3b` | yes | `codegen/packed_alignment`, `packed_call_abi` |
| Packed structs through host C `extern fn` | `1213ac3b` | partial | `packages/pkg_float_abi`: sphere and mesh print `false` |
| Threads, contained workers and queues | pin | yes | `threads/*` 26/26 pinned; new `thread_shared_fills`, `host_exit` pass |
| Serialization and self-relative values | pin | partial | `storage/serialize_adt_tail` passes; `serialize` and `serialize_image_checks` are recorded gaps |
| Variable images with cursor fields | pin | partial | 6 tests: "c: variable image fields require canonical array/reference cursors" |
| Coroutines, child threads, `own` | design notes | n/a | Upstream has design notes only; no tests |

## Arrays and runtime

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| `.check_length(n)` | `d6a3ceaa`, 2026-10-17 | no (wip) | `runtime/check_length_{large,message,negative,unsigned}` |
| `.range_index(slice)` | `d6a3ceaa` | no (wip) | `runtime/range_index_*`, `codegen/range_index` |
| `.move_from(src)` (overlap-safe copy) | `d24161f4`, 2026-10-25 | no (wip) | `codegen/slice_move*` |
| Data-stack overflow message for large default appends | `0e62366f` | partial | `runtime/bulk_default_overflow` aborts, with different wording |
| Aborts inside the stdlib report the caller's line | `52282722`, `2b509397` | no | 8 stdlib abort tests differ only in stderr: we print `std.goose:N` |
| Debug-mode cast and overflow aborts | pin | yes | `runtime/cast_abort_*`, `overflow_abort_location` |
| Vector elementwise float ops; f32 constant rounding | `be25f6d7`, `9f53461f` | yes | `codegen/vec_elemwise`, `optimizer/constant_f32_casts` |

## Standard library (upstream HEAD)

| Module or feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| `slot_pool`, `slice_pool` | `fa1b1640`, `71ca3687` | refused (needs root structs) | about 40 `stdlib_sl*_pool*`, `threads/*_pool_worker` and `runtime/slot_pool_*` tests |
| Bit rotations, byte swaps, `ilog2`, `isqrt`, `gcd`, `lcm` | `75ad5bd3` | no native symbols (wip) | Undefined `gs_rotl32` and `gs_rotl64`: `stdlib_bits`, `samples/15_word_freq` |
| `math` additions (`hypot`, `cbrt`, `expm1`, …) | `13712d6a` | no native symbols (wip) | Undefined `gs_hypot` |
| `binary` (all widths, both byte orders) | `23a7533b`, `71455360` | no native symbols (wip) | Undefined `gs_f32_from_bits` |
| `format_flt` rewrite | `24a2aad8` | blocked by char-literal inference | `stdlib_std` and samples 03, 09, 10, 21, 22 |
| `each_utf8` block form | | no | `stdlib_each_utf8`: "no overload matches" |
| `ascii` namespace | `335fddc1` | yes | `stdlib_ascii` |
| `mat`, `quat` | `855f1037` | yes | `stdlib_mat`, `stdlib_quat` |
| `parse_uint` and base range checks | `eee6f2d0`, `d5ae5bbd` | yes | `stdlib_parse_uint_range` |
| `dictionary` | pin | partial | `stdlib_dictionary_refs` is a recorded gap |
| `csv`, `regex`, `exception` | pin | partial | csv: recorded gap; regex: a lifetime refusal at `std.goose:200`; exception: needs `defer` |
| `os`, `base64`, `heap`, `vec`, `sort`, `byteset`; checkfree std leaves | pin, `d2de07bf` | yes | stdlib tests pass |

## Checker precision

| Area | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Lifetime refinements (80+ commits since the pin) | 2026-11 | partial | New `lifetimes/*` 5/7. `emptied_static_fields` and `holder_param_stores_later` are refused. |
| Invalid programs accepted | | 9 | `errors_tc/holder_param_inexact_views`, `holder_param_inexact_copy`, `global_before_init_from_bytes_index`, `checkfree_loaded_index` and 5 more |
| Error recovery ordering | | partial | All 16 `errors_tc/recovery` files are rejected; the expected error sequence matches in 0 |

## Tools and packages

| Feature | Upstream | Status | Evidence and notes |
|---|---|---|---|
| Native packages `gfx`, `audio`, `physics`, `ui` | pin | no | "blessed packages are not yet supported"; also `embed_shader` |
| Package C sources (`.build` sidecars) | pin | partial | `pkg_own_c` passes when its C is linked by hand; no CLI flag |
| `--shared`, `--header`, `goose_init` | `09198beb` | no | "unknown compiler option" |
| `format`, `lsp`, `fetch`, `completion`, `--jit`, `--include` | various | no | Not part of this compiler's driver |

## Compiler defects found by the inventory

- A call to a function whose parameter type is unknown aborts the compiler (`checker.goose:4048`, index -1) instead of reporting "unknown type name". (wip)
- `--run` without `-o` writes `out.c` and then fails to execute `out.c.bin`.
