# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 179 of 5,300 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 42. Cold direct Wasm builds took 50.4–132.9 ms; native C builds took 252.9–1988.9 ms. [Results and method](bench/results/2026-11-05/match-render-and-views/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 167.9 ms with minimal AOT and 117.0 ms natively. The native column uses this compiler's C backend. Snapshot 41 was measured separately; these runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 42 passed C-only fixed-point verification; its final two generated C outputs match. Snapshot 42 improves match decoding, rendering, view lifetimes and assignment analysis.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 42 passed 5,121 of 5,300 frozen source and output contracts; 179 failed. Against snapshot 41, 25 of 5,118 shared checks improved and none regressed. All 182 new source-authored checks passed. The curated Wasm corpus passed 2,090/2,090 checks each in Wasmtime and V8; all 119 curated native controls also passed. The remaining failures are 33 accepted invalid programs and 146 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification](selfhost/results/2026-11-05/match-render-and-views/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
