# goose-wasmtime

A Rust host for direct Goose WebAssembly on the Wasmtime crate (50.0.1, the version `requirements.txt` pins): the imports, output, error text and exit codes of `scripts/run_wasmtime.py`, without Python.

With Rust 1.97 or newer, run `cargo build --locked --release` in this directory. The binary is `target/release/goose-wasmtime`.
Run `goose-wasmtime module.wasm [--entry name] [--fast-jit] [--timing-json path] [--cache path | --no-cache] [-- program arguments]` with the program's input on stdin.
`--entry name` invokes the named exported function after `_start` (for example `--entry blot_goose_main` for Blot2 compiled directly to Wasm64 with `--library --reachable-program`, using the built-in `env.blot_*` and math host imports).
`--fast-jit` selects Cranelift `OptLevel::None` + `RegallocAlgorithm::SinglePass` for ~2× faster cold JIT compilation on large `-O0` modules (separate `.sha256` cache stamp from the default `OptLevel::Speed` mode).
`--cache` keeps the compiled module in that file beside a `.sha256` stamp of the module bytes; keep it apart from the Python runner's cache, since each host refuses the other's file (this one then compiles again and replaces it, the Python runner fails).
The memory64 conformance suite selects this release binary when present. Its `--python-host` switch runs the same rows through Python.

Tests: `cargo test`, then from the repository root `.venv/bin/python host/rust/tests/float_text.py` (float text against `goose_float`; needs `cargo build --release --examples`) and `.venv/bin/python host/rust/tests/compare_hosts.py --work DIR examples/*.goose` (both hosts on the same modules).
