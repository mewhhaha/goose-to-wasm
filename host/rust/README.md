# goose-wasmtime

A Rust host for direct Goose WebAssembly on the Wasmtime crate (50.0.1, the version `requirements.txt` pins): the imports, output, error text and exit codes of `scripts/run_wasmtime.py`, without Python.

Build with `cargo build --release` in this directory; the binary is `target/release/goose-wasmtime`.
Run `goose-wasmtime module.wasm [--timing-json path] [--cache path] [-- program arguments]` with the program's input on stdin.
`--cache` keeps the compiled module in that file beside a `.sha256` stamp of the module bytes; keep it apart from the Python runner's cache, since each host refuses the other's file (this one then compiles again and replaces it, the Python runner fails).
Tests: `cargo test`, then from the repository root `.venv/bin/python host/rust/tests/float_text.py` (float text against `goose_float`; needs `cargo build --release --examples`) and `.venv/bin/python host/rust/tests/compare_hosts.py --work DIR examples/*.goose` (both hosts on the same modules).
