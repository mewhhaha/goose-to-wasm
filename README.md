# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 134 of 6,537 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 46. Cold direct Wasm builds took 53.2–140.4 ms; native C builds took 263.2–1933.8 ms. [Results and method](bench/results/2026-11-05/bounded-images-and-early-results/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 179.5 ms with minimal AOT and 124.9 ms natively. The native column uses this compiler's C backend. Snapshot 45 was measured separately; sorting took longer in both columns in this run. These runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 46 passed C-only fixed-point verification; its final two generated C outputs match. This batch adds bounded flat relative-image access and preserves conversions and mutations through completed early blocks.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 46 passed 6,403 of 6,537 frozen source and output contracts; 134 failed. Against snapshot 45, 4 of 6,389 shared checks improved and none regressed. All 148 new source-authored checks passed. The curated Wasm corpus passed 2,676/2,676 checks each in Wasmtime and V8; all 770 curated native controls also passed. The remaining failures are 12 accepted invalid programs and 122 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification](selfhost/results/2026-11-05/bounded-images-and-early-results/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
