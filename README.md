# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. Frontend and runtime gaps remain.

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X · lower is better.** Medians of five samples for ten examples using Goose compiler snapshot 34. Every output passed its check. Cold builds include driver startup; direct Wasm builds took 50.2–126.0 ms and native C builds took 255.9–1,702.4 ms. Separately collected snapshot 32 builds took 48.9–119.9 ms and 242.7–1,670.9 ms, respectively.

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch to exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT; preparation is measured separately in a host run using the same artifacts.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The native column uses this Goose compiler's C backend, which has its own overhead; it is not a native performance ceiling. In the host run, Sorting took 162.0 ms with minimal AOT and 113.2 ms natively. [Results, inputs and method](bench/results/2026-11-05/fixed-relative-and-bindings/README.md) · [Earlier C++ compiler results](bench/results/2026-11-04/leaf-and-loads/README.md) · [Historical example results](bench/examples.md)

## How it was built

The compiler implements source loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap compiles a frozen C seed with a native C compiler, then uses it to build the Goose source. Snapshot 34 passed C-only fixed-point verification. It adds fixed-width relative places, corrects generated C for seven previously invalid programs, and improves binding and float inference.

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Correctness is checked against frozen source and output contracts without running a reference compiler. Snapshot 34 passed 4,681 of 5,021 contract rows; 340 failed; 123 checks improved over snapshot 32 with no regressions. The curated Wasm corpus passed 1,944 checks each in Wasmtime and V8. Variable images, varints, natural result projection and frontend lifetime gaps remain.

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
