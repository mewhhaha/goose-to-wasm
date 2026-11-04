# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. Frontend and runtime gaps remain.

## Benchmarks

**2026-11-04 · AMD Ryzen 7 3800X · lower is better.** Medians of five samples for ten examples, using Goose compiler snapshot 23. Every output passed its check. Cold builds include driver startup; direct Wasm builds took 48.9–276.4 ms and native C builds took 144.2–1,236.3 ms.

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch to exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT; preparation is measured separately. For Functions, minimal AOT took 1.047 ms versus 0.562 ms for native C, about 1.86× as long.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

The native column uses this Goose compiler's C backend, which has its own overhead; it is not a native performance ceiling. For Sorting, Wasm took about 162 ms versus 1,500 ms for this C backend. [Results, inputs and method](bench/results/2026-11-04/goose-compiler/README.md) · [Earlier C++ compiler results](bench/results/2026-11-04/leaf-and-loads/README.md) · [Historical example results](bench/examples.md)

## How it was built

The compiler implements source loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap compiles a frozen C seed with a native C compiler, then uses it to build the Goose source. Snapshot 23 passed a three-generation C-only fixed-point check; later fixes are outside that proof.

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Correctness is checked against frozen source and output contracts without running a reference compiler. Snapshot 23 passed 4,076 of 4,989 contract rows; 913 failed. Native backend, semantic and Wasm fixes continue.

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
