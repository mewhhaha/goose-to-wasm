# Direct Wasm64 Blot2 (`cb1e9e15`) on pure-Rust `wtime` (`host/wtime`)

- **Date:** 2026-11-25
- **Compiler:** `selfhost/` with `--library --reachable-program` skipping unreachable non-generic bodies (`selfhost/checker.goose`)
- **Host:** `host/wtime` (`goose-wtime`, `#![forbid(unsafe_code)]`, `rustc 1.99.1` / `cargo 1.99.1`), linking read-only sibling `../wtime` at `ad175d5` (`wtime-runtime` 0.1.2, `wtime-types` 0.1.2)
- **Frozen workload:** Archived Blot2 `cb1e9e15` (`compiler-goose/src/main.goose` + 1-line sound §5.2 `finishReflection` sort-buffer patch in scratch archive `build/blot2-qual-cb1e9e15`, read-only `../blot2` untouched), compiled with `--stdlib build/blot-stdlib --target wasm-direct --wasm-memory64 --wasm-max-pages 65536 --library --reachable-program --expansion-node-limit 1000000 -O2` directly into a `43 MB` Wasm64 module (3 exports: `memory`, `_start`, `blot_goose_main`; 85 imports: 10 `goose.*`, 19 math, 56 `env.blot_*`)
- **Reference binaries:** Native `blotc-goose` compiled from the exact same frozen archive (`build/blot2-qual-cb1e9e15/out/*.wasm`)

## Pinned CPU 7 comparison of `wtime` execution modes (`fibonacci.blot`)

Command (`taskset -c 7`, `--max-instructions 4000000000`):

```sh
taskset -c 7 host/wtime/target/release/goose-wtime build/blot2-cb1e9e15-lib-wasm64.wasm \
  --entry blot_goose_main --execution <mode> --max-instructions 4000000000 \
  -- build-project build/blot2-qual-cb1e9e15/benchmarks/idiomatic/fibonacci.blot <out.wasm> \
     --std-root build/blot2-qual-cb1e9e15/std --prelude build/blot2-qual-cb1e9e15/std/prelude.blot
```

| Execution mode | Compile (s) | Instantiate (ms) | Run (s) | Output bytes | SHA-256 vs native `blotc-goose` |
|---|---:|---:|---:|---:|---|
| `compact` | 0.987 | 2.26 | 14.87 | 1,958 | `fd6bacef670e` (**exact match**) |
| `register` | 0.804 | 1.95 | 16.77 | 1,958 | `fd6bacef670e` (**exact match**) |
| `decoded` | 0.844 | 2.05 | 17.62 | 1,958 | `fd6bacef670e` (**exact match**) |

## All 18/18 idiomatic Blot2 benchmarks on `wtime`

All 18 frozen `benchmarks/idiomatic/*.blot` benchmarks were compiled by `goose-wtime` (`--execution decoded`, 8 parallel workers) and compared byte-for-byte against native `blotc-goose`: **18/18 bit-exact SHA-256 matches**.

| Benchmark | Output bytes | SHA-256 (prefix) | Native match |
|---|---:|---|---|
| `array_filter` | 2,859 | `7ebbfecd20ed` | exact |
| `array_map_reduce` | 2,859 | `2f841a74f34f` | exact |
| `binary_search` | 2,484 | `cf166b8e5346` | exact |
| `csv_numbers` | 3,616 | `89ea6059fbbd` | exact |
| `decimal_format` | 3,532 | `b00086a9f48c` | exact |
| `dot_product` | 2,311 | `38573b4858b2` | exact |
| `expression_eval` | 2,240 | `61fc69a62652` | exact |
| `fibonacci` | 1,958 | `fd6bacef670e` | exact |
| `gcd` | 2,058 | `881e76ab6b4c` | exact |
| `histogram` | 2,207 | `e48ebc72571f` | exact |
| `integer_recurrence` | 1,900 | `c0e0209819f0` | exact |
| `list_pipeline` | 2,875 | `6d1da477d965` | exact |
| `matrix_multiply` | 3,069 | `5b267073e5b5` | exact |
| `option_pipeline` | 2,084 | `ad6165a66588` | exact |
| `prefix_scan` | 2,883 | `b2acaf1edfaf` | exact |
| `prime_sieve` | 2,370 | `5be12f132b94` | exact |
| `run_length` | 2,765 | `47ca9372c68a` | exact |
| `tree_reduce` | 2,106 | `7697f0b98ce5` | exact |
