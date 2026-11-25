# goose-wtime

A thin `#![forbid(unsafe_code)]` Rust host for direct Goose WebAssembly (wasm32 and `--wasm-memory64`) on [`wtime`](https://github.com/mewhhaha/wtime) (`wtime-runtime` 0.1.2).

It binds:
- Standard direct-Goose `goose.*` imports (`write`, `print_*`, `newline`, `abort`, `exit`, `format_f64`) and pure-Rust math imports (`frexp`, `ldexp`, `gs_*`, `acosh`, `asinh`, `atanh`, `sinh`, `tanh`, `exp2`).
- Goose OS imports (`env.gs_os_*`).
- Blot2's `env.blot_*` POSIX/fd/directory/args/env/clock/bit/atomic surface, allowing frozen Blot2 compiled directly to Wasm64 (`--library --reachable-program --target wasm-direct --wasm-memory64`) to run unmodified under `wtime`.

## Build

Requires the sibling read-only `../wtime` checkout and Rust 1.99+:

```sh
cargo +1.99.1 build --release --manifest-path host/wtime/Cargo.toml
```

The binary is `host/wtime/target/release/goose-wtime`.

## Usage

```sh
goose-wtime module.wasm [--entry NAME] [--execution decoded|compact|register] \
            [--max-instructions N] [--max-memory-mb N] [--timing-json PATH] \
            [-- program arguments...]
```

- `--entry NAME`: invoke exported function `NAME` after `_start` (for example `--entry blot_goose_main` for Blot2 compiled with `--library --reachable-program`).
- `--execution`: `decoded` (default), `compact`, or `register`.
- `--max-instructions`: instruction budget passed to `wtime_types::ResourceLimits` (default `100_000_000`; use e.g. `4_000_000_000` for large compiler modules like Blot2).
- `--max-memory-mb`: linear memory cap in MiB (default `16384`).
- `--timing-json PATH`: write `{"engine":"wtime","compile_ns":...,"instantiate_ns":...,"run_ns":...}` to `PATH`.

## Example: running Blot2 Wasm64 on `wtime`

```sh
goose compiler-goose/src/main.goose --stdlib blot-stdlib \
      --target wasm-direct --wasm-memory64 --wasm-max-pages 65536 \
      --library --reachable-program --expansion-node-limit 1000000 -O2 \
      -o build/blot2-wasm64.wasm

host/wtime/target/release/goose-wtime build/blot2-wasm64.wasm \
      --entry blot_goose_main --execution decoded --max-instructions 4000000000 \
      -- build-project benchmarks/idiomatic/fibonacci.blot build/fibonacci.wasm \
         --std-root std --prelude std/prelude.blot
```
