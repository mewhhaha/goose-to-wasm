# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial; 311 of 5,028 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X · lower is better.** Five-sample medians for ten examples using snapshot 37. Cold direct Wasm builds took 52.1–137.1 ms; native C builds took 268.1–1,830.8 ms. Separately collected snapshot 34 builds took 50.2–126.0 ms and 255.9–1,702.4 ms, respectively. [Results and method](bench/results/2026-11-05/rendering-and-results/README.md) · [Earlier C++ compiler results](bench/results/2026-11-04/leaf-and-loads/README.md) · [Historical examples](bench/examples.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The native column includes this compiler's C backend overhead. In the separately collected host run, Sorting took 178.5 ms with minimal AOT and 122.1 ms natively.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 37 passed C-only fixed-point verification. It adds natural result projection and fixes relative receivers, native array views, printing and validation.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 37 passed 4,717 of 5,028 frozen source and output contracts; 311 failed. Against snapshot 34, 29 of 5,021 shared checks improved and none regressed; seven new literal-kind checks all passed. The curated Wasm corpus passed 1,946/1,946 checks each in Wasmtime and V8. Remaining gaps include 61 accepted invalid types and 250 runtime contracts that fail to compile or execute, including variable images, varints, lifetimes and default names. [Qualification](selfhost/results/2026-11-05/rendering-and-results/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
