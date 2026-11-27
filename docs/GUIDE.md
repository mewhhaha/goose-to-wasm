# Goose to Wasm guide

Run commands from the repository root. Bootstrap needs Python 3 and a native C compiler; Clang is the default. Running Wasm examples needs Node, or the optional Wasmtime host below.

## Build and run

```sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

The example prints `sum=140`. Bootstrap installs the `goosew` compiler and standard library in `build/bin` (named `goosew` to avoid colliding with upstream C++ `goose`; symlink or rename it if you prefer `goose`). It uses the checked-in C seed and verifies generated C across compiler generations. See [bootstrap details](../selfhost/README.md).

To distribute a smaller Wasm module, install Binaryen (`wasm-opt` on your path) and compact the emitted file.

```sh
python scripts/goose_wasm.py compact build/squares.wasm -o build/squares.release.wasm
```

The default `balanced` profile folds common branch endings and gives frequently referenced functions shorter indexes. Use `--profile size` for Binaryen’s more expensive `-Oz` pass. Both profiles accept Goose memory32 and memory64 modules and copy the original bytes if optimization would enlarge the file. Keep the original for debugging with function names. [Size and runtime measurements with Binaryen 133](../bench/results/2026-11-20/compact-releases/README.md)

Build a native executable using the same compiler's C backend:

```sh
python scripts/goose_wasm.py build examples/squares.goose \
  --backend native -o build/squares-native
./build/squares-native
```

Use `--goose` and `--stdlib` to select a compiler and library, `--cc` to select the native C compiler, and `-O0`, `-O1`, or `-O2` to choose optimization. Native builds compile the runtime once per C compiler and flags, cached under `build/cache/native-runtime`, and split large programs into C units that compile in parallel; `--jobs N` sets the unit count, and `--jobs 1` compiles one C file with the runtime embedded. Run `python scripts/goose_wasm.py build --help` for the remaining options. The direct backend emits Wasm without a C compiler; native output compiles generated C.

Every function in your own source files is checked, including functions the program never calls. Modules found through `--stdlib` are libraries: the compiler parses and checks a library function only when the program reaches it, so an error inside an unused library function is not reported.

## Fast iteration on large projects (`--jobs`, `--cache-dir`, `--wasm-memory64`)

When invoking `goosew` directly on multi-file codebases:

```sh
# Incremental typecheck & Direct Wasm64 dev build (deterministic across thread counts)
goosew src/main.goose --target wasm-direct --wasm-memory64 --wasm-max-pages 65536 \
  --cache-dir build/goose-cache --jobs auto -O0 -o build/app.wasm
```

- **`--jobs N|auto` (`-j N`):** Parallelizes source I/O, lex/parse, body typechecking, pure-function lifetimes, IR optimization, Direct Wasm emission, and Native C emission (`auto` by default) while guaranteeing SHA-256 bit-identical output across thread counts (`--jobs 1..N`).
- **`--cache-dir DIR`:** Content-addressed build cache (`selfhost/cache.goose`) with two layers:
  - **Whole-build cache:** SHA-256 keys compiler binary identity, target/opt/flags, entry + transitive imports, `embed_file`/`embed_shader` payloads, and shadowing probes — returning unchanged `--check` or `.wasm`/`.c` outputs in tens of milliseconds.
  - **Incremental lifetime certificates (`l_<fp>.life`):** On edited-file rebuilds whose canonical lifetime skeleton is unchanged (comments, formatting, literal values, pure scalar `let`/`var`/`if` body logic, inert helpers), `goosew` reuses the validated lifetime certificate instead of re-running the full lifetime fixed point, while automatically re-analyzing whenever reference flow, borrowing, mutation, or control flow changes.
- **`--wasm-memory64` & `--wasm-max-pages N`:** Targets 64-bit WebAssembly linear memory so large self-hosted programs and compilers can reserve gigabytes of virtual address space without exhausting wasm32's 4 GiB cap.
- **`--library` & `--reachable-program`:** Compile library modules without a `main` function (checking only exported entrypoints and reachable code).
- **`--error-format text|json`, `--color auto|always|never`, `--wasm-stats FILE`:** Structured diagnostics and per-stage compile/cache timing telemetry (`parse_ns`, `typecheck_ns`, `lifetime_ns`, `optimize_ns`, `backend_ns`, `cache_hit`, `life_cache_hit`).
- **`goosew guide [topic|--cheatsheet|--list]`:** Prints a built-in, version-matched Goose language & `goosew` CLI cheatsheet (or one focused topic: `rules`, `types`, `structs`, `refs`, `control`, `stdlib`, `cli`) directly from both the native and portable Wasm compiler binaries.

## Optional Wasmtime & `wtime` hosts

### Native Rust Wasmtime host (recommended for Wasm64 & fast cold JIT)

With Rust 1.97 or newer, build [`host/rust`](../host/rust/README.md):

```sh
cargo build --locked --release --manifest-path host/rust/Cargo.toml
host/rust/target/release/goose-wasmtime --fast-jit build/app.wasm \
  --cache build/app.cwasm -- arg1 arg2
```

- **`--fast-jit`** enables Wasmtime 50.0.1's **Winch** baseline compiler (`Strategy::Winch`, ~2× faster cold JIT than Cranelift `OptLevel::None` and ~4–5× faster than `OptLevel::Speed` on large `-O0` modules), automatically falling back to Cranelift `OptLevel::None + SinglePass` for modules that use proposals Winch does not yet support (`wasm_exceptions`, `wasm_tail_call`, `wasm_gc`, etc.).
- **`--cache PATH`** persists the compiled `.cwasm` beside a mode-specific `.sha256` stamp (`winch-fast-jit:`, `cranelift-fast-jit:`, or bare digest for `OptLevel::Speed`).
- **`--entry NAME`** invokes an exported function after `_start` (for `--library` modules such as Blot2's `blot_goose_main`).

### Safe-Rust `wtime` host & legacy C++ Wasmtime host

- For a zero-`unsafe` (`#![forbid(unsafe_code)]`) interpreter/register runner for Wasm32 and Wasm64 modules, see [`host/wtime/README.md`](../host/wtime/README.md).
- To build the legacy C++ Wasmtime host instead:

```sh
python scripts/build_wasmtime_host.py
build/bin/goose-wasmtime build/squares.wasm
```

See [host notes](../bench/wasmtime-host.md) for the legacy C++ host configuration and historical measurements.

## Contracts and scope

See [running the contracts](../tests/README.md) for the test commands and [upstream compatibility](FEATURES.md) for supported features and open gaps.
