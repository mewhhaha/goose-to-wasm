# Blot2 C-host build interface and end-to-end native `blotc-goose` build (2026-11-24)

This batch implements the native C-host and shared-library build interface (`--emit-runtime`, `--header`, `--shared`, `--standalone`, `goose_init`, `goose_exit`, direct C `extern fn` linking without `-rdynamic`/`-ldl`, and reachable-export checking) and qualifies an end-to-end native build and execution of archived Blot2 (`cb1e9e15`) through its C host (`compiler-goose/native/*.c`).

## Pinned environment and inputs

- **Repository base commit:** `5839a70a21200f2e2784fcae06407f4bdf6e604b` (Batch 1: Blot2 lifetime fixes)
- **Qualified Batch 2 compiler (v2, memoized `cc_concrete`):**
  - Built by `scripts/qualify.py --output-dir build/qualify-blot2-chost-v2 --jobs 8`
  - Fixed-point C SHA-256 (`next_generation == third_generation`): `494c3011ed1420689f70ac39abce7c8fceae259a7704969241da5fdd58d24eed`
  - Executable SHA-256: `51fbbebd08266da3fa52862be7629c4f925fcd9f80573746786d00a203cfb6a6`
- **Plain upstream Goose reference check:** `build/native/goose` (`d5ae5bb`) on `selfhost/main.goose --stdlib stdlib`: **exit 0**
- **Host tool versions:**
  - `clang`: `clang version 23.1.5`
  - `node`: `v26.5.0`
  - `rustc`: `rustc 1.96.0-nightly (3645249d7 2026-03-16)`
- **Frozen Blot2 source:** `cb1e9e156d73c87c873f15888cd4fb6d2a399576`, exported from read-only `../blot2` via `git -C ../blot2 archive cb1e9e15 compiler-goose/src compiler-goose/native benchmarks/idiomatic std` into `build/blot2-qual-cb1e9e15/` (sibling `../blot2` remained untouched).
- **Scratch archive patch (`patch_sha256: 396ed573ff9a733f4c298f079a2773300fefcaa6e74c158970adda581fea37ba`):** A 1-line sound §5.2 sort-buffer workaround on `finishReflection` (`compiler-goose/src/check/check.goose:2045`) copying `self_.reflections` into a local grow-only `Reflection[>..]` before calling `makeReflectionOrder` and writing back, bypassing the single §5.2 diagnostic documented in [blot2-lifetime-fixes/README.md](../blot2-lifetime-fixes/README.md) (where plain upstream `d5ae5bb` has a `LoadSliceArgs` UAF false-accept bug).
- **Pinned Blot2 stdlib:** `build/blot-stdlib` (Blot2 `cb1e9e15`'s selected Goose standard library).

## What changed

### C-host / library build interface

- **`native/storage.h`:** Added `G_SHARED int g_runtime_active;` and `g_runtime_stop()` (idempotent teardown releasing regions/transfer/pool state and resetting `g_argc`/`g_argv`, keeping vendored `native/runtime/*` untouched so SHA-256 manifest checks in `native/pack.py` remain intact).
- **`selfhost/model.goose` & `selfhost/driver.goose`:** Added `--emit-runtime <out.c>` (standalone runtime unit emission without requiring a Goose source file), `--header <out.h>` (defaults target to native C, refuses `--target wasm-direct`, guards against overwriting source or `-o` output), `--shared` (compiles/links `.so` with `-shared -fPIC` when `-o` does not end in `.c`), and `--standalone` (embeds runtime even with `--header`).
- **`selfhost/checker.goose`:** Under `p.c_host` (`--header` / `--shared`), skipped unreachable non-generic function bodies (`check_unreached`) and dropped the `fn main()` requirement (`check_program_types`) while still checking all `export` entries, `main` if present, threads, and transitively reachable functions.
- **`selfhost/codegen_c.goose`:**
  - Added `generate_c_runtime` (emits `#define G_RUNTIME_UNIT 1` + runtime headers/impl/threads/unit) and `generate_c_header` (`#pragma once`, `<stdint.h>`, optional `gs_slice`, `extern "C"`, `goose_init`, `goose_exit`, and C-ABI prototypes for emittable `F_EXPORT` functions).
  - Updated `generate_c` to emit `#define GS_SEPARATE_RUNTIME 1` under `p.separate_runtime` and `goose_init(int argc, char **argv)` / `goose_exit(void)` instead of `int main` under `p.library || p.c_host`.
  - Upgraded `cc_emit_export` (`needs_env` aware, C-ABI scalar/pointer/slice parameters and slice return via `int64_t *gs_export_len`, `_WIN32` `dllexport` under `p.shared`, and `if (!g_initialized) gs_panic(...)` guard under `p.c_host`).
  - Upgraded `cc_emit_extern` to emit direct file-scope `extern <ret> g_ext_<fn>(<params>) __asm__("<name>");` declarations for plain `extern fn` without a shared-library path (`aux < 0`), allowing C host objects (`native/*.o`) and `-lm`/`libc` to link statically without `-rdynamic` or `-ldl`.

### Compiler bugs surfaced and fixed by building and running Blot2 natively

1. **Uninitialized local `var x: T;` (`selfhost/codegen_c.goose`, `cc_variable`):** Returned immediately after `cc_seed_symbol` when `n.right < 0` instead of calling `cc_default` on unchecked struct field defaults.
2. **Empty slice literals allocating transient regions (`selfhost/codegen_c.goose`, `cc_array` & `cc_default`):** Empty `TY_SLICE` literals (`default<T[:]>()`, `[]`) previously called `cc_raw_array`, holding a bogus transient region slot across recursive calls in Blot2 (`check/types.goose`, `check/package_contracts.goose`, `reuse/principal_type_graph.goose`, `eval/given_equations.goose`). Now emits `(GSlice){(GRef)(uintptr_t)&g_empty_byte, 0}` with zero region slots.
3. **Struct/enum fields missed by `cc_used_types` (`selfhost/codegen_c.goose`):** Walked `t.first` instead of `p.nodes[t.declaration].first` for `TY_STRUCT` / `TY_ENUM`, omitting field-only concrete types (e.g., `Buffer<T>.storage`). Fixed and guarded by `cc_concrete`.
4. **Non-recursive `cc_concrete` (`selfhost/codegen_c_storage.goose`):** Previously checked only direct field kinds, misclassifying generic templates like `Declaration<O, P, Q>` (whose fields wrap type parameters as `const O&`, `const P[:]`) as concrete while their field types were non-concrete. Made recursive with cycle tracking and memoized in unused slot 7 of `p.type_properties`.
5. **Pool slice builtin picking unused duplicate slice type (`selfhost/codegen_c.goose`, `cc_pool_builtin`):** `cc_slice_type(p, element)` could return an unused `const T[:]` type id for `realloc_slice`/`free_slice` instead of the argument's own already-used slice type. Now reuses the argument's slice type (or `n.type_id`).
6. **Struct field-default scope shadowing (`selfhost/checker.goose`, `check_layout_fields` / `check_layout_nominal` / `check_layout_variant`):** `N_FIELD` symbols were declared directly into the struct's lookup scope (`f.scope`), causing `struct OpenReply { epoch: const u8[:] = epoch }` (in `reuse/zig_project_server_loop.goose`) to resolve `= epoch` to `N_FIELD` instead of the outer `let epoch = "1"` global — generating bogus `g_env->captures` propagated all the way to `blot_goose_main` (`g_env == NULL` SIGSEGV). Fixed by isolating `N_FIELD` duplicate checks in a private child scope while keeping `p.nodes[field].scope` at the struct's type-parameter scope (matching plain upstream `build/native/goose`, which rejects sibling-field default references and resolves same-name globals cleanly).

## Qualification results

`build/qualify-blot2-chost-v2/summary.json` (total `304.5 s`, `units_pass: true`, **all 6 stages exit 0**):

| Stage | Exit | Time | Summary |
|---|---|---|---|
| `bootstrap` (`--verify`) | 0 | 138.1 s | Fixed point `494c3011…`, executable `51fbbebd…` |
| `conformance` (`-O0`, `-O2`, gcc) | 0 | 103.6 s | `10,697/10,801` (104 recorded gaps, 0 unexpected) |
| `native-checks` (`native/tests/check.py`) | 0 | 14.0 s | `54 steps ok` |
| `conformance-native-units-3` | 0 | 39.9 s | `5,926/6,022` (96 recorded gaps, 0 unexpected) |
| `conformance-memory64` | 0 | 166.3 s | `4,771/4,779` (8 recorded gaps, 0 unexpected) |
| `unit-tests` (19 modules) | 0 | 61.0 s | All passed, including `CHostLibraryBuild` (3 test methods covering separate runtime, `--standalone`, `--shared`, slice returns, double `goose_init`/`goose_exit`, direct C linking without `-rdynamic`/`-ldl`, uninitialized panic, header/target refusals, and all native codegen/checker regressions) |

## Rejected / superseded experiment: unmemoized `cc_concrete`

Before memoizing `cc_concrete` in slot 7 of `p.type_properties`, two intermediate implementations were measured and replaced:

| Variant | `selfhost/main.goose --target c -O2` (median) | Blot2 `cb1e9e15` emit `-O2` | Notes |
|---|---|---|---|
| Batch 1 baseline (`qualify-blot2-lifetimes`) | `0.695 s` (3-round solo) / `0.886 s` (5-round alt) | — | Non-recursive `cc_concrete` (fails Clang on Blot2 generic templates) |
| Unmemoized `cc_concrete` with `work`/`seen` dynamic arrays (v1, `3d1673fe…`) | `0.849 s` (+22.2% vs `0.695 s`) | `176.44 s` | Allocated 2 Goose region vectors and re-walked transitive structs per call |
| Zero-region recursive `cc_concrete` with stack `i32[64]` (`dev2`) | `0.825 s` (+18.7% vs `0.695 s`) | — | Eliminated region churn, still re-walked `Program`/`Checker` repeatedly |
| **Memoized `cc_concrete` in `p.type_properties[id*8+7]` (v2, `51fbbebd…`)** | **`0.883 s` (−0.4% vs `0.886 s` Batch 1)** | **`116.79 s` (−33.8% vs v1)** | Byte-identical `blot_goose.c` (`d82c8e39…`), `blot_goose.h`, `goose_runtime.c` |

## Own-source alternating comparison (Batch 1 vs Batch 2 v2)

5 alternating rounds on `selfhost/main.goose --stdlib stdlib` (both compilers built by `scripts/bootstrap.py --verify`):

| Workload | Batch 1 (`7a08e2ee…`) | Batch 2 v2 (`51fbbebd…`) | Delta | Output size |
|---|---:|---:|---:|---|
| `--check` | `0.497 s` | `0.515 s` | `+3.5%` | — |
| `--target c -O2` | `0.886 s` | `0.883 s` | `-0.4%` | `21,772,803 → 21,773,075 B` (`+272 B`) |
| `--target wasm-direct -O2` | `0.762 s` | `0.703 s` | `-7.8%` | `4,014,681 → 4,014,681 B` (byte-identical) |

## End-to-end Blot2 `cb1e9e15` native build

Built with Blot2's exact C-host pipeline (`compiler-goose/build.py` flags: `-std=gnu11 -D_GNU_SOURCE -O2 -pthread`, linking `blot_goose.c`, 7 `native/*.o`, `goose_runtime.o`, `-lm`, with **no `-rdynamic`** and **no `-ldl`**):

| Stage | Time | Output | Size / SHA-256 |
|---|---:|---|---|
| `--emit-runtime goose_runtime.c` | `0.001 s` | `goose_runtime.c` | `142,148 B` |
| Compile `goose_runtime.c` + 7 `native/*.c` (`-O2`) | `0.738 s` | `goose_runtime.o` + 7 `*.o` | `goose_runtime.o`: `56,216 B` |
| Emit program (`-O2 --header blot_goose.h`) | `116.79 s` | `blot_goose.c`, `blot_goose.h` | `151,115,539 B` (`d82c8e39…`), `194 B` |
| Clang compile & link dev (`-O0`) | `59.72 s` | `blotc-goose-dev` | `178,717,320 B` |
| Clang compile & link release (`-O2`) | `134.33 s` | `blotc-goose` | `10,450,184 B` (`525d4633…`) |

Dynamic dependencies (`ldd blotc-goose`): only `libm.so.6` and `libc.so.6` (plus `linux-vdso.so.1` and loader).

Generated `blot_goose.h`:

```c
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void goose_init(int argc, char **argv);
void goose_exit(void);
int32_t blot_goose_main(void);
#ifdef __cplusplus
}
#endif
```

## Real `.blot` execution verification (18/18 bit-exact vs Rust)

Compiled all 18 `benchmarks/idiomatic/*.blot` programs to WebAssembly with the qualified release `blotc-goose` (`build-project --std-root std --prelude std/prelude.blot`, total wall time for all 18 + 2 variants: `0.491 s`) and verified `run(1)` in Node `v26.5.0` against the sibling `benchmarks/idiomatic/*.rs` reference implementations compiled with `rustc -O`:

| Benchmark | `.wasm` bytes | `blotc-goose` `total_us` | Rust `run(1)` | `blotc-goose` `run(1)` | Match |
|---|---:|---:|---:|---:|:---:|
| `array_filter` | 2,859 | 12,770 | `89422506` | `89422506` | yes |
| `array_map_reduce` | 2,859 | 13,438 | `3420278784` | `3420278784` | yes |
| `binary_search` | 2,484 | 13,449 | `2097155` | `2097155` | yes |
| `csv_numbers_16`¹ | 3,615 | 11,881 | `491544` | `491544` | yes |
| `decimal_format_16`¹ | 3,531 | 12,174 | `2062386165` | `2062386165` | yes |
| `dot_product` | 2,311 | 12,391 | `2140983296` | `2140983296` | yes |
| `expression_eval` | 2,240 | 9,031 | `0` | `0` | yes |
| `fibonacci` | 1,958 | 8,841 | `4004785664` | `4004785664` | yes |
| `gcd` | 2,058 | 8,930 | `59564` | `59564` | yes |
| `histogram` | 2,207 | 12,573 | `2115277` | `2115277` | yes |
| `integer_recurrence` | 1,900 | 10,334 | `2144605973` | `2144605973` | yes |
| `list_pipeline` | 2,875 | 13,547 | `3139584` | `3139584` | yes |
| `matrix_multiply` | 3,069 | 13,565 | `222898304` | `222898304` | yes |
| `option_pipeline` | 2,084 | 10,212 | `322174978` | `322174978` | yes |
| `prefix_scan` | 2,883 | 13,494 | `4235018240` | `4235018240` | yes |
| `prime_sieve` | 2,370 | 13,303 | `14584641` | `14584641` | yes |
| `run_length` | 2,765 | 13,485 | `2333949943` | `2333949943` | yes |
| `tree_reduce` | 2,106 | 11,222 | `2505396224` | `2505396224` | yes |

¹ Both `csv_numbers.blot` and `decimal_format.blot` compile with `rc=0` at full `0..512` (`3,616 B` and `3,532 B`), but at frozen commit `cb1e9e15` Blot2's `std/text.blot` implemented `Builder = List U32` using `[...self, scalar]` snoc-appends that overflow the Wasm runtime stack at `0..512` (later replaced in Blot2 `f730b31e`). Scaling both the `.blot` and `.rs` loops identically to `0..16` confirms bit-exact execution of `std/text` as well (`18/18` matches).
