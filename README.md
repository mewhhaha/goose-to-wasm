# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. Frontend and runtime gaps remain.

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X · lower is better.** Medians of five samples for ten examples, using Goose compiler snapshot 32. All outputs passed their checks. Cold builds include driver startup; direct Wasm builds took 48.9–119.9 ms and native C builds took 242.7–1,670.9 ms. Separately collected snapshot 27 builds took 50.4–114.6 ms and 247.0–1,337.3 ms, respectively.

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch to exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT; preparation is measured separately in a host run using the same artifacts.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The native column uses this Goose compiler's C backend, which has its own overhead; it is not a native performance ceiling. Sorting native execution took 113.6 ms; the separately collected snapshot 27 host run took 1,157.2 ms. [Results, inputs and method](bench/results/2026-11-05/threads-pools-and-access/README.md) · [Earlier C++ compiler results](bench/results/2026-11-04/leaf-and-loads/README.md) · [Historical example results](bench/examples.md)

## How it was built

The compiler implements source loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap compiles a frozen C seed with a native C compiler, then uses it to build the Goose source. Snapshot 32 passed C-only fixed-point verification. In a matched Sorting experiment, an access inlining hint reduced runtime from 1.193 s to 0.113 s while increasing C build time from 1.216 s to 1.576 s.

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Correctness is checked against frozen source and output contracts without running a reference compiler. Snapshot 32 passed 4,558 of 5,021 contract rows; 463 failed. The curated Wasm corpus passed 1,944 checks each in Wasmtime and V8. Packed relative cells, general variable images and frontend gaps remain.

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
