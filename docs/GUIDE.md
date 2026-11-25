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

## Optional Wasmtime host

```sh
python scripts/build_wasmtime_host.py
build/bin/goose-wasmtime build/squares.wasm
```

The host builder uses the pinned Wasmtime SDK and a C++ compiler. See [host notes](../bench/wasmtime-host.md) for its configuration and historical measurements.

## Contracts and scope

See [running the contracts](../tests/README.md) for the test commands and [upstream compatibility](FEATURES.md) for supported features and open gaps.
