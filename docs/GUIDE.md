# Goose to Wasm guide

Run commands from the repository root. Bootstrap needs Python 3 and a native C compiler; Clang is the default. Running Wasm examples needs Node, or the optional Wasmtime host below.

## Build and run

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

The example prints `sum=140`. Bootstrap installs the Goose compiler and standard library in `build/bin`. It uses the checked-in C seed and verifies generated C across compiler generations. See [bootstrap details](../selfhost/README.md).

Build a native executable using the same compiler's C backend:

```sh
python scripts/goose_wasm.py build examples/squares.goose \
  --backend native -o build/squares-native
./build/squares-native
```

Use `--goose` and `--stdlib` to select a compiler and library, `--cc` to select the native C compiler, and `-O0`, `-O1`, or `-O2` to choose optimization. Run `python scripts/goose_wasm.py build --help` for the remaining options. The direct backend emits Wasm without a C compiler; native output compiles generated C.

## Optional Wasmtime host

```sh
python scripts/build_wasmtime_host.py
build/bin/goose-wasmtime build/squares.wasm
```

The host builder uses the pinned Wasmtime SDK and a C++ compiler. See [host notes](../bench/wasmtime-host.md) for its configuration and historical measurements.

## Contracts and scope

```sh
python tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

The output directory must be new. Contracts specify source, expected output, exit status and failure phase independently of a reference compiler. Failures are reported in `report.json`; there is no expected-output update mode. The frozen contracts describe the tested scope. Frontend and runtime gaps remain; native packed images, threads, pools, packages, tooling, sessions and caches are still in progress. See the [compiler notes](../selfhost/README.md) for recent results.
