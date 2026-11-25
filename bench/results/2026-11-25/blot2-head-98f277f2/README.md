# Blot2 HEAD `98f277f2` Direct Wasm64 + Fast Wasmtime & `wtime` Turnaround

Date: 2026-11-25  
Host: AMD Ryzen 7 7800X3D (16 threads, Linux 7.3.5-2-cachyos)

## Pinned Inputs & Tools

- **Compiler (`goose-to-wasm`):** qualified PGO binary `build/qualify-blot2-head/bootstrap/bin/goose` (SHA-256 `a78e2c43725b9df68a1a95e3adc6446e49e8a93370cbba15b9be02540fc7f163`), bootstrapped at fixed point with Clang 23 and the tracked PGO profile (`scripts/qualify.py --output-dir build/qualify-blot2-head --jobs 8`, exit 0 in `117.6 s`).
- **Blot2 source:** read-only sibling `../blot2` at commit `98f277f2`, archived into scratch build directories (`build/probe-life/blot2-raw` unmodified, and `build/blot2-head-probe` with the single 1-line `finishReflection` grow-only sort-buffer patch in the scratch copy only for the genuine §5.2 `makeReflectionOrder` bug at `check/check.goose:5049`).
- **Blot2 selected Goose stdlib (read-only):** `../blot2/build/goose-port/upstream-d5ae5bb/source-precision/stdlib`.
- **Reference upstream Goose (read-only):** `../blot2/build/goose-port/upstream-d5ae5bb/build-precision/goose` and pre-built native `../blot2/compiler-goose/build/blotc-goose` (`98f277f2`).
- **Wasmtime host:** `host/rust/target/release/goose-wasmtime` (`wasmtime 50.0.1`, `parallel-compilation`, `--entry`, `--cache`, built with `rustc 1.99.1`).
- **`wtime` host:** `host/wtime/target/release/goose-wtime` (`#![forbid(unsafe_code)]`, pinned read-only `../wtime` at `1125fd5` / `wtime-runtime 0.1.3`, built with `rustc 1.99.1`).

## Compiler & Host Changes Qualified in This Batch

1. **Multi-discard `_` bindings (`selfhost/parser.goose`, `selfhost/checker.goose`):**
   - Allows multiple `_` bindings in local `let`/`var` multi-return declarations (`let a, _, _ = ...`, `var _, _ = ...`), repeated local `let _ = ...`, and `for _, _ in ...` loops, matching plain upstream C++ Goose semantics.
   - Keeps duplicate `_` parameters (`fn f(_: i64, _: i64)`), duplicate global `_` declarations, and undeclared `_` assignment (`a, _ = ...`) rejected, matching upstream Goose.
2. **Folded-global shrink vs disjoint class-parameter target (`selfhost/checker_lifetimes.goose`):**
   - `life_shrink_places` narrows folded global-bound alternatives (`l.globals_root`, `target_type < 0`) to `array_type` (`u8[>..<]`) and drops type-incompatible global-bound alternatives.
   - `life_alias` and `life_alias_deep` apply symmetric `life_contains_memo` type-containment pruning when comparing a typed non-byteview global-bound alternative against an exact non-byteview class-mode root (`class_frame >= 0`, using `class_pointee` / `class_type`).
   - Eliminates the `check/check.goose:1271` conservative false-positive (`array shrink invalidates a value still needed by the enclosing expression`) on unmodified Blot2 `98f277f2` while preserving full soundness:
     - `forced0` (`LIFE_CONCRETE_FRAMES = 0`): `selfhost/main.goose --check` exit 0, `10,679 / 10,801` frontend conformance passing (**0 regressions** vs `HEAD` `forced0` `10,679 / 10,801`).
     - Positive + negative regression tests in `tests/test_cli_outputs.py` (`ClassLifetimeChecks`).
3. **Host support for Blot2 `98f277f2`:**
   - Added `env.blot_copy_u8` and `env.blot_copy_u32` (the only 2 new imports among `98f277f2`'s 84 Wasm imports vs `cb1e9e15`) to `host/wtime`.
   - Added `--entry NAME`, `env.blot_*` (including `blot_copy_u8` / `blot_copy_u32`), and `env` math imports to `host/rust` (`goose-wasmtime`) for fast parallel Cranelift JIT + `.cwasm` caching.

## Qualification Summary

- Plain upstream C++ Goose (`build/native/goose check selfhost/main.goose --stdlib stdlib`): exit 0.
- `scripts/qualify.py --output-dir build/qualify-blot2-head --jobs 8`: **passed in `117.6 s`**:
  - `bootstrap`: exit 0 (`28.9 s`, fixed-point + PGO)
  - `conformance`: `10,709 / 10,801` passed (`92` known gaps)
  - `native-checks`: `54 / 54` ok
  - `conformance-memory64`: `4,773 / 4,779` passed (`6` known gaps, running on updated `goose-wasmtime`)
  - `unit-tests`: exit 0 (`56.4 s`)
- `host/rust`: `cargo +1.99.1 test` `6/6` ok; `host/rust/tests/compare_hosts.py` `20/20` modules (`0` differences vs `scripts/run_wasmtime.py`).

## Bit-Exact Verification on Blot2 `98f277f2` (`benchmarks/idiomatic/*.blot`)

Command pattern (run across all 18 archived `.blot` files with `--std-root build/blot2-head-probe/std --prelude build/blot2-head-probe/std/prelude.blot`):

```sh
goose build/blot2-head-probe/compiler-goose/src/main.goose \
  --stdlib ../blot2/build/goose-port/upstream-d5ae5bb/source-precision/stdlib \
  --target wasm-direct --wasm-memory64 --wasm-max-pages 65536 \
  --library --reachable-program --expansion-node-limit 1000000 -O0|-O2 -o blot2.wasm

goose-wasmtime blot2.wasm --entry blot_goose_main --cache blot2.cwasm -- \
  build-project <bench.blot> <out.wasm> --std-root std --prelude std/prelude.blot

goose-wtime blot2-O2.wasm --entry blot_goose_main --max-instructions 10000000000 -- \
  build-project <bench.blot> <out.wasm> --std-root std --prelude std/prelude.blot
```

- **16/16** benchmarks that compile in `98f277f2` emit **byte-identical `.wasm`** (matching SHA-256) across native `blotc-goose`, `goose-wasmtime` (`-O0` and `-O2`), and `goose-wtime` (`-O2`).
- **2/2** remaining benchmarks (`list_pipeline.blot`, `run_length.blot`, which import removed `std/list`) exit with the identical `rc=1` across all 4 runners (**18/18 total agreement**).

## Measured Turnaround & Runtime Performance (`98f277f2`)

All single-core rows pinned to CPU 7 (`taskset -c 7`), median of 3 runs unless marked `(1 run)`. Parallel Cranelift rows run unpinned so Wasmtime uses its multi-threaded JIT compiler as in interactive development.

| Stage / Workload | Pinning | Median wall | Runs (s) | Max RSS | Notes |
|---|---|---:|---|---:|---|
| `goose-to-wasm --check` (1-line patched, 0 errors) | CPU 7 | **3.284 s** | `3.339, 3.284, 3.260` | 1,318 MiB | **3.27× faster** than upstream |
| `goose-to-wasm --check` (unmodified `98f277f2`, 1 §5.2 error) | CPU 7 | **4.190 s** | `3.919, 4.472, 4.190` | 1,314 MiB | **2.56× faster** than upstream |
| Upstream Blot2 `goose check` (`d5ae5bb` precision build) | CPU 7 | 10.729 s | `10.723, 10.768, 10.729` | 1,663 MiB | Reference run |
| `goose-to-wasm` Direct Wasm64 `-O0` emit | CPU 7 | **3.838 s** | `3.773, 3.838, 3.855` | 1,401 MiB | `22.82 MB` valid `.wasm` |
| `goose-to-wasm` Direct Wasm64 `-O2` emit | CPU 7 | **4.581 s** | `4.638, 4.581, 4.562` | 1,512 MiB | `33.31 MB` valid `.wasm` |
| `goose-wasmtime` `-O0` cold JIT + compile `fibonacci.blot` | unpinned | **2.404 s** | `2.404, 2.307, 2.535` | 1,257 MiB | `2.37 s` JIT + `0.12 s` run |
| `goose-wasmtime` `-O2` cold JIT + compile `fibonacci.blot` | unpinned | **4.529 s** | `4.529, 4.596, 4.462` | 2,226 MiB | `4.24 s` JIT + `0.12 s` run |
| `goose-wasmtime` `-O0` cold JIT + compile `fibonacci.blot` | CPU 7 (1 run) | 16.773 s | `16.773` | 700 MiB | Single-core Cranelift |
| `goose-wasmtime` `-O2` cold JIT + compile `fibonacci.blot` | CPU 7 (1 run) | 25.246 s | `25.246` | 989 MiB | Single-core Cranelift |
| `goose-wasmtime` `-O0` warm `.cwasm` `fibonacci.blot` | CPU 7 | **0.165 s** | `0.169, 0.165, 0.158` | 79 MiB | Cached module reuse |
| `goose-wasmtime` `-O2` warm `.cwasm` `fibonacci.blot` | CPU 7 | **0.142 s** | `0.141, 0.143, 0.142` | 97 MiB | Cached module reuse |
| `goose-wasmtime` `-O0` warm `.cwasm` `matrix_multiply.blot` | CPU 7 | **0.213 s** | `0.215, 0.210, 0.213` | 81 MiB | Cached module reuse |
| `goose-wasmtime` `-O2` warm `.cwasm` `matrix_multiply.blot` | CPU 7 | **0.196 s** | `0.196, 0.196, 0.198` | 100 MiB | Cached module reuse |
| Native `blotc-goose` `fibonacci.blot` | CPU 7 | 0.012 s | `0.014, 0.012, 0.012` | 23 MiB | Reference native `-O2` |
| `goose-wtime` (`register`) `-O2` `fibonacci.blot` | CPU 7 (1 run) | **3.733 s** | `3.733` | 892 MiB | `0.59 s` decode + `3.05 s` run (`wtime 0.1.3`) |
| `goose-wtime` (`compact`) `-O2` `fibonacci.blot` | CPU 7 (1 run) | 8.294 s | `8.294` | 838 MiB | `0.60 s` decode + `7.61 s` run |
| `goose-wtime` (`decoded`) `-O2` `fibonacci.blot` | CPU 7 (1 run) | 8.593 s | `8.593` | 837 MiB | `0.65 s` decode + `7.85 s` run |

### Edit → Rebuild → Run Turnaround Summary (`98f277f2`)

- **Fastest edit → compile → run (`goose-to-wasm -O0` + `goose-wasmtime` parallel JIT):** `3.84 s + 2.40 s` = **`6.24 s`** (no C compiler or linker).
- **Optimized Wasm64 edit → compile → run (`goose-to-wasm -O2` + `goose-wasmtime` parallel JIT):** `4.58 s + 4.53 s` = **`9.11 s`**.
- **Single-core no-JIT pure-Rust (`goose-to-wasm -O2` + `goose-wtime --execution register`):** `4.58 s + 3.73 s` = **`8.31 s`**.
- **Separate reference — Blot2 upstream C pipeline (`98f277f2`):**
  - Recorded release incremental rebuild (`../blot2/compiler-goose/build/stages/{emit-program,compile-and-link-program}.json`, cached runtime/native `.o`s): `15.33 s` emit + `83.50 s` `clang-23 -O2` = **`98.83 s`** (**~15.8× slower** than Direct Wasm64 `-O0` + `goose-wasmtime`).
  - Separate earlier unpinned `-O0` debug C reference measurement: `13.30 s` emit + `17.34 s` `clang -O0` = **`30.64 s`** (**~4.9× slower** than Direct Wasm64 `-O0` + `goose-wasmtime`).
