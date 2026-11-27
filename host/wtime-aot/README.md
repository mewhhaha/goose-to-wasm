# `goose-wtime-aot`: Native x86-64 `wtime-aot` Host for Direct Goose & Blot2

`goose-wtime-aot` compiles and runs Direct Goose Wasm32/Wasm64 modules — including full 84-import `blot2` and 24-import `selfhost` — using [`mewhhaha/wtime`](https://github.com/mewhhaha/wtime)'s pure-Rust x86-64 AOT compiler (`wtime-aot-host` / `StoreCdylib`) with zero Clang, zero LLVM, and zero Wasmtime dependencies.

## Build

Requires Rust `1.99+` and the sibling `../wtime` checkout:

```sh
cargo +1.99.1 build --release --manifest-path host/wtime-aot/Cargo.toml
```

The binary is `host/wtime-aot/target/release/goose-wtime-aot`.

## Usage

```sh
goose-wtime-aot module.wasm [--entry NAME] [--fast] [--cache PATH]
                [--timing-json PATH] [-- program arguments...]
```

- `--entry NAME`: invoke exported function `NAME` after `_start` (for example `--entry blot_goose_main` for Blot2 compiled with `--library --reachable-program`).
- `--fast`: disable Stage 2 AOT optimizations (`OptLevel::None`) for faster cold compilation.
- `--cache PATH`: serialize the compiled native `StoreCdylib` ELF `.so` beside a SHA-256 stamp (`PATH.stamp`) and reuse it when the `.wasm` bytes and optimization mode match.
- `--timing-json PATH`: write engine timings (`compile_ns`, `instantiate_ns`, `run_ns`, `compile_instantiate_ns`, `start_function_ns`, `engine_total_ns`).
