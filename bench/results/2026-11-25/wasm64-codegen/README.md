# Direct Wasm64 & Wasm32 codegen speedups (`selfhost/codegen.goose`)

- **Date:** 2026-11-25
- **Baseline:** Batch 3 qualified compiler (`e8a2457`, `build/qualify-batch3/bootstrap/bin/goose`)
- **Candidate:** `selfhost/codegen.goose` with kept changes below (`build/dev-b4/bin/goose`)
- **Host / CPU:** Pinned CPU 7 (`taskset -c 7`), Wasmtime 50.0.1 (cached `.cwasm`), `host/wtime` (`ad175d5`, `compact` mode)

## Kept changes

1. **`m.safe_refs` & Memory64 field-offset folding (`cg_member_memory_offset`, `cg_record_fields` `fold_base`):**
   - Added `cg_safe_refs_module`: true when no `as!` cast touches `TY_REF`, no `export fn` accepts a `TY_REF`, no `extern fn` returns `TY_REF` or takes a `TY_REF` to a non-primitive/non-primitive-array (or is a verified bundled-host import), and `m.resolver < 0 && m.prefix_helper < 0`.
   - Enabled `cg_member_memory_offset` and `fold_base` on `--wasm-memory64` (where 64-bit `u64` linear addresses never wrap within `2^48`) and on non-bundled safe modules (keeping the 32-bit `offset <= 4294967295 - p.maximum_pages * 65536` guard on memory32).
2. **Inline small scalar `cg_clear_bytes` (`1, 2, 4, 8, 12` bytes) and `cg_fixed_copy` (`1, 2, 4, 8` bytes) at `-O2`:**
   - Emits direct scalar load/store instructions (`align=0`, highest offset first for `size == 12` to preserve boundary-trap atomicity) instead of `memory.fill` / `memory.copy` libcalls on both memory32 and memory64.
3. **Fast `const_idx` and `simple_idx` array indexing on Memory64 (`cg_address`):**
   - Avoids saving `ptr`, `len`, and `index` into 3 extra locals when indexing a growable array by a non-negative integer constant or existing `i64` local on memory64 (`m.ordinary_owners`).

## Paired alternating CPU-7 results (Kept changes vs `e8a2457`)

| Workload | Metric | Baseline (`e8a2457`) | Candidate | Delta |
|---|---|---:|---:|---:|
| `selfhost` Wasm64 (plain) | `.wasm` bytes | 5,599,075 | 5,383,316 | **−3.9%** |
| `selfhost` Wasm64 (plain) | `.cwasm` bytes | 16,412,424 | 16,195,200 | **−1.3%** |
| `selfhost` Wasm64 (plain) | `--check` (5 alt. rounds) | 1.554 s | 1.547 s | −0.5% |
| `selfhost` Wasm64 (plain) | emit Wasm64 `-O2` (3 alt. rounds) | 2.015 s | 1.872 s | **−7.1%** |
| `selfhost` Wasm64 (`--wasm-bundled-host`) | `.wasm` bytes | 4,601,089 | 4,320,788 | **−6.1%** |
| `selfhost` Wasm64 (`--wasm-bundled-host`) | `.cwasm` bytes | 12,204,984 | 12,016,488 | **−1.5%** |
| `selfhost` Wasm64 (`--wasm-bundled-host`) | `--check` (5 alt. rounds) | 1.217 s | 1.192 s | **−2.1%** |
| `selfhost` Wasm64 (`--wasm-bundled-host`) | emit Wasm64 `-O2` (3 alt. rounds) | 1.382 s | 1.367 s | −1.1% |
| Blot2 `cb1e9e15` Wasm64 (`wtime` `compact`) | `fibonacci.blot` compile | 0.849 s | 0.799 s | **−5.9%** |
| Blot2 `cb1e9e15` Wasm64 (`wtime` `compact`) | `fibonacci.blot` run (bit-exact `fd6bacef670e`) | 15.45 s | 14.38 s | **−6.9%** |
| `examples/sorting.goose` (Wasm32, in-proc Wasmtime) | runtime (7 alt. rounds) | 47.31 ms | 46.65 ms | **−1.4%** |

## Preserved rejected experiments

1. **Enabling `v128` SIMD `cg_fixed_vectors` (`16..256` bytes) on Memory64 (`cg_wide`):**
   - *Result:* **Rejected.** On `selfhost` Wasm64 (plain), even combined with field-offset folding, `.cwasm` grew (`16,412,424 → 16,424,672 B`, `+0.1%`), `--check` regressed `+3.1%` (`1.406 s → 1.450 s`), and `emit64` regressed `+1.4%` (`1.859 s → 1.886 s`).
   - *Cause:* Unlike memory32 (which relies on hardware 4 GiB guard pages), Wasmtime memory64 emits an explicit software bounds check per `v128.load`/`v128.store`. Expanding a `128`-byte `memory.fill`/`memory.copy` into up to 16 `v128` memory instructions adds up to 16 inline 64-bit bounds checks and `i8x16.splat`s, inflating Cranelift machine code and icache pressure.
2. **Relaxing Memory64 `cg_hoist` slice-in-local threshold from `uses < 3` to `!needs_len && uses < 2`:**
   - *Result:* **Rejected** together with experiment 1. Keeping `cg_wide && cands[j].uses < 3` avoids extra live `i64` register pressure inside memory64 loops where a `v128` slice already resides in an XMM register.
