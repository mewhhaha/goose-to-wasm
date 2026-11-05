# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 146 of 6,061 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 44. Cold direct Wasm builds took 49.8–131.7 ms; native C builds took 249.8–1823.3 ms. [Results and method](bench/results/2026-11-05/relative-cells-and-control-values/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 163.8 ms with minimal AOT and 113.6 ms natively. The native column uses this compiler's C backend. Snapshot 43 was measured separately; these runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 44 passed C-only fixed-point verification; its final two generated C outputs match. This batch corrects default-callback returns, readonly iteration, tail references, pool rebinding, scalar relative cells and numeric control values.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 44 passed 5,915 of 6,061 frozen source and output contracts; 146 failed. Against snapshot 43, 20 of 5,677 shared checks improved and none regressed. All 384 new source-authored checks passed. The curated Wasm corpus passed 2,454/2,454 checks each in Wasmtime and V8; all 516 curated native controls also passed. The remaining failures are 18 accepted invalid programs and 128 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification](selfhost/results/2026-11-05/relative-cells-and-control-values/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
