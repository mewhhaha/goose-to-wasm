# Direct backend differential qualification

```sh
python3 tests/run_differential.py
```

The default suite compiles runtime-input fixtures at `-O0` and `-O2` with the
direct backend, the Emscripten C oracle, and the native C oracle. Each emitted
Wasm binary runs unchanged on V8 and Wasmtime. Native Goose supplies the
independent observation; selected arithmetic, control-flow, array, and reference
cases also have explicitly derived answers. Float output is compared byte for
byte with Goose's formatter, including signed zero, infinities, NaN, subnormals,
format thresholds, and deterministic samples of binary32 and binary64 values.

The suite covers integer widths and wrapping, signed division/remainder edges,
debug overflow and conversion failures, short-circuit side effects, recursion,
generic specialization, globals, scalar multiple results, value-producing
blocks/loops/matches, implicit and explicit references, reference identity,
nullable values, aggregate copying, mutable slices, aggregate fields, bounds
errors, print argument snapshots and their unwinding on inline returns,
assertion failures, and explicit exit codes.
The input `bench_input` and `bench_input_f64` externs use the same stdin values
on every target. `bench/host_input.c` implements them for C targets; the Wasm
host imports implement them for direct output.

Valid Goose constructs outside the direct profile, such as resizable arrays
and pointer-bearing extern signatures, must produce a compile-time refusal and
no Wasm artifact. A malformed source fixture checks that ordinary source
diagnostics remain distinct from target refusals. Passing this suite does not
mean the direct backend accepts the complete Goose language.

Results and exact command/stdout/stderr logs are retained under
`build/differential/`. `report.json` records the compiler hash and toolchain pin.
Use `--filter`, `--scalar-only`, `--levels`, `--backends`, or `--engines` to focus
a diagnosis. Reduced runs are useful during development; the complete default
run is the qualification gate.

The host scripts are:

- `scripts/run_wasm.mjs`: Node/V8.
- `scripts/run_wasmtime.py`: the pinned Wasmtime Python bindings.

They implement the direct scalar I/O contract and the small WASI64 contract
needed by the standalone memory64 C oracle. Their optional `--timing-json`
records engine compile/instantiate and entry-function time, independently of
the benchmark's in-program timed region.

The full C-oracle language/runtime suite remains under `oracle/tests/`.
`test_incremental.py` independently verifies cache and persistent-server
behavior.
