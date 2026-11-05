# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. Frontend and runtime gaps remain.

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X · lower is better.** Medians of five samples for ten examples, using Goose compiler snapshot 27. Every output passed its check. Cold builds include driver startup; direct Wasm builds took 50.4–114.6 ms and native C builds took 247.0–1,337.3 ms. The prior separately collected snapshot 23 native builds took 144.2–1,236.3 ms.

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch to exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT; preparation is measured separately in a host run using the same artifacts.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The native column uses this Goose compiler's C backend, which has its own overhead; it is not a native performance ceiling. For Sorting, minimal AOT took 169.6 ms versus 1,157.2 ms for this C backend. Functions native startup measured 0.932 ms in the example run, up from 0.562 ms in the separately collected snapshot 23 host run. [Results, inputs and method](bench/results/2026-11-05/ordinary-regions/README.md) · [Earlier C++ compiler results](bench/results/2026-11-04/leaf-and-loads/README.md) · [Historical example results](bench/examples.md)

## How it was built

The compiler implements source loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap compiles a frozen C seed with a native C compiler, then uses it to build the Goose source. Snapshot 27 passed a three-generation C-only fixed-point check. Its bounded ordinary native regions reduced a matched 20,000-array stress test from 134.7 ms to 5.4 ms versus snapshot 26.

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Correctness is checked against frozen source and output contracts without running a reference compiler. Snapshot 27 passed 4,360 of 5,021 contract rows; 661 failed. The curated Wasm corpus passed 1,944 checks each in Wasmtime and V8. Native packed images, pools and threads remain unfinished.

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
