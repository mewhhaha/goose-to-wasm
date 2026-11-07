# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 108 of 7,435 contract rows fail.**

## Benchmarks

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 51. Cold direct Wasm builds took 49.3–131.2 ms; native C builds took 247.9–1820.1 ms. [Results and method](bench/results/2026-11-07/contextual-enum-dispatch/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 172.2 ms with minimal AOT and 116.9 ms natively. Both targets use this compiler. Previous snapshots were collected separately; no matched runtime speedup is claimed.

## Construction and contracts

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 51 passed C-only fixed-point verification; its final two generated C outputs match.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 51 passed 7,327 of 7,435 frozen source and output contracts; 108 failed. Against snapshot 50, 4 of 7,371 shared checks improved and none regressed. All 64 new source-authored checks passed. The curated Wasm corpus passed 3,110/3,110 checks each in Wasmtime and V8; all 1,234 curated native controls also passed. The remaining failures are 6 accepted invalid programs and 102 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed. [Qualification](selfhost/results/2026-11-07/contextual-enum-dispatch/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
